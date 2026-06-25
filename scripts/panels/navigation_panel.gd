extends Control

signal contact_selected(c_id: String)

const WORLD_HALF_EXTENT := 200000.0 # map clamps the camera/grid to +/- this on each axis

var current_state: Dictionary = {
	"pos": Vector2.ZERO,
	"rot": 0.0,
	"vel": Vector2.ZERO
}

var map_zoom: float = 1.0

var zoom_slider: HSlider

var active_lasers: Array = []

# Toggles
var show_weapon_arcs: bool = true
var show_sensor_arcs: bool = false
var show_contact_labels: bool = true
var show_velocity_vectors: bool = true
var show_grid: bool = true

func _ready() -> void:
	clip_contents = true # Ensure drawings don't bleed out of panel
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Top overlay container for controls
	var overlay = HBoxContainer.new()
	overlay.position = Vector2(10, 10)
	overlay.size = Vector2(300, 40)
	add_child(overlay)
	

	
	var zoom_label = Label.new()
	zoom_label.text = "Zoom:"
	overlay.add_child(zoom_label)
	
	zoom_slider = HSlider.new()
	zoom_slider.min_value = 0.01
	zoom_slider.max_value = 2.0
	zoom_slider.step = 0.001
	zoom_slider.exp_edit = true
	zoom_slider.value = 0.5
	zoom_slider.custom_minimum_size = Vector2(100, 20)
	zoom_slider.value_changed.connect(func(val: float):
		map_zoom = val
		queue_redraw()
	)
	overlay.add_child(zoom_slider)
	
	_add_toggle(overlay, "Weapon Arcs", "show_weapon_arcs")
	_add_toggle(overlay, "Sensor Arcs", "show_sensor_arcs")
	_add_toggle(overlay, "Contact Labels", "show_contact_labels")
	_add_toggle(overlay, "Velocity Vectors", "show_velocity_vectors")
	_add_toggle(overlay, "Grid", "show_grid")

# Binds a checkbox directly to one of this panel's own show_* bool properties
# by name, instead of hand-writing a near-identical CheckButton + closure for
# each toggle.
func _add_toggle(parent: Control, label: String, property_name: String) -> void:
	var cb = CheckButton.new()
	cb.text = label
	cb.button_pressed = get(property_name)
	cb.toggled.connect(func(pressed: bool):
		set(property_name, pressed)
		queue_redraw()
	)
	parent.add_child(cb)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_slider.value *= 1.25
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_slider.value /= 1.25
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)

func _handle_click(click_pos: Vector2) -> void:
	var pos = current_state.get("pos", Vector2.ZERO)
	var rot = current_state.get("rot", 0.0)
	var camera_pos = pos
	
	var is_ship_oriented = current_state.get("is_ship_oriented", false)
	if not is_ship_oriented:
		var grid_size = WORLD_HALF_EXTENT
		var visible_half = (size / 2.0) / map_zoom
		if visible_half.x < grid_size:
			camera_pos.x = clampf(camera_pos.x, -grid_size + visible_half.x, grid_size - visible_half.x)
		else:
			camera_pos.x = 0.0
		if visible_half.y < grid_size:
			camera_pos.y = clampf(camera_pos.y, -grid_size + visible_half.y, grid_size - visible_half.y)
		else:
			camera_pos.y = 0.0

	var t = Transform2D()
	t = t.translated(-camera_pos)
	t = t.rotated(Utils.get_map_rotation(is_ship_oriented, rot))
	t = t.scaled(Vector2(map_zoom, map_zoom))
	t.origin += size / 2.0
	
	var best_dist = 20.0 # Pixel radius for clicking
	var best_id = ""
	
	var contacts = current_state.get("contacts", {})
	for c_id in contacts.keys():
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		var screen_pos = t.basis_xform(c_pos) + t.origin
		
		var dist = screen_pos.distance_to(click_pos)
		if dist < best_dist:
			best_dist = dist
			best_id = c_id
			
	if best_id != "":
		emit_signal("contact_selected", best_id)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	if packet.has("transient_events"):
		for ev in packet["transient_events"]:
			if ev["type"] == "laser":
				active_lasers.append({"start": ev["start_pos"], "end": ev["end_pos"], "age": 0.0})
	queue_redraw()

func _process(delta: float) -> void:
	if active_lasers.size() > 0:
		for i in range(active_lasers.size() - 1, -1, -1):
			active_lasers[i]["age"] += delta
			if active_lasers[i]["age"] > 0.1:
				active_lasers.remove_at(i)
		queue_redraw()

