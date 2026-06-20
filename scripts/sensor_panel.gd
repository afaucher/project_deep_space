extends Control

var current_state: Dictionary = {}
var sensor_modules: Dictionary = {}

var main_hbox: HBoxContainer
var main_vbox: VBoxContainer
var modules_container: HFlowContainer
var contact_list_vbox: VBoxContainer
var contact_filter_dropdown: OptionButton

var selected_contact_id: String = ""

const SensorModuleUI = preload("res://scripts/sensor_module_ui.gd")
const SensorUnionUI = preload("res://scripts/sensor_union_ui.gd")

var union_view: SensorUnionUI

func _ready() -> void:
	clip_contents = true
	
	main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	union_view = SensorUnionUI.new()
	union_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	union_view.size_flags_stretch_ratio = 1.0 # 50%
	union_view.contact_selected.connect(_on_contact_selected)
	main_vbox.add_child(union_view)
	
	main_hbox = HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_stretch_ratio = 1.0 # 50%
	main_vbox.add_child(main_hbox)
	
	modules_container = HFlowContainer.new()
	modules_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(modules_container)
	
	var right_panel = PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(300, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style.border_width_left = 2
	style.border_color = Color.GREEN
	right_panel.add_theme_stylebox_override("panel", style)
	
	var right_vbox = VBoxContainer.new()
	right_panel.add_child(right_vbox)
	
	var title = Label.new()
	title.text = "TACTICAL CONTACTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.GREEN)
	right_vbox.add_child(title)
	
	contact_filter_dropdown = OptionButton.new()
	contact_filter_dropdown.add_item("All Contacts")
	contact_filter_dropdown.add_item("All Ships")
	contact_filter_dropdown.add_item("Enemies Only")
	contact_filter_dropdown.item_selected.connect(_on_filter_selected)
	right_vbox.add_child(contact_filter_dropdown)
	
	right_vbox.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)
	
	contact_list_vbox = VBoxContainer.new()
	contact_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contact_list_vbox)
	
	main_hbox.add_child(right_panel)

func _on_filter_selected(idx: int) -> void:
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])

func _on_contact_selected(c_id: String) -> void:
	selected_contact_id = c_id
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])
	
	# Force an immediate redraw on modules
	for sensor_id in sensor_modules.keys():
		var mod = sensor_modules[sensor_id]
		mod.selected_contact_id = selected_contact_id
		mod.queue_redraw()

func _on_contact_panel_gui_input(event: InputEvent, c_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_contact_selected(c_id)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	
	if current_state.has("sensors"):
		var sensors_dict = current_state["sensors"]
		var my_pos = current_state.get("pos", Vector2.ZERO)
		var c_dict = current_state.get("contacts", {})
		
		if is_instance_valid(union_view):
			union_view.update_data(sensors_dict, my_pos, c_dict, selected_contact_id)
		
		for sensor_id in sensors_dict.keys():
			if not sensor_modules.has(sensor_id):
				var mod = SensorModuleUI.new()
				mod.contact_selected.connect(_on_contact_selected)
				modules_container.add_child(mod)
				sensor_modules[sensor_id] = mod
			
			sensor_modules[sensor_id].update_data(sensor_id, sensors_dict[sensor_id], my_pos, current_state.get("contacts", {}), selected_contact_id)
			
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])

func _update_contact_list(contacts: Dictionary) -> void:
	# Clear old contacts
	for child in contact_list_vbox.get_children():
		child.queue_free()
	
	var my_pos = current_state.get("pos", Vector2.ZERO)
	var filter_idx = 0
	if is_instance_valid(contact_filter_dropdown):
		filter_idx = contact_filter_dropdown.selected
		
	var sorted_contacts = []
	for c_id in contacts.keys():
		var c = contacts[c_id].duplicate(true)
		c["_id"] = c_id
		c["_dist"] = my_pos.distance_to(c.get("pos", Vector2.ZERO))
		sorted_contacts.append(c)
		
	sorted_contacts.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
	
	for c in sorted_contacts:
		var c_id = c["_id"]
		var classification = c.get("classification", "UNKNOWN")
		
		# Filtering
		if filter_idx == 1: # All Ships
			if classification == "ASTEROID": continue
		elif filter_idx == 2: # Enemies Only
			if classification != "UNIDENTIFIED VESSEL": continue
		
		var panel = PanelContainer.new()
		var p_style = StyleBoxFlat.new()
		
		if c_id == selected_contact_id:
			p_style.bg_color = Color(0.2, 0.4, 0.2, 0.8)
			p_style.border_color = Color.WHITE
		else:
			p_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
			if c.get("classification") == "UNIDENTIFIED VESSEL":
				p_style.border_color = Color.RED
			else:
				p_style.border_color = Color.GRAY
				
		p_style.border_width_left = 4
		panel.add_theme_stylebox_override("panel", p_style)
		panel.gui_input.connect(_on_contact_panel_gui_input.bind(c_id))
		
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		
		var header = Label.new()
		header.text = c_id + " [" + c.get("classification", "UNKNOWN") + "]"
		if c.get("classification") == "UNIDENTIFIED VESSEL":
			header.add_theme_color_override("font_color", Color.RED)
		else:
			header.add_theme_color_override("font_color", Color.GRAY)
		vbox.add_child(header)
		
		var dist = c["_dist"]
		var vel = c.get("vel", Vector2.ZERO)
		var speed = vel.length()
		
		var info = Label.new()
		info.text = "Dist: %.1f m\nSpeed: %.1f m/s\nHeat: %.1f | EM: %.1f" % [dist, speed, c["signature"]["heat"], c["signature"]["em_noise"]]
		info.add_theme_font_size_override("font_size", 12)
		vbox.add_child(info)
		
		contact_list_vbox.add_child(panel)

func _draw() -> void:
	pass
