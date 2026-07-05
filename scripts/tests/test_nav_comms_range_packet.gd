extends Node

# Regression test for the comms-range rendering fix (M-comms-range-nav-fix):
# main.gd's per-player packet must carry a top-level "comms_range" field so
# navigation_panel.gd can draw it as one more ring alongside the sensor arcs.
# Before the fix, navigation_panel read current_state.get("ship_components",
# []) which was never present at the top level (it's nested under
# "engineering"."ship_components"), so the comms ring never drew. This test
# exercises the REAL pipeline: a spawned player ship -> main._distribute_state()
# -> terminal_display.update_data() -> navigation_panel.update_data(), then
# reads the nav panel's current_state back out.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_nav_comms_range_packet
# Synchronous. Pass marker per CLAUDE.md.

const Frigate = preload("res://scripts/ships/frigate.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	print("Starting nav comms_range packet regression test")

	var ship = Frigate.new()
	ship.owner_id = 1
	ship.name = "TestPlayer"
	main.add_child(ship)
	main.players[1] = ship

	# Drive one distribution pass through the real host pipeline (same call
	# main.gd's _physics_process makes every tick while hosting).
	main._distribute_state()

	var nav_panel = main.terminal_display.nav_panel
	_assert(nav_panel != null, "main.terminal_display.nav_panel should exist")

	if nav_panel != null:
		_assert(nav_panel.current_state.has("comms_range"),
			"packet delivered to navigation_panel should carry a top-level 'comms_range' key")
		var comms_range: float = nav_panel.current_state.get("comms_range", 0.0)
		_assert(comms_range > 0.0,
			"a normal frigate's comms array is powered by default, so comms_range should be > 0 (got %s)" % comms_range)
		_assert(is_equal_approx(comms_range, ship.get_comms_range()),
			"packet's comms_range should match ship.get_comms_range() exactly (got %s vs %s)" % [comms_range, ship.get_comms_range()])

	ship.queue_free()
	main.players.erase(1)

	if failures.is_empty():
		print(">>> [TEST PASSED] test_nav_comms_range_packet <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_nav_comms_range_packet <<<")
		get_tree().quit(1)
