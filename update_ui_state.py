import re

def update_file(filename, callback):
    with open(filename, 'r') as f:
        content = f.read()
    content = callback(content)
    with open(filename, 'w') as f:
        f.write(content)

# 1. terminal_display.gd
def update_terminal(content):
    # Add toggle to top bar
    bar_code = """	var eng_toggle = CheckButton.new()
	eng_toggle.text = "Engineering"
	eng_toggle.button_pressed = true
	top_bar.add_child(eng_toggle)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	var ship_oriented_toggle = CheckButton.new()
	ship_oriented_toggle.text = "Ship Oriented"
	ship_oriented_toggle.button_pressed = false
	ship_oriented_toggle.toggled.connect(func(pressed): current_ship_oriented = pressed)
	top_bar.add_child(ship_oriented_toggle)"""
    
    content = content.replace('var pinned_contacts: Array = []', 'var pinned_contacts: Array = []\nvar current_ship_oriented: bool = false')
    content = re.sub(r'\tvar eng_toggle = CheckButton\.new\(\).*?top_bar\.add_child\(eng_toggle\)', bar_code, content, flags=re.DOTALL)
    
    # Inject state
    state_code = """func update_data(packet: Dictionary) -> void:
	# Inject local UI state into the packet so sub-panels can read it
	packet["pinned_contacts"] = pinned_contacts
	packet["is_ship_oriented"] = current_ship_oriented"""
    content = content.replace('func update_data(packet: Dictionary) -> void:\n\t# Inject local UI state into the packet so sub-panels can read it\n\tpacket["pinned_contacts"] = pinned_contacts', state_code)
    return content

# 2. navigation_panel.gd
def update_nav(content):
    content = content.replace('var is_ship_oriented: bool = false', '')
    content = re.sub(r'\tvar toggle = CheckButton\.new\(\)\n\ttoggle\.text = "Ship Oriented"\n\ttoggle\.toggled\.connect\(_on_ship_oriented_toggled\)\n\tpanel\.add_child\(toggle\)\n\n', '', content)
    content = re.sub(r'func _on_ship_oriented_toggled\(pressed: bool\) -> void:\n\tis_ship_oriented = pressed\n\tqueue_redraw\(\)\n', '', content)
    
    content = content.replace('if not is_ship_oriented:', 'var is_ship_oriented = current_state.get("is_ship_oriented", false)\n\tif not is_ship_oriented:')
    
    # Wait, is_ship_oriented is accessed multiple times. We should just read it at the top of functions.
    # _gui_input
    gui_input_repl = """func _gui_input(event: InputEvent) -> void:
	var is_ship_oriented = current_state.get("is_ship_oriented", false)"""
    content = content.replace('func _gui_input(event: InputEvent) -> void:', gui_input_repl)
    
    # _draw
    draw_repl = """func _draw() -> void:
	var is_ship_oriented = current_state.get("is_ship_oriented", false)"""
    content = content.replace('func _draw() -> void:', draw_repl)
    
    return content

# 3. engineering_panel.gd
def update_eng(content):
    # Pass state to EMChart
    update_data_repl = """		var is_ship_oriented = current_state.get("is_ship_oriented", false)
		em_chart.is_ship_oriented = is_ship_oriented
		em_chart.ship_rot = current_state.get("rot", 0.0)
		em_chart.em_value = em_sig"""
    content = content.replace('em_chart.em_value = em_sig', update_data_repl)
    
    # EMChart fields
    chart_fields = """class EMPolarChart extends Control:
	var em_value: float = 0.0
	var sensor_config: Array = []
	var is_ship_oriented: bool = false
	var ship_rot: float = 0.0"""
    content = content.replace('class EMPolarChart extends Control:\n\tvar em_value: float = 0.0\n\tvar sensor_config: Array = []', chart_fields)
    
    # EMChart draw logic
    em_draw_repl = """					var s_arc = s.get("arc_width", TAU)
					var s_heading = s.get("heading", 0.0)
					if is_ship_oriented:
						s_heading += -PI/2.0
					else:
						s_heading += ship_rot
						
					var diff = abs(wrapf(a - s_heading, -PI, PI))"""
    content = re.sub(r'\t\t\t\t\tvar s_arc = s\.get\("arc_width", TAU\)\n\t\t\t\t\tvar s_heading = s\.get\("heading", 0\.0\) - PI/2\.0 .*?\n\t\t\t\t\tvar diff = abs\(wrapf\(a - s_heading, -PI, PI\)\)', em_draw_repl, content)
    
    return content

