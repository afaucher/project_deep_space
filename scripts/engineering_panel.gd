extends Control

signal component_power_toggled(component_id: String, is_active: bool)

var current_state: Dictionary = {}

var top_hbox: HBoxContainer
var heat_bar: ProgressBar
var heat_gen_bar: ProgressBar
var em_chart: EMPolarChart
var spatial_view: ComponentSpatialView
var components_vbox: VBoxContainer
var comp_rows: Dictionary = {}

var lbl_peak_em: Label
var lbl_det_dist: Label

class EMPolarChart extends Control:
	var em_value: float = 0.0
	var sensor_config: Array = []
	var is_ship_oriented: bool = false
	var ship_rot: float = 0.0
	
	func _process(delta: float) -> void:
		queue_redraw()
	
	func _draw() -> void:
		var center = size / 2.0
		var max_radius = min(size.x, size.y) / 2.0 - 5.0
		# draw rings
		draw_arc(center, max_radius, 0, TAU, 32, Color(0.2, 0.4, 0.2, 0.5), 1.0)
		draw_arc(center, max_radius * 0.66, 0, TAU, 32, Color(0.2, 0.4, 0.2, 0.5), 1.0)
		draw_arc(center, max_radius * 0.33, 0, TAU, 32, Color(0.2, 0.4, 0.2, 0.5), 1.0)
		
		draw_line(center - Vector2(max_radius, 0), center + Vector2(max_radius, 0), Color(0.2, 0.4, 0.2, 0.5), 1.0)
		draw_line(center - Vector2(0, max_radius), center + Vector2(0, max_radius), Color(0.2, 0.4, 0.2, 0.5), 1.0)
		
		# draw radiation pattern
		var pts = PackedVector2Array()
		var random = RandomNumberGenerator.new()
		var time_offset = Time.get_ticks_msec() / 100 # Change every 100ms
		random.seed = 12345 + int(em_value) + time_offset
		
		var base_radius = (em_value / 400.0) * max_radius
		
		for i in range(32):
			var a = (i / 32.0) * TAU
			
			var rear_angle = ship_rot + PI
			if is_ship_oriented:
				rear_angle = PI / 2.0
				
			var rear_bias = 1.0 + 0.5 * max(0.0, cos(a - rear_angle))
			var local_r = base_radius * rear_bias
			
			for s in sensor_config:
				if s.get("type", "") == "active" and s.get("active", true):
					var s_arc = s.get("arc_width", TAU)
					var s_heading = s.get("heading", 0.0)
					if is_ship_oriented:
						s_heading = (s_heading - ship_rot) - PI/2.0
					# else: s_heading is already absolute world heading
						
					var diff = abs(wrapf(a - s_heading, -PI, PI))
					if diff <= s_arc / 2.0:
						var s_power = s.get("em_emission", 0.0)
						local_r += (s_power / 200.0) * max_radius * (1.0 - diff/(s_arc/2.0))
			
			var noise = random.randf_range(0.9, 1.1)
			var r = min(max_radius, local_r * noise)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
			
		if pts.size() > 0:
			pts.append(pts[0])
			draw_polygon(pts, PackedColorArray([Color(0.2, 0.6, 1.0, 0.5)]))
			draw_polyline(pts, Color(0.2, 0.8, 1.0, 1.0), 2.0)

