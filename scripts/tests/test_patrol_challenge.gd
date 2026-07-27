extends Node

# M49 -- patrol DEMAND(IDENTIFY) flow (design_ideas/comms_verbs.md's
# "Patrol" policy, challenge_leaf.gd). A dark (non-reporting) vessel contact
# inside a station's controlled space gets challenged; relighting its
# transponder within the ~20s window resolves the challenge quietly and the
# contact reads NEUTRAL; a dark contact OUTSIDE any zone is never challenged
# at all. No standing change from the challenge itself (IDENTIFY is never
# coercion, per comms_verbs.md's "one rule that keys on the rung"), and no
# shooting (an UNREPORTED contact was never a valid Engage target anyway).
#
# `await get_tree().physics_frame` live-ship style, same as test_drift_
# residents.gd/test_honored_stop.gd -- settle loops with generous timeouts,
# never exact frames (Godot 2D physics/timing isn't bit-deterministic
# run-to-run, CLAUDE.md).
#
# The "station" here is a plain Ship with port_zone hand-set directly (a
# lighter stand-in than a full MediumStation -- challenge_leaf's controlled-
# space gate only calls get_port_zone()/reads .position, both of which any
# Ship provides; the milestone doesn't need the docking-bay machinery a real
# station hull drags in).

const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var ship = Frigate.new()
	ship.name = ship_name
	ship.owner_id = owner
	ship.iff_tags = tags
	ship.position = pos
	main_node.add_child(ship)
	spawned.append(ship)
	return ship

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func setup(main) -> void:
	main_node = main
	print("Starting Patrol Challenge (M49) Tests")

	# A zone-declaring stand-in "station" (see header) -- radius 8000, centered
	# at the origin.
	var station = _make_ship("Station", 600, Vector2.ZERO, ["TEAM_CONTROL"])
	station.port_zone = {"radius": 8000.0, "authority": "TestControl"}

	var patrol = _make_ship("Patrol", 601, Vector2(3000, 2000), ["TEAM_PATROL"])
	var patrol_tree: Node = AITreeFactory.build_patrol()
	patrol.add_child(patrol_tree)

	# Dark (transponder off), well INSIDE the station's 8000u zone.
	var dark_ship = _make_ship("DarkInZone", 602, Vector2(3000, 0), ["TEAM_DARK"])
	dark_ship.set_transponder_active(false)

	# Dark, but OUTSIDE any zone (>8000 from the station, still in the
	# patrol's sensor + comms range) -- must never be challenged.
	var outside_ship = _make_ship("DarkOutsideZone", 603, Vector2(20000, 2000), ["TEAM_DARK2"])
	outside_ship.set_transponder_active(false)

	var ammo_before: int = 0
	for w in patrol.get_components_by_type("weapons"):
		ammo_before += int(w.get("ammo", 0))

	# --- Phase 1: the in-zone dark ship gets DEMAND(IDENTIFY) within a few
	# seconds; no standing change; no shooting. ---
	var challenged := false
	for i in range(600): # up to 10s (30-tick scan gate + sensor correlation)
		await main_node.get_tree().physics_frame
		if dark_ship.pending_demand.get("rung", "") == Hail.RUNG_IDENTIFY and dark_ship.pending_demand.get("sender_iid", -1) == patrol.get_instance_id():
			challenged = true
			break
	_assert(challenged, "in-zone dark contact gets a DEMAND(IDENTIFY) from the patrol within the timeout (pending_demand=%s)" % str(dark_ship.pending_demand))

	var patrol_view: Dictionary = _find_contact(patrol, dark_ship)
	_assert(patrol_view.get("standing", "") == Standing.UNREPORTED,
		"IDENTIFY never changes standing -- patrol still reads the dark ship as UNREPORTED (got '%s')" % patrol_view.get("standing", ""))

	var ammo_after: int = 0
	for w in patrol.get_components_by_type("weapons"):
		ammo_after += int(w.get("ammo", 0))
	_assert(ammo_after == ammo_before, "patrol never fired on the challenged contact (ammo unchanged)")

	# --- Phase 2: relight within the window -> resolved, reads NEUTRAL. ---
	dark_ship.set_transponder_active(true)

	var resolved := false
	var reads_neutral := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		var bb = patrol_tree.blackboard
		if bb.get_value("challenge_resolved", {}).has(_trk_for(dark_ship)):
			resolved = true
		var pv: Dictionary = _find_contact(patrol, dark_ship)
		if pv.get("standing", "") == Standing.NEUTRAL:
			reads_neutral = true
		if resolved and reads_neutral:
			break
	_assert(resolved, "relighting within the window marks the challenge resolved on the patrol's own blackboard")
	_assert(reads_neutral, "the relit contact reads NEUTRAL to the patrol")

	# --- Phase 3: a dark ship outside any zone is never challenged. ---
	var never_challenged: bool = outside_ship.pending_demand.is_empty()
	var bb_final = patrol_tree.blackboard
	var outside_trk: String = _trk_for(outside_ship)
	var was_tracked_as_challenge: bool = (bb_final.get_value("challenged", {}).has(outside_trk)
		or bb_final.get_value("challenge_resolved", {}).has(outside_trk)
		or bb_final.get_value("challenge_ignored", {}).has(outside_trk))
	_assert(never_challenged and not was_tracked_as_challenge,
		"a dark contact outside any controlled zone is never challenged (pending_demand=%s, tracked_by_challenge=%s)" % [str(outside_ship.pending_demand), was_tracked_as_challenge])

	await _phase_left_comms_range(station, patrol, patrol_tree)
	await _phase_ignored_in_range(station, patrol, patrol_tree)

	_finish()