# 4. sensor_module_ui.gd
def update_sensor(content):
    content = content.replace('var current_bins: Array = []', 'var current_bins: Array = []\nvar current_state: Dictionary = {}')
    
    update_data_repl = """func update_data(id: String, bins: Array, p_pos: Vector2, c_dict: Dictionary, sel_id: String) -> void:
	sensor_id = id
	current_bins = bins
	my_pos = p_pos
	contacts = c_dict
	selected_contact_id = sel_id"""
    content = content.replace(update_data_repl, """func update_data(id: String, bins: Array, p_pos: Vector2, c_dict: Dictionary, sel_id: String, state: Dictionary = {}) -> void:
	sensor_id = id
	current_bins = bins
	my_pos = p_pos
	contacts = c_dict
	selected_contact_id = sel_id
	current_state = state""")
    
    # In sensor_panel.gd we need to pass `packet` as the 6th arg to `update_data`! We'll do that in another function.
    
    # Draw logic
    draw_repl = """func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 20.0
	
	var is_ship_oriented = current_state.get("is_ship_oriented", false)
	var ship_rot = current_state.get("rot", 0.0)
	var map_rot = 0.0
	if is_ship_oriented:
		map_rot = -ship_rot - PI/2.0
		
	var start_angle = sensor_heading - (sensor_arc_width / 2.0) + map_rot
	var end_angle = sensor_heading + (sensor_arc_width / 2.0) + map_rot"""
    content = re.sub(r'func _draw\(\) -> void:\n\tvar center = size / 2\.0\n\tvar radius = min\(size\.x, size\.y\) / 2\.0 - 20\.0\n\t\n\tvar start_angle = sensor_heading - \(sensor_arc_width / 2\.0\)\n\tvar end_angle = sensor_heading \+ \(sensor_arc_width / 2\.0\)', draw_repl, content)
    
    # Update all drawing angles
    content = content.replace('var ui_pos = center + Vector2(dist, 0).rotated(angle)', 'var ui_pos = center + Vector2(dist, 0).rotated(angle + map_rot)')
    content = content.replace('var dot_pos = center + Vector2(dot_radius, 0).rotated(angle)', 'var dot_pos = center + Vector2(dot_radius, 0).rotated(angle + map_rot)')
    content = content.replace('var b_start = sensor_heading - (sensor_arc_width / 2.0) + (i * bin_angle)', 'var b_start = sensor_heading - (sensor_arc_width / 2.0) + (i * bin_angle) + map_rot')
    
    # In gui_input
    input_repl = """			if rel_angle >= -half_arc and rel_angle <= half_arc:
				var dist_ratio = clampf(dist / sensor_range, 0.0, 1.0)
				var dot_radius = radius * dist_ratio
				
				var is_ship_oriented = current_state.get("is_ship_oriented", false)
				var ship_rot = current_state.get("rot", 0.0)
				var map_rot = 0.0
				if is_ship_oriented:
					map_rot = -ship_rot - PI/2.0
					
				var ui_pos = center + Vector2(dot_radius, 0).rotated(angle + map_rot)"""
    content = re.sub(r'\t\t\tif rel_angle >= -half_arc and rel_angle <= half_arc:\n\t\t\t\tvar dist_ratio = clampf\(dist / sensor_range, 0\.0, 1\.0\)\n\t\t\t\tvar dot_radius = radius \* dist_ratio\n\t\t\t\tvar ui_pos = center \+ Vector2\(dot_radius, 0\)\.rotated\(angle\)', input_repl, content)

    # Add range text at the bottom
    content += """
	var font = ThemeDB.fallback_font
	var text = "Range: %.1f km" % (sensor_range / 1000.0)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14)
	draw_string(font, size - Vector2(text_size.x + 10, 10), text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, Color.GRAY)"""
    return content

