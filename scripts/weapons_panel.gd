extends PanelContainer
class_name WeaponsPanel

signal fire_weapon_requested(weapon_id: String)

var current_state: Dictionary = {}
var selected_contact_id: String = ""

var weapon_buttons: Dictionary = {}

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