class ComponentSpatialView extends Control:
	var eng_state: Dictionary = {}
	var font: Font
	
	func _ready() -> void:
		font = ThemeDB.fallback_font
	
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08), true)
		
		var center = size / 2.0
		var scale_factor = 3.0
		
		var min_x = INF; var max_x = -INF
		var min_y = INF; var max_y = -INF
		
		if eng_state.has("ship_components"):
			for c in eng_state["ship_components"]:
				var r: Rect2 = c["rect"]
				min_x = min(min_x, r.position.x)
				max_x = max(max_x, r.position.x + r.size.x)
				min_y = min(min_y, r.position.y)
				max_y = max(max_y, r.position.y + r.size.y)
		
		var offset_x = 0.0
		var offset_y = 0.0
		
		if min_x != INF:
			var ship_w = max_y - min_y # Y is width in UI space
			var ship_h = max_x - min_x # X is height in UI space
			offset_x = (min_y + max_y) / 2.0
			offset_y = (min_x + max_x) / 2.0
			
			if ship_w > 0 and ship_h > 0:
				var scale_w = size.x / (ship_w * 1.2)
				var scale_h = size.y / (ship_h * 1.2)
				scale_factor = min(scale_w, scale_h)
		
		if eng_state.has("ship_components"):
			for c in eng_state["ship_components"]:
				var r: Rect2 = c["rect"]
				var health_ratio = max(0.0, c["health"]) / max(1.0, c["max_health"])
				
				var color = Color(1.0 - health_ratio, health_ratio, 0.0, 0.8)
				if health_ratio <= 0.0:
					color = Color(0.1, 0.1, 0.1, 0.8) # Dead
					
				var draw_x = center.x + ((r.position.y - offset_x) * scale_factor)
				var draw_y = center.y - ((r.position.x - offset_y) * scale_factor) - (r.size.x * scale_factor)
				var draw_w = r.size.y * scale_factor
				var draw_h = r.size.x * scale_factor
				
				var draw_rect2 = Rect2(draw_x, draw_y, draw_w, draw_h)
				
				draw_rect(draw_rect2, color, true)
				draw_rect(draw_rect2, Color(0.8, 0.8, 0.8, 0.5), false, 1.0)
				
				var label = c["type"]
				if c["health"] <= 0: label = "DEAD"
				if font:
					var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
					var text_pos = Vector2(draw_x + (draw_w - text_size.x) / 2.0, draw_y + (draw_h + text_size.y) / 2.0)
					draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

		if eng_state.has("hit_traces"):
			for trace in eng_state["hit_traces"]:
				var alpha = clamp(trace.get("time_remaining", 3.0) / 3.0, 0.0, 1.0)
				
				var prev_pos = trace.get("start_local", Vector2.ZERO)
				var prev_ui_x = center.x + ((prev_pos.y - offset_x) * scale_factor)
				var prev_ui_y = center.y - ((prev_pos.x - offset_y) * scale_factor)
				
				var max_dmg = 0.0
				if trace.get("segments", []).size() > 0:
					max_dmg = trace["segments"][0].get("dmg_remaining", 1.0)
				
				for seg in trace.get("segments", []):
					var p = seg["pos"]
					var ui_x = center.x + ((p.y - offset_x) * scale_factor)
					var ui_y = center.y - ((p.x - offset_y) * scale_factor)
					
					var dmg = seg.get("dmg_remaining", 1.0)
					var dmg_ratio = dmg / max(1.0, max_dmg)
					var thickness = clamp(dmg_ratio * 5.0, 1.0, 5.0)
					
					var c = Color(1.0, 0.2, 0.2, alpha)
					if seg.get("hit", false):
						c = Color(1.0, 0.8, 0.2, alpha)
						draw_circle(Vector2(ui_x, ui_y), thickness * 1.5, Color(1.0, 0.8, 0.2, alpha * 0.5))
						
					draw_line(Vector2(prev_ui_x, prev_ui_y), Vector2(ui_x, ui_y), c, thickness)
					
					prev_ui_x = ui_x
					prev_ui_y = ui_y

