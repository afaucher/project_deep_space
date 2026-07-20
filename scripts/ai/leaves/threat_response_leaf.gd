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

	# M52a (H1): keep a per-contact PEAK observed speed while we hold a track.
	# The comply-or-run decision below used the threat's INSTANTANEOUS speed at
	# demand time -- but a pirate decelerates to hail range before demanding,
	# so it reads as nearly stationary and every hull "outran" it, so everyone
	# ran and no robbery ever completed (the campaign's takes_total=0). Peak
	# speed over the encounter is the honest capability read a victim actually
	# has (it watched the thing chase it down); accumulate it every tick,
	# including during the pre-demand approach when this leaf otherwise just
	# returns FAILURE and hands back to CargoRun.
	_update_contact_peaks(actor, blackboard)

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

	# H1: compare against the threat's demonstrated CAPABILITY -- the higher of
	# its instantaneous speed and the peak we clocked while it chased us down --
	# not the near-zero speed it coasts at once alongside to demand.
	var peaks: Dictionary = blackboard.get_value("contact_peaks", {})
	var threat_capability: float = maxf(threat_speed, peaks.get(issuer_iid, 0.0))

	var ratio: float = RUN_SPEED_RATIO_PIRATE_FLAG if demand.get("sender_flag", "") == Standing.FLAG_PIRATE else RUN_SPEED_RATIO
	var will_run: bool = actor.max_speed > threat_capability * ratio

	if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
		print("[Cargo] %s: %s (my max %.0f vs threat cap %.0f x%.1f = %.0f)" %
			[actor.name, "RUN" if will_run else "COMPLY", actor.max_speed, threat_capability, ratio, threat_capability * ratio])

	# Always broadcast SOS once per incident, regardless of the comply-or-run call.
	if actor.has_method("send_sos"):
		actor.send_sos(Hail.NATURE_UNDER_ATTACK)

	if will_run:
		blackboard.set_value("threat_issuer_iid", issuer_iid)
		_run_from(actor, threat_pos)
	elif actor.has_method("comply_with_stop"):
		actor.comply_with_stop()
	return SUCCESS

# Per-contact peak observed speed, keyed by true instance id, held only while
# the track is continuously fresh (pruned the moment a contact drops out of
# sensor range) -- so it reflects "fastest I've seen this thing move during
# THIS encounter", forgotten cleanly when the encounter ends. No decay: the
# encounter is short and the prune-on-loss is the reset.
func _update_contact_peaks(actor: Node, blackboard) -> void:
	var peaks: Dictionary = blackboard.get_value("contact_peaks", {})
	var seen := {}
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		if c.get("last_seen_timer", 999.0) > actor.FIRE_STALENESS_MAX:
			continue
		var iid: int = c.get("instance_id", -1)
		if iid == -1:
			continue
		peaks[iid] = maxf(peaks.get(iid, 0.0), c.get("vel", Vector2.ZERO).length())
		seen[iid] = true
	for iid in peaks.keys():
		if not seen.has(iid):
			peaks.erase(iid)
	blackboard.set_value("contact_peaks", peaks)

func _run_from(actor: Node, threat_pos: Vector2) -> void:
	var away_dir: Vector2 = (actor.position - threat_pos).normalized()
	var avoided: Vector2 = Steering.steer(actor, away_dir, null)
	actor.apply_control_input(0.0, RUN_SPEED, avoided.angle(), 1, 1) # nose away, full velocity
