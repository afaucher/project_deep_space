extends Control

signal sensor_state_changed(sensor_id: String, is_active: bool)
signal all_sensors_state_changed(is_active: bool)
signal selection_changed(c_id: String) # Still need this in case clicking a blip in a sensor module selects it

var current_state: Dictionary = {}
var sensor_modules: Dictionary = {}

var main_hbox: HBoxContainer
var main_vbox: VBoxContainer
var modules_container: HFlowContainer
var master_sensor_dropdown: OptionButton

var selected_contact_id: String = ""

func set_selected_contact_id(c_id: String) -> void:
	if selected_contact_id != c_id:
		selected_contact_id = c_id
		# Force an immediate redraw on modules so the highlight updates
		for sensor_id in sensor_modules.keys():
			var mod = sensor_modules[sensor_id]
			mod.selected_contact_id = selected_contact_id
			mod.queue_redraw()
		queue_redraw()

func get_selected_contact_id() -> String:
	return selected_contact_id

const SensorModuleUI = preload("res://scripts/ui/sensor_module_ui.gd")

func _ready() -> void:
	clip_contents = true
	
	main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	var master_hbox = HBoxContainer.new()
	master_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var master_lbl = Label.new()
	master_lbl.text = "MASTER SENSOR MODE: "
	master_hbox.add_child(master_lbl)
	master_sensor_dropdown = OptionButton.new()
	master_sensor_dropdown.add_item("ALL ON")
	master_sensor_dropdown.add_item("ALL OFF")
	master_sensor_dropdown.add_item("MIXED")
	master_sensor_dropdown.set_item_disabled(2, true)
	master_sensor_dropdown.item_selected.connect(_on_master_mode_selected)
	master_hbox.add_child(master_sensor_dropdown)
	main_vbox.add_child(master_hbox)
	
	main_hbox = HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(main_hbox)
	
	modules_container = HFlowContainer.new()
	modules_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(modules_container)

func _on_contact_selected(c_id: String) -> void:
	if selected_contact_id == c_id:
		selected_contact_id = ""
	else:
		selected_contact_id = c_id
		
	emit_signal("selection_changed", selected_contact_id)
	set_selected_contact_id(selected_contact_id)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	
	if current_state.has("sensors"):
		var sensors_dict = current_state["sensors"]
		var my_pos = current_state.get("pos", Vector2.ZERO)
		
		if current_state.has("sensor_config"):
			var cfg = current_state["sensor_config"]
			var all_on = true
			var all_off = true
			for c in cfg:
				var sensor_id = c.get("id", "")
				if not sensor_modules.has(sensor_id):
					var mod = SensorModuleUI.new()
					mod.contact_selected.connect(_on_contact_selected)
					mod.toggle_changed.connect(_on_sensor_module_toggled)
					modules_container.add_child(mod)
					sensor_modules[sensor_id] = mod
				
				sensor_modules[sensor_id].set_active(c.get("active", true))
				
				if c.get("active", true): all_off = false
				else: all_on = false
					
			if all_on: master_sensor_dropdown.selected = 0
			elif all_off: master_sensor_dropdown.selected = 1
			else: master_sensor_dropdown.selected = 2
			
		for sensor_id in sensor_modules.keys():
			var bins = sensors_dict.get(sensor_id, [])
			sensor_modules[sensor_id].update_data(sensor_id, bins, my_pos, current_state.get("contacts", {}), selected_contact_id, current_state)

func _draw() -> void:
	pass

func _on_master_mode_selected(idx: int) -> void:
	if idx == 0:
		all_sensors_state_changed.emit(true)
	elif idx == 1:
		all_sensors_state_changed.emit(false)

func _on_sensor_module_toggled(s_id: String, is_active: bool) -> void:
	sensor_state_changed.emit(s_id, is_active)
