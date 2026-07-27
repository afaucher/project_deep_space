extends Node

# M48 -- pure-rules unit pass over Standing.compute_standing + wanted names +
# severity ordering. No physics, no scene tree simulation (model: test_
# classifiers.gd's table style). The observer needs real .iff_tags/
# .known_enemy_flags fields, so we use bare Ship instances (never added to
# the tree, never _ready()'d -- compute_standing only reads those two
# fields) rather than a hand-rolled duck-typed double.

const Ship = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")

func _make_observer(tags: Array, enemy_flags: Array = [Standing.FLAG_PIRATE]) -> Ship:
	var o = Ship.new()
	o.iff_tags = tags
	o.known_enemy_flags = enemy_flags
	return o

func setup(_main) -> void:
	print("Test test_standing_rules initialized.")
	Standing.reset()

	var passed = 0
	var failed = 0

	# --- compute_standing precedence table --------------------------------
	# Each case: [contact, transponder, observer, expected_standing, reason_substr_or_empty]
	var observer_a := _make_observer(["TEAM_A"])

	var cases = []

	# 0. Vessels only: non-vessel classification -> "" regardless of anything else.
	cases.append([
		{"classification": "WRECKAGE", "signature": {}, "standing": "HOSTILE", "standing_reason": "fired on us"},
		{}, observer_a, "", ""
	])

	# 1. Crypto IFF overlap -> FRIENDLY, beats everything else.
	cases.append([
		{"classification": "FRIENDLY VESSEL", "signature": {"iff_tags": ["TEAM_A"]}},
		{}, observer_a, Standing.FRIENDLY, "IFF"
	])

	# 2. M52b -- an OPEN, enforceable warrant matching the subject -> HOSTILE.
	# Replaces the old "sticky HOSTILE stays HOSTILE" case: the disposition
	# is now DERIVED from observer.warrant_index (rebuilt each fusion tick
	# from the observer's own `warrants` store), not a bit cached on the
	# contact dict. Dedicated observer (not observer_a) since warrant_index
	# is stateful and this table evaluates every case against the SAME
	# observer object after all cases are built.
	var observer_warrant := _make_observer(["TEAM_WARR"])
	observer_warrant.warrant_index = {
		Standing.subject_key("Raider2", {}): Standing.make_warrant(
			Standing.OFF_SUSTAINED_ASSAULT, {"claimed_name": "Raider2"}, {"iid": 1, "name": "Witness"}, "", "k-case2", "sustained attack on target")
	}
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Raider2", "flag": ""}, observer_warrant, Standing.HOSTILE, "sustained attack"
	])

	# 3. Known-enemy flag -> HOSTILE ("flying <flag>").
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Raider", "flag": Standing.FLAG_PIRATE}, observer_a, Standing.HOSTILE, "flying"
	])

	# 4. Suspicion is not a standing -- a reporting ship stays NEUTRAL no matter
	# what anyone thinks of the name. (This case used to seed a wanted-names
	# entry first; that registry was deleted 2026-07-26 as dead ambient global
	# state -- see the note further down. The assertion it guards is unchanged
	# and still worth keeping: a name is cheap talk and never moves standing.)
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Mule", "flag": ""}, observer_a, Standing.NEUTRAL, "reporting clean"
	])

	# 6. Transponder reporting a clean (non-wanted) name -> NEUTRAL.
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Trader One", "flag": ""}, observer_a, Standing.NEUTRAL, ""
	])

	# 7. No transponder received at all -> UNREPORTED ("not reporting").
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{}, observer_a, Standing.UNREPORTED, "not reporting"
	])

	# 8. Precedence: crypto beats even a matching warrant (order 1 before 2).
	var observer_warrant_crypto := _make_observer(["TEAM_A"])
	observer_warrant_crypto.warrant_index = {
		Standing.subject_key("Ally", {}): Standing.make_warrant(
			Standing.OFF_ASSAULT, {"claimed_name": "Ally"}, {"iid": 1, "name": "Witness"}, "", "k-case8", "warrant test reason")
	}
	cases.append([
		{"classification": "FRIENDLY VESSEL", "signature": {"iff_tags": ["TEAM_A"]}},
		{"name": "Ally", "flag": ""}, observer_warrant_crypto, Standing.FRIENDLY, ""
	])

	# 9. Precedence: a HOSTILE-GRADE warrant beats the known-enemy flag check
	# (order 2 before 3) -- both land on HOSTILE, so the REASON text is what
	# proves which rule actually fired (the warrant's, not "flying <flag>").
	#
	# The offense here used to be ARMED_THREAT. It has to be a hostile-grade one
	# now: a warrant no longer implies HOSTILE, and a caution-grade warrant
	# deliberately does NOT short-circuit this rule (case 9b below).
	var observer_warrant_precedence := _make_observer(["TEAM_A"])
	observer_warrant_precedence.warrant_index = {
		Standing.subject_key("Raider3", {}): Standing.make_warrant(
			Standing.OFF_ARMED_ROBBERY, {"claimed_name": "Raider3"}, {"iid": 1, "name": "Witness"}, "", "k-case9", "warrant precedence reason")
	}
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Raider3", "flag": Standing.FLAG_PIRATE}, observer_warrant_precedence, Standing.HOSTILE, "warrant precedence reason"
	])

	# 9b. The other half of that precedence: a CAUTION-grade warrant must not
	# MASK the enemy-flag rule. A pirate who has also picked up a NO_ID is still
	# red -- reading yellow here would be a strictly worse bug than the flat
	# HOSTILE this tier column was added to fix.
	var observer_caution_no_mask := _make_observer(["TEAM_A"])
	observer_caution_no_mask.warrant_index = {
		Standing.subject_key("Raider4", {}): Standing.make_warrant(
			Standing.OFF_NO_ID, {"claimed_name": "Raider4"}, {"iid": 1, "name": "Witness"}, "", "k-case9b", "ignored identify challenge")
	}
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Raider4", "flag": Standing.FLAG_PIRATE}, observer_caution_no_mask, Standing.HOSTILE, "flying"
	])

	# 9c. But a caution-grade warrant still outranks NEUTRAL -- otherwise a
	# warrant for a minor offense would be invisible on a hull reporting clean.
	var observer_caution_over_neutral := _make_observer(["TEAM_A"])
	observer_caution_over_neutral.warrant_index = {
		Standing.subject_key("Quiet One", {}): Standing.make_warrant(
			Standing.OFF_NO_ID, {"claimed_name": "Quiet One"}, {"iid": 1, "name": "Witness"}, "", "k-case9c", "ignored identify challenge")
	}
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Quiet One", "flag": Standing.FLAG_CIVILIAN}, observer_caution_over_neutral, Standing.CAUTION, "ignored identify challenge"
	])

	for i in range(cases.size()):
		var contact = cases[i][0]
		var transponder = cases[i][1]
		var observer = cases[i][2]
		var expected_standing = cases[i][3]
		var expected_reason_substr = cases[i][4]

		var result = Standing.compute_standing(contact, transponder, observer)
		var ok = result.get("standing", "<<missing>>") == expected_standing
		if ok and expected_reason_substr != "":
			ok = expected_reason_substr in result.get("reason", "")

		if ok:
			passed += 1
		else:
			failed += 1
			printerr("[TEST FAILED] Case ", i, " expected standing=", expected_standing,
				" reason~='", expected_reason_substr, "' got=", result)

	# --- wanted names: REMOVED 2026-07-26 -------------------------------------
	# Standing.wanted_names / add_wanted / is_wanted are gone. The registry was
	# written by three call sites and read by NONE outside these tests -- the
	# cases here were the only thing keeping it alive, testing a mechanism no
	# production code consulted. It was also an ambient process-global set of
	# hostile names with no expiry, no per-observer scoping, no comms gating
	# and no authority check, which is precisely the "ambient global truth"
	# design_ideas/warrants.md set out to replace with per-observer warrants.
	# See design_ideas/2026-07-26-warrant_stickiness_audit.md, mismatch 3.
	Standing.reset()

	# --- severity ordering ---------------------------------------------------
	var order = ["", Standing.NEUTRAL, Standing.UNREPORTED, Standing.HOSTILE]
	var order_ok = true
	for i in range(order.size() - 1):
		if not (Standing.severity(order[i]) < Standing.severity(order[i + 1])):
			order_ok = false
			printerr("[TEST FAILED] severity ordering broken between '", order[i], "' and '", order[i + 1], "'")
	if order_ok:
		passed += 1
	else:
		failed += 1

	if Standing.is_more_severe(Standing.HOSTILE, Standing.UNREPORTED) and not Standing.is_more_severe(Standing.NEUTRAL, Standing.HOSTILE) and not Standing.is_more_severe(Standing.UNREPORTED, Standing.UNREPORTED):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] is_more_severe basic comparisons")

	# --- M52b: response classes (INTERCEPT/MAX) per offense -------------------
	# Pins the design doc's taxonomy table so a future tweak can't silently
	# flip which offenses get MAX's shortened patience. The M52 patrol
	# milestone is the actual CONSUMER (a behavior tree reading "do I
	# enforce this offense, and at what class") -- this milestone only needs
	# to prove the class is correctly attached to each warrant type.
	var response_table := {
		Standing.OFF_ASSAULT: Standing.RESPONSE_INTERCEPT,
		Standing.OFF_SUSTAINED_ASSAULT: Standing.RESPONSE_MAX,
		Standing.OFF_ARMED_THREAT: Standing.RESPONSE_INTERCEPT,
		Standing.OFF_ARMED_ROBBERY: Standing.RESPONSE_MAX,
		Standing.OFF_NO_ID: Standing.RESPONSE_INTERCEPT,
		Standing.OFF_SPEED_VIOLATION: Standing.RESPONSE_INTERCEPT,
		Standing.OFF_OPERATOR_FLAGGED: Standing.RESPONSE_INTERCEPT,
	}
	var response_ok := true
	for offense in response_table:
		if Standing.response_class(offense) != response_table[offense]:
			response_ok = false
			printerr("[TEST FAILED] response_class(", offense, ") expected ", response_table[offense], " got ", Standing.response_class(offense))
	if response_ok:
		passed += 1
	else:
		failed += 1

	# --- M52b: warrants -- origin scoping ------------------------------------
	if Standing.scoped_origin("SOVEREIGN_DRIFT", ["SOVEREIGN_DRIFT"]) == "SOVEREIGN_DRIFT":
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] scoped_origin: an authorized flag should ride through unchanged")

	if Standing.scoped_origin("SOVEREIGN_DRIFT", []) == "":
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] scoped_origin: an unauthorized flag should still post, scoped personal (\"\")")

	# --- M52b: warrants -- expiry -------------------------------------------
	var w_short: Dictionary = Standing.make_warrant(Standing.OFF_ASSAULT, {"claimed_name": "X"}, {"iid": 1}, "", "k1")
	if not Standing.is_expired(w_short, w_short["timestamp"]):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a freshly-posted warrant should not read expired at its own timestamp")

	if Standing.is_expired(w_short, w_short["timestamp"] + int(9999 * Standing.PHYSICS_HZ)):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] ASSAULT (short expiry) should read expired far enough in the future")

	var w_never: Dictionary = Standing.make_warrant(Standing.OFF_SUSTAINED_ASSAULT, {"claimed_name": "X"}, {"iid": 1}, "", "k2")
	if not Standing.is_expired(w_never, w_never["timestamp"] + int(999999 * Standing.PHYSICS_HZ)):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] SUSTAINED_ASSAULT should never expire on its own clock")

	# --- M52b: warrants -- resolve / latest-timestamp-wins merge -------------
	var w_open: Dictionary = Standing.make_warrant(Standing.OFF_OPERATOR_FLAGGED, {"claimed_name": "Y"}, {"iid": 1}, "", "k3")
	var w_resolved: Dictionary = Standing.resolve_warrant(w_open)
	if w_resolved["status"] == Standing.WARRANT_RESOLVED and w_resolved["timestamp"] >= w_open["timestamp"]:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] resolve_warrant should flip status to RESOLVED with a timestamp >= the original")

	var m_old: Dictionary = {"timestamp": 10, "status": Standing.WARRANT_OPEN}
	var m_new: Dictionary = {"timestamp": 20, "status": Standing.WARRANT_OPEN}
	if Standing.merge_warrant(m_old, m_new) == m_new and Standing.merge_warrant(m_new, m_old) == m_new:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] merge_warrant should keep the later timestamp regardless of argument order")

	var m_tie_open: Dictionary = {"timestamp": 10, "status": Standing.WARRANT_OPEN}
	var m_tie_resolved: Dictionary = {"timestamp": 10, "status": Standing.WARRANT_RESOLVED}
	if Standing.merge_warrant(m_tie_open, m_tie_resolved) == m_tie_resolved and Standing.merge_warrant(m_tie_resolved, m_tie_open) == m_tie_resolved:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] merge_warrant should prefer RESOLVED over OPEN on a timestamp tie")

	# --- M52b: warrants -- event_key/subject_key dedup ------------------------
	var k_a: String = Standing.subject_key("Same Ship", {})
	var k_b: String = Standing.subject_key("Same Ship", {"iff_tags": ["X"]})
	var k_c: String = Standing.subject_key("Different Ship", {})
	if k_a == k_b and k_a != k_c:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] subject_key: a claimed name should collide regardless of signature; a different name must not collide")

	var k_sig_a: String = Standing.subject_key("", {"iff_tags": ["TEAM_X"], "cross_section": 12.0})
	var k_sig_b: String = Standing.subject_key("", {"iff_tags": ["TEAM_Y"], "cross_section": 12.0})
	if k_sig_a != k_sig_b:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] subject_key: dark subjects with different signatures should not collide")

	# --- M52b: enforcement gate mirrors the issuing gate ----------------------
	var w_flagged: Dictionary = Standing.make_warrant(Standing.OFF_ARMED_THREAT, {"claimed_name": "Z"}, {"iid": 42, "name": "Issuer"}, "SOVEREIGN_DRIFT", "k4")
	if not Standing.warrant_enforceable_by(w_flagged, [], 99):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a flagged warrant should NOT be enforceable by a ship lacking that flag's authority")

	if Standing.warrant_enforceable_by(w_flagged, ["SOVEREIGN_DRIFT"], 99):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] granting the flag's warrant_authority should flip it enforceable -- same gate as issuing")

	var w_personal: Dictionary = Standing.make_warrant(Standing.OFF_OPERATOR_FLAGGED, {"claimed_name": "Z"}, {"iid": 42, "name": "Issuer"}, "", "k5")
	if Standing.warrant_enforceable_by(w_personal, [], 42) and not Standing.warrant_enforceable_by(w_personal, [], 99):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] a personal-origin warrant should be enforceable ONLY by its own issuer")

	# build_warrant_index: keeps the WORST (highest response class) OPEN
	# warrant per subject; MAX (SUSTAINED_ASSAULT) beats INTERCEPT (ASSAULT).
	var idx_warrants: Dictionary = {
		"a1": Standing.make_warrant(Standing.OFF_ASSAULT, {"claimed_name": "Idx"}, {"iid": 1}, "", "a1"),
		"a2": Standing.make_warrant(Standing.OFF_SUSTAINED_ASSAULT, {"claimed_name": "Idx"}, {"iid": 1}, "", "a2"),
	}
	var idx: Dictionary = Standing.build_warrant_index(idx_warrants, [], 1)
	var idx_key: String = Standing.subject_key("Idx", {})
	if idx.get(idx_key, {}).get("offense", "") == Standing.OFF_SUSTAINED_ASSAULT:
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] build_warrant_index should keep the WORST (MAX > INTERCEPT) open warrant per subject, got ", idx.get(idx_key, {}))

	# --- M52b: wreck gate survives the warrant-index rule ---------------------
	# A warrant names a subject; a hulk (WRECKAGE classification) must never
	# match it -- the same guarantee the old sticky bit had to preserve
	# (M52a's wreck-gate fix). classify_contact keying on EM-not-heat is
	# unrelated to this change, but the interaction is worth pinning here.
	var wreck_observer := _make_observer(["TEAM_WRECK"])
	wreck_observer.warrant_index = {
		Standing.subject_key("Deceased", {}): Standing.make_warrant(
			Standing.OFF_SUSTAINED_ASSAULT, {"claimed_name": "Deceased"}, {"iid": 1}, "", "wk")
	}
	var wreck_result: Dictionary = Standing.compute_standing(
		{"classification": "WRECKAGE", "signature": {}},
		{"name": "Deceased", "flag": ""},
		wreck_observer
	)
	if wreck_result.get("standing", "<<missing>>") == "":
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] wreck gate: a WRECKAGE-classified contact must never read a warrant's standing, got ", wreck_result)
	wreck_observer.free()

	# --- cleanup --------------------------------------------------------------
	Standing.reset()
	observer_a.free()
	observer_warrant.free()
	observer_warrant_crypto.free()
	observer_warrant_precedence.free()

	if failed == 0:
		print(">>> [TEST PASSED] test_standing_rules <<<")
		print("[TEST PASSED] test_standing_rules. Passed ", passed, "/", passed + failed, " cases.")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_standing_rules <<<")
		printerr("[TEST SUITE FAILED] ", failed, " of ", passed + failed, " checks failed.")
		get_tree().quit(1)
