extends Node

# UI-level test for the controls remap screen (scripts/ui/controls_menu.gd):
# drives the actual widget -- button press starts a capture, an injected
# InputEvent lands in _input, the InputMap and the slot label both update.
# Covers the conflict refusal, the Esc cancel, the stick-deflection grace
# window, and Esc-closes-the-screen. InputBindings' persistence contract is
# test_input_remap's job; this is the screen's wiring on top of it.
#
# Events are fed to _input() directly (deterministic; headless input-queue
# dispatch isn't part of what's under test).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_controls_menu_ui

const ControlsMenu = preload("res://scripts/ui/controls_menu.gd")
const SCRATCH_CFG := "user://test_controls_menu_ui.cfg"

var failures: Array = []
var closed_fired := false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _key_event(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	ev.pressed = true
	return ev

func _kb_keycodes(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.keycode)
	return out

func setup(main) -> void:
	print("=== test_controls_menu_ui: capture flow, conflicts, cancel, close ===")
	var ib = get_node("/root/InputBindings")
	ib.config_path = SCRATCH_CFG

	var ui = ControlsMenu.new()
	main.add_child(ui)
	ui.closed.connect(func(): closed_fired = true)
	ui.open()
	_assert(ui.visible, "open(): screen visible")

	var fire_key_btn: Button = ui._rows["combat_fire_all"]["key"]
	var fire_pad_btn: Button = ui._rows["combat_fire_all"]["pad"]
	_assert(fire_key_btn.text == "Space", "slot shows current binding (Space), got '%s'" % fire_key_btn.text)
	_assert(fire_pad_btn.text == "RT", "pad slot shows current binding (RT), got '%s'" % fire_pad_btn.text)

	# Keyboard capture: press the slot, then press J.
	fire_key_btn.pressed.emit()
	_assert(fire_key_btn.text == ui.CAPTURE_KEY_PROMPT, "capture starts: slot shows key prompt")
	ui._input(_key_event(KEY_J))
	_assert(_kb_keycodes("combat_fire_all") == [KEY_J], "captured J landed in the InputMap")
	_assert(fire_key_btn.text == "J", "slot label refreshed to J")

	# Conflict: J is now taken -- steering must refuse it and keep its default.
	var steer_key_btn: Button = ui._rows["helm_steer_left"]["key"]
	steer_key_btn.pressed.emit()
	ui._input(_key_event(KEY_J))
	_assert(_kb_keycodes("helm_steer_left") == [KEY_A, KEY_LEFT], "conflicting key refused, steering keeps A/Left")
	_assert("bound" in ui._status.text, "conflict reported in status line")

	# Esc during capture cancels without binding Escape.
	steer_key_btn.pressed.emit()
	ui._input(_key_event(KEY_ESCAPE))
	_assert(_kb_keycodes("helm_steer_left") == [KEY_A, KEY_LEFT], "Esc cancelled the capture, binding unchanged")
	_assert(ui.visible, "Esc during capture does NOT close the screen")

	# Gamepad capture with the stick-settle grace window: a motion event right
	# after capture starts is ignored; the same event after the grace binds.
	var zoom_pad_btn: Button = ui._rows["nav_zoom_in"]["pad"]
	zoom_pad_btn.pressed.emit()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_TRIGGER_LEFT
	motion.axis_value = 1.0
	ui._input(motion)
	_assert(ui._capture_action == "nav_zoom_in", "motion inside grace window ignored, still capturing")
	ui._capture_started_ms -= ui.MOTION_GRACE_MS + 100
	ui._input(motion)
	_assert(ui._capture_action == "", "motion after grace window captured")
	_assert(zoom_pad_btn.text == "LT", "pad slot refreshed to LT, got '%s'" % zoom_pad_btn.text)

	# Pad button capture too (Guide is unused by defaults -- no conflict).
	fire_pad_btn.pressed.emit()
	var pad_press := InputEventJoypadButton.new()
	pad_press.button_index = JOY_BUTTON_GUIDE
	pad_press.pressed = true
	ui._input(pad_press)
	_assert(fire_pad_btn.text == "Guide", "pad button captured, slot shows Guide")

	# Esc while NOT capturing closes the screen (instead of quitting the game).
	ui._input(_key_event(KEY_ESCAPE))
	_assert(not ui.visible, "Esc with no capture closes the screen")
	_assert(closed_fired, "closed signal emitted")

	# Leave the InputMap and disk exactly as we found them.
	ib.reset_to_defaults()
	ib.config_path = ib.CONFIG_PATH
	_assert(KEY_SPACE in _kb_keycodes("combat_fire_all"), "cleanup: defaults restored")

	if failures.is_empty():
		print(">>> [TEST PASSED] test_controls_menu_ui <<<")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("  ASSERT FAILED: ", msg)
		printerr(">>> [TEST FAILED] test_controls_menu_ui <<<")
		get_tree().quit(1)
