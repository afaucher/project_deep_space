extends Node

# Playtest A2 (design_ideas/2026-07-26-campaign_playtest.md): "Ironhold is
# classified inconsistently -- enemy in one place, neutral in another", plus
# the follow-up report that the station's colour on the map did not match its
# colour in the contact list.
#
# THREE surfaces each had their own rule and only ONE consulted Standing:
#
#   contacts_panel row colour   SOS > standing > classification   correct
#   navigation_panel blips      classification only               red
#   helm_panel heading dial     classification only               red
#
# ...and the panel's SECTION bucketing was a fourth rule, keyed on
# classification, which is how a hull could be filed under "Enemies" while
# being painted neutral grey in the same panel.
#
# The reason this was campaign-breaking rather than cosmetic: classify_contact()
# returns "UNIDENTIFIED VESSEL" for ANY live vessel without an IFF crypto
# handshake -- including a fully identified, reporting, NEUTRAL station. So
# every neutral station and civilian in the cluster drew red on the nav map and
# filed under Enemies. The classification name is the lie: it means "not
# IFF-friendly", not "unknown".
#
# What this test actually pins is the STRUCTURE that stops it recurring:
# colour and section are both derived from one Utils.contact_tier() call
# against one table, so they cannot disagree. A future tier that adds a colour
# and forgets a section (or vice versa) fails here rather than shipping as a
# contradiction the player has to notice.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_contact_tier

