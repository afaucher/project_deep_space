extends Control

const UIStyle = preload("res://scripts/ui/ui_style.gd")

signal contact_selected(c_id: String)
signal toggle_changed(s_id: String, is_active: bool)

var sensor_id: String = ""
var current_bins: Array = []
var current_state: Dictionary = {}
var sensor_heading: float = 0.0
var sensor_arc_width: float = TAU
var sensor_range: float = 40000.0
var num_bins: int = 36
var map_zoom: float = 0.3

var my_pos: Vector2 = Vector2.ZERO
var contacts: Dictionary = {}
var selected_contact_id: String = ""

var active_toggle: CheckButton

func _ready() -> void:
	custom_minimum_size = Vector2(300, 300)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	active_toggle = CheckButton.new()
	active_toggle.text = "ON"
	active_toggle.anchor_top = 1.0
	active_toggle.anchor_bottom = 1.0
	active_toggle.offset_top = -40
	active_toggle.offset_bottom = -10
	active_toggle.offset_left = 10
	active_toggle.toggled.connect(_on_toggle)
	add_child(active_toggle)

func _on_toggle(pressed: bool) -> void:
	active_toggle.text = "ON" if pressed else "OFF"
	toggle_changed.emit(sensor_id, pressed)

func set_active(is_active: bool) -> void:
	if is_instance_valid(active_toggle):
		active_toggle.set_pressed_no_signal(is_active)
		active_toggle.text = "ON" if is_active else "OFF"

