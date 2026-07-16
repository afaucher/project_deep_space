extends Node

# Regression test for the InputBindings autoload (control remapping):
# rebind -> persist -> wipe -> reload round-trip, conflict detection, gamepad
# rebinds, and reset-to-defaults. The autoload deliberately SKIPS loading a
# real config in --run-test mode (so test_input_bindings keeps asserting the
# project.godot defaults); this test drives the API directly against a scratch
# config path, then restores defaults so it can't poison later assertions.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_input_remap

const SCRATCH_CFG := "user://test_input_remap.cfg"

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _kb_keycodes(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.keycode)
	return out

func _pad_desc(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return "button:%d" % ev.button_index
		elif ev is InputEventJoypadMotion:
			return "axis:%d:%s" % [ev.axis, "+" if ev.axis_value > 0.0 else "-"]
	return ""

func setup(_main) -> void:
	print("=== test_input_remap: rebind/persist/reload/reset round-trip ===")
	var ib = get_node("/root/InputBindings")
	ib.config_path = SCRATCH_CFG
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))

	# 1. Defaults in place (autoload skipped its load in test mode).
	_assert(KEY_SPACE in _kb_keycodes("combat_fire_all"), "default: fire-all is Space")
	_assert(_pad_desc("combat_fire_all") == "axis:5:+", "default: fire-all pad is RT (axis 5 +)")

	# 2. Keyboard rebind replaces keyboard events only, keeps the pad binding.
	ib.rebind_keyboard("combat_fire_all", KEY_F)
	_assert(_kb_keycodes("combat_fire_all") == [KEY_F], "rebind: fire-all keyboard is now F only")
	_assert(_pad_desc("combat_fire_all") == "axis:5:+", "rebind: pad binding untouched by keyboard rebind")
	_assert(FileAccess.file_exists(SCRATCH_CFG), "rebind: config file written")

	# 3. Wipe the runtime map back to defaults, then reload from the config --
	# the remap must survive the round-trip (this is the persistence contract).
	InputMap.load_from_project_settings()
	_assert(KEY_SPACE in _kb_keycodes("combat_fire_all"), "wipe: project defaults restored")
	ib.load_bindings()
	_assert(_kb_keycodes("combat_fire_all") == [KEY_F], "reload: F remap survived save/load round-trip")
	_assert(_pad_desc("combat_fire_all") == "axis:5:+", "reload: pad binding survived round-trip")
	_assert(_kb_keycodes("helm_steer_left") == [KEY_A, KEY_LEFT], "reload: untouched action's multi-key default intact")

	# 4. Conflict detection: F is taken by fire-all now; J is free.
	var f_ev := InputEventKey.new()
	f_ev.keycode = KEY_F
	_assert(ib.find_conflict("helm_steer_left", f_ev) == "combat_fire_all", "conflict: F reported as taken by fire-all")
	var j_ev := InputEventKey.new()
	j_ev.keycode = KEY_J
	_assert(ib.find_conflict("helm_steer_left", j_ev) == "", "conflict: J reported as free")

	# 5. Gamepad rebind (button) replaces the axis event, keeps keyboard F.
	var pad_ev := InputEventJoypadButton.new()
	pad_ev.button_index = JOY_BUTTON_B
	ib.rebind_gamepad("combat_fire_all", pad_ev)
	_assert(_pad_desc("combat_fire_all") == "button:1", "pad rebind: fire-all is now pad button B")
	_assert(_kb_keycodes("combat_fire_all") == [KEY_F], "pad rebind: keyboard binding untouched")

	# 6. Gamepad axis rebind round-trips with direction sign.
	var axis_ev := InputEventJoypadMotion.new()
	axis_ev.axis = JOY_AXIS_TRIGGER_LEFT
	axis_ev.axis_value = 0.83 # captured mid-pull; must snap to +1
	ib.rebind_gamepad("nav_zoom_in", axis_ev)
	InputMap.load_from_project_settings()
	ib.load_bindings()
	_assert(_pad_desc("nav_zoom_in") == "axis:4:+", "axis rebind: LT (+) snapped, saved, and reloaded")

	# 7. Reset restores defaults and deletes the config.
	ib.reset_to_defaults()
	_assert(KEY_SPACE in _kb_keycodes("combat_fire_all"), "reset: fire-all back to Space")
	_assert(_pad_desc("combat_fire_all") == "axis:5:+", "reset: fire-all pad back to RT")
	_assert(not FileAccess.file_exists(SCRATCH_CFG), "reset: config file deleted")

	# Restore the real path constant semantics for anything after us.
	ib.config_path = ib.CONFIG_PATH

	if failures.is_empty():
		print(">>> [TEST PASSED] test_input_remap <<<")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("  ASSERT FAILED: ", msg)
		printerr(">>> [TEST FAILED] test_input_remap <<<")
		get_tree().quit(1)
