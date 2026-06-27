extends Control

# M13b: F1 controls overlay. Toggled by terminal_display on the `help_toggle` action.
# v1 is the glyph-rich reference list (keyboard glyph(s) + generic gamepad glyph + label);
# anchored callouts drawn over the live UI controls are the planned follow-up (per-panel
# get_help_annotations) -- see implementation_plans/m13_playable_sandbox_design.md.
#
# Glyphs are Kenney Input Prompts (CC0), assets/input_prompts/. A missing glyph file just
# renders nothing (load() -> null is skipped), never an error.
const KB := "res://assets/input_prompts/keyboard/"
const PAD := "res://assets/input_prompts/generic/"
const GLYPH_SIZE := 28

# function label, keyboard glyph names, generic gamepad glyph name, gamepad text note.
const ROWS := [
	{"label": "Steer", "keys": ["keyboard_a", "keyboard_d"], "pad": "generic_joystick_left", "pad_text": "Left Stick"},
	{"label": "Throttle", "keys": ["keyboard_w", "keyboard_s"], "pad": "generic_joystick", "pad_text": "Left Stick"},
	{"label": "Fire All", "keys": ["keyboard_space"], "pad": "generic_button_trigger_a", "pad_text": "Right Trigger"},
	{"label": "Target Next / Prev", "keys": ["keyboard_e", "keyboard_q"], "pad": "generic_joystick", "pad_text": "Stick Click"},
	{"label": "Zoom Map", "keys": ["keyboard_equals", "keyboard_minus"], "pad": "generic_joystick", "pad_text": "Right Stick"},
	{"label": "Throttle Mode", "keys": ["keyboard_v"], "pad": "generic_button", "pad_text": "Start"},
	{"label": "Steering Mode", "keys": ["keyboard_c"], "pad": "generic_button", "pad_text": "X"},
	{"label": "Map Orientation", "keys": ["keyboard_m"], "pad": "generic_button", "pad_text": "Y"},
	{"label": "Quit", "keys": ["keyboard_escape"], "pad": "generic_button", "pad_text": "Back"},
	{"label": "Help (this screen)", "keys": ["keyboard_f1"], "pad": "", "pad_text": ""},
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
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
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for row in ROWS:
		var fn := Label.new()
		fn.text = row["label"]
		fn.custom_minimum_size = Vector2(170, 0)
		grid.add_child(fn)

		grid.add_child(_glyph_row(KB, row["keys"]))

		var pad_box := HBoxContainer.new()
		pad_box.add_theme_constant_override("separation", 6)
		if row["pad"] != "":
			var g := _glyph(PAD + row["pad"] + ".svg")
			if g: pad_box.add_child(g)
		if row["pad_text"] != "":
			var t := Label.new()
			t.text = row["pad_text"]
			t.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			pad_box.add_child(t)
		grid.add_child(pad_box)

	vbox.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = "Mouse: drag the helm dial to steer  -  click a contact to target  -  F1 to close"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(footer)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide()

func _glyph_row(dir: String, names: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for n in names:
		var g := _glyph(dir + n + ".svg")
		if g: box.add_child(g)
	return box

func _glyph(path: String) -> TextureRect:
	var tex = load(path)
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r
