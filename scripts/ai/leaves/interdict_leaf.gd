extends "res://addons/beehave/nodes/leaves/action.gd"

# M52 -- patrol/station interdiction (implementation_plans/
# m52_patrol_interdiction.md item 1): "demand surrender BEFORE weapons." The
# 2026-07-20 playtest's root cause -- build_patrol/build_station went straight
# from AcquireTarget to FireOpportunity, no demand step in between. Inserted
# in both trees BETWEEN Disengage and Engage (ai_tree_factory.gd): scans
# active_contacts for a fresh HOSTILE contact this actor hasn't already
# demanded-and-been-refused-by (see the refusal-memory blackboard below),
# looks up its matching warrant (Standing.subject_key + actor.warrant_index)
# to pick DEMAND_STOP's patience via Standing.response_class, and assigns a
# 2-step [INTERCEPT, DEMAND_STOP] job onto actor.assignment (the same hand-
# built job shape M52c's test fixtures use -- SELECT_VICTIM is irrelevant
# here, the target is already known via standing/warrant).
#
# Always returns FAILURE (cheap side-effect leaf, same idiom as ChallengeLeaf/
# BroadcastTransponderLeaf) -- JobRunnerLeaf, next in the selector, picks up
# the freshly-assigned job on the SAME tick and starts ticking it (returns
# SUCCESS), which is what actually pre-empts Engage below it: while the job
# runs, JobRunner claims every tick and Engage never gets evaluated. No new
# gating needed on Engage itself.
#
# Refusal memory: without something remembering "we already demanded this iid
# and got refused," this leaf would re-trigger the instant assignment clears
# (HOSTILE persists, complied_stop is still false) and re-demand the SAME
# target forever, never reaching Engage. Bookkeeping choice (mirrors the
# frame-stamped-cooldown SHAPE of JobSteps._blacklist_victim, but keyed only
# by presence, not a timed expiry -- see the plan doc's "simplest correct
# rule"): a plain iid -> true dict on the tree's own blackboard, stamped the
# instant a demand is ASSIGNED (not waiting to observe the eventual abort --
# assign-once-per-standing-color is sufficient and simpler). An iid's entry
# is cleared the moment that contact drops out of active_contacts entirely
# (died, or dead-reckoned past CONTACT_TIMEOUT and pruned) -- so a LATER,
# unrelated HOSTILE spell against the same ship (e.g. a new warrant after a
# long gap, once the track was re-acquired fresh) gets a fresh demand.
const Standing = preload("res://scripts/combat/standing.gd")

# RESPONSE_MAX -- "shoot-on-sight-ish, but still one demand" per warrants.md's
# response-level framing. RESPONSE_INTERCEPT matches JobSteps' own
# step_demand_stop default (25.0) exactly, so a HOSTILE contact with no
# matching warrant at all (e.g. via known_enemy_flags) gets the same patience
# as an INTERCEPT-class offense.
const PATIENCE_MAX := 8.0
const PATIENCE_INTERCEPT := 25.0

func tick(actor: Node, blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE

	# A demand job (or any other assignment) is already running -- don't
	# stomp it.
	if not actor.assignment.is_empty():
		return FAILURE

	# No working radio -- can't send a demand at all (Hail.send silently
	# no-ops with no seq), so a job would just sit there un-completable,
	# permanently blocking Engage below via JobRunner instead of actually
	# warning anyone (a comms-less hull, e.g. the mine hull -- see mine.gd's
	# header comment -- has no legal way to hail in the first place). Same
	# gate ChallengeLeaf already uses for the identical reason.
	if actor.get_comms_range() <= 0.0:
		return FAILURE

	var refused: Dictionary = blackboard.get_value("interdict_refused", {})

	# Prune refusal memory for iids no longer tracked AT ALL (see header) --
	# this runs every tick regardless of whether a fresh target is found below,
	# so the memory stays honest even during ticks this leaf finds nothing.
	var seen_iids: Dictionary = {}
	for c_id in actor.active_contacts:
		var iid: int = actor.active_contacts[c_id].get("instance_id", -1)
		if iid != -1:
			seen_iids[iid] = true
	var to_forget: Array = []
	for iid in refused:
		if not seen_iids.has(iid):
			to_forget.append(iid)
	for iid in to_forget:
		refused.erase(iid)

	var target_iid := -1
	var target_c: Dictionary = {}
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		if c.get("standing", "") != Standing.HOSTILE:
			continue
		# A dead ship's classification flips to WRECKAGE but Standing.HOSTILE
		# is sticky and never clears on death -- nothing to demand from a hulk.
		if c.get("classification", "") == "WRECKAGE":
			continue
		# M49 honor rule: a contact already holding station under a demand is
		# off the table regardless of standing (AcquireTargetLeaf mirrors this
		# for the same reason).
		if c.get("complied_stop", false):
			continue
		if c.get("last_seen_timer", 999.0) > actor.FIRE_STALENESS_MAX:
			continue
		var iid: int = c.get("instance_id", -1)
		if iid == -1 or refused.has(iid):
			continue
		target_iid = iid
		target_c = c
		break

	blackboard.set_value("interdict_refused", refused)

	if target_iid == -1:
		return FAILURE

	var claimed_name: String = actor.active_transponders.get(target_iid, {}).get("name", "")
	var skey: String = Standing.subject_key(claimed_name, target_c.get("signature", {}))
	var w: Dictionary = actor.warrant_index.get(skey, {})
	var patience: float = PATIENCE_INTERCEPT
	if not w.is_empty() and Standing.response_class(w.get("offense", "")) == Standing.RESPONSE_MAX:
		patience = PATIENCE_MAX

	var job := {
		"steps": [
			{"verb": "INTERCEPT"},
			{"verb": "DEMAND_STOP", "show_colors": false, "patience": patience, "on_abort": ""},
		],
		"current": 0,
		"victim_iid": target_iid,
	}
	actor.assignment = job

	# Stamp refusal memory NOW (assign-once-per-standing-color), not on the
	# eventual abort -- see header.
	refused[target_iid] = true
	blackboard.set_value("interdict_refused", refused)

	return FAILURE