# 5. sensor_panel.gd
def update_sensor_panel(content):
    content = content.replace('mod.update_data(sensor_id, bins, my_pos, contacts, selected_contact_id)', 'mod.update_data(sensor_id, bins, my_pos, contacts, selected_contact_id, current_state)')
    return content

# 6. helm_panel.gd
def update_helm(content):
    content = content.replace('heading_dial.target_angle = target_heading', 'heading_dial.target_angle = target_heading\n\t\theading_dial.is_ship_oriented = current_state.get("is_ship_oriented", false)')
    
    fields = """class HeadingDial extends Control:
	signal target_angle_changed(angle: float)
	var target_angle: float = 0.0
	var actual_angle: float = 0.0
	var is_ship_oriented: bool = false"""
    content = content.replace('class HeadingDial extends Control:\n\tsignal target_angle_changed(angle: float)\n\tvar target_angle: float = 0.0\n\tvar actual_angle: float = 0.0', fields)
    
    gui_input_repl = """			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var center = size / 2.0
				var clicked_angle = center.angle_to_point(get_local_mouse_position())
				if is_ship_oriented:
					clicked_angle += actual_angle + PI/2.0
				target_angle = wrapf(clicked_angle, -PI, PI)"""
    content = re.sub(r'\t\t\tif Input\.is_mouse_button_pressed\(MOUSE_BUTTON_LEFT\):\n\t\t\t\tvar center = size / 2\.0\n\t\t\t\ttarget_angle = center\.angle_to_point\(get_local_mouse_position\(\)\)', gui_input_repl, content)
    
    draw_repl = """		var font_size = 12
		var map_rot = 0.0
		if is_ship_oriented:
			map_rot = -actual_angle - PI/2.0
			
		for i in range(0, 360, 30):
			var godot_angle = deg_to_rad(i - 90.0)
			var draw_angle = godot_angle + map_rot
			var dir = Vector2.RIGHT.rotated(draw_angle)"""
    content = re.sub(r'\t\tvar font_size = 12\n\t\tfor i in range\(0, 360, 30\):\n\t\t\tvar godot_angle = deg_to_rad\(i - 90\.0\)\n\t\t\tvar dir = Vector2\.RIGHT\.rotated\(godot_angle\)', draw_repl, content)

    # needles
    needle_repl = """		# Draw ghost needle (Target)
		var draw_target = target_angle + map_rot
		var ghost_end = center + Vector2.RIGHT.rotated(draw_target) * radius
		draw_line(center, ghost_end, Color(0.5, 0.5, 0.5, 0.5), 6.0)
		
		# Draw actual needle
		var draw_actual = actual_angle + map_rot
		var actual_end = center + Vector2.RIGHT.rotated(draw_actual) * radius"""
    content = re.sub(r'\t\t# Draw ghost needle \(Target\)\n\t\tvar ghost_end = center \+ Vector2\.RIGHT\.rotated\(target_angle\) \* radius\n\t\tdraw_line\(center, ghost_end, Color\(0\.5, 0\.5, 0\.5, 0\.5\), 6\.0\)\n\t\t\n\t\t# Draw actual needle\n\t\tvar actual_end = center \+ Vector2\.RIGHT\.rotated\(actual_angle\) \* radius', needle_repl, content)
    
    return content


update_file('scripts/terminal_display.gd', update_terminal)
update_file('scripts/navigation_panel.gd', update_nav)
update_file('scripts/engineering_panel.gd', update_eng)
update_file('scripts/sensor_module_ui.gd', update_sensor)
update_file('scripts/sensor_panel.gd', update_sensor_panel)
update_file('scripts/helm_panel.gd', update_helm)
print("Finished updates.")
