extends Control

const NavigationPanel = preload("res://scripts/navigation_panel.gd")
const HelmPanel = preload("res://scripts/helm_panel.gd")
const SensorPanel = preload("res://scripts/sensor_panel.gd")
const WeaponsPanel = preload("res://scripts/weapons_panel.gd")
const EngineeringPanel = preload("res://scripts/engineering_panel.gd")

var nav_panel: Control
var helm_panel: Control
var sensor_panel: Control
var weapons_panel: Control
var eng_panel: Control

var pinned_contacts: Array = []
var current_ship_oriented: bool = false

var sfx_laser: AudioStreamPlayer
var spawn_dropdown: OptionButton

func _ready() -> void:
	sfx_laser = AudioStreamPlayer.new()
	sfx_laser.stream = preload("res://assets/audio/laser.wav")
	add_child(sfx_laser)
	
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	# --- Top Bar for Toggling ---
	var top_bar = HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 40)
	var top_panel = PanelContainer.new()
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0.1, 0.1, 0.15)
	top_panel.add_theme_stylebox_override("panel", top_style)
	top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_panel.add_child(top_bar)
	main_vbox.add_child(top_panel)
	
	var nav_toggle = CheckButton.new()
	nav_toggle.text = "Navigation"
	nav_toggle.button_pressed = true
	top_bar.add_child(nav_toggle)
	
	var sensor_toggle = CheckButton.new()
	sensor_toggle.text = "Sensors"
	sensor_toggle.button_pressed = true
	top_bar.add_child(sensor_toggle)
	
	var helm_toggle = CheckButton.new()
	helm_toggle.text = "Helm"
	helm_toggle.button_pressed = true
	top_bar.add_child(helm_toggle)
	
	var weapons_toggle = CheckButton.new()
	weapons_toggle.text = "Weapons"
	weapons_toggle.button_pressed = true
	top_bar.add_child(weapons_toggle)
	
	var eng_toggle = CheckButton.new()
	eng_toggle.text = "Engineering"
	eng_toggle.button_pressed = true
	top_bar.add_child(eng_toggle)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	spawn_dropdown = OptionButton.new()
	spawn_dropdown.add_item("Spawn...")
	spawn_dropdown.add_item("Asteroids (10)")
	spawn_dropdown.add_item("Target Drone")
	spawn_dropdown.add_item("Target Buoy")
	spawn_dropdown.item_selected.connect(_on_spawn_selected)
	top_bar.add_child(spawn_dropdown)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer2)
	
	var spacer3 = Control.new()
	spacer3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer3)
	
	var ship_oriented_toggle = CheckButton.new()
	ship_oriented_toggle.text = "Ship Oriented"
	ship_oriented_toggle.button_pressed = false
	ship_oriented_toggle.toggled.connect(func(pressed): current_ship_oriented = pressed)
	top_bar.add_child(ship_oriented_toggle)
	
	# --- Main Content Area ---
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)
	
	# --- Navigation Panel ---
	var nav_container = PanelContainer.new()
	nav_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_container.size_flags_stretch_ratio = 2.0
	var nav_style = StyleBoxFlat.new()
	nav_style.bg_color = Color(0.05, 0.05, 0.1)
	nav_style.border_width_right = 2
	nav_style.border_color = Color(0.2, 0.4, 0.2)
	_add_margins(nav_style)
	nav_container.add_theme_stylebox_override("panel", nav_style)
	
	nav_panel = NavigationPanel.new()
	nav_panel.contact_selected.connect(_on_selection_changed)
	nav_container.add_child(nav_panel)
	content_hbox.add_child(nav_container)
	
	# --- Sensor Panel ---
	var sensor_container = PanelContainer.new()
	sensor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensor_container.size_flags_stretch_ratio = 1.0
	var sensor_style = StyleBoxFlat.new()
	sensor_style.bg_color = Color(0.02, 0.05, 0.02)
	sensor_style.border_width_right = 2
	sensor_style.border_color = Color(0.2, 0.4, 0.2)
	_add_margins(sensor_style)
	sensor_container.add_theme_stylebox_override("panel", sensor_style)
	
	sensor_panel = SensorPanel.new()
	sensor_panel.contact_pin_toggled.connect(_on_contact_pin_toggled)
	sensor_panel.selection_changed.connect(_on_selection_changed)
	sensor_panel.sensor_state_changed.connect(_on_sensor_state_changed)
	sensor_panel.all_sensors_state_changed.connect(_on_all_sensors_state_changed)
	sensor_container.add_child(sensor_panel)
	content_hbox.add_child(sensor_container)
	
	# --- Right Panel Stack (Helm + Weapons) ---
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(right_vbox)
	
	# --- Helm Panel ---
	var helm_container = PanelContainer.new()
	helm_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var helm_style = StyleBoxFlat.new()
	helm_style.bg_color = Color(0.05, 0.05, 0.05)
	helm_style.border_width_left = 2
	helm_style.border_color = Color(0.2, 0.4, 0.2)
	_add_margins(helm_style)
	helm_container.add_theme_stylebox_override("panel", helm_style)
	
	helm_panel = HelmPanel.new()
	helm_container.add_child(helm_panel)
	right_vbox.add_child(helm_container)
	
	# --- Weapons Panel ---
	var weapons_container = PanelContainer.new()
	weapons_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var weapons_style = StyleBoxFlat.new()
	weapons_style.bg_color = Color(0.05, 0.0, 0.0)
	weapons_style.border_width_top = 2
	weapons_style.border_width_left = 2
	weapons_style.border_color = Color.DARK_RED
	_add_margins(weapons_style)
	weapons_container.add_theme_stylebox_override("panel", weapons_style)
	
	weapons_panel = WeaponsPanel.new()
	weapons_panel.fire_weapon_requested.connect(_on_fire_weapon_requested)
	weapons_container.add_child(weapons_panel)
	right_vbox.add_child(weapons_container)
	
	# --- Engineering Panel ---
	var eng_container = PanelContainer.new()
	eng_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eng_container.size_flags_stretch_ratio = 1.0
	var eng_style = StyleBoxFlat.new()
	eng_style.bg_color = Color(0.05, 0.05, 0.05)
	eng_style.border_width_left = 2
	eng_style.border_color = Color(0.6, 0.4, 0.1)
	_add_margins(eng_style)
	eng_container.add_theme_stylebox_override("panel", eng_style)
	
	eng_panel = EngineeringPanel.new()
	eng_panel.component_power_toggled.connect(_on_component_power_toggled)
	eng_container.add_child(eng_panel)
	content_hbox.add_child(eng_container)
	eng_container.visible = true
	
	# Connect toggles
	nav_toggle.toggled.connect(func(pressed): nav_container.visible = pressed)
	sensor_toggle.toggled.connect(func(pressed): sensor_container.visible = pressed)
	helm_toggle.toggled.connect(func(pressed): helm_container.visible = pressed)
	weapons_toggle.toggled.connect(func(pressed): weapons_container.visible = pressed)
	eng_toggle.toggled.connect(func(pressed): eng_container.visible = pressed)

