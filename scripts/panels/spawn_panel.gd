extends Control

# M10 sandbox spawn panel -- a small corner UI for host/local-test sessions
# that lets the player pick a hull from ShipCatalog.SPAWNABLE and a team
# (Friendly / Enemy / Pirate), then spawn it near the player ship via
# main.gd's _spawn_ship() director. Toggled with F2 (see main.gd's
# _unhandled_input). Purely additive -- doesn't touch the existing
# request_spawn (asteroids/drone/buoy) dropdown in terminal_display.gd.
const ShipCatalog = preload("res://scripts/ship_catalog.gd")

var main_node: Node = null

var ship_dropdown: OptionButton
var team_dropdown: OptionButton

const TEAM_OPTIONS := [
	{ "label": "Friendly", "team": ShipCatalog.Team.FRIENDLY },
	{ "label": "Enemy", "team": ShipCatalog.Team.ENEMY },
	{ "label": "Pirate", "team": ShipCatalog.Team.PIRATE },
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -220
	offset_right = -10
	offset_top = 10
	offset_bottom = 140
	grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.5, 0.3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "SANDBOX SPAWN (F2)"
	vbox.add_child(title)

	var ship_label = Label.new()
	ship_label.text = "Hull"
	vbox.add_child(ship_label)

	ship_dropdown = OptionButton.new()
	for entry in ShipCatalog.SPAWNABLE:
		ship_dropdown.add_item(entry["name"])
	vbox.add_child(ship_dropdown)

	var team_label = Label.new()
	team_label.text = "Team"
	vbox.add_child(team_label)

	team_dropdown = OptionButton.new()
	for opt in TEAM_OPTIONS:
		team_dropdown.add_item(opt["label"])
	vbox.add_child(team_dropdown)

	var spawn_button = Button.new()
	spawn_button.text = "Spawn"
	spawn_button.pressed.connect(_on_spawn_pressed)
	vbox.add_child(spawn_button)

func _on_spawn_pressed() -> void:
	if main_node == null or not main_node.has_method("_spawn_ship"):
		return

	var ship_idx = ship_dropdown.selected
	if ship_idx < 0 or ship_idx >= ShipCatalog.SPAWNABLE.size():
		return
	var ship_script = ShipCatalog.SPAWNABLE[ship_idx]["script"]

	var team_idx = team_dropdown.selected
	if team_idx < 0 or team_idx >= TEAM_OPTIONS.size():
		return
	var team = TEAM_OPTIONS[team_idx]["team"]

	main_node._spawn_ship(ship_script, team)
