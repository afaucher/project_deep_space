extends "res://addons/beehave/nodes/leaves/action.gd"

# D28 -- what a CORNERED PIRATE does when a patrol says stop.
#
# WHY THIS EXISTS, and it is not a tuning story. EngagementProbe's first run
# measured 39 patrol interdictions with this outcome split:
#
#     complied 0   ·   refused (patience expired) 27   ·   outpaced 0
#
# Zero outpaced means the patrols KEPT UP every single time. The subject simply
# never stopped -- because `build_pirate` was ShouldDisengage/Flee/JobRunner/Idle
# with NO demand handler at all. `ThreatResponseLeaf`, the comply-or-run leaf,
# lives only in `build_cargo`. A pirate hearing DEMAND_STOP had nothing anywhere
# in its tree that reads `pending_demand`, so patience expired 100% of the time
# BY CONSTRUCTION. "Patrols never stop pirates" was never a balance problem.
#
# WHY NOT JUST REUSE ThreatResponseLeaf. Because the two hulls are answering
# different questions, and pretending otherwise would quietly invent a policy:
#
#   a hauler weighs  "can I outrun this, or do I lose the cargo?"
#   an outlaw weighs "can I outrun this, or do I lose the SHIP AND MY FREEDOM?"
#
# A hauler that stops is inconvenienced. An outlaw that stops is arrested. So an
# outlaw should be willing to run on a THINNER speed margin than a hauler --
# it is playing for more -- which is the one substantive difference encoded
# below (RUN_SPEED_RATIO_OUTLAW < ThreatResponseLeaf.RUN_SPEED_RATIO).
#
# WHAT THIS DELIBERATELY DOES NOT DO: fight. `build_pirate` has no Engage leaf
# at all -- pirates fight through job steps (TAKE_ALONGSIDE and friends), never
# through the tree -- so a "stand and fight the patrol" branch would be brand
# new combat machinery, not a policy toggle. Inventing it here to answer a
# design question nobody has settled is exactly the wrong move. Run-or-comply is
# the honest floor: it makes stops POSSIBLE, which is what the goal asks for
# first ("stopping some pirates -- then refine desired outcomes"), and leaves
# fight-or-surrender open as a real decision rather than one made by accident.
#
# NO SOS. A hauler under threat calls for help; an outlaw cornered by an
# authority has nobody to call, and broadcasting distress would summon the very
# patrols hunting it. Calling kin for a rescue is a genuinely interesting
# mechanic and is NOT this leaf's business.
#
# Sits between Disengage and JobRunner in build_pirate -- same slot and same
# contract ThreatResponseLeaf holds in build_cargo: returns FAILURE whenever
# there is nothing to answer, so the hunt job runs untouched.
const Steering = preload("res://scripts/ai/steering.gd")
const Hail = preload("res://scripts/comms/hail.gd")

# My max_speed must exceed the threat's demonstrated capability by THIS factor
# before running is the better play. Cargo uses 1.3 (1.6 against shown pirate
# colours). An outlaw accepts a thinner margin because the downside of stopping
# is categorically worse than a hauler's.
#
# STATIC so a sim can sweep it without touching authored ship data -- same shape
# as ThreatResponseLeaf.sos_chance. This is THE dial for "how often do patrols
# actually stop anyone", and it is meant to be swept once stops exist at all.
static var run_speed_ratio: float = 1.05

const RUN_SPEED := 900.0

func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	# Same demonstrated-capability read as ThreatResponseLeaf, and for the same
	# reason: a patrol decelerates to hail range before demanding, so its
	# INSTANTANEOUS speed at demand time reads as nearly stationary and every
	# subject would "outrun" it. Peak observed over the encounter is what the
	# subject has actually watched the thing do.
	_update_contact_peaks(actor, blackboard)

	if not actor.compelled_stop.is_empty():
		blackboard.set_value("was_held", true)
		return SUCCESS # held -- the ship-level throttle override owns motion
	elif blackboard.get_value("was_held", false):
		blackboard.erase_value("was_held")

	# An active RUN in progress: keep running while the issuer's track is fresh,
	# and re-check every tick whether the race is still winnable (M52a's
	# overtaken rule -- a pirate that watched a patrol close the gap should give
	# up rather than burn fuel on a race already lost).
	if blackboard.has_value("flee_issuer_iid"):
		var issuer_iid: int = blackboard.get_value("flee_issuer_iid")
		var c: Dictionary = actor.active_contacts.get(Ship.track_id(issuer_iid), {})
		if c.is_empty() or Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
			blackboard.erase_value("flee_issuer_iid")
			return FAILURE # lost them -- back to the hunt
		var peaks: Dictionary = blackboard.get_value("contact_peaks", {})
		if actor.max_speed <= peaks.get(issuer_iid, 0.0) * run_speed_ratio:
			blackboard.erase_value("flee_issuer_iid")
			if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
				print("[Outlaw] %s: run lost -- heaving to" % actor.debug_label())
			if actor.has_method("engage_dead_stop"):
				actor.engage_dead_stop()
			return SUCCESS
		_run_from(actor, c.get("pos", actor.position))
		return SUCCESS

	var demand: Dictionary = actor.pending_demand
	if demand.get("rung", "") != Hail.RUNG_STOP:
		return FAILURE

	# Decide ONCE per incident, keyed on the demand's own seq. A pending_demand
	# dict already acted on must not re-decide every tick; a genuinely new demand
	# (different seq, even from the same issuer) re-triggers the call.
	var demand_seq: int = demand.get("seq", -1)
	if blackboard.get_value("last_decided_seq", -1) == demand_seq:
		return FAILURE
	blackboard.set_value("last_decided_seq", demand_seq)

	var issuer_iid2: int = demand.get("sender_iid", -1)
	var threat_pos: Vector2 = demand.get("sender_pos", actor.position)
	var threat_speed: float = 0.0
	var trk: String = Ship.track_id(issuer_iid2)
	if actor.active_contacts.has(trk):
		var ic: Dictionary = actor.active_contacts[trk]
		threat_speed = ic.get("vel", Vector2.ZERO).length()
		threat_pos = ic.get("pos", threat_pos)
	var peaks2: Dictionary = blackboard.get_value("contact_peaks", {})
	var capability: float = maxf(threat_speed, peaks2.get(issuer_iid2, 0.0))

	var will_run: bool = actor.max_speed > capability * run_speed_ratio
	if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
		print("[Outlaw] %s: %s (my max %.0f vs patrol capability %.0f x%.2f)" % [
			actor.debug_label(), "RUN" if will_run else "HEAVE TO",
			actor.max_speed, capability, run_speed_ratio])

	if will_run:
		blackboard.set_value("flee_issuer_iid", issuer_iid2)
		_run_from(actor, threat_pos)
	elif actor.has_method("engage_dead_stop"):
		# engage_dead_stop broadcasts ACKNOWLEDGE itself, which is what stamps
		# `complied_stop` on the patrol's contact -- the thing step_demand_stop
		# waits for, and the thing EngagementProbe scores as a STOP.
		actor.engage_dead_stop()
	return SUCCESS

# Per-contact peak observed speed, keyed by true instance id, held only while
# the track stays fresh. Same routine as ThreatResponseLeaf's; duplicated rather
# than shared because the two leaves keep separate blackboards and neither
# should be able to perturb the other's encounter memory.
func _update_contact_peaks(actor: Node, blackboard) -> void:
	var peaks: Dictionary = blackboard.get_value("contact_peaks", {})
	var seen := {}
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		if Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
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
	actor.apply_control_input(0.0, RUN_SPEED, avoided.angle(), 1, 1)
