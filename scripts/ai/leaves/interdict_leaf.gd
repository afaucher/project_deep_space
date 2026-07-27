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

	var refused: Dictionary = blackboard.get_value("interdict_refused", {})

	# PRIORITY: red threats, then SOS, then yellow. Interdict/JobRunner sit
	# ABOVE Engage and SOSResponse in the tree, because a demand job used to be
	# a red matter by definition -- "demand before weapons" against the very
	# contact Engage would otherwise shoot. Once caution-grade warrants became
	# interdictable that stopped being true, and a NO_ID chase would pre-empt
	# both a firefight and a distress call: JobRunner claims every tick while a
	# job runs, and DEMAND_STOP's INTERCEPT patience is 25s on top of the
	# intercept itself.
	#
	# Rather than reorder the tree (one assignment slot, one runner -- moving
	# this leaf below SOSResponse would not help, because the RUNNER above
	# Engage still executes whatever got assigned), the yellow work yields
	# directly: it is abandoned when outranked, and not started while outranked.
	#
	# The refusal entry is CLEARED on abandonment, deliberately. It normally
	# means "we already demanded this hull, don't loop" -- but a demand we broke
	# off to go deal with a pirate was never actually pressed, so keeping it
	# would retire the interdiction permanently (the entry only clears when the
	# contact drops out of tracking entirely). Yielding must not be indistinct
	# from being refused.
	if not actor.assignment.is_empty():
		var running: Dictionary = actor.assignment
		if running.get("interdict_tier", "") == Standing.CAUTION and _outranked(actor):
			var yielded_iid: int = running.get("victim_iid", -1)
			actor.assignment = {}
			refused.erase(yielded_iid)
			blackboard.set_value("interdict_refused", refused)
		# Either way: a job is (or was just) running -- never stomp it here.
		return FAILURE

	# No working radio -- can't send a demand at all (Hail.send silently
	# no-ops with no seq), so a job would just sit there un-completable,
	# permanently blocking Engage below via JobRunner instead of actually
	# warning anyone (a comms-less hull, e.g. the mine hull -- see mine.gd's
	# header comment -- has no legal way to hail in the first place). Same
	# gate ChallengeLeaf already uses for the identical reason.
	if actor.get_comms_range() <= 0.0:
		return FAILURE

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
	var target_w: Dictionary = {}
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		# INTERDICTION FOLLOWS THE WARRANT, ENGAGEMENT FOLLOWS THE STANDING.
		# This used to gate on HOSTILE alone, which was right when every
		# enforceable warrant read HOSTILE. Now that a warrant can be
		# caution-grade (Standing's offense-table `standing` column), gating on
		# HOSTILE would silently drop the entire patrol response to NO_ID --
		# the offense the ladder exists for -- leaving it with no consequence
		# but the docking denial.
		#
		# So: demand a stop from anyone we hold an enforceable warrant against
		# at ANY tier, and separately let AcquireTargetLeaf decide about
		# weapons. That is the ladder the playtest asked for -- a NO_ID hull
		# gets intercepted and hailed, and never shot at.
		#
		# The warrant requirement is load-bearing, not incidental: CAUTION is
		# also what an ordinary non-reporting contact reads, and interdicting on
		# the tier alone would have every patrol demanding a stop from every
		# unidentified hull in the cluster.
		var c_claimed: String = actor.active_transponders.get(c.get("instance_id", -1), {}).get("name", "")
		var c_w: Dictionary = actor.warrant_index.get(
			Standing.subject_key(c_claimed, c.get("signature", {})), {})
		if c.get("standing", "") != Standing.HOSTILE and c_w.is_empty():
			continue
		# Don't START yellow work while there are bigger fish -- the other half
		# of the priority rule above. `continue`, not `return`: a HOSTILE-grade
		# candidate further down the list is still worth interdicting (that IS
		# the red response), only the caution-grade ones defer.
		if _tier_of(c, c_w) == Standing.CAUTION and _outranked(actor):
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
		if Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
			continue
		var iid: int = c.get("instance_id", -1)
		if iid == -1 or refused.has(iid):
			continue
		target_iid = iid
		target_c = c
		target_w = c_w
		break

	blackboard.set_value("interdict_refused", refused)

	if target_iid == -1:
		return FAILURE

	# Already resolved during the scan above (the warrant is now part of the
	# selection rule, not just a patience lookup).
	var w: Dictionary = target_w
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
		# What this job is WORTH, so the priority rule at the top of tick() can
		# recognise its own yellow work and yield it. Read nowhere else.
		"interdict_tier": _tier_of(target_c, w),
	}
	actor.assignment = job

	# Stamp refusal memory NOW (assign-once-per-standing-color), not on the
	# eventual abort -- see header.
	refused[target_iid] = true
	blackboard.set_value("interdict_refused", refused)

	return FAILURE

# What a candidate is worth: HOSTILE if we have determined it is an enemy,
# otherwise the tier its warrant carries. A contact that is HOSTILE with no
# warrant behind it (declared enemy flag, or the one-tick eager cache stamp)
# is red work, not yellow.
func _tier_of(contact: Dictionary, warrant: Dictionary) -> String:
	if contact.get("standing", "") == Standing.HOSTILE:
		return Standing.HOSTILE
	if warrant.is_empty():
		return Standing.HOSTILE
	return Standing.standing_for_offense(warrant.get("offense", ""))

# Is there something more urgent than yellow work right now -- a red threat or
# a live distress call? Mirrors SOSResponseLeaf's own freshness rules so the
# two leaves agree about what counts (a stale track is a guess about where a
# ship USED to be, and a hulk is nobody's emergency).
func _outranked(actor: Node) -> bool:
	for c_id in actor.active_contacts:
		var c: Dictionary = actor.active_contacts[c_id]
		# A distress call counts while the contact merely EXISTS -- no
		# staleness filter, deliberately. SOSResponseLeaf chases any live
		# DISTRESS CALL and lets CONTACT_TIMEOUT prune it; filtering here on
		# FIRE_STALENESS_MAX (a fire-discipline constant, much shorter) would
		# leave a window where this leaf holds its yellow job because the SOS
		# looks stale while SOSResponseLeaf would still be flying to it. The
		# two must agree or the patrol neither yields nor responds.
		if c.get("classification", "") == "DISTRESS CALL":
			return true
		# Hostiles use the same freshness rule SOSResponseLeaf's own
		# _has_fresh_hostile applies, for the same reason: a stale track is a
		# guess about where a ship USED to be, and a hulk is not a threat.
		if c.get("standing", "") != Standing.HOSTILE:
			continue
		if c.get("classification", "") == "WRECKAGE":
			continue
		if Ship.contact_age(c) > actor.FIRE_STALENESS_MAX:
			continue
		return true
	return false
