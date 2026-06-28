extends Control

signal contact_pin_toggled(c_id: String, is_pinned: bool)
signal selection_changed(c_id: String)
signal sensor_state_changed(sensor_id: String, is_active: bool)
signal all_sensors_state_changed(is_active: bool)

var current_state: Dictionary = {}
var sensor_modules: Dictionary = {}
var contact_panels: Dictionary = {}

var main_hbox: HBoxContainer
var main_vbox: VBoxContainer
var modules_container: HFlowContainer
var contact_list_vbox: VBoxContainer
var contact_filter_dropdown: OptionButton
var master_sensor_dropdown: OptionButton

var selected_contact_id: String = ""

func get_selected_contact_id() -> String:
	return selected_contact_id

func set_selected_contact_id(c_id: String) -> void:
	if selected_contact_id != c_id:
		selected_contact_id = c_id
		selection_changed.emit(c_id)
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("nav_next_contact") or event.is_action_pressed("nav_prev_contact"):
		var contacts = current_state.get("contacts", {})
		if contacts.is_empty(): return
		
		var filter_idx = 0
		if is_instance_valid(contact_filter_dropdown):
			filter_idx = contact_filter_dropdown.selected
			
		var contact_list = []
		for c_id in contacts.keys():
			var classification = contacts[c_id].get("classification", "UNKNOWN")
			if filter_idx == 1 and classification == "ASTEROID": continue
			if filter_idx == 2 and classification != "UNIDENTIFIED VESSEL": continue
			contact_list.append(c_id)
			
		if contact_list.is_empty(): return
		
		var pos = current_state.get("pos", Vector2.ZERO)
		# Sort by distance
		contact_list.sort_custom(func(a, b): return contacts[a]["pos"].distance_to(pos) < contacts[b]["pos"].distance_to(pos))
		
		var idx = contact_list.find(selected_contact_id)
		if idx == -1:
			idx = 0
		elif event.is_action_pressed("nav_next_contact"):
			idx = (idx + 1) % contact_list.size()
		else:
			idx = (idx - 1) if idx > 0 else contact_list.size() - 1
			
		set_selected_contact_id(contact_list[idx])

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
	contact_filter_dropdown.select(2) # Default to All Ships
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
	if selected_contact_id == c_id:
		selected_contact_id = ""
	else:
		selected_contact_id = c_id
		
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])
		
	emit_signal("selection_changed", selected_contact_id)
	
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
			
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])

func _update_contact_list(contacts: Dictionary) -> void:
	var my_pos = current_state.get("pos", Vector2.ZERO)
	var filter_idx = 0
	if is_instance_valid(contact_filter_dropdown):
		filter_idx = contact_filter_dropdown.selected
		
	var sorted_contacts = []
	for c_id in contacts.keys():
		var c = contacts[c_id].duplicate(true)
		var classification = c.get("classification", "UNKNOWN")
		
		# Filtering
		if filter_idx == 1 and classification == "ASTEROID": continue # All Ships
		if filter_idx == 2 and classification != "UNIDENTIFIED VESSEL": continue # Enemies Only
		
		c["_id"] = c_id
		c["_dist"] = my_pos.distance_to(c.get("pos", Vector2.ZERO))
		sorted_contacts.append(c)
		
	sorted_contacts.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
	
	# Keep track of which IDs are currently valid
	var active_ids = []
	for c in sorted_contacts:
		active_ids.append(c["_id"])
		
	# Remove old panels
	for c_id in contact_panels.keys():
		if not c_id in active_ids:
			var old_panel = contact_panels[c_id]["panel"]
			if is_instance_valid(old_panel):
				old_panel.queue_free()
			contact_panels.erase(c_id)
			
	var pinned_list = current_state.get("pinned_contacts", [])
			
	# Update or create panels
	var idx = 0
	for c in sorted_contacts:
		var c_id = c["_id"]
		var panel: PanelContainer
		var header: Label
		var pin_btn: CheckButton
		var info: Label
		var p_style: StyleBoxFlat

		if contact_panels.has(c_id):
			# Named refs cached at creation time below -- not positional
			# get_child() lookups, so any future change to this row's child
			# layout can't silently break this.
			var refs = contact_panels[c_id]
			panel = refs["panel"]
			p_style = refs["style"]
			header = refs["header"]
			pin_btn = refs["pin_btn"]
			info = refs["info"]
		else:
			panel = PanelContainer.new()
			p_style = StyleBoxFlat.new()
			p_style.border_width_left = 4
			panel.add_theme_stylebox_override("panel", p_style)
			panel.gui_input.connect(_on_contact_panel_gui_input.bind(c_id))

			var vbox = VBoxContainer.new()
			panel.add_child(vbox)

			var header_hbox = HBoxContainer.new()
			vbox.add_child(header_hbox)

			header = Label.new()
			header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header_hbox.add_child(header)

			pin_btn = CheckButton.new()
			pin_btn.text = "Pin"
			pin_btn.toggled.connect(func(pressed): emit_signal("contact_pin_toggled", c_id, pressed))
			header_hbox.add_child(pin_btn)

			info = Label.new()
			info.add_theme_font_size_override("font_size", 12)
			vbox.add_child(info)

			contact_list_vbox.add_child(panel)
			contact_panels[c_id] = {"panel": panel, "style": p_style, "header": header, "pin_btn": pin_btn, "info": info}

		# Reorder to keep sorted
		panel.get_parent().move_child(panel, idx)
		idx += 1
		
		# Update visual properties
		var classification_str = c.get("classification", "UNKNOWN")
		if c_id == selected_contact_id:
			p_style.bg_color = Color(0.2, 0.4, 0.2, 0.8)
			p_style.border_color = Color.WHITE
		else:
			p_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
			p_style.border_color = Utils.classification_color(classification_str)

		header.text = c_id + " [" + classification_str + "]"
		header.add_theme_color_override("font_color", Utils.classification_color(classification_str))

		# Update state without emitting signal
		pin_btn.set_pressed_no_signal(pinned_list.has(c_id))
		
		var dist = c["_dist"]
		var vel = c.get("vel", Vector2.ZERO)
		var speed = vel.length()
		var sig = c.get("signature", {})
		# Track age = whole seconds since the last real detection (it's been
		# dead-reckoned since). 0s = measured this frame; a climbing number flags a
		# stale/coasting contact without dimming the row.
		var age_s = int(c.get("last_seen_timer", 0.0))
		info.text = "Dist: %s | Spd: %.1f m/s | Age: %ds\nHeat: %.1f | EM: %.1f\nCS: %.1f | Den: %.1f" % [
			Utils.format_dist(dist), speed, age_s, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0)
		]

func _draw() -> void:
	pass

func _on_master_mode_selected(idx: int) -> void:
	if idx == 0:
		all_sensors_state_changed.emit(true)
	elif idx == 1:
		all_sensors_state_changed.emit(false)

func _on_sensor_module_toggled(s_id: String, is_active: bool) -> void:
	sensor_state_changed.emit(s_id, is_active)