func _ready() -> void:
	custom_minimum_size = Vector2(400, 400)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	# Title
	var title = Label.new()
	title.text = "ENGINEERING DIAGNOSTICS"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
	main_vbox.add_child(title)
	
	# Top Gauges (Heat and EM)
	top_hbox = HBoxContainer.new()
	main_vbox.add_child(top_hbox)
	
	var heat_vbox = VBoxContainer.new()
	heat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(heat_vbox)
	var heat_lbl = Label.new()
	heat_lbl.text = "Accumulated Heat"
	heat_vbox.add_child(heat_lbl)
	heat_bar = ProgressBar.new()
	heat_bar.max_value = 200.0
	heat_bar.custom_minimum_size.y = 15
	heat_bar.modulate = Color(1.0, 0.3, 0.1)
	heat_vbox.add_child(heat_bar)
	
	var heat_gen_lbl = Label.new()
	heat_gen_lbl.text = "Heat Sink Capacity"
	heat_vbox.add_child(heat_gen_lbl)
	heat_gen_bar = ProgressBar.new()
	heat_gen_bar.max_value = 5.0
	heat_gen_bar.custom_minimum_size.y = 15
	heat_gen_bar.modulate = Color(0.2, 0.8, 0.2)
	heat_vbox.add_child(heat_gen_bar)
	
	var em_vbox = VBoxContainer.new()
	em_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(em_vbox)
	var em_lbl = Label.new()
	em_lbl.text = "EM Emissions"
	em_vbox.add_child(em_lbl)
	
	var em_content_hbox = HBoxContainer.new()
	em_vbox.add_child(em_content_hbox)
	
	em_chart = EMPolarChart.new()
	em_chart.custom_minimum_size = Vector2(80, 80)
	em_content_hbox.add_child(em_chart)
	
	var em_stats_vbox = VBoxContainer.new()
	em_stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	em_stats_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	em_content_hbox.add_child(em_stats_vbox)
	
	lbl_peak_em = Label.new()
	lbl_peak_em.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	em_stats_vbox.add_child(lbl_peak_em)
	
	lbl_det_dist = Label.new()
	lbl_det_dist.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	em_stats_vbox.add_child(lbl_det_dist)
	
	# Separator
	var sep = HSeparator.new()
	main_vbox.add_child(sep)
	
	# Split into Top (Spatial) and Bottom (List)
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_vbox)
	
	spatial_view = ComponentSpatialView.new()
	spatial_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spatial_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spatial_view.size_flags_stretch_ratio = 1.0
	content_vbox.add_child(spatial_view)
	
	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.size_flags_stretch_ratio = 1.5
	content_vbox.add_child(list_vbox)
	
	var sep2 = HSeparator.new()
	list_vbox.add_child(sep2)
	
	# Component List Header
	var header_hbox = HBoxContainer.new()
	var h1 = Label.new(); h1.text = "Component"; h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h1.size_flags_stretch_ratio = 2.0
	var h_pwr = Label.new(); h_pwr.text = "PWR"
	var h2 = Label.new(); h2.text = "Integrity"; h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h2.size_flags_stretch_ratio = 2.0
	var h3 = Label.new(); h3.text = "Heat"; h3.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h3.size_flags_stretch_ratio = 1.0
	var h4 = Label.new(); h4.text = "EM"; h4.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h4.size_flags_stretch_ratio = 1.0
	header_hbox.add_child(h1); header_hbox.add_child(h_pwr); header_hbox.add_child(h2); header_hbox.add_child(h3); header_hbox.add_child(h4)
	list_vbox.add_child(header_hbox)
	
	var sep3 = HSeparator.new()
	list_vbox.add_child(sep3)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_child(scroll)
	
	components_vbox = VBoxContainer.new()
	components_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(components_vbox)

