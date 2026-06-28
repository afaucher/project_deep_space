extends Control

var current_state: Dictionary = {}

var comms_list_vbox: VBoxContainer
var transponder_panels: Dictionary = {}

# Controls for our own transponder
var btn_active: CheckButton
var btn_share_name: CheckButton
var btn_share_loc: CheckButton
var custom_name_edit: LineEdit

signal transponder_toggled(active: bool)
signal transponder_share_name_toggled(share: bool)
signal transponder_share_loc_toggled(share: bool)
signal transponder_custom_name_changed(new_name: String)

func _ready() -> void:
	clip_contents = true
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	var title = Label.new()
	title.text = "COMMS & TRANSPONDERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.CYAN)
	main_vbox.add_child(title)
	
	var my_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.2, 0.3, 0.8)
	my_panel.add_theme_stylebox_override("panel", style)
	main_vbox.add_child(my_panel)
	
	var my_vbox = VBoxContainer.new()
	my_panel.add_child(my_vbox)
	
	var my_title = Label.new()
	my_title.text = "My Transponder Settings"
	my_vbox.add_child(my_title)
	
	btn_active = CheckButton.new()
	btn_active.text = "Broadcast Active"
	btn_active.toggled.connect(func(pressed): emit_signal("transponder_toggled", pressed))
	my_vbox.add_child(btn_active)
	
	var hbox1 = HBoxContainer.new()
	btn_share_name = CheckButton.new()
	btn_share_name.text = "Share Name"
	btn_share_name.toggled.connect(func(pressed): emit_signal("transponder_share_name_toggled", pressed))
	hbox1.add_child(btn_share_name)
	
	btn_share_loc = CheckButton.new()
	btn_share_loc.text = "Share Location"
	btn_share_loc.toggled.connect(func(pressed): emit_signal("transponder_share_loc_toggled", pressed))
	hbox1.add_child(btn_share_loc)
	my_vbox.add_child(hbox1)
	
	var hbox2 = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = "Custom Name: "
	hbox2.add_child(name_label)
	custom_name_edit = LineEdit.new()
	custom_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_name_edit.text_submitted.connect(func(text): emit_signal("transponder_custom_name_changed", text))
	hbox2.add_child(custom_name_edit)
	my_vbox.add_child(hbox2)
	
	main_vbox.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	comms_list_vbox = VBoxContainer.new()
	comms_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(comms_list_vbox)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	
	# Update my transponder state from engineering packet if available
	if current_state.has("engineering"):
		var eng = current_state["engineering"]
		var comps = eng.get("ship_components", [])
		for c in comps:
			if c.get("type") == "comms":
				btn_active.set_pressed_no_signal(c.get("transponder_active", true))
				btn_share_name.set_pressed_no_signal(c.get("transponder_share_name", true))
				btn_share_loc.set_pressed_no_signal(c.get("transponder_share_location", true))
				if not custom_name_edit.has_focus():
					custom_name_edit.text = c.get("transponder_custom_name", "")
				break
				
	if current_state.has("transponders"):
		_update_transponder_list(current_state["transponders"])

func _update_transponder_list(transponders: Dictionary) -> void:
	var my_pos = current_state.get("pos", Vector2.ZERO)
	var active_ids = []
	
	for t_id in transponders.keys():
		active_ids.append(t_id)
		var t_data = transponders[t_id]
		
		var panel: PanelContainer
		var header: Label
		var info: Label
		
		if transponder_panels.has(t_id):
			var refs = transponder_panels[t_id]
			panel = refs["panel"]
			header = refs["header"]
			info = refs["info"]
		else:
			panel = PanelContainer.new()
			var p_style = StyleBoxFlat.new()
			p_style.border_width_left = 4
			p_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			p_style.border_color = Color(0.2, 0.8, 0.8)
			panel.add_theme_stylebox_override("panel", p_style)
			
			var vbox = VBoxContainer.new()
			panel.add_child(vbox)
			
			header = Label.new()
			header.add_theme_color_override("font_color", Color(0.2, 0.8, 0.8))
			vbox.add_child(header)
			
			info = Label.new()
			info.add_theme_font_size_override("font_size", 12)
			vbox.add_child(info)
			
			comms_list_vbox.add_child(panel)
			transponder_panels[t_id] = {"panel": panel, "header": header, "info": info}
			
		header.text = t_data.get("name", "UNKNOWN")
		var flag = t_data.get("flag", "")
		if flag != "":
			header.text += " (Flag: " + flag + ")"
			
		if t_data.has("pos"):
			var dist_km = my_pos.distance_to(t_data["pos"]) / 1000.0
			info.text = "Distance: %.1f km" % [dist_km]
		else:
			info.text = "Distance: UNKNOWN (Location hidden)"
			
	# Remove old panels
	for t_id in transponder_panels.keys():
		if not t_id in active_ids:
			var old_panel = transponder_panels[t_id]["panel"]
			if is_instance_valid(old_panel):
				old_panel.queue_free()
			transponder_panels.erase(t_id)
