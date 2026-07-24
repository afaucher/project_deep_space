extends "res://addons/beehave/nodes/leaves/action.gd"

# M52 -- SOS response (implementation_plans/m52_patrol_interdiction.md item
# 2): "comms range >> sensor range -- fly to the marker." Inserted in
# build_patrol ONLY, between Engage and Challenge (ai_tree_factory.gd) -- a
# closer HOSTILE contact (including one the SOS itself reported) still wins
# via Engage above it; SOS response is what gets the patrol close enough to
# sense one in the first place.
#
# M52 follow-up (implementation_plans/m52_sos_as_contact.md item 3): SOS is
# now a real active_contacts entry classified "DISTRESS CALL" (the bare
# classification -- see that doc for why it's deliberately excluded from
# Standing/JobSteps' vessel-classification allow-lists), decaying on the
# SAME CONTACT_TIMEOUT clock as every other contact, relayed for free by the
# existing datalink loop -- there is no more separate heard_sos side-channel.
# Commits to the freshest "DISTRESS CALL" contact (blackboard-tracked
# "sos_responding_to", keyed by track id, so an already-committed response
# doesn't restart toward a newer, farther call every tick -- resolves one at
# a time) and steers toward its position. The old "prefer live contact"
# consumer-side check is gone -- the merge-in point (ship.gd's
# _reconcile_sos_contact, implementation_plans/m52_sos_passive_sync.md)
# never overwrites a real detection's pos with the SOS snapshot, so
# whatever's on the contact IS already the freshest available position.
#
# Gives up (clears "sos_responding_to", returns FAILURE, resumes patrol) on
# any of the plan-doc conditions: arrived within a close radius, the contact
# is no longer a fresh "DISTRESS CALL" entry (pruned by the normal
# CONTACT_TIMEOUT sweep, or self-healed into a real classification by a
# later correlated detection -- either way nothing left for this leaf to
# chase), or a HOSTILE contact is already held (Engage above already wins
# the tick whenever that's true; this leaf self-clears rather than fight it
# on the ticks it still runs).
const Steering = preload("res://scripts/ai/steering.gd")
const Standing = preload("res://scripts/combat/standing.gd")

const CRUISE_SPEED := 500.0
const ARRIVAL_RADIUS := 1000.0

func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	if blackboard.has_value("sos_responding_to") and _has_fresh_hostile(actor):
		blackboard.erase_value("sos_responding_to")
		return FAILURE

	var responding_to: String = blackboard.get_value("sos_responding_to", "")

	if responding_to == "":
		# Not currently committed -- pick the freshest "DISTRESS CALL"
		# contact (lowest contact_age(), the same clock every other
		# contact decays on -- no separate age field anymore).
		var best_trk := ""
		var best_age := INF
		for c_id in actor.active_contacts:
			var c: Dictionary = actor.active_contacts[c_id]
			if c.get("classification", "") != "DISTRESS CALL":
				continue
			var age: float = Ship.contact_age(c)
			if age < best_age:
				best_age = age
				best_trk = c_id
		if best_trk == "":
			return FAILURE
		responding_to = best_trk
		blackboard.set_value("sos_responding_to", responding_to)

	var sos: Dictionary = actor.active_contacts.get(responding_to, {})
	if sos.is_empty() or sos.get("classification", "") != "DISTRESS CALL":
		# Gone stale (pruned by CONTACT_TIMEOUT) or self-healed into a real
		# classification via a later correlated detection -- either way,
		# nothing left here for this leaf to chase.
		blackboard.erase_value("sos_responding_to")
		return FAILURE

	var pos: Vector2 = sos.get("pos", actor.position)
	if actor.position.distance_to(pos) <= ARRIVAL_RADIUS:
		blackboard.erase_value("sos_responding_to")
		return FAILURE

	_cruise_toward(actor, pos)
	return SUCCESS

func _has_fresh_hostile(actor: Node) -> bool:
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		if c.get("standing", "") != Standing.HOSTILE:
			continue
		if c.get("classification", "") == "WRECKAGE":
			continue
		if Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
			continue
		return true
	return false

func _cruise_toward(actor: Node, target: Vector2) -> void:
	var desired: Vector2 = target - actor.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	var avoided: Vector2 = Steering.steer(actor, desired, null)
	var desired_vel: Vector2 = avoided.normalized() * CRUISE_SPEED
	var steer: Vector2 = desired_vel - actor.linear_velocity
	if steer.length() < 10.0:
		steer = desired_vel
	actor.apply_control_input(0.0, CRUISE_SPEED, steer.angle(), 1, 1)