func _noid_warrants(observer: Node) -> int:
	var n: int = 0
	for key in observer.warrants:
		if observer.warrants[key].get("offense", "") == Standing.OFF_NO_ID:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Phase 4 -- REGRESSION GUARD for the challenge-expiry comms-range check
# (commit f6cbaeb; campaign playtest A1/A3, design_ideas/2026-07-26-campaign_
# playtest.md).
#
# A hull is challenged legitimately inside the zone and then simply LEAVES, as
# anyone would. The window lapses while it is out of comms range. Before the
# fix, ChallengeLeaf's expiry path posted a NO_ID warrant anyway -- convicting
# it of refusing to answer a question the patrol could no longer hear the
# answer to. compute_standing then read that warrant as HOSTILE and the home
# station opened fire. "If you move, the station shoots you" was literal.
#
# THE BAND IS THE WHOLE TEST. Comms reach is deliberately shorter than sensor
# reach (test_patrol_id_read measures both), and parking the subject between
# the two is what makes this guard non-vacuous: it stays a live, UNREPORTED
# contact the patrol can SEE, so the buggy code would post, and only the range
# check stops it. Teleport it out of SENSOR range too and the track is dropped
# entirely -- standing goes "" rather than UNREPORTED, the old code would not
# have posted either, and the test passes against the very bug it exists to
# catch.
#
# The band is built by giving the SUBJECT a weak radio rather than by flying it
# far away, because a link is capped by the weaker of the two sets
# (ship.gd's datalink loop: `link_range = min(self_comms, their_comms)`, and
# ChallengeLeaf's expiry check mirrors it exactly). Two Frigates both carry
# 30000u radios and 40000u sensors, so the natural band sits past 30000 -- and
# out there a DARK hull is not reliably detected at all, which is exactly the
# vacuum described above. Capping the subject's own radio moves the same band
# in to a distance where the track is solid, and exercises the identical
# min()-of-two-ranges code path. A small hull with a cheap radio produces this
# situation for real; nothing here is contrived for the test.
const SUBJECT_COMMS_RANGE := 8000.0
const BAND_DISTANCE := 15000.0   # > the 8000 link, well inside 40000 sensor reach

