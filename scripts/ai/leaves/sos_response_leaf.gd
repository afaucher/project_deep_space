extends "res://addons/beehave/nodes/leaves/action.gd"

# M52 -- SOS response (implementation_plans/m52_patrol_interdiction.md item
# 2): "comms range >> sensor range -- fly to the marker." Inserted in
# build_patrol ONLY, between Engage and Challenge (ai_tree_factory.gd) -- a
# closer HOSTILE contact (including one the SOS itself reported) still wins
# via Engage above it; SOS response is what gets the patrol close enough to
# sense one in the first place.
#
# Reads actor.heard_sos (already populated end-to-end by the M49 wire
# protocol -- Ship.send_sos / the VERB_SOS receive branch / TTL decay --
# nothing else reads it). Commits to the freshest entry (blackboard-tracked
# "sos_responding_to" so an already-committed response doesn't restart toward
# a newer, farther call every tick -- resolves one at a time) and steers
# toward its snapshot position (sos["pos"] -- a snapshot from send time, not a
# live track; "fly to the marker" means the marker). Returns SUCCESS while en
# route (claims the tick, pre-empting FollowRoute/Challenge below).
#
# Gives up (clears "sos_responding_to", returns FAILURE, resumes patrol) on
# any of the three plan-doc conditions: arrived within a close radius, the
# heard_sos entry for that sender goes stale (HEARD_SOS_TTL already expires
# it out of heard_sos entirely -- ship.gd), or a HOSTILE contact is already
# held (Engage above already wins the tick whenever that's true; this leaf
# self-clears rather than fight it on the ticks it still runs).
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

	var responding_to: int = blackboard.get_value("sos_responding_to", -1)

	if responding_to == -1:
		# Not currently committed -- pick the freshest heard_sos entry (lowest
		# age; "age" is delta-accumulated seconds since first heard/last
		# relayed, ship.gd's decay loop).
		var best_iid := -1
		var best_age := INF
		for sender_iid in actor.heard_sos:
			var age: float = actor.heard_sos[sender_iid].get("age", 0.0)
			if age < best_age:
				best_age = age
				best_iid = sender_iid
		if best_iid == -1:
			return FAILURE
		responding_to = best_iid
		blackboard.set_value("sos_responding_to", responding_to)

	var sos: Dictionary = actor.heard_sos.get(responding_to, {})
	if sos.is_empty():
		# Gone stale -- HEARD_SOS_TTL already erased it out of heard_sos.
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
		if c.get("last_seen_timer", 999.0) > actor.FIRE_STALENESS_MAX:
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