const Standing = preload("res://scripts/combat/standing.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# A contact shaped like the real thing: an identified, reporting, NEUTRAL
# station. classify_contact calls this "UNIDENTIFIED VESSEL" because there is no
# IFF crypto overlap -- which is exactly the trap.
func _ironhold() -> Dictionary:
	return {
		"instance_id": 42,
		"classification": "UNIDENTIFIED VESSEL",
		"standing": Standing.NEUTRAL,
		"transponder_name": "Ironhold",
	}

func setup(_main) -> void:
	print("=== test_contact_tier: one tier table drives colour AND section (playtest A2) ===")

	# --- The structural invariant: no tier can define one and not the other ---
	print("\n--- every tier resolves to both a colour and a real section ---")
	for tier in [Utils.TIER_SOS, Utils.TIER_HOSTILE, Utils.TIER_CAUTION,
			Utils.TIER_FRIENDLY, Utils.TIER_NEUTRAL]:
		var c: Dictionary = {"classification": "UNIDENTIFIED VESSEL"}
		if tier == Utils.TIER_SOS:
			c["sos"] = true
		else:
			c["standing"] = Utils.TIER_CAUTION if tier == Utils.TIER_CAUTION else tier
		# CAUTION's standing string is still spelled UNREPORTED (the rename is
		# deferred to its own commit) -- go through Standing so this keeps
		# working after it lands.
		if tier == Utils.TIER_CAUTION:
			c["standing"] = Standing.CAUTION
		_assert(Utils.contact_tier(c) == tier,
			"a contact carrying %s resolves to that tier" % tier)
		_assert(Utils.CONTACT_SECTIONS.has(Utils.contact_section(c)),
			"%s files under a section that actually exists (got '%s')" % [tier, Utils.contact_section(c)])

	# --- A2 itself -----------------------------------------------------------
	print("\n--- Ironhold: identified, reporting, NEUTRAL ---")
	var iron := _ironhold()
	_assert(Utils.contact_section(iron) == "All Contacts",
		"a NEUTRAL station does NOT file under Enemies (got '%s')" % Utils.contact_section(iron))
	_assert(Utils.contact_color(iron) != Utils.classification_color("UNIDENTIFIED VESSEL"),
		"...and is NOT painted the classification's red -- standing wins over the sensor bucket")
	_assert(Utils.contact_color(iron) == Color(0.85, 0.85, 0.85),
		"a NEUTRAL contact is grey on EVERY surface, map and list alike")

	# The bug in one assertion: the two views agreeing is the whole fix.
	_assert(Utils.contact_section(iron) != "Enemies" or Utils.contact_color(iron) == Color(0.85, 0.2, 0.2),
		"filed-as-enemy and painted-neutral can never both be true (the literal A2 contradiction)")

	# --- The tiers that SHOULD be alarming still are -------------------------
	print("\n--- the alarming tiers are unaffected ---")
	var hostile: Dictionary = {"classification": "UNIDENTIFIED VESSEL", "standing": Standing.HOSTILE}
	_assert(Utils.contact_section(hostile) == "Enemies", "a HOSTILE contact still files under Enemies")

	var caution: Dictionary = {"classification": "UNIDENTIFIED VESSEL", "standing": Standing.CAUTION}
	_assert(Utils.contact_section(caution) == "Alerts",
		"a CAUTION contact files under Alerts -- unidentified, warranted, or coercing us")

	var sos: Dictionary = {"classification": "FRIENDLY VESSEL", "standing": Standing.FRIENDLY, "sos": true}
	_assert(Utils.contact_section(sos) == "Alerts",
		"a distress call files under Alerts even from a FRIENDLY ship (it used to land in All Contacts)")
	_assert(Utils.contact_color(sos) == Color(1.0, 0.25, 0.1, 0.95),
		"...and keeps the SOS colour, which outranks its ordinary friendly green")

	# --- Non-vessels are untouched -------------------------------------------
	# Ordnance/wreckage/asteroids carry no standing at all and must keep falling
	# through to the classification layer exactly as before.
	print("\n--- non-vessels fall through to classification, unchanged ---")
	var rock: Dictionary = {"classification": "ASTEROID"}
	_assert(Utils.contact_tier(rock) == "", "an asteroid has no tier")
	_assert(Utils.contact_color(rock) == Utils.classification_color("ASTEROID"),
		"...so it keeps its classification colour")
	_assert(Utils.contact_section(rock) == "All Contacts", "...and files under All Contacts")

	var ordnance: Dictionary = {"classification": "INCOMING ORDNANCE"}
	_assert(Utils.contact_color(ordnance) == Utils.classification_color("INCOMING ORDNANCE"),
		"incoming ordnance keeps its own colour (it carries no standing)")

	# --- What the player is SHOWN -------------------------------------------
	# Both of these came out of the 2026-07-27 playtest and both are one-liners
	# over tables that already existed -- pinned here so a future edit to the
	# tier table can't silently change what a player reads.
	print("\n--- standing display names ---")
	_assert(Utils.standing_display(Standing.UNREPORTED) == "CAUTION",
		"the wire constant UNREPORTED is SHOWN as CAUTION -- 'not reporting' is one cause of the tier, not the tier")
	_assert(Utils.standing_display(Standing.HOSTILE) == "HOSTILE",
		"every other tier shows under its own name")
	_assert(Utils.standing_display("") == "",
		"no standing displays as nothing, not as a fabricated tier")

	print("\n--- entity labels: one naming grammar for every list ---")
	_assert(Utils.entity_label("TRK-068", "", "", "UNIDENTIFIED VESSEL") == "TRK-068",
		"an unidentified vessel is just its track id -- no '[UNIDENTIFIED VESSEL]', no 'dark'")
	_assert(Utils.entity_label("TRK-815", "Ironhold", "SOVEREIGN_DRIFT", "UNIDENTIFIED VESSEL")
			== "TRK-815 \"Ironhold\" — SOVEREIGN_DRIFT",
		"an identified vessel shows its flag, NOT the sensor bucket that calls it unidentified")
	_assert(Utils.entity_label("TRK-402", "", "", "WRECKAGE") == "TRK-402 [WRECKAGE]",
		"a non-vessel keeps its classification -- there the class IS the news")
	_assert(Utils.entity_label("TRK-777", "Old Hull", "", "ASTEROID") == "TRK-777 \"Old Hull\" [ASTEROID]",
		"...and a named non-vessel shows both")
	_assert(not Utils.entity_label("TRK-815", "Ironhold", "SOVEREIGN_DRIFT", "UNIDENTIFIED VESSEL").contains("UNIDENTIFIED"),
		"the label a player reads never contradicts the name printed beside it")

	# Section order is the display order, and Alerts sits directly under
	# Enemies -- the two attention-demanding sections adjacent at the top.
	print("\n--- section order ---")
	_assert(Utils.CONTACT_SECTIONS[0] == "Enemies" and Utils.CONTACT_SECTIONS[1] == "Alerts",
		"Alerts sits directly below Enemies (got %s)" % str(Utils.CONTACT_SECTIONS))

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_contact_tier <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_contact_tier <<<")
		get_tree().quit(1)