func _phase_left_comms_range(station: Node, patrol: Node, patrol_tree: Node) -> void:
	print("--- Phase 4: challenged, then leaves comms range -> NO warrant ---")
	var noid_before: int = _noid_warrants(patrol)

	var leaver = _make_ship("Leaver", 604, Vector2(2000, 500), ["TEAM_LEAVER"])
	leaver.set_transponder_active(false)
	for c in leaver.get_components_by_type("comms"):
		c["range"] = SUBJECT_COMMS_RANGE
	_assert(leaver.get_comms_range() == SUBJECT_COMMS_RANGE,
		"phase 4 (setup): the leaver carries a short-range radio (%.0fu), so the link caps well inside sensor reach" % SUBJECT_COMMS_RANGE)

	var trk: String = _trk_for(leaver)
	var challenged := false
	for i in range(900):
		await main_node.get_tree().physics_frame
		if patrol_tree.blackboard.get_value("challenged", {}).has(trk):
			challenged = true
			break
	_assert(challenged, "phase 4: the leaver is challenged while in-zone (setup for the guard)")

	# Out past comms, still inside sensor reach -- measured from the patrol's
	# CURRENT position, since the patrol is free to have moved.
	var far_pos: Vector2 = patrol.position + Vector2.RIGHT * BAND_DISTANCE
	# Wake-safe teleport (CLAUDE.md's sleeping-RigidBody2D gotcha): a settled
	# body's collision shape does not follow a plain `.position =`, and the
	# patrol's sensor queries would keep finding it at the OLD spot forever.
	var xform: Transform2D = leaver.global_transform
	xform.origin = far_pos
	PhysicsServer2D.body_set_state(leaver.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	leaver.position = far_pos
	leaver.linear_velocity = Vector2.ZERO
	leaver.sleeping = false

	# Outlast the challenge window (1200 frames) with room to spare.
	for i in range(1500):
		await main_node.get_tree().physics_frame

	var still_open: bool = patrol_tree.blackboard.get_value("challenged", {}).has(trk)
	_assert(not still_open, "phase 4: the challenge window closed (entry voided, not left pending)")

	# Non-vacuity: the patrol must still SEE it, and still read it UNREPORTED.
	# If either fails, the guard proves nothing and says so.
	var view: Dictionary = _find_contact(patrol, leaver)
	var gap: float = patrol.position.distance_to(leaver.position)
	_assert(not view.is_empty(),
		"phase 4 (non-vacuity): the leaver is STILL a live contact at %.0fu -- seen but unheard, the band this guard needs" % gap)
	_assert(view.get("standing", "") == Standing.UNREPORTED,
		"phase 4 (non-vacuity): and still reads UNREPORTED (got '%s') -- so the old code WOULD have posted" % view.get("standing", ""))

	_assert(_noid_warrants(patrol) == noid_before,
		"phase 4: NO NO_ID warrant against a hull that was out of comms range when the window lapsed -- silence we cannot hear is not evidence")

	_free_ship(leaver)

# ---------------------------------------------------------------------------
# Phase 5 -- the positive control for phase 4, and the LIVE proof of NO_ID
# self-resolution.
#
# Same challenge, but the subject stays in comms range and stays dark. That is
# a real refusal, so the warrant SHOULD land -- without this, phase 4 would
# also pass against a build that had simply stopped posting NO_ID at all.
#
# Then it lights its transponder. warrants.md says NO_ID "resolves itself the
# moment the subject reports a transponder... no separate revocation path to
# build for it," and test_warrant_identity_change proves that at the
# compute_standing level. What it cannot prove is that the LIVE path agrees:
# the transponder has to reach the patrol over the datalink relay, the warrant
# index has to be rebuilt, and the fusion tick has to recompute this track's
# standing. That chain is what the enforcement model leans on -- NO_ID is
# supposed to self-resolve most of the time -- so it is worth a live test.
# ---------------------------------------------------------------------------
func _phase_ignored_in_range(station: Node, patrol: Node, patrol_tree: Node) -> void:
	print("--- Phase 5: challenged in range and ignored -> warrant; then relight -> self-resolves ---")
	var noid_before: int = _noid_warrants(patrol)

	var ignorer = _make_ship("Ignorer", 605, Vector2(2500, 1200), ["TEAM_IGNORER"])
	ignorer.set_transponder_active(false)

	var trk: String = _trk_for(ignorer)
	var challenged := false
	for i in range(900):
		await main_node.get_tree().physics_frame
		if patrol_tree.blackboard.get_value("challenged", {}).has(trk):
			challenged = true
			break
	_assert(challenged, "phase 5: the ignorer is challenged while in-zone")

	var posted := false
	for i in range(1500):
		await main_node.get_tree().physics_frame
		if _noid_warrants(patrol) > noid_before:
			posted = true
			break
	_assert(posted, "phase 5: ignoring the challenge IN RANGE does post a NO_ID warrant (the mechanism still works -- phase 4's control)")

	# The warrant colors the contact CAUTION, not HOSTILE -- NO_ID is
	# caution-grade, which is the playtest fix one layer upstream of the
	# targeting gate: this hull never goes red, so nothing ever considers it a
	# target in the first place.
	#
	# Asserted on the REASON, not the tier. This subject is dark, so it already
	# reads caution-tier for an unrelated cause ("not reporting") and a tier
	# check here would pass whether or not the warrant existed at all. The
	# reason flipping to the warrant's own text is the only proof the warrant is
	# what is being read.
	var caution_reason := ""
	for i in range(300):
		await main_node.get_tree().physics_frame
		var pv: Dictionary = _find_contact(patrol, ignorer)
		if "identify challenge" in pv.get("standing_reason", ""):
			caution_reason = pv.get("standing_reason", "")
			break
	_assert(caution_reason != "",
		"phase 5: the warrant colors the contact CAUTION with the warrant's own reason (got '%s')"
			% _find_contact(patrol, ignorer).get("standing_reason", ""))
	_assert(_find_contact(patrol, ignorer).get("standing", "") != Standing.HOSTILE,
		"phase 5: and never HOSTILE -- a NO_ID hull is not an enemy determination")

	# Now light up. The subject_key gap IS the resolution mechanism: the warrant
	# was filed under `sig:` (a NO_ID subject has no claimed name by
	# definition), lookups now ask for `name:`, and compute_standing's signature
	# fallback deliberately skips offenses marked self_resolves_on_id.
	ignorer.set_transponder_active(true)
	var resolved := false
	for i in range(600):
		await main_node.get_tree().physics_frame
		if _find_contact(patrol, ignorer).get("standing", "") == Standing.NEUTRAL:
			resolved = true
			break
	_assert(resolved,
		"phase 5: lighting the transponder SELF-RESOLVES the NO_ID live -- back to NEUTRAL with no revocation (got '%s')"
			% _find_contact(patrol, ignorer).get("standing", ""))

	_free_ship(ignorer)

func _free_ship(s: Node) -> void:
	spawned.erase(s)
	if is_instance_valid(s):
		s.queue_free()

func _trk_for(ship: Node) -> String:
	return "TRK-%03d" % (abs(ship.get_instance_id()) % 1000)

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_patrol_challenge <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_patrol_challenge <<<")
		get_tree().quit(1)
