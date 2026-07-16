extends Node

# Runtime control remapping with persistence (see design_ideas/control_remapping.md).
#
# Defaults live in project.godot's [input] section and are NEVER modified; this
# autoload applies saved overrides on top of them at startup and persists the
# full binding set to a human-editable ConfigFile in the project directory
# (res:// is the repo root in this from-source workflow). Each action gets one
# section: `keys` is the keycode-name list (OS.get_keycode_string round-trip),
# `pad` is "button:<index>" or "axis:<index>:<+/->".
#
# Automated runs (--run-test / --run-tactical-sim) skip loading overrides:
# test_input_bindings asserts the project.godot defaults, and a developer's
# personal remaps must never leak into sim/test behavior.

const CONFIG_PATH := "res://input_bindings.cfg"

# Tests point this at a scratch file so they never touch a real config.
var config_path: String = CONFIG_PATH

# action -> menu label, in display order. Every remappable action is listed
# here; anything not listed (ui_*, editor actions) is untouched by remapping.
const REMAPPABLE := [
	{"action": "helm_steer_left", "label": "Steer Left"},
	{"action": "helm_steer_right", "label": "Steer Right"},
	{"action": "helm_throttle_up", "label": "Throttle Up"},
	{"action": "helm_throttle_down", "label": "Throttle Down"},
	{"action": "helm_linear_toggle", "label": "Throttle Mode Toggle"},
	{"action": "combat_fire_all", "label": "Fire All Weapons"},
	{"action": "combat_steer_toggle", "label": "Combat Steering Toggle"},
	{"action": "nav_next_contact", "label": "Next Contact"},
	{"action": "nav_prev_contact", "label": "Previous Contact"},
	{"action": "nav_zoom_in", "label": "Map Zoom In"},
	{"action": "nav_zoom_out", "label": "Map Zoom Out"},
	{"action": "map_orient_toggle", "label": "Map Orientation"},
	{"action": "menu_start", "label": "Menu: Start Game"},
	{"action": "help_toggle", "label": "Help Overlay"},
	{"action": "system_exit", "label": "Quit Game"},
	{"action": "debug_spawn_enemy", "label": "Debug: Spawn Enemy"},
]

# Xbox-style names for Godot's SDL-mapped JOY_BUTTON_* indices.
const PAD_BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start",
	7: "L3", 8: "R3", 9: "LB", 10: "RB",
	11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right",
}
const PAD_AXIS_NAMES := {0: "LS", 1: "LS", 2: "RS", 3: "RS", 4: "LT", 5: "RT"}

func _ready() -> void:
	var args = OS.get_cmdline_args()
	if "--run-test" in args or "--run-tactical-sim" in args:
		return
	load_bindings()

# --- Remapping API (the controls menu calls these) -------------------------

# Replace ALL keyboard events on the action with the single captured key,
# keeping gamepad events untouched. Defaults with two keys (e.g. A + Left
# arrow for steering) collapse to one on remap; reset restores both.
func rebind_keyboard(action: String, keycode: int) -> void:
	var kept: Array = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			kept.append(ev)
	InputMap.action_erase_events(action)
	var new_ev := InputEventKey.new()
	new_ev.keycode = keycode as Key
	new_ev.device = -1
	InputMap.action_add_event(action, new_ev)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	save_bindings()

# Replace ALL gamepad events (buttons AND axes) with the captured one, keeping
# keyboard events untouched. `event` must be a JoypadButton or JoypadMotion;
# it is normalized (device -1, axis_value snapped to +/-1) before storing.
func rebind_gamepad(action: String, event: InputEvent) -> void:
	var new_ev: InputEvent = null
	if event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = event.button_index
		b.device = -1
		new_ev = b
	elif event is InputEventJoypadMotion:
		var m := InputEventJoypadMotion.new()
		m.axis = event.axis
		m.axis_value = 1.0 if event.axis_value > 0.0 else -1.0
		m.device = -1
		new_ev = m
	else:
		push_error("rebind_gamepad: not a gamepad event: " + str(event))
		return
	var kept: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			kept.append(ev)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, new_ev)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	save_bindings()

# Which OTHER remappable action already uses this binding? "" if none.
func find_conflict(action: String, event: InputEvent) -> String:
	for entry in REMAPPABLE:
		var other: String = entry["action"]
		if other == action or not InputMap.has_action(other):
			continue
		for ev in InputMap.action_get_events(other):
			if _same_binding(ev, event):
				return other
	return ""

func label_for(action: String) -> String:
	for entry in REMAPPABLE:
		if entry["action"] == action:
			return entry["label"]
	return action

func reset_to_defaults() -> void:
	InputMap.load_from_project_settings()
	var global := ProjectSettings.globalize_path(config_path)
	if FileAccess.file_exists(config_path):
		DirAccess.remove_absolute(global)

# --- Persistence ------------------------------------------------------------

func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for entry in REMAPPABLE:
		var action: String = entry["action"]
		if not InputMap.has_action(action):
			continue
		var keys := PackedStringArray()
		var pad := ""
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var kc: int = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
				keys.append(OS.get_keycode_string(kc))
			elif ev is InputEventJoypadButton:
				pad = "button:%d" % ev.button_index
			elif ev is InputEventJoypadMotion:
				pad = "axis:%d:%s" % [ev.axis, "+" if ev.axis_value > 0.0 else "-"]
		cfg.set_value(action, "keys", keys)
		cfg.set_value(action, "pad", pad)
	var err := cfg.save(config_path)
	if err != OK:
		push_error("InputBindings: failed to save %s (error %d)" % [config_path, err])

func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return # no config yet -- project.godot defaults stand
	print("[InputBindings] applying control remaps from ", config_path)
	for entry in REMAPPABLE:
		var action: String = entry["action"]
		if not cfg.has_section(action) or not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for key_name in cfg.get_value(action, "keys", PackedStringArray()):
			var kc := OS.find_keycode_from_string(key_name)
			if kc == KEY_NONE:
				continue
			var ev := InputEventKey.new()
			ev.keycode = kc
			ev.device = -1
			InputMap.action_add_event(action, ev)
		var pad_ev := _pad_event_from_string(cfg.get_value(action, "pad", ""))
		if pad_ev:
			InputMap.action_add_event(action, pad_ev)

# --- Display text (controls menu + anything showing live bindings) ----------

func keyboard_text(action: String) -> String:
	var names := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
			names.append(OS.get_keycode_string(kc))
	return " / ".join(names) if names.size() > 0 else "--"

func gamepad_text(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return PAD_BUTTON_NAMES.get(ev.button_index, "Pad %d" % ev.button_index)
		elif ev is InputEventJoypadMotion:
			var axis_name: String = PAD_AXIS_NAMES.get(ev.axis, "Axis %d" % ev.axis)
			match ev.axis:
				JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X:
					return axis_name + (" Right" if ev.axis_value > 0.0 else " Left")
				JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_Y:
					return axis_name + (" Down" if ev.axis_value > 0.0 else " Up")
				_:
					return axis_name
	return "--"

# --- Internals ---------------------------------------------------------------

func _same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.keycode == b.keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false

func _pad_event_from_string(pad: String) -> InputEvent:
	var parts := pad.split(":")
	if parts.size() >= 2 and parts[0] == "button" and parts[1].is_valid_int():
		var ev := InputEventJoypadButton.new()
		ev.button_index = parts[1].to_int() as JoyButton
		ev.device = -1
		return ev
	if parts.size() >= 3 and parts[0] == "axis" and parts[1].is_valid_int():
		var ev := InputEventJoypadMotion.new()
		ev.axis = parts[1].to_int() as JoyAxis
		ev.axis_value = 1.0 if parts[2] == "+" else -1.0
		ev.device = -1
		return ev
	return null
