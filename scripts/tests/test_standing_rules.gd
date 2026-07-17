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

	# 2. Sticky HOSTILE stays HOSTILE even with no other evidence.
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}, "standing": "HOSTILE", "standing_reason": "fired on us"},
		{}, observer_a, Standing.HOSTILE, "fired on us"
	])

	# 3. Known-enemy flag -> HOSTILE ("flying <flag>").
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}},
		{"name": "Raider", "flag": Standing.FLAG_PIRATE}, observer_a, Standing.HOSTILE, "flying"
	])

	# 4. A claimed name on the wanted list does NOT change standing -- suspicion
	# is not a standing, it's the patrol's own assessment (which reads the
	# wanted-names registry itself). A reporting ship stays NEUTRAL.
	Standing.add_wanted(["TEAM_A"], "Mule")
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

	# 8. Precedence: crypto beats even a sticky HOSTILE mark (order 1 before 2).
	cases.append([
		{"classification": "FRIENDLY VESSEL", "signature": {"iff_tags": ["TEAM_A"]}, "standing": "HOSTILE", "standing_reason": "fired on us"},
		{}, observer_a, Standing.FRIENDLY, ""
	])

	# 9. Precedence: sticky HOSTILE beats a known-enemy flag check (order 2 before 3)
	# -- flying a clean flag doesn't clear a HOSTILE mark.
	cases.append([
		{"classification": "UNIDENTIFIED VESSEL", "signature": {"iff_tags": []}, "standing": "HOSTILE", "standing_reason": "fired on us"},
		{"name": "Raider", "flag": ""}, observer_a, Standing.HOSTILE, "fired on us"
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

	# --- wanted names -------------------------------------------------------
	Standing.reset()
	if Standing.is_wanted(["TEAM_A"], "Ghost"):
		failed += 1
		printerr("[TEST FAILED] wanted names: fresh registry should not know 'Ghost'")
	else:
		passed += 1

	Standing.add_wanted(["TEAM_A", "TEAM_B"], "Ghost")
	if Standing.is_wanted(["TEAM_A"], "Ghost") and Standing.is_wanted(["TEAM_B"], "Ghost") and not Standing.is_wanted(["TEAM_C"], "Ghost"):
		passed += 1
	else:
		failed += 1
		printerr("[TEST FAILED] wanted names: multi-tag add/lookup mismatch")

	# Empty claimed name never registers (names are cheap talk, but an empty
	# claim shouldn't pollute the registry).
	Standing.add_wanted(["TEAM_A"], "")
	if Standing.is_wanted(["TEAM_A"], ""):
		failed += 1
		printerr("[TEST FAILED] wanted names: empty name should never be wanted")
	else:
		passed += 1

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

	# --- cleanup --------------------------------------------------------------
	Standing.reset()
	observer_a.free()

	if failed == 0:
		print(">>> [TEST PASSED] test_standing_rules <<<")
		print("[TEST PASSED] test_standing_rules. Passed ", passed, "/", passed + failed, " cases.")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_standing_rules <<<")
		printerr("[TEST SUITE FAILED] ", failed, " of ", passed + failed, " checks failed.")
		get_tree().quit(1)
