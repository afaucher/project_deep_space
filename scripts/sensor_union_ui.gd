extends Control

signal contact_selected(c_id: String)

var current_sensors_dict: Dictionary = {}
var my_pos: Vector2 = Vector2.ZERO
var contacts: Dictionary = {}
var selected_contact_id: String = ""

# Master scale: 40,000m (the max range of our main scanner)
const MASTER_RANGE = 40000.0

func _ready() -> void:
	custom_minimum_size = Vector2(500, 300)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func update_data(sensors_dict: Dictionary, p_pos: Vector2, c_dict: Dictionary, sel_id: String) -> void:
	current_sensors_dict = sensors_dict
	my_pos = p_pos
	contacts = c_dict
	selected_contact_id = sel_id
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var center = size / 2.0
		var radius = min(size.x, size.y) / 2.0 - 20.0
		
		var best_dist = 20.0
		var best_id = ""
		
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var dist = my_pos.distance_to(c["pos"])
			if dist > MASTER_RANGE: continue
			
			var angle = my_pos.angle_to_point(c["pos"])
			var dist_ratio = clampf(dist / MASTER_RANGE, 0.0, 1.0)
			var dot_radius = radius * dist_ratio
			var ui_pos = center + Vector2(dot_radius, 0).rotated(angle)
			
			var click_dist = event.position.distance_to(ui_pos)
			if click_dist < best_dist:
				best_dist = click_dist
				best_id = c_id
				
		if best_id != "":
			emit_signal("contact_selected", best_id)

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 20.0
	
	# 1. Draw Master Rings
	for i in range(1, 5):
		var r = radius * (i / 4.0)
		draw_arc(center, r, 0, TAU, 32, Color(0.1, 0.3, 0.1, 0.2), 1.0)
		
	# 2. Draw Global Tick Marks
	var font = ThemeDB.fallback_font
	for i in range(36):
		var a = i * (TAU / 36.0)
		var p1 = center + Vector2(radius, 0).rotated(a)
		var p2 = center + Vector2(radius + 5, 0).rotated(a)
		var tick_color = Color(0.1, 0.3, 0.1, 0.5)
		if i % 9 == 0:
			tick_color = Color(0.2, 0.5, 0.2, 0.8)
			p2 = center + Vector2(radius + 8, 0).rotated(a)
			
			var label = ""
			if i == 0: label = "090"
			elif i == 9: label = "180"
			elif i == 18: label = "270"
			elif i == 27: label = "000"
			
			var text_pos = center + Vector2(radius + 20, 0).rotated(a)
			text_pos.y += 4
			text_pos.x -= 12
			draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 0.5, 0.2, 0.8))
		draw_line(p1, p2, tick_color, 1.0)
		
	# 3. Draw Each Sensor's Coverage Arc
	for sensor_id in current_sensors_dict.keys():
		var bins = current_sensors_dict[sensor_id]
		if bins.size() == 0: continue
		
		var s_heading = bins[0].get("sensor_heading", 0.0)
		var s_arc_width = bins[0].get("sensor_arc_width", TAU)
		var s_range = bins[0].get("sensor_range", MASTER_RANGE)
		
		var s_radius = radius * (s_range / MASTER_RANGE)
		
		if s_arc_width >= TAU - 0.01:
			draw_arc(center, s_radius, 0, TAU, 64, Color(0.2, 0.5, 0.2, 0.4), 2.0)
		else:
			var s_start = s_heading - (s_arc_width / 2.0)
			var s_end = s_heading + (s_arc_width / 2.0)
			draw_arc(center, s_radius, s_start, s_end, 32, Color(0.2, 0.8, 0.8, 0.4), 2.0)
			draw_line(center, center + Vector2(s_radius, 0).rotated(s_start), Color(0.2, 0.8, 0.8, 0.4), 2.0)
			draw_line(center, center + Vector2(s_radius, 0).rotated(s_end), Color(0.2, 0.8, 0.8, 0.4), 2.0)
	
	# 4. Draw Sensor Returns (Wedges and Dots)
	for sensor_id in current_sensors_dict.keys():
		var bins = current_sensors_dict[sensor_id]
		if bins.size() == 0: continue
		var s_heading = bins[0].get("sensor_heading", 0.0)
		var s_arc_width = bins[0].get("sensor_arc_width", TAU)
		var s_range = bins[0].get("sensor_range", MASTER_RANGE)
		var bin_angle = bins[0].get("bin_angle", TAU/36.0)
		var s_start_angle = s_heading - (s_arc_width / 2.0)
		
		var s_radius = radius * (s_range / MASTER_RANGE)
		
		for sig in bins:
			var b_idx = sig["bin_idx"]
			var b_start = s_start_angle + (b_idx * bin_angle)
			var b_end = b_start + bin_angle
			
			var points = PackedVector2Array()
			points.append(center)
			for i in range(5):
				var a = lerp(b_start, b_end, i / 4.0)
				points.append(center + Vector2(s_radius, 0).rotated(a))
			points.append(center)
			draw_colored_polygon(points, Color(0.3, 0.3, 0.3, 0.2)) # More transparent wedges for union view
			
			var dist = sig.get("distance", 0.0)
			var dist_ratio = clampf(dist / MASTER_RANGE, 0.0, 1.0)
			var dot_radius = radius * dist_ratio
			var b_center = (b_start + b_end) / 2.0
			var dot_pos = center + Vector2(dot_radius, 0).rotated(b_center)
			
			var color = Color.YELLOW
			if sensor_id == "dir_high_res": color = Color.CYAN
			elif sensor_id == "omni_short_hi_res": color = Color.ORANGE
			draw_circle(dot_pos, 4.0, color)
			
	# 5. Draw Target Highlight
	if selected_contact_id != "" and contacts.has(selected_contact_id):
		var c = contacts[selected_contact_id]
		var dist = my_pos.distance_to(c["pos"])
		if dist <= MASTER_RANGE:
			var angle = my_pos.angle_to_point(c["pos"])
			var dist_ratio = clampf(dist / MASTER_RANGE, 0.0, 1.0)
			var dot_radius = radius * dist_ratio
			var ui_pos = center + Vector2(dot_radius, 0).rotated(angle)
			draw_circle(ui_pos, 10.0, Color(1, 1, 1, 0.5))
			draw_arc(ui_pos, 15.0, 0, TAU, 16, Color.WHITE, 2.0)
			
	# Name label
	draw_string(font, Vector2(10, 20), "UNION SENSOR VIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