func update_data(id: String, bins: Array, p_pos: Vector2, c_dict: Dictionary, sel_id: String, state: Dictionary = {}) -> void:
	sensor_id = id
	current_bins = bins
	my_pos = p_pos
	contacts = c_dict
	selected_contact_id = sel_id
	current_state = state
	
	if bins.size() > 0:
		sensor_heading = bins[0].get("sensor_heading", 0.0)
		sensor_arc_width = bins[0].get("sensor_arc_width", TAU)
		sensor_range = bins[0].get("sensor_range", 40000.0)
		var reported_bin_angle = bins[0].get("bin_angle", TAU/36.0)
		num_bins = int(sensor_arc_width / reported_bin_angle) if reported_bin_angle > 0.0 else 1
		
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var center = size / 2.0
		var radius = min(size.x, size.y) / 2.0 - 20.0
		
		var best_dist = 20.0
		var best_id = ""
		
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var c_pos = c.get("pos", Vector2.ZERO)
			var dist = my_pos.distance_to(c_pos)
			if dist > sensor_range: continue

			var angle = (c_pos - my_pos).angle()
			var rel_angle = wrapf(angle - sensor_heading, -PI, PI)

			var half_arc = sensor_arc_width / 2.0
			if rel_angle >= -half_arc and rel_angle <= half_arc:
				var dist_ratio = clampf(dist / sensor_range, 0.0, 1.0)
				var dot_radius = radius * dist_ratio

				var map_rot = Utils.get_map_rotation(current_state.get("is_ship_oriented", false), current_state.get("rot", 0.0))
				var ui_pos = center + Vector2(dot_radius, 0).rotated(angle + map_rot)
				
				var click_dist = event.position.distance_to(ui_pos)
				if click_dist < best_dist:
					best_dist = click_dist
					best_id = c_id
					
		if best_id != "":
			emit_signal("contact_selected", best_id)

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 20.0

	var map_rot = Utils.get_map_rotation(current_state.get("is_ship_oriented", false), current_state.get("rot", 0.0))

	var start_angle = sensor_heading - (sensor_arc_width / 2.0) + map_rot
	var end_angle = sensor_heading + (sensor_arc_width / 2.0) + map_rot
	
	# Draw background arc
	if sensor_arc_width >= TAU - 0.01:
		draw_arc(center, radius, 0, TAU, 64, Color(0.2, 0.5, 0.2, 0.3), 2.0)
	else:
		draw_arc(center, radius, start_angle, end_angle, 32, Color(0.2, 0.5, 0.2, 0.3), 2.0)
		draw_line(center, center + Vector2(radius, 0).rotated(start_angle), Color(0.2, 0.5, 0.2, 0.3), 2.0)
		draw_line(center, center + Vector2(radius, 0).rotated(end_angle), Color(0.2, 0.5, 0.2, 0.3), 2.0)
		
	# Draw range rings
	for i in range(1, 4):
		var r = radius * (i / 4.0)
		if sensor_arc_width >= TAU - 0.01:
			draw_arc(center, r, 0, TAU, 32, Color(0.1, 0.3, 0.1, 0.2), 1.0)
		else:
			draw_arc(center, r, start_angle, end_angle, 16, Color(0.1, 0.3, 0.1, 0.2), 1.0)
			
	# Draw degree tick marks and NESW labels (Global Frame)
	var font = ThemeDB.fallback_font
	for i in range(36):
		var a = i * (TAU / 36.0)
		# Only draw ticks inside the arc if it's a directional scanner
		var rel_angle = wrapf(a - sensor_heading, -PI, PI)
		if sensor_arc_width >= TAU - 0.01 or (rel_angle >= -(sensor_arc_width/2.0) and rel_angle <= (sensor_arc_width/2.0)):
			var p1 = center + Vector2(radius, 0).rotated(a)
			var p2 = center + Vector2(radius + 5, 0).rotated(a)
			var tick_color = Color(0.1, 0.3, 0.1, 0.5)
			if i % 3 == 0:
				tick_color = Color(0.2, 0.5, 0.2, 0.8)
				p2 = center + Vector2(radius + 8, 0).rotated(a)
				
				var label = ""
				var display_angle = int(wrapf(i * 10 + 90, 0, 360))
				if display_angle == 0: label = "N"
				elif display_angle == 90: label = "E"
				elif display_angle == 180: label = "S"
				elif display_angle == 270: label = "W"
				else: label = str(display_angle)
				
				var text_pos = center + Vector2(radius + 20, 0).rotated(a)
				text_pos.y += 4
				text_pos.x -= 8
				draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, UIStyle.FONT_CANVAS_TINY, Color(0.2, 0.5, 0.2, 0.8))
			draw_line(p1, p2, tick_color, 1.0)
			
	# Name label
	draw_string(font, Vector2(10, 20), sensor_id.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.FONT_CANVAS_LARGE, Color.GREEN)
	
	# Bins
	var bin_angle = sensor_arc_width / float(num_bins)
	for sig in current_bins:
		var b_idx = sig.get("bin_idx", 0)
		var b_start = start_angle + (b_idx * bin_angle)
		var b_end = b_start + bin_angle

		# Grey background wedge for hit
		var points = PackedVector2Array()
		points.append(center)
		for i in range(5):
			var a = lerp(b_start, b_end, i / 4.0)
			points.append(center + Vector2(radius, 0).rotated(a))
		points.append(center)
		draw_colored_polygon(points, Color(0.3, 0.3, 0.3, 0.4))

		# Draw dot at distance
		var dist = sig.get("distance", 0.0)
		var dist_ratio = clampf(dist / sensor_range, 0.0, 1.0)
		var dot_radius = radius * dist_ratio

		var b_center = (b_start + b_end) / 2.0
		var dot_pos = center + Vector2(dot_radius, 0).rotated(b_center)

		draw_circle(dot_pos, 4.0, Color.CYAN)

	# Draw highlight
	if selected_contact_id != "" and contacts.has(selected_contact_id):
		var c = contacts[selected_contact_id]
		var dist = my_pos.distance_to(c.get("pos", Vector2.ZERO))
		if dist <= sensor_range:
			var angle = (c.get("pos", Vector2.ZERO) - my_pos).angle()
			var rel_angle = wrapf(angle - sensor_heading, -PI, PI)
			var half_arc = sensor_arc_width / 2.0
			if rel_angle >= -half_arc and rel_angle <= half_arc:
				var dist_ratio = clampf(dist / sensor_range, 0.0, 1.0)
				var dot_radius = radius * dist_ratio
				
				var ui_pos = center + Vector2(dot_radius, 0).rotated(angle + map_rot)
				draw_circle(ui_pos, 10.0, Color(1, 1, 1, 0.5))
				draw_arc(ui_pos, 15.0, 0, TAU, 16, Color.WHITE, 2.0)

	var text = "Range: %s" % Utils.format_dist(sensor_range)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12)
	draw_string(font, size - Vector2(text_size.x + 10, 10), text, HORIZONTAL_ALIGNMENT_RIGHT, -1, UIStyle.FONT_CANVAS, Color.GRAY)