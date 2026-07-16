extends Control

# Control-remapping screen, opened from the main menu's CONTROLS button
# (see design_ideas/control_remapping.md). One row per remappable action with
# a keyboard slot and a gamepad slot; click (or gamepad-select) a slot, then
# press the new key / pad input. Persistence is InputBindings' job -- this
# screen only captures events and calls its API.
#
# Built in code like help_overlay.gd -- no .tscn edit. Gamepad-navigable: the
# engine's built-in ui_* actions (D-pad / left stick / A) drive focus, the
# ScrollContainer follows focus, and capture-mode swallows ALL input in
# _input() so a press being bound can never also activate a focused button or
# fire a game action (main.gd quits on system_exit in _unhandled_input --
# marking the event handled here keeps Esc/Start safe to rebind around).

signal closed

const CAPTURE_KEY_PROMPT := "PRESS A KEY..."
const CAPTURE_PAD_PROMPT := "PRESS PAD..."
# A stick used for focus navigation is often still deflected when capture
# starts; ignore motion for a grace window and demand a firm deflection.
const MOTION_GRACE_MS := 300
const MOTION_THRESHOLD := 0.6

var _rows: Dictionary = {} # action -> {"key": Button, "pad": Button}
var _capture_action: String = ""
var _capture_kind: String = "" # "key" | "pad"
var _capture_button: Button = null
var _capture_started_ms: int = 0
var _status: Label
var _first_slot: Button = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.98)
	style.border_color = Color(0.3, 0.6, 0.9)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CONTROLS -- REMAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(520, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for header in ["ACTION", "KEYBOARD", "GAMEPAD"]:
		var h := Label.new()
		h.text = header
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		grid.add_child(h)

	for entry in InputBindings.REMAPPABLE:
		var action: String = entry["action"]
		var fn := Label.new()
		fn.text = entry["label"]
		fn.custom_minimum_size = Vector2(190, 0)
		grid.add_child(fn)

		var key_btn := _slot_button()
		key_btn.pressed.connect(_begin_capture.bind(action, "key", key_btn))
		grid.add_child(key_btn)

		var pad_btn := _slot_button()
		pad_btn.pressed.connect(_begin_capture.bind(action, "pad", pad_btn))
		grid.add_child(pad_btn)

		_rows[action] = {"key": key_btn, "pad": pad_btn}
		if _first_slot == null:
			_first_slot = key_btn

	vbox.add_child(HSeparator.new())

	_status = Label.new()
	_status.text = "Select a binding to change it. Esc cancels a capture."
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	vbox.add_child(footer)

	var reset_btn := Button.new()
	reset_btn.text = "RESET DEFAULTS"
	reset_btn.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_btn)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.pressed.connect(_close)
	footer.add_child(back_btn)

func open() -> void:
	_refresh_all()
	_set_status("Select a binding to change it. Esc cancels a capture.")
	show()
	if _first_slot:
		_first_slot.grab_focus()

func _close() -> void:
	_end_capture()
	hide()
	closed.emit()

# All capture handling lives in _input so it runs BEFORE GUI focus navigation
# and before main.gd's _unhandled_input -- a captured press can't double as a
# button activation or a game action.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture_action != "":
		_handle_capture(event)
		return
	# Not capturing: Esc/Start closes this screen instead of quitting the game.
	if event.is_action_pressed("system_exit"):
		get_viewport().set_input_as_handled()
		_close()

func _handle_capture(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			_end_capture()
			_set_status("Capture cancelled.")
		elif _capture_kind == "key":
			_try_bind(event)
		return
	if event is InputEventMouseButton and event.pressed:
		# Clicking away cancels rather than binding a mouse button.
		get_viewport().set_input_as_handled()
		_end_capture()
		_set_status("Capture cancelled.")
		return
	if _capture_kind != "pad":
		return
	if event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		_try_bind(event)
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		if Time.get_ticks_msec() - _capture_started_ms < MOTION_GRACE_MS:
			return
		if absf(event.axis_value) < MOTION_THRESHOLD:
			return
		_try_bind(event)

func _try_bind(event: InputEvent) -> void:
	var action := _capture_action
	var conflict: String = InputBindings.find_conflict(action, event)
	if conflict != "":
		_end_capture()
		_set_status("Already bound to '%s' -- unbind that first." % InputBindings.label_for(conflict))
		return
	if event is InputEventKey:
		InputBindings.rebind_keyboard(action, event.keycode)
	else:
		InputBindings.rebind_gamepad(action, event)
	_end_capture()
	_refresh_all()
	_set_status("'%s' rebound." % InputBindings.label_for(action))

func _begin_capture(action: String, kind: String, button: Button) -> void:
	_end_capture() # only one capture at a time
	_capture_action = action
	_capture_kind = kind
	_capture_button = button
	_capture_started_ms = Time.get_ticks_msec()
	button.text = CAPTURE_KEY_PROMPT if kind == "key" else CAPTURE_PAD_PROMPT
	_set_status("Listening for input for '%s'... (Esc to cancel)" % InputBindings.label_for(action))

func _end_capture() -> void:
	if _capture_button and is_instance_valid(_capture_button):
		var row: Dictionary = _rows.get(_capture_action, {})
		if not row.is_empty():
			row["key"].text = InputBindings.keyboard_text(_capture_action)
			row["pad"].text = InputBindings.gamepad_text(_capture_action)
		_capture_button.grab_focus() # keep gamepad navigation anchored
	_capture_action = ""
	_capture_kind = ""
	_capture_button = null

func _on_reset_pressed() -> void:
	_end_capture()
	InputBindings.reset_to_defaults()
	_refresh_all()
	_set_status("Defaults restored.")

func _refresh_all() -> void:
	for action in _rows:
		_rows[action]["key"].text = InputBindings.keyboard_text(action)
		_rows[action]["pad"].text = InputBindings.gamepad_text(action)

func _set_status(msg: String) -> void:
	_status.text = msg

func _slot_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 0)
	btn.add_theme_font_size_override("font_size", 13)
	return btn
