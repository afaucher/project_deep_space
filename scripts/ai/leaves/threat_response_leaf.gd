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
#     issuer's track goes stale, OR (M52a) once the threat is OVERTAKEN --
#     see below.
#   - "threat_ratio": the RUN_SPEED_RATIO(_PIRATE_FLAG) that applied when this
#     RUN started, carried alongside threat_issuer_iid so the overtaken-check
#     below re-uses the same threshold rather than a fresh flag lookup.
#   - "last_decided_seq": the seq of the last pending_demand this leaf already
#     acted on, so a still-pending demand dict doesn't re-trigger the
#     comply-or-run decision (and a fresh SOS) every single tick.
#
# M52a -- overtaken mid-flight: the comply-or-run call used to be made ONCE
# per incident and never revisited while running, even as _update_contact_
# peaks() (below) kept recording the chaser's speed in the background -- a
# victim that watched its pursuer visibly closing the gap had no way to
# reconsider short of a brand-new DEMAND. Now the active-RUN branch re-checks
# the SAME threshold every tick against the live peak; once the threat has
# actually demonstrated it can catch us, running is no longer rational and we
# comply instead of burning fuel on a race already lost.
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
		blackboard.set_value("was_held", true)
		return SUCCESS # held -- ship-level throttle override owns motion, do nothing
	elif blackboard.get_value("was_held", false):
		# M52 -- compelled_stop just cleared on its own heartbeat lapse (the
		# hold/incident is genuinely over -- issuer dead, out of comms, job
		# aborted, or done, see ship.gd's HAIL_HEARTBEAT_TIMEOUT comment) --
		# symmetric with the RUN incident's track-lost/overtaken cleanups
		# below, this is the "immediate comply" path's only resolution point.
		# set_sos_active(false, ...) just flips the live sos_active field now
		# (implementation_plans/m52_sos_passive_sync.md) -- datalink_relay's
		# continuous reconciliation clears the sos badge on anyone holding a
		# track on us within a tick or two, no broadcast to send.
		blackboard.erase_value("was_held")
		if actor.has_method("set_sos_active"):
			actor.set_sos_active(false, "")

	# An active RUN incident in progress: keep running while the issuer's
	# track stays fresh; once it goes stale, clear the incident and fall
	# through to CargoRun (resume route).
	if blackboard.has_value("threat_issuer_iid"):
		var issuer_iid: int = blackboard.get_value("threat_issuer_iid")
		var issuer_trk: String = "TRK-%03d" % (abs(issuer_iid) % 1000)
		var c: Dictionary = actor.active_contacts.get(issuer_trk, {})
		if c.is_empty() or c.get("last_seen_timer", 999.0) > actor.FIRE_STALENESS_MAX:
			blackboard.erase_value("threat_issuer_iid")
			blackboard.erase_value("threat_ratio")
			# M52 -- track lost, incident genuinely over. See the was_held
			# branch above for why this is just a plain field write now.
			if actor.has_method("set_sos_active"):
				actor.set_sos_active(false, "")
			return FAILURE

		# M52a: re-check the SAME threshold every tick against the live peak
		# (_update_contact_peaks already refreshed it above) -- if the chaser
		# has now demonstrably closed to catching-up speed, running is no
		# longer the winning move. Give up and comply instead of continuing
		# to burn fuel on a race we're now losing.
		var run_ratio: float = blackboard.get_value("threat_ratio", RUN_SPEED_RATIO)
		var live_peaks: Dictionary = blackboard.get_value("contact_peaks", {})
		var live_threat_capability: float = live_peaks.get(issuer_iid, 0.0)
		if actor.max_speed <= live_threat_capability * run_ratio:
			if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
				print("[Cargo] %s: overtaken mid-flight (threat now %.0f x%.1f >= my %.0f) -- giving up, STOP" %
					[actor.debug_label(), live_threat_capability, run_ratio, actor.max_speed])
			blackboard.erase_value("threat_issuer_iid")
			blackboard.erase_value("threat_ratio")
			# M52 -- RUN incident resolved (overtaken -> comply). See the
			# was_held branch above for why this is just a plain field write.
			if actor.has_method("set_sos_active"):
				actor.set_sos_active(false, "")
			# M52d -- decoupled: AI's comply-or-run decision has no "buy time"
			# nuance, so giving up means actually stopping, not just
			# acknowledging (engage_dead_stop, not acknowledge).
			if actor.has_method("engage_dead_stop"):
				actor.engage_dead_stop()
			return SUCCESS

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
			[actor.debug_label(), "RUN" if will_run else "STOP", actor.max_speed, threat_capability, ratio, threat_capability * ratio])

	# M52 -- turn SOS on at incident start, regardless of the comply-or-run
	# call. M52 passive sync (implementation_plans/m52_sos_passive_sync.md):
	# this just sets the live sos_active/sos_nature fields -- datalink_
	# relay's continuous reconciliation keeps anyone in range showing the
	# distress badge for as long as they stay set, no heartbeat/timer
	# involved. The track-lost/overtaken cleanups above and the was_held/
	# compelled_stop-lapse check at the top of this function (on a LATER
	# tick) turn it back off once the incident genuinely resolves.
	if actor.has_method("set_sos_active"):
		actor.set_sos_active(true, Hail.NATURE_UNDER_ATTACK)

	if will_run:
		blackboard.set_value("threat_issuer_iid", issuer_iid)
		blackboard.set_value("threat_ratio", ratio)
		_run_from(actor, threat_pos)
	# M52d -- decoupled: no "buy time" nuance for AI yet, so complying means
	# actually stopping (engage_dead_stop broadcasts ACKNOWLEDGE itself).
	elif actor.has_method("engage_dead_stop"):
		actor.engage_dead_stop()
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
