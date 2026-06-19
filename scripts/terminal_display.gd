extends Control

const NavigationPanel = preload("res://scripts/navigation_panel.gd")
const HelmPanel = preload("res://scripts/helm_panel.gd")

var nav_panel: Control
var helm_panel: Control

func _ready() -> void:
	# Ensure it resizes with the window
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)
	
	# --- Left Side: Navigation ---
	var nav_container = PanelContainer.new()
	nav_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var nav_style = StyleBoxFlat.new()
	nav_style.bg_color = Color(0.05, 0.05, 0.1)
	nav_style.border_width_right = 2
	nav_style.border_color = Color(0.2, 0.4, 0.2)
	nav_container.add_theme_stylebox_override("panel", nav_style)
	
	var nav_vbox = VBoxContainer.new()
	
	var nav_title = Label.new()
	nav_title.text = "NAVIGATION"
	nav_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_vbox.add_child(nav_title)
	
	nav_panel = NavigationPanel.new()
	nav_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_vbox.add_child(nav_panel)
	
	nav_container.add_child(nav_vbox)
	hbox.add_child(nav_container)
	
	# --- Right Side: Helm ---
	var helm_container = PanelContainer.new()
	helm_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var helm_style = StyleBoxFlat.new()
	helm_style.bg_color = Color(0.05, 0.05, 0.05)
	helm_style.border_width_left = 2
	helm_style.border_color = Color(0.2, 0.4, 0.2)
	helm_container.add_theme_stylebox_override("panel", helm_style)
	
	var helm_vbox = VBoxContainer.new()
	
	var helm_title = Label.new()
	helm_title.text = "HELM / STEERING"
	helm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	helm_vbox.add_child(helm_title)
	
	helm_panel = HelmPanel.new()
	helm_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	helm_vbox.add_child(helm_panel)
	
	helm_container.add_child(helm_vbox)
	hbox.add_child(helm_container)

func update_data(packet: Dictionary) -> void:
	if nav_panel and nav_panel.has_method("update_data"):
		nav_panel.update_data(packet)
	if helm_panel and helm_panel.has_method("update_data"):
		helm_panel.update_data(packet)
