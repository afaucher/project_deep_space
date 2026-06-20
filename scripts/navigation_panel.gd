extends Control

var current_state: Dictionary = {
	"pos": Vector2.ZERO,
	"rot": 0.0,
	"vel": Vector2.ZERO
}

var map_zoom: float = 1.0
var is_ship_oriented: bool = false
var zoom_slider: HSlider

func _ready() -> void:
	clip_contents = true # Ensure drawings don't bleed out of panel
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Top overlay container for controls
	var overlay = HBoxContainer.new()
	overlay.position = Vector2(10, 10)
	overlay.size = Vector2(300, 40)
	add_child(overlay)
	
	var orient_btn = CheckButton.new()
	orient_btn.text = "Ship Oriented"
	orient_btn.toggled.connect(func(pressed: bool): 
		is_ship_oriented = pressed
		queue_redraw()
	)
	overlay.add_child(orient_btn)
	
	var zoom_label = Label.new()
	zoom_label.text = "Zoom:"
	overlay.add_child(zoom_label)
	
	zoom_slider = HSlider.new()
	zoom_slider.min_value = 0.01
	zoom_slider.max_value = 2.0
	zoom_slider.step = 0.01
	zoom_slider.value = 0.5
	zoom_slider.custom_minimum_size = Vector2(100, 20)
	zoom_slider.value_changed.connect(func(val: float):
		map_zoom = val
		queue_redraw()
	)
	overlay.add_child(zoom_slider)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_slider.value += 0.05
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_slider.value -= 0.05
			accept_event()

func update_data(packet: Dictionary) -> void:
	current_state = packet
	queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	var pos = current_state.get("pos", Vector2.ZERO)
	var rot = current_state.get("rot", 0.0)
	var vel = current_state.get("vel", Vector2.ZERO)
	
	# Transform logic
	var grid_size = 200000.0
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
	if is_ship_oriented:
		t = t.rotated(-rot - PI/2.0) # 2. Rotate around origin if needed
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
	if vel.length() > 0:
		draw_line(pos, pos + vel * 2.0, Color(0.5, 0.5, 0.0), 2.0 / map_zoom)
		
	# Draw ship rotation indicator
	var forward = Vector2.RIGHT.rotated(rot) * 40.0
	draw_line(pos, pos + forward, Color.CYAN, 2.0 / map_zoom)
	
	# Draw ship blip and physical bounds
	draw_circle(pos, 8.0 / map_zoom, Color.GREEN)
	draw_arc(pos, 50.0, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.5), 2.0 / map_zoom)
	
	# Draw Contacts
	var contacts = current_state.get("contacts", {})
	for c_id in contacts.keys():
		var c = contacts[c_id]
		var c_pos = c.get("pos", Vector2.ZERO)
		var is_enemy = (c.get("classification") == "UNIDENTIFIED VESSEL")
		var color = Color.RED if is_enemy else Color.WHITE
		draw_circle(c_pos, 8.0 / map_zoom, color)
		
		# Draw physical bounds (estimated from radar cross section)
		var cross_section = c.get("signature", {}).get("cross_section", 0.0)
		if cross_section > 0:
			draw_arc(c_pos, cross_section, 0, TAU, 32, Color(color.r, color.g, color.b, 0.3), 2.0 / map_zoom)
			
		# Draw a small velocity vector
		var c_vel = c.get("vel", Vector2.ZERO)
		if c_vel.length() > 0:
			draw_line(c_pos, c_pos + c_vel * 2.0, color, 1.0 / map_zoom)
	
	# Reset transform to draw absolute overlays (UI, Compass)
	draw_set_transform_matrix(Transform2D())
	
	# Draw Compass Ring
	var compass_radius = min(size.x, size.y) / 2.0 - 40.0
	draw_arc(center, compass_radius, 0, PI*2, 64, Color(0.0, 0.5, 0.0, 0.3), 2.0)
	
	var map_rot = 0.0
	if is_ship_oriented:
		map_rot = -rot - PI/2.0
		
	var font = ThemeDB.fallback_font
	var font_size = 14
	
	for i in range(0, 360, 30):
		var godot_angle = deg_to_rad(i - 90.0)
		var draw_angle = godot_angle + map_rot
		
		var dir = Vector2.RIGHT.rotated(draw_angle)
		var p1 = center + dir * compass_radius
		var p2 = center + dir * (compass_radius + 10.0)
		
		# Make cardinal directions stand out
		var is_cardinal = (i % 90 == 0)
		var tick_color = Color.GREEN if is_cardinal else Color(0.0, 0.8, 0.0, 0.6)
		var tick_width = 3.0 if is_cardinal else 1.0
		draw_line(p1, p2, tick_color, tick_width)
		
		var text_pos = center + dir * (compass_radius + 25.0)
		var text = str(i)
		if i == 0: text = "N"
		elif i == 90: text = "E"
		elif i == 180: text = "S"
		elif i == 270: text = "W"
		
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, text_pos - text_size / 2.0 + Vector2(0, font_size / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, tick_color)
	
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
			
			var edge_pos = center + offset / max_ratio
			
			var dir_to_contact = offset.normalized()
			
			# Draw an arrow at edge_pos pointing outward
			var p_tip = edge_pos + dir_to_contact * 10.0
			var p_left = edge_pos + dir_to_contact.rotated(PI * 0.8) * 10.0
			var p_right = edge_pos + dir_to_contact.rotated(-PI * 0.8) * 10.0
			
			var is_enemy = (c.get("classification") == "UNIDENTIFIED VESSEL")
			var color = Color.RED if is_enemy else Color.WHITE
			
			var pts = PackedVector2Array([p_tip, p_left, p_right])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([p_tip, p_left, p_right, p_tip]), color, 2.0)
			
			# Draw label
			var text_size = font.get_string_size(c_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			var label_pos = edge_pos - dir_to_contact * 15.0 - Vector2(text_size.x/2.0, -text_size.y/3.0)
			draw_string(font, label_pos, c_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)
