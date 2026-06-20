extends PanelContainer
class_name WeaponsPanel

signal fire_weapon_requested(weapon_id: String)

var current_state: Dictionary = {}
var selected_contact_id: String = ""
var weapon_buttons: Dictionary = {}
var target_info_label: Label
var spider_chart: Control

func _ready() -> void:
	custom_minimum_size = Vector2(300, 200)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.05, 0.8)
	style.border_width_top = 2
	style.border_color = Color.RED
	add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var title = Label.new()
	title.text = "WEAPONS CONTROL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	
	_create_weapon_ui(grid, "laser_head", "LASER HEAD")
	_create_weapon_ui(grid, "ship_laser", "SHIP LASER")
	
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
	
	spider_chart = load("res://scripts/spider_chart.gd").new()
	spider_chart.custom_minimum_size = Vector2(160, 160)
	spider_chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(spider_chart)
	spider_chart.hide()

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
	selected_contact_id = target_id
	
	# The packet needs to contain weapon state. We haven't passed it yet!
	# We need to add weapons to the packet in main.gd, or just extract it.
	if current_state.has("weapons"):
		var weapons = current_state["weapons"]
		for w_id in weapons.keys():
			if weapon_buttons.has(w_id):
				var w_info = weapons[w_id]
				var ammo = w_info["ammo"]
				var cd = w_info["cooldown"]
				
				var lbl = weapon_buttons[w_id]["ammo_label"]
				lbl.text = "Ammo: %d | CD: %.1f" % [ammo, cd]
				
				var btn = weapon_buttons[w_id]["btn"]
				btn.disabled = (ammo <= 0 or cd > 0.0 or selected_contact_id == "")
				if selected_contact_id == "":
					btn.text = "NO LOCK"
				else:
					btn.text = "FIRE"
					
	if selected_contact_id == "":
		target_info_label.text = "NO TARGET LOCKED"
		if is_instance_valid(spider_chart): spider_chart.hide()
	else:
		if current_state.has("contacts") and current_state["contacts"].has(selected_contact_id):
			var c = current_state["contacts"][selected_contact_id]
			var sig = c.get("signature", {"heat": 0.0, "em_noise": 0.0, "cross_section": 1.0, "density": 0.0})
			var speed = c.get("vel", Vector2.ZERO).length()
			var dist = current_state["pos"].distance_to(c["pos"]) if current_state.has("pos") and c.has("pos") else 0.0
			target_info_label.text = "Target: %s\nHeat: %.1f | EM: %.1f\nCS: %.1f | Den: %.1f\nDist: %.1f m | Spd: %.1f m/s" % [
				selected_contact_id, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0), dist, speed
			]
			if is_instance_valid(spider_chart):
				spider_chart.set_values(sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0))
				spider_chart.show()
		else:
			target_info_label.text = "TARGET LOST"
			if is_instance_valid(spider_chart): spider_chart.hide()
