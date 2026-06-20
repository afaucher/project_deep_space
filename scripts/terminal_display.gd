extends Control

const NavigationPanel = preload("res://scripts/navigation_panel.gd")
const HelmPanel = preload("res://scripts/helm_panel.gd")
const SensorPanel = preload("res://scripts/sensor_panel.gd")

var nav_panel: Control
var helm_panel: Control
var sensor_panel: Control

func _ready() -> void:
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
	
	# --- Main Content Area ---
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)
	
	# --- Navigation Panel ---
	var nav_container = PanelContainer.new()
	nav_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nav_style = StyleBoxFlat.new()
	nav_style.bg_color = Color(0.05, 0.05, 0.1)
	nav_style.border_width_right = 2
	nav_style.border_color = Color(0.2, 0.4, 0.2)
	nav_container.add_theme_stylebox_override("panel", nav_style)
	
	nav_panel = NavigationPanel.new()
	nav_container.add_child(nav_panel)
	content_hbox.add_child(nav_container)
	
	# --- Sensor Panel ---
	var sensor_container = PanelContainer.new()
	sensor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sensor_style = StyleBoxFlat.new()
	sensor_style.bg_color = Color(0.02, 0.05, 0.02)
	sensor_style.border_width_right = 2
	sensor_style.border_color = Color(0.2, 0.4, 0.2)
	sensor_container.add_theme_stylebox_override("panel", sensor_style)
	
	sensor_panel = SensorPanel.new()
	sensor_container.add_child(sensor_panel)
	content_hbox.add_child(sensor_container)
	
	# --- Helm Panel ---
	var helm_container = PanelContainer.new()
	helm_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var helm_style = StyleBoxFlat.new()
	helm_style.bg_color = Color(0.05, 0.05, 0.05)
	helm_style.border_width_left = 2
	helm_style.border_color = Color(0.2, 0.4, 0.2)
	helm_container.add_theme_stylebox_override("panel", helm_style)
	
	helm_panel = HelmPanel.new()
	helm_container.add_child(helm_panel)
	content_hbox.add_child(helm_container)
	
	# Connect toggles
	nav_toggle.toggled.connect(func(pressed): nav_container.visible = pressed)
	sensor_toggle.toggled.connect(func(pressed): sensor_container.visible = pressed)
	helm_toggle.toggled.connect(func(pressed): helm_container.visible = pressed)

func update_data(packet: Dictionary) -> void:
	if nav_panel and nav_panel.has_method("update_data"):
		nav_panel.update_data(packet)
	if helm_panel and helm_panel.has_method("update_data"):
		helm_panel.update_data(packet)
	if sensor_panel and sensor_panel.has_method("update_data"):
		sensor_panel.update_data(packet)
