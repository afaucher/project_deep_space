extends Node

# M52b -- pins WeaponsPanel._update_standing_row's new warrant-reason display
# (scripts/ui/weapons_panel.gd): the standing line now appends
# contact["standing_reason"] when present -- data compute_standing/ship.gd
# already cache-stamp on every warrant post, previously with zero UI
# consumers. Drives the actual widget (headless-safe: no scene/physics
# dependency, same "instantiate the Control directly" pattern as
# test_controls_menu_ui.gd) rather than asserting on the text-building logic
# in isolation, since _update_standing_row is a tiny private func with real
# Label state worth exercising end to end.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_weapons_panel_standing

const WeaponsPanel = preload("res://scripts/ui/weapons_panel.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	print("=== test_weapons_panel_standing: targeting computer shows the warrant reason ===")

	var panel := WeaponsPanel.new()
	main.add_child(panel)

	panel._update_standing_row({
		"classification": "UNIDENTIFIED VESSEL",
		"standing": "HOSTILE",
		"standing_reason": "sustained attack on Trader",
	})
	_assert(panel.standing_label.text == "Standing: HOSTILE -- sustained attack on Trader",
		"HOSTILE with a reason appends it, got '%s'" % panel.standing_label.text)

	panel._update_standing_row({
		"classification": "UNIDENTIFIED VESSEL",
		"standing": "NEUTRAL",
		"standing_reason": "",
	})
	_assert(panel.standing_label.text == "Standing: NEUTRAL",
		"a standing with no reason shows plain (no dangling separator), got '%s'" % panel.standing_label.text)

	panel._update_standing_row({
		"classification": "WRECKAGE",
		"standing": "HOSTILE",
		"standing_reason": "sustained attack on Trader",
	})
	_assert(panel.standing_label.text == "",
		"a non-vessel contact never shows standing/reason (wreck gate), got '%s'" % panel.standing_label.text)

	panel._update_standing_row({})
	_assert(panel.standing_label.text == "",
		"no target locked -> blank, got '%s'" % panel.standing_label.text)

	panel.queue_free()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_weapons_panel_standing <<<")
		get_tree().quit(0)
	else:
		printerr(">>> [TEST FAILED] test_weapons_panel_standing <<<")
		for f in failures:
			printerr("  FAIL: ", f)
		get_tree().quit(1)
