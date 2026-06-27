extends Node

# M13a: verify the keyboard control bindings loaded from project.godot's [input] map.
# The InputMap loads at engine startup, so a malformed edit (dropped/garbled event) shows
# up here as a missing keycode. Keeps the gamepad bindings too (not asserted -- this test
# only guards the keyboard additions).
const EXPECTED := {
	"helm_steer_left": [65, 4194319],     # A, Left
	"helm_steer_right": [68, 4194321],    # D, Right
	"helm_throttle_up": [87, 4194320],    # W, Up
	"helm_throttle_down": [83, 4194322],  # S, Down
	"combat_fire_all": [32],              # Space
	"nav_next_contact": [69],             # E
	"nav_prev_contact": [81],             # Q
	"nav_zoom_in": [61],                  # =
	"nav_zoom_out": [45],                 # -
	"helm_linear_toggle": [86],           # V
	"combat_steer_toggle": [67],          # C
	"map_orient_toggle": [77],            # M
	"menu_start": [4194310],              # Enter
	"system_exit": [4194305],             # Esc
	"help_toggle": [4194332],             # F1
}

func setup(_main) -> void:
	print("Test test_input_bindings initialized.")
	var failures: Array = []
	for action in EXPECTED:
		if not InputMap.has_action(action):
			failures.append("missing action: %s" % action)
			continue
		var keycodes := []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keycodes.append(ev.keycode)
		for kc in EXPECTED[action]:
			if kc not in keycodes:
				failures.append("%s missing keyboard keycode %d (has %s)" % [action, kc, keycodes])

	if failures.is_empty():
		print("All keyboard bindings present.")
		print(">>> [TEST PASSED] test_input_bindings <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_input_bindings <<<")
		get_tree().quit(1)
