extends Node

# M52 -- pins ContactsPanel's SOS badge (scripts/ui/contacts_panel.gd): a
# contact carrying sos/sos_nature/sos_name (ship.gd's comms_inbox VERB_SOS
# branch -- only ever stamped onto a REAL, already-existing track, never a
# manufactured one) now shows a "[SOS]" header prefix, a distinct row color
# (matching navigation_panel.gd's SOS_COLOR), and an "SOS: <nature>" line in
# the detail text -- taking priority over the contact's ordinary standing
# color, since a friendly ship in distress is more urgent than its usual
# green row. Drives the actual widget (headless-safe: no scene/physics
# dependency), same "instantiate the Control directly" pattern test_weapons_
# panel_standing.gd uses.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_contacts_panel_sos

const ContactsPanel = preload("res://scripts/ui/contacts_panel.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("=== test_contacts_panel_sos: SOS contact attribute shows a badge, color, and detail line ===")

	var panel := ContactsPanel.new()
	main.add_child(panel)

	panel.update_data({
		"pos": Vector2.ZERO,
		"contacts": {
			"TRK-100": {
				"instance_id": 100, "classification": "FRIENDLY VESSEL", "standing": "FRIENDLY",
				"pos": Vector2(1000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0,
				"sos": true, "sos_nature": "UNDER_ATTACK", "sos_name": "Hauler Joe",
			},
			"TRK-200": {
				"instance_id": 200, "classification": "FRIENDLY VESSEL", "standing": "FRIENDLY",
				"pos": Vector2(2000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0,
			},
		},
		"transponders": {
			100: {"name": "Hauler Joe", "flag": "FEDERATION"},
			200: {"name": "Quiet Trader", "flag": "FEDERATION"},
		},
	})

	_assert(panel.contact_panels.has("TRK-100") and panel.contact_panels.has("TRK-200"),
		"both contacts rendered")

	if panel.contact_panels.has("TRK-100"):
		var refs: Dictionary = panel.contact_panels["TRK-100"]
		var header: Label = refs["header"]
		var info: Label = refs["info"]
		var style: StyleBoxFlat = refs["style"]
		_assert(header.text.begins_with("[SOS] "), "SOS contact's header is prefixed with '[SOS] ', got '%s'" % header.text)
		_assert(header.text.contains("Hauler Joe"), "header still shows the transponder name, got '%s'" % header.text)
		_assert(info.text.contains("SOS: UNDER_ATTACK"), "detail text carries the SOS nature, got:\n%s" % info.text)
		_assert(style.border_color == Color(1.0, 0.25, 0.1, 0.95), "SOS row uses the distress color, not the standing color, got %s" % str(style.border_color))
		_assert(header.get_theme_color("font_color") == Color(1.0, 0.25, 0.1, 0.95), "SOS header font color matches, got %s" % str(header.get_theme_color("font_color")))

	if panel.contact_panels.has("TRK-200"):
		var refs2: Dictionary = panel.contact_panels["TRK-200"]
		var header2: Label = refs2["header"]
		var info2: Label = refs2["info"]
		_assert(not header2.text.begins_with("[SOS] "), "an ordinary contact's header carries no SOS prefix, got '%s'" % header2.text)
		_assert(not info2.text.contains("SOS:"), "an ordinary contact's detail text carries no SOS line")

	# SOS clears (e.g. once the report ages out server-side) -> the badge
	# and color revert to the plain standing-based treatment.
	panel.update_data({
		"pos": Vector2.ZERO,
		"contacts": {
			"TRK-100": {
				"instance_id": 100, "classification": "FRIENDLY VESSEL", "standing": "FRIENDLY",
				"pos": Vector2(1000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0,
			},
		},
		"transponders": {100: {"name": "Hauler Joe", "flag": "FEDERATION"}},
	})
	if panel.contact_panels.has("TRK-100"):
		var refs3: Dictionary = panel.contact_panels["TRK-100"]
		var header3: Label = refs3["header"]
		var style3: StyleBoxFlat = refs3["style"]
		_assert(not header3.text.begins_with("[SOS] "), "once the sos attribute clears, the badge is gone, got '%s'" % header3.text)
		_assert(style3.border_color == Color(0.2, 0.8, 0.2), "row reverts to the ordinary FRIENDLY standing color, got %s" % str(style3.border_color))

	panel.queue_free()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_contacts_panel_sos <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_contacts_panel_sos <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)