func update_data(state: Dictionary) -> void:
	current_state = state
	
	if state.has("engineering"):
		var eng = state["engineering"]
		
		if eng.has("current_heat") and heat_bar:
			heat_bar.value = eng.get("current_heat", 0.0)
		heat_bar.max_value = max(1.0, eng.get("max_heat", 200.0))
		
		var h_gen = eng.get("heat_gen", 0.0)
		var h_cap = eng.get("heat_dissipation_rate", 5.0)
		heat_gen_bar.max_value = max(1.0, h_cap)
		heat_gen_bar.value = h_gen
		if h_gen > h_cap:
			heat_gen_bar.modulate = Color(1.0, 0.2, 0.2) # Over capacity (Red)
		else:
			heat_gen_bar.modulate = Color(0.2, 0.8, 0.2) # Within capacity (Green)
		
		var em_sig = eng.get("em_signature", 0.0)
		var is_ship_oriented = current_state.get("is_ship_oriented", false)
		em_chart.is_ship_oriented = is_ship_oriented
		em_chart.ship_rot = current_state.get("rot", 0.0)
		em_chart.em_value = em_sig
		em_chart.sensor_config = current_state.get("sensor_config", [])
		em_chart.queue_redraw()
		
		var peak_em = em_sig
		for s in em_chart.sensor_config:
			if s.get("type", "") == "active" and s.get("active", true):
				if s.get("id") == "dir_high_res":
					peak_em += 40.0
					
		if lbl_peak_em: lbl_peak_em.text = "Peak: %.0f EM" % peak_em
		if lbl_det_dist:
			var det_dist = (peak_em * 10000.0) / 15.0
			lbl_det_dist.text = "Det. Range: %s" % Utils.format_dist(det_dist)
		
		spatial_view.eng_state = eng
		spatial_view.queue_redraw()
		
		if eng.has("ship_components"):
			var comps = eng["ship_components"]
			var active_ids = []
			
			for c in comps:
				var c_id = c.get("id", c.get("type", "unknown"))
				active_ids.append(c_id)
				
				var row: HBoxContainer
				var lbl_name: Label
				var power_btn: CheckButton
				var prog_health: ProgressBar
				var lbl_heat: Label
				var lbl_em: Label
				
				if comp_rows.has(c_id):
					row = comp_rows[c_id]
					lbl_name = row.get_child(0)
					power_btn = row.get_child(1)
					prog_health = row.get_child(2)
					lbl_heat = row.get_child(3)
					lbl_em = row.get_child(4)
				else:
					row = HBoxContainer.new()
					lbl_name = Label.new()
					lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					lbl_name.size_flags_stretch_ratio = 2.0
					
					power_btn = CheckButton.new()
					var c_id_copy = c_id # Capture for closure
					power_btn.toggled.connect(func(pressed): 
						power_btn.set_meta("pending_toggle", Time.get_ticks_msec())
						emit_signal("component_power_toggled", c_id_copy, pressed)
					)
					
					prog_health = ProgressBar.new()
					prog_health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					prog_health.size_flags_stretch_ratio = 2.0
					prog_health.custom_minimum_size.y = 15
					
					lbl_heat = Label.new()
					lbl_heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					lbl_heat.size_flags_stretch_ratio = 1.0
					
					lbl_em = Label.new()
					lbl_em.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					lbl_em.size_flags_stretch_ratio = 1.0
					
					row.add_child(lbl_name)
					row.add_child(power_btn)
					row.add_child(prog_health)
					row.add_child(lbl_heat)
					row.add_child(lbl_em)
					
					components_vbox.add_child(row)
					comp_rows[c_id] = row
					
				# Update values
				lbl_name.text = c_id
				
				var is_switchable = c.get("switchable", false)
				if is_switchable:
					power_btn.disabled = false
					power_btn.modulate = Color(1, 1, 1, 1)
				else:
					power_btn.disabled = true
					power_btn.modulate = Color(0, 0, 0, 0)
					
				var is_powered = c.get("powered_on", true)
				var last_toggle_time = power_btn.get_meta("pending_toggle", 0)
				if Time.get_ticks_msec() - last_toggle_time > 500: # Wait 500ms after a click before allowing server to override
					if power_btn.button_pressed != is_powered:
						power_btn.set_pressed_no_signal(is_powered)
					
				var hp = max(0.0, c.get("health", 0.0))
				var mhp = max(1.0, c.get("max_health", 1.0))
				prog_health.value = hp
				prog_health.max_value = mhp
				
				var health_ratio = hp / mhp
				prog_health.modulate = Color(1.0 - health_ratio, health_ratio, 0.0)
				
				lbl_heat.text = "%.1f" % c.get("heat", 0.0)
				lbl_em.text = "%.1f" % c.get("em_emission", 0.0)
				
			# Cleanup old rows
			for key in comp_rows.keys():
				if not key in active_ids:
					comp_rows[key].queue_free()
					comp_rows.erase(key)
