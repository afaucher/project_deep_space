extends PanelContainer
class_name WeaponsPanel

signal fire_weapon_requested(weapon_id: String)

const FIRING_FLASH_WINDOW := 0.2 # seconds before cooldown ends where the button reads "* FIRING *" instead of "COOLDOWN"

var current_state: Dictionary = {}
var selected_contact_id: String = ""
var weapon_buttons: Dictionary = {}
var target_info_label: Label
var weapon_grid: GridContainer
var spider_chart: Control
var history_graph: Control

func _ready() -> void:
	custom_minimum_size = Vector2(460, 200)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.05, 0.8)
	style.border_width_top = 2
	style.border_color = Color.RED
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var title = Label.new()
	title.text = "WEAPONS CONTROL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	weapon_grid = GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(weapon_grid)
	
	vbox.add_child(HSeparator.new())
	
	var target_label = Label.new()
	target_label.text = "TARGETING COMPUTER"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_color_override("font_color", Color.ORANGE)
	vbox.add_child(target_label)
	
	target_info_label = Label.new()
	target_info_label.text = "NO TARGET LOCKED"
	target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_info_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(target_info_label)
	
	var charts_hbox = HBoxContainer.new()
	charts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(charts_hbox)

	spider_chart = load("res://scripts/spider_chart.gd").new()
	spider_chart.custom_minimum_size = Vector2(160, 160)
	charts_hbox.add_child(spider_chart)
	spider_chart.hide()

	history_graph = load("res://scripts/timeseries_graph.gd").new()
	history_graph.custom_minimum_size = Vector2(220, 160)
	charts_hbox.add_child(history_graph)
	history_graph.hide()

func _create_weapon_ui(grid: GridContainer, w_id: String, w_name: String) -> void:
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_label = Label.new()
	name_label.text = w_name
	info_vbox.add_child(name_label)
	
	var ammo_label = Label.new()
	ammo_label.text = "Ammo: -- | CD: --"
	ammo_label.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(ammo_label)
	
	grid.add_child(info_vbox)
	
	var fire_btn = Button.new()
	fire_btn.text = "FIRE"
	fire_btn.add_theme_color_override("font_color", Color.RED)
	fire_btn.pressed.connect(func(): emit_signal("fire_weapon_requested", w_id))
	grid.add_child(fire_btn)
	
	weapon_buttons[w_id] = {
		"ammo_label": ammo_label,
		"btn": fire_btn
	}

func update_data(packet: Dictionary, target_id: String) -> void:
	current_state = packet
	# Switching targets (including to/from "no target") shows a fresh history
	# instead of graphing a mix of two different ships' signatures.
	if target_id != selected_contact_id and is_instance_valid(history_graph):
		history_graph.reset()
	selected_contact_id = target_id

	if current_state.has("weapons"):
		var weapons = current_state["weapons"] # Array of ship_components weapon entries

		# Generate UI dynamically if not present
		if weapon_buttons.size() == 0:
			for w_info in weapons:
				_create_weapon_ui(weapon_grid, w_info.get("id", ""), w_info.get("id", "").to_upper())

		for w_info in weapons:
			var w_id = w_info.get("id", "")
			if weapon_buttons.has(w_id):
				var ammo = w_info.get("ammo", 0)
				var cd = w_info.get("cooldown", 0.0)

				var lbl = weapon_buttons[w_id]["ammo_label"]
				lbl.text = "Ammo: %d | CD: %.1f" % [ammo, cd]

				var btn = weapon_buttons[w_id]["btn"]

				var is_in_arc = false
				var is_in_range = false
				var has_target = false

				var is_powered = true
				var is_alive = true
				if current_state.has("engineering") and current_state["engineering"].has("ship_components"):
					for comp in current_state["engineering"]["ship_components"]:
						if comp.get("id", "") == w_id:
							is_alive = comp.get("health", 0.0) > 0.0
							is_powered = comp.get("powered_on", true)
							break

				if selected_contact_id != "" and current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
					has_target = true
					var c = current_state["contacts"][selected_contact_id]
					var c_pos = c.get("pos", Vector2.ZERO)
					var s_pos = current_state.get("pos", Vector2.ZERO)
					var s_rot = current_state.get("rot", 0.0)

					var w_heading = w_info.get("heading", 0.0)
					var arc_w = w_info.get("arc_width", TAU)
					var w_range = w_info.get("range", 999999.0)

					var dist = s_pos.distance_to(c_pos)
					is_in_range = (dist <= w_range)

					var angle_to = (c_pos - s_pos).angle()
					var weapon_global_heading = s_rot + w_heading
					var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)

					is_in_arc = (abs(rel_angle) <= arc_w / 2.0)

				var is_laser = w_info.get("weapon_type", "") == "laser"
				var range_ok = is_in_range or not is_laser # range only gates lasers -- missiles fly to target regardless of launch distance

				# Single ordered priority list so can_fire and the status text
				# can never disagree about which condition is actually blocking
				# the shot -- each entry is (blocking_condition, display_text).
				var blockers = [
					[not is_alive, "DESTROYED"],
					[not is_powered, "OFFLINE"],
					[not has_target, "NO LOCK"],
					[ammo <= 0, "EMPTY"],
					[cd > w_info.get("cooldown_max", 1.0) - FIRING_FLASH_WINDOW, "* FIRING *"],
					[cd > 0.0, "COOLDOWN"],
					[not is_in_arc, "OUT OF ARC"],
					[not range_ok, "OUT OF RANGE"],
				]
				var can_fire = true
				var status_text = "FIRE"
				for blocker in blockers:
					if blocker[0]:
						can_fire = false
						status_text = blocker[1]
						break

				btn.disabled = not can_fire
				btn.text = status_text
					
	if selected_contact_id == "":
		target_info_label.text = "NO TARGET LOCKED"
		if is_instance_valid(spider_chart): spider_chart.hide()
		if is_instance_valid(history_graph): history_graph.hide()
	else:
		if current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
			var c = current_state["contacts"][selected_contact_id]
			# c["signature"] is OUR OWN sensors' fused, lerp-smoothed track data
			# (Ship._run_sensor_sweep + the correlation lerp in _physics_process),
			# not the target's actual current_heat/em_signature -- the spider
			# chart and history graph below are both observed readings, same as
			# this label.
			var sig = c.get("signature", {"heat": 0.0, "em_noise": 0.0, "cross_section": 1.0, "density": 0.0})
			var speed = c.get("vel", Vector2.ZERO).length()
			var dist = current_state.get("pos", Vector2.ZERO).distance_to(c.get("pos", Vector2.ZERO))
			target_info_label.text = "Target: %s\nHeat: %.1f | EM: %.1f\nCS: %.1f | Den: %.1f\nDist: %.1f m | Spd: %.1f m/s" % [
				selected_contact_id, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0), dist, speed
			]
			if is_instance_valid(spider_chart):
				spider_chart.set_values(sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0))
				spider_chart.show()
			if is_instance_valid(history_graph):
				history_graph.push_sample(sig.get("heat", 0.0), sig.get("em_noise", 0.0))
				history_graph.show()
		else:
			target_info_label.text = "TARGET LOST"
			if is_instance_valid(spider_chart): spider_chart.hide()
			if is_instance_valid(history_graph): history_graph.hide()

