extends "res://addons/beehave/nodes/leaves/action.gd"

# M49 -- cargo/civilian comply-or-run (design_ideas/comms_verbs.md's "Cargo AI"
# policy): reacts to a STOP demand addressed to this actor, or to being held
# under compulsion. Ticks BEFORE CargoRun in build_cargo (ai_tree_factory.gd,
# inserted between Disengage and CargoRun) so an active incident preempts the
# transit/dock cycle. Returns FAILURE when there is nothing to respond to so
# the tree falls through to CargoRun untouched -- same "leaf that can decline
# the tick" shape as acquire_target_leaf's no-hostile-in-range case.
#
# Two-state blackboard style (mirrors cargo_run_leaf.gd's cargo_docking/
# cargo_captured_seen pair, just kept on the tree's own blackboard instead of
# actor fields since this state is AI-decision-only, not something the ship
# body or other leaves need to read):
#   - "threat_issuer_iid": set while actively RUNNING from a demand; cleared
#     (and this leaf returns FAILURE, handing back to CargoRun) once the
#     issuer's track goes stale.
#   - "last_decided_seq": the seq of the last pending_demand this leaf already
#     acted on, so a still-pending demand dict doesn't re-trigger the
#     comply-or-run decision (and a fresh SOS) every single tick.
const Steering = preload("res://scripts/ai/steering.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")

const RUN_SPEED_RATIO := 1.3              # my max_speed must exceed threat speed x this to run
const RUN_SPEED_RATIO_PIRATE_FLAG := 1.6  # shown pirate colors weigh toward compliance
const RUN_SPEED := 900.0

func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	if not actor.compelled_stop.is_empty():
		return SUCCESS # held -- ship-level throttle override owns motion, do nothing

	# An active RUN incident in progress: keep running while the issuer's
	# track stays fresh; once it goes stale, clear the incident and fall
	# through to CargoRun (resume route).
	if blackboard.has_value("threat_issuer_iid"):
		var issuer_iid: int = blackboard.get_value("threat_issuer_iid")
		var issuer_trk: String = "TRK-%03d" % (abs(issuer_iid) % 1000)
		var c: Dictionary = actor.active_contacts.get(issuer_trk, {})
		if c.is_empty() or c.get("last_seen_timer", 999.0) > actor.FIRE_STALENESS_MAX:
			blackboard.erase_value("threat_issuer_iid")
			return FAILURE
		_run_from(actor, c.get("pos", actor.position))
		return SUCCESS

	var demand: Dictionary = actor.pending_demand
	if demand.get("rung", "") != Hail.RUNG_STOP:
		return FAILURE

	# Decide once per incident, keyed on the demand's own seq -- a stale
	# pending_demand dict (already acted on) must not re-decide every tick;
	# a genuinely NEW demand (different seq, even from the same issuer)
	# re-triggers the decision.
	var demand_seq: int = demand.get("seq", -1)
	if blackboard.get_value("last_decided_seq", -1) == demand_seq:
		return FAILURE
	blackboard.set_value("last_decided_seq", demand_seq)

	var issuer_iid: int = demand.get("sender_iid", -1)
	var issuer_trk2: String = "TRK-%03d" % (abs(issuer_iid) % 1000)
	var threat_speed: float = 0.0
	var threat_pos: Vector2 = demand.get("sender_pos", actor.position)
	if actor.active_contacts.has(issuer_trk2):
		var issuer_c: Dictionary = actor.active_contacts[issuer_trk2]
		threat_speed = issuer_c.get("vel", Vector2.ZERO).length()
		threat_pos = issuer_c.get("pos", threat_pos)

	var ratio: float = RUN_SPEED_RATIO_PIRATE_FLAG if demand.get("sender_flag", "") == Standing.FLAG_PIRATE else RUN_SPEED_RATIO
	var will_run: bool = actor.max_speed > threat_speed * ratio

	# Always broadcast SOS once per incident, regardless of the comply-or-run call.
	if actor.has_method("send_sos"):
		actor.send_sos(Hail.NATURE_UNDER_ATTACK)

	if will_run:
		blackboard.set_value("threat_issuer_iid", issuer_iid)
		_run_from(actor, threat_pos)
	elif actor.has_method("comply_with_stop"):
		actor.comply_with_stop()
	return SUCCESS

func _run_from(actor: Node, threat_pos: Vector2) -> void:
	var away_dir: Vector2 = (actor.position - threat_pos).normalized()
	var avoided: Vector2 = Steering.steer(actor, away_dir, null)
	actor.apply_control_input(0.0, RUN_SPEED, avoided.angle(), 1, 1) # nose away, full velocity