func _draw() -> void:
	var is_ship_oriented = current_state.get("is_ship_oriented", false)
	var center = size / 2.0
	var pos = current_state.get("pos", Vector2.ZERO)
	var rot = current_state.get("rot", 0.0)
	var vel = current_state.get("vel", Vector2.ZERO)
	
	# Transform logic
	var grid_size = WORLD_HALF_EXTENT
	var camera_pos = pos
	
	if not is_ship_oriented:
		# Clamp camera so map boundaries don't pan past the center of screen
		var visible_half = (size / 2.0) / map_zoom
		
		if visible_half.x < grid_size:
			camera_pos.x = clampf(camera_pos.x, -grid_size + visible_half.x, grid_size - visible_half.x)
		else:
			camera_pos.x = 0.0
			
		if visible_half.y < grid_size:
			camera_pos.y = clampf(camera_pos.y, -grid_size + visible_half.y, grid_size - visible_half.y)
		else:
			camera_pos.y = 0.0

	var t = Transform2D()
	t = t.translated(-camera_pos) # 1. Move camera target to origin
	t = t.rotated(Utils.get_map_rotation(is_ship_oriented, rot)) # 2. Rotate around origin if needed
	t = t.scaled(Vector2(map_zoom, map_zoom)) # 3. Scale around origin
	t.origin += center # 4. Shift origin to center of screen

	draw_set_transform_matrix(t)
	
	# Draw background grid (Dynamic scale based on zoom)
	var visible_width_world = size.x / map_zoom
	var ideal_step = visible_width_world / 10.0
	var log_step = log(ideal_step) / log(10.0)
	var pow_step = pow(10.0, floor(log_step))
	var grid_step = pow_step
	if ideal_step > pow_step * 5.0:
		grid_step = pow_step * 5.0
	elif ideal_step > pow_step * 2.0:
		grid_step = pow_step * 2.0
	
	grid_step = max(100.0, grid_step)
	
	if show_grid:
		# Calculate visible bounds (using diagonal to account for rotation)
		var visible_radius = (size.length() / 2.0) / map_zoom
		# Pad the bounding box heavily so the square bounds never rotate into the visible screen
		visible_radius += grid_step * 3.0 
		
		var min_x = max(-grid_size, camera_pos.x - visible_radius)
		var max_x = min(grid_size, camera_pos.x + visible_radius)
		var min_y = max(-grid_size, camera_pos.y - visible_radius)
		var max_y = min(grid_size, camera_pos.y + visible_radius)
		
		var start_x = floor(min_x / grid_step) * grid_step
		var start_y = floor(min_y / grid_step) * grid_step
		
		for x in range(start_x, max_x + grid_step, grid_step):
			if x >= -grid_size and x <= grid_size:
				draw_line(Vector2(x, min_y), Vector2(x, max_y), Color(0.1, 0.2, 0.1), 1.0 / map_zoom)
				
		for y in range(start_y, max_y + grid_step, grid_step):
			if y >= -grid_size and y <= grid_size:
				draw_line(Vector2(min_x, y), Vector2(max_x, y), Color(0.1, 0.2, 0.1), 1.0 / map_zoom)
		
	# Draw origin reference
	draw_circle(Vector2.ZERO, 10.0, Color(0.2, 0.2, 0.5))
		
	# Draw velocity vector
	if show_velocity_vectors and vel.length() > 0:
		draw_line(pos, pos + vel * 2.0, Color(0.5, 0.5, 0.0), 2.0 / map_zoom)
		
	# Draw ship rotation indicator
	var forward = Vector2.RIGHT.rotated(rot) * 40.0
	draw_line(pos, pos + forward, Color.CYAN, 2.0 / map_zoom)
	
	# Draw ship blip and physical bounds
	draw_circle(pos, 8.0 / map_zoom, Color.GREEN)
	draw_arc(pos, 50.0, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.5), 2.0 / map_zoom)
	
	# Draw weapon firing arcs
	if show_weapon_arcs:
		var weapons = current_state.get("weapons", []) # Array of ship_components weapon entries
		for w in weapons:
			if w.has("range") and w.has("arc_width") and w.has("heading"):
				var r = w["range"]
				var arc_w = w["arc_width"]
				var w_heading = w["heading"]
				var mount_pos = w.get("rect", Rect2()).position
				var global_mount = pos + mount_pos.rotated(rot)
				
				var start_angle = rot + w_heading - arc_w / 2.0
				var end_angle = rot + w_heading + arc_w / 2.0
				var arc_color = Color(1.0, 0.3, 0.0, 0.2) # slightly more transparent
				draw_arc(global_mount, r, start_angle, end_angle, 32, arc_color, 2.0 / map_zoom)
				draw_line(global_mount, global_mount + Vector2(r, 0).rotated(start_angle), arc_color, 1.0 / map_zoom)
				draw_line(global_mount, global_mount + Vector2(r, 0).rotated(end_angle), arc_color, 1.0 / map_zoom)
				
	# Draw sensor arcs and wedges
	if show_sensor_arcs:
		var sensors_dict = current_state.get("sensors", {})
		for sensor_id in sensors_dict.keys():
			var bins = sensors_dict[sensor_id]
			if bins.size() == 0: continue
			
			var s_heading = bins[0].get("sensor_heading", 0.0)
			var s_arc_width = bins[0].get("sensor_arc_width", TAU)
			var s_range = bins[0].get("sensor_range", 40000.0)
			var bin_angle = bins[0].get("bin_angle", TAU/36.0)
			
			if s_arc_width >= TAU - 0.01:
				draw_arc(pos, s_range, 0, TAU, 64, Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
			else:
				var s_start = s_heading - (s_arc_width / 2.0)
				var s_end = s_heading + (s_arc_width / 2.0)
				draw_arc(pos, s_range, s_start, s_end, 32, Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				draw_line(pos, pos + Vector2(s_range, 0).rotated(s_start), Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				draw_line(pos, pos + Vector2(s_range, 0).rotated(s_end), Color(0.2, 0.8, 0.8, 0.4), 2.0 / map_zoom)
				
			var s_start_angle = s_heading - (s_arc_width / 2.0)
			for sig in bins:
				var b_idx = sig.get("bin_idx", 0)
				var b_start = s_start_angle + (b_idx * bin_angle)
				var b_end = b_start + bin_angle

				var dist = sig.get("distance", 0.0)
				var b_center = (b_start + b_end) / 2.0
				var dot_pos = pos + Vector2(dist, 0).rotated(b_center)

				var color = Color.YELLOW
				if sensor_id == Utils.HIGHLIGHT_SENSOR_ID: color = Color.CYAN
				elif sensor_id == "omni_short_hi_res": color = Color.ORANGE
				draw_circle(dot_pos, 4.0 / map_zoom, color)
	
	# Draw Contacts
	var contacts = current_state.get("contacts", {})
	for c_id in contacts.keys():
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		var color = _get_contact_color(c)
		draw_circle(c_pos, 8.0 / map_zoom, color)
		
		# Draw physical bounds (estimated from radar cross section)
		var cross_section = c.get("signature", {}).get("cross_section", 0.0)
		if cross_section > 0:
			var estimated_radius = sqrt(max(0.0, cross_section)) * 10.0 # arbitrary visual scaling
			draw_arc(c_pos, estimated_radius, 0, TAU, 16, color, 1.0 / map_zoom)
			
		# Draw velocity vector
		if show_velocity_vectors and c.get("vel", Vector2.ZERO).length() > 0:
			draw_line(c_pos, c_pos + c.get("vel", Vector2.ZERO) * 2.0, color, 1.0 / map_zoom)

	# Contact labels are drawn later, after the transform reset below --
	# world-space text would scale with map_zoom otherwise.

	# Draw active lasers
	for laser in active_lasers:
		var alpha = max(0.0, 1.0 - (laser["age"] / 0.1))
		draw_line(laser["start"], laser["end"], Color(1.0, 0.2, 0.2, alpha), 2.0 / map_zoom)

	# Draw HUD overlay (Reset Transform)
	draw_set_transform_matrix(Transform2D())
	
	var selected_id = current_state.get("selected_contact_id", "")
	
	if show_contact_labels or selected_id != "":
		var font = ThemeDB.fallback_font
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var c_pos = c.get("pos", Vector2.ZERO)
			var screen_pos = t.basis_xform(c_pos) + t.origin
			var color = _get_contact_color(c)
			
			if show_contact_labels:
				draw_string(font, screen_pos + Vector2(10, 10), c_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
				
			if c_id == selected_id:
				# Draw bracket
				var b_size = 15.0
				draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size/2, -b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(-b_size, -b_size), screen_pos + Vector2(-b_size, -b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size/2, -b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(b_size, -b_size), screen_pos + Vector2(b_size, -b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size/2, b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(-b_size, b_size), screen_pos + Vector2(-b_size, b_size/2), Color.WHITE, 2.0)
				
				draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size/2, b_size), Color.WHITE, 2.0)
				draw_line(screen_pos + Vector2(b_size, b_size), screen_pos + Vector2(b_size, b_size/2), Color.WHITE, 2.0)
	
	# Scale Reference
	if show_grid:
		var scale_text = "Grid: %s" % Utils.format_dist(grid_step)
		var scale_font = ThemeDB.fallback_font
		var scale_text_size = scale_font.get_string_size(scale_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14)
		
		var ref_len = grid_step * map_zoom
		var bottom_right = size - Vector2(20, 20)
		
		# Draw line
		draw_line(bottom_right - Vector2(ref_len, 0), bottom_right, Color.WHITE, 2.0)
		# Draw tick marks
		draw_line(bottom_right - Vector2(ref_len, 5), bottom_right - Vector2(ref_len, -5), Color.WHITE, 2.0)
		draw_line(bottom_right - Vector2(0, 5), bottom_right - Vector2(0, -5), Color.WHITE, 2.0)
		
		# Draw text centered above the line
		var scale_text_pos = bottom_right - Vector2(ref_len / 2.0 + scale_text_size.x / 2.0, 10)
		draw_string(scale_font, scale_text_pos, scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)



	# Reset transform to draw absolute overlays (UI, Compass)
	draw_set_transform_matrix(Transform2D())
	
	# Draw Compass Ring
	var compass_radius = min(size.x, size.y) / 2.0 - 40.0
	draw_arc(center, compass_radius, 0, PI*2, 64, Color(0.0, 0.5, 0.0, 0.3), 2.0)
	
	var map_rot = Utils.get_map_rotation(is_ship_oriented, rot)

	var font = ThemeDB.fallback_font
	var font_size = 14

	for i in range(0, 360, 30):
		var draw_angle = deg_to_rad(i - 90.0) + map_rot

		var dir = Vector2.RIGHT.rotated(draw_angle)
		var p1 = center + dir * compass_radius
		var p2 = center + dir * (compass_radius + 10.0)

		var style = Utils.compass_tick_style(i)
		draw_line(p1, p2, style["color"], style["width"])

		var text_pos = center + dir * (compass_radius + 25.0)
		var text = Utils.compass_label_text(i)

		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, text_pos - text_size / 2.0 + Vector2(0, font_size / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, style["color"])
	
	# Draw telemetry text
	var default_font_size = 16
	draw_string(font, Vector2(10, size.y - 40), "X: %.2f Y: %.2f" % [pos.x, pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, Color.GREEN)
	draw_string(font, Vector2(10, size.y - 20), "SPD: %.2f HDG: %.2f" % [vel.length(), wrapf(rad_to_deg(rot) + 90.0, 0.0, 360.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, Color.GREEN)

	# Draw Pinned Contact Off-screen Indicators
	var pinned_contacts = current_state.get("pinned_contacts", [])
	var rect = Rect2(Vector2.ZERO, size)
	var margin = 30.0
	var safe_rect = rect.grow(-margin)
	
	for c_id in pinned_contacts:
		if not contacts.has(c_id): continue
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		
		# Transform world pos to screen pos manually
		var screen_pos = t.basis_xform(c_pos) + t.origin
		
		if not safe_rect.has_point(screen_pos):
			# It's off screen, calculate edge intersection
			var offset = screen_pos - center
			var x_ratio = abs(offset.x) / (size.x/2.0 - margin)
			var y_ratio = abs(offset.y) / (size.y/2.0 - margin)
			var max_ratio = max(x_ratio, y_ratio)
			if max_ratio <= 0.0: continue # contact is dead-center, can't be off-screen -- avoid a divide-by-zero

			var edge_pos = center + offset / max_ratio
			
			var dir_to_contact = offset.normalized()
			
			# Draw an arrow at edge_pos pointing outward
			var p_tip = edge_pos + dir_to_contact * 10.0
			var p_left = edge_pos + dir_to_contact.rotated(PI * 0.8) * 10.0
			var p_right = edge_pos + dir_to_contact.rotated(-PI * 0.8) * 10.0
			
			var color = _get_contact_color(c)
			
			var pts = PackedVector2Array([p_tip, p_left, p_right])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([p_tip, p_left, p_right, p_tip]), color, 2.0)
			
			
			# Draw label
			var text_size = font.get_string_size(c_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			var label_pos = edge_pos - dir_to_contact * 15.0 - Vector2(text_size.x/2.0, -text_size.y/3.0)
			draw_string(font, label_pos, c_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)

func _get_contact_color(c: Dictionary) -> Color:
	return Utils.classification_color(c.get("classification", ""))