func _add_margins(style: StyleBoxFlat) -> void:
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 3
	style.content_margin_bottom = 3

func _on_spawn_selected(idx: int) -> void:
	if idx == 0: return
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		if idx == 1:
			ship_node.rpc_id(1, "request_spawn", "asteroids")
		elif idx == 2:
			ship_node.rpc_id(1, "request_spawn", "drone")
		elif idx == 3:
			ship_node.rpc_id(1, "request_spawn", "buoy")
	
	spawn_dropdown.select(0)

func update_data(packet: Dictionary) -> void:
	# Inject local UI state into the packet so sub-panels can read it
	packet["pinned_contacts"] = pinned_contacts
	packet["is_ship_oriented"] = current_ship_oriented
	
	var selected_target = sensor_panel.get_selected_contact_id() if sensor_panel.has_method("get_selected_contact_id") else ""
	packet["selected_contact_id"] = selected_target
	
	if nav_panel and nav_panel.has_method("update_data"):
		nav_panel.update_data(packet)
	if helm_panel and helm_panel.has_method("update_data"):
		helm_panel.update_data(packet)
	if sensor_panel and sensor_panel.has_method("update_data"):
		sensor_panel.update_data(packet)
	if weapons_panel and weapons_panel.has_method("update_data"):
		weapons_panel.update_data(packet, selected_target)
	if eng_panel and eng_panel.has_method("update_data"):
		eng_panel.update_data(packet)

	if packet.has("transient_events"):
		for ev in packet["transient_events"]:
			if ev["type"] == "laser":
				sfx_laser.play()

func _on_fire_weapon_requested(weapon_id: String) -> void:
	var target_id = sensor_panel.get_selected_contact_id() if sensor_panel.has_method("get_selected_contact_id") else ""
	if target_id == "": return
	var target_pos = Vector2.ZERO # The host will compute actual lead pos, we just send a zero vector for now
	
	# We need the ship's ID to call the RPC on the correct node
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		ship_node.rpc_id(1, "fire_weapon", weapon_id, target_pos, target_id)

func _on_contact_pin_toggled(c_id: String, is_pinned: bool) -> void:
	if is_pinned and not pinned_contacts.has(c_id):
		pinned_contacts.append(c_id)
	elif not is_pinned and pinned_contacts.has(c_id):
		pinned_contacts.erase(c_id)

func _on_selection_changed(c_id: String) -> void:
	if sensor_panel and sensor_panel.has_method("set_selected_contact_id"):
		sensor_panel.set_selected_contact_id(c_id)
	
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		ship_node.rpc_id(1, "set_sensor_target", c_id)

func _on_sensor_state_changed(sensor_id: String, is_active: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		ship_node.rpc_id(1, "set_sensor_state", sensor_id, is_active)

func _on_all_sensors_state_changed(is_active: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		ship_node.rpc_id(1, "set_all_sensors_state", is_active)

func _on_component_power_toggled(component_id: String, is_active: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	var ship_node_name = "Ship_" + str(my_id)
	var ship_node = get_node_or_null("/root/Main/" + ship_node_name)
	if ship_node:
		ship_node.rpc_id(1, "set_component_power", component_id, is_active)




