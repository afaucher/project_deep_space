extends Control

const NavigationPanel = preload("res://scripts/ui/navigation_panel.gd")
const HelmPanel = preload("res://scripts/ui/helm_panel.gd")
const SensorPanel = preload("res://scripts/ui/sensor_panel.gd")
const ContactsPanel = preload("res://scripts/ui/contacts_panel.gd")
const WeaponsPanel = preload("res://scripts/ui/weapons_panel.gd")
const EngineeringPanel = preload("res://scripts/ui/engineering_panel.gd")
const CommsPanel = preload("res://scripts/ui/comms_panel.gd")
const HelpOverlay = preload("res://scripts/ui/help_overlay.gd")

var nav_panel: Control
var helm_panel: Control
var sensor_panel: Control
var contacts_panel: Control
var weapons_panel: Control
var eng_panel: Control
var comms_panel: Control
var help_overlay: Control
var sensor_container: PanelContainer

var pinned_contacts: Array = []
var current_ship_oriented: bool = false

var sfx_laser: AudioStreamPlayer

# --- Player feedback: heat / overheat / damage (audio + haptics + on-screen) ---
var sfx_fan: AudioStreamPlayer       # looping coolant whir, ramped with heat
var sfx_alarm: AudioStreamPlayer     # looping overheat klaxon
var sfx_impact: AudioStreamPlayer    # one-shot hull thud on damage
var damage_flash: ColorRect          # red full-screen flash on damage
var overheat_label: Label            # blinking on-screen overheat alert

var _heat_fraction: float = 0.0      # latest current_heat / max_heat, drives the fan
var _is_overheating: bool = false    # edge state for alarm + sustained rumble
var _flash_alpha: float = 0.0        # current red-flash intensity, fades out
var _rumble_refresh: float = 0.0     # re-arm timer for sustained overheat rumble

const FAN_HEAT_FLOOR := 0.45         # fan inaudible below this heat fraction
const OVERHEAT_FRACTION := 0.99      # current_heat clamps to max_heat, so ~1.0 == pegged
const FLASH_FADE := 2.5              # red damage-flash fade-out per second

const ShipCatalog = preload("res://scripts/ship_catalog.gd")
var spawn_hull_dropdown: OptionButton
var spawn_team_dropdown: OptionButton
var ship_oriented_toggle: CheckButton

# Live performance readout (top bar). "phys tick %%" is the share of each fixed
# physics tick (1/Engine.physics_ticks_per_second) actually spent computing the
# physics step -- the rest is idle headroom. Directly answers "how much room is
# left before something like CCD would cost us frames". EMA-smoothed so it reads
# steadily instead of flickering per frame.
var _perf_label: Label
var _perf_phys_ema: float = 0.0
var _perf_fps_ema: float = 0.0
const PERF_EMA := 0.1

# Debug menu plumbing: each popup item id is an index into _debug_menu_items, which
# records which DebugSettings key + choice that row represents. Auto-built from the
# DebugSettings.OPTIONS registry, so new debug knobs need zero UI code here.
var _debug_popup: PopupMenu
var _debug_menu_items: Array = []  # [{key, choice}], parallel to popup item ids

# Builds the top-bar "Debug" MenuButton from the DebugSettings.OPTIONS registry. Every
# option becomes a labelled section of radio items; picking one writes straight to the
# global DebugSettings singleton. Adding a new knob is purely a registry edit.
func _build_debug_menu() -> MenuButton:
	var mb := MenuButton.new()
	mb.text = "Debug"
	_debug_popup = mb.get_popup()
	_debug_popup.hide_on_checkable_item_selection = false
	_rebuild_debug_popup()
	_debug_popup.id_pressed.connect(_on_debug_menu_id_pressed)
	return mb

func _rebuild_debug_popup() -> void:
	_debug_popup.clear()
	_debug_menu_items.clear()
	for key in DebugSettings.OPTIONS:
		var opt = DebugSettings.OPTIONS[key]
		_debug_popup.add_separator(opt["label"])
		var current = DebugSettings.get_choice(key)
		for choice_idx in range(opt["choices"].size()):
			var id = _debug_menu_items.size()
			_debug_menu_items.append({"key": key, "choice": choice_idx})
			_debug_popup.add_radio_check_item(opt["choices"][choice_idx], id)
			_debug_popup.set_item_checked(_debug_popup.get_item_index(id), choice_idx == current)

func _on_debug_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= _debug_menu_items.size():
		return
	var entry = _debug_menu_items[id]
	DebugSettings.set_choice(entry["key"], entry["choice"])
	_rebuild_debug_popup()  # refresh radio checks

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("help_toggle") and help_overlay:
		help_overlay.visible = not help_overlay.visible
	if event.is_action_pressed("map_orient_toggle") and ship_oriented_toggle:
		ship_oriented_toggle.button_pressed = !ship_oriented_toggle.button_pressed

func _ready() -> void:
	sfx_laser = AudioStreamPlayer.new()
	sfx_laser.stream = preload("res://assets/audio/laser.wav")
	add_child(sfx_laser)

	sfx_fan = AudioStreamPlayer.new()
	var fan_stream = load("res://assets/audio/fan.wav")
	if fan_stream is AudioStreamWAV: fan_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sfx_fan.stream = fan_stream
	sfx_fan.volume_db = -60.0
	add_child(sfx_fan)

	sfx_alarm = AudioStreamPlayer.new()
	var alarm_stream = load("res://assets/audio/alarm.wav")
	if alarm_stream is AudioStreamWAV: alarm_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sfx_alarm.stream = alarm_stream
	add_child(sfx_alarm)

	sfx_impact = AudioStreamPlayer.new()
	sfx_impact.stream = load("res://assets/audio/impact.wav")
	add_child(sfx_impact)

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
	
	var contacts_toggle = CheckButton.new()
	contacts_toggle.text = "Contacts"
	contacts_toggle.button_pressed = true
	top_bar.add_child(contacts_toggle)
	
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
	
	var comms_toggle = CheckButton.new()
	comms_toggle.text = "Comms"
	comms_toggle.button_pressed = false
	top_bar.add_child(comms_toggle)
	
	var sensor_toggle = CheckButton.new()
	sensor_toggle.text = "Sensors"
	sensor_toggle.button_pressed = false
	top_bar.add_child(sensor_toggle)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	# Sandbox spawn: hull dropdown + team dropdown + Spawn button (replaces the
	# old single dropdown and the removed F2 overlay panel). Catalog hulls spawn
	# on the selected team; the two legacy non-ship objects ignore the team.
	spawn_hull_dropdown = OptionButton.new()
	for entry in ShipCatalog.SPAWNABLE:
		spawn_hull_dropdown.add_item(entry["name"])
	spawn_hull_dropdown.add_item("Target Buoy")
	spawn_hull_dropdown.add_item("Asteroids (10)")
	top_bar.add_child(spawn_hull_dropdown)

	spawn_team_dropdown = OptionButton.new()
	spawn_team_dropdown.add_item("Friendly")
	spawn_team_dropdown.add_item("Enemy")
	spawn_team_dropdown.add_item("Pirate")
	spawn_team_dropdown.select(ShipCatalog.Team.ENEMY)
	top_bar.add_child(spawn_team_dropdown)

	var spawn_button = Button.new()
	spawn_button.text = "Spawn"
	spawn_button.pressed.connect(_on_spawn_pressed)
	top_bar.add_child(spawn_button)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer2)
	
	var spacer3 = Control.new()
	spacer3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer3)
	
	top_bar.add_child(_build_debug_menu())

	ship_oriented_toggle = CheckButton.new()
	ship_oriented_toggle.text = "Ship Oriented"
	ship_oriented_toggle.button_pressed = false
	ship_oriented_toggle.toggled.connect(func(pressed): current_ship_oriented = pressed)
	top_bar.add_child(ship_oriented_toggle)

	# Prevent top bar buttons from stealing focus and consuming the spacebar hotkey
	for child in top_bar.get_children():
		if child is BaseButton:
			child.focus_mode = Control.FOCUS_NONE


	
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
	

	# --- Contacts Panel ---
	var contacts_container = PanelContainer.new()
	contacts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contacts_container.size_flags_stretch_ratio = 1.0
	var contacts_style = StyleBoxFlat.new()
	contacts_style.bg_color = Color(0.02, 0.05, 0.02)
	contacts_style.border_width_right = 2
	contacts_style.border_color = Color(0.2, 0.4, 0.2)
	_add_margins(contacts_style)
	contacts_container.add_theme_stylebox_override("panel", contacts_style)
	
	contacts_panel = ContactsPanel.new()
	contacts_panel.contact_pin_toggled.connect(_on_contact_pin_toggled)
	contacts_panel.selection_changed.connect(_on_selection_changed)
	contacts_container.add_child(contacts_panel)
	content_hbox.add_child(contacts_container)
	
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
	
	# --- Comms Panel ---
	var comms_container = PanelContainer.new()
	comms_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comms_container.size_flags_stretch_ratio = 1.0
	var comms_style = StyleBoxFlat.new()
	comms_style.bg_color = Color(0.05, 0.05, 0.1)
	comms_style.border_width_left = 2
	comms_style.border_color = Color(0.2, 0.6, 0.8)
	_add_margins(comms_style)
	comms_container.add_theme_stylebox_override("panel", comms_style)
	
	comms_panel = CommsPanel.new()
	comms_panel.transponder_toggled.connect(_on_transponder_toggled)
	comms_panel.transponder_share_name_toggled.connect(_on_transponder_share_name_toggled)
	comms_panel.transponder_share_loc_toggled.connect(_on_transponder_share_loc_toggled)
	comms_container.add_child(comms_panel)
	content_hbox.add_child(comms_container)
	comms_container.visible = false
	
	# --- Sensor Panel ---
	sensor_container = PanelContainer.new()
	sensor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensor_container.size_flags_stretch_ratio = 1.0
	var sensor_style = StyleBoxFlat.new()
	sensor_style.bg_color = Color(0.02, 0.05, 0.02)
	sensor_style.border_width_right = 2
	sensor_style.border_color = Color(0.2, 0.4, 0.2)
	_add_margins(sensor_style)
	sensor_container.add_theme_stylebox_override("panel", sensor_style)
	
	sensor_panel = SensorPanel.new()
	sensor_panel.selection_changed.connect(_on_selection_changed)
	sensor_panel.sensor_state_changed.connect(_on_sensor_state_changed)
	sensor_panel.all_sensors_state_changed.connect(_on_all_sensors_state_changed)
	sensor_container.add_child(sensor_panel)
	content_hbox.add_child(sensor_container)
	sensor_container.visible = false
	eng_container.visible = true
	
	# Connect toggles
	nav_toggle.toggled.connect(func(pressed): nav_container.visible = pressed)
	contacts_toggle.toggled.connect(func(pressed): contacts_container.visible = pressed)
	sensor_toggle.toggled.connect(func(pressed): sensor_container.visible = pressed)
	helm_toggle.toggled.connect(func(pressed): helm_container.visible = pressed)
	weapons_toggle.toggled.connect(func(pressed): weapons_container.visible = pressed)
	eng_toggle.toggled.connect(func(pressed): eng_container.visible = pressed)
	comms_toggle.toggled.connect(func(pressed): comms_container.visible = pressed)

	# Damage red-flash + overheat alert overlays. Added before the help overlay so it
	# still draws on top; both ignore the mouse so they never eat clicks.
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)

	overheat_label = Label.new()
	overheat_label.text = "!!  OVERHEAT  !!"
	overheat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overheat_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	overheat_label.offset_top = 50
	overheat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	overheat_label.add_theme_font_size_override("font_size", 28)
	overheat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overheat_label.visible = false
	add_child(overheat_label)

	# F1 controls overlay (added last so it draws on top of every panel) + a persistent
	# nudge so a cold player discovers it.
	help_overlay = HelpOverlay.new()
	add_child(help_overlay)

	# Bottom bar: help hint on the left, live perf readout on the right.
	var bottom_bar := HBoxContainer.new()

	var help_hint := Label.new()
	help_hint.text = "F1  Controls"
	help_hint.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	help_hint.add_theme_font_size_override("font_size", 13)
	bottom_bar.add_child(help_hint)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(bottom_spacer)

	_perf_label = Label.new()
	_perf_label.text = "FPS --"
	_perf_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	_perf_label.add_theme_font_size_override("font_size", 13)
	bottom_bar.add_child(_perf_label)

	main_vbox.add_child(bottom_bar)

func _add_margins(style: StyleBoxFlat) -> void:
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 3
	style.content_margin_bottom = 3

func _get_my_ship() -> Node:
	var ship_node_name = "Ship_" + str(multiplayer.get_unique_id())
	return get_node_or_null("/root/Main/" + ship_node_name)

func _on_spawn_pressed() -> void:
	var ship_node = _get_my_ship()
	if not ship_node: return
	var hull_idx = spawn_hull_dropdown.selected
	var n_ships = ShipCatalog.SPAWNABLE.size()
	if hull_idx >= 0 and hull_idx < n_ships:
		# Catalog hull -> spawn on the selected team. Team dropdown index matches
		# the ShipCatalog.Team enum (Friendly=0, Enemy=1, Pirate=2). The host
		# resolves the name to a ship script and routes through _spawn_ship().
		var ship_name = ShipCatalog.SPAWNABLE[hull_idx]["name"]
		var team = spawn_team_dropdown.selected
		ship_node.rpc_id(1, "request_spawn_ship", ship_name, team)
	elif hull_idx == n_ships:
		ship_node.rpc_id(1, "request_spawn", "buoy")
	elif hull_idx == n_ships + 1:
		ship_node.rpc_id(1, "request_spawn", "asteroids")

func update_data(packet: Dictionary) -> void:
	# Inject local UI state into the packet so sub-panels can read it
	packet["pinned_contacts"] = pinned_contacts
	packet["is_ship_oriented"] = current_ship_oriented
	
	var selected_target = contacts_panel.get_selected_contact_id() if is_instance_valid(contacts_panel) else ""
	packet["selected_contact_id"] = selected_target
	
	if nav_panel and nav_panel.has_method("update_data"):
		nav_panel.update_data(packet)
	if helm_panel and helm_panel.has_method("update_data"):
		helm_panel.update_data(packet)
	if sensor_panel and sensor_panel.has_method("update_data"):
		sensor_panel.update_data(packet)
	if contacts_panel and contacts_panel.has_method("update_data"):
		contacts_panel.update_data(packet)
	if weapons_panel and weapons_panel.has_method("update_data"):
		weapons_panel.update_data(packet, selected_target)
	if eng_panel and eng_panel.has_method("update_data"):
		eng_panel.update_data(packet)
	if comms_panel and comms_panel.has_method("update_data"):
		comms_panel.update_data(packet)

	if packet.has("transient_events"):
		for ev in packet["transient_events"]:
			if ev["type"] == "laser":
				sfx_laser.play()
			elif ev["type"] == "damage":
				_on_player_damage(ev.get("amount", 0.0))

	# Heat feedback: fan (continuous, in _process) + overheat alert (edge).
	var eng = packet.get("engineering", {})
	var maxh = eng.get("max_heat", 0.0)
	_heat_fraction = (eng.get("current_heat", 0.0) / maxh) if maxh > 0.0 else 0.0
	_update_overheat(_heat_fraction >= OVERHEAT_FRACTION)

func _on_fire_weapon_requested(weapon_id: String) -> void:
	var target_id = contacts_panel.get_selected_contact_id() if is_instance_valid(contacts_panel) else ""
	if target_id == "": return
	var target_pos = Vector2.ZERO # The host will compute actual lead pos, we just send a zero vector for now

	var ship_node = _get_my_ship()
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
	if contacts_panel and contacts_panel.has_method("set_selected_contact_id"):
		contacts_panel.set_selected_contact_id(c_id)

	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_sensor_target", c_id)

func _on_sensor_state_changed(sensor_id: String, is_active: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_sensor_state", sensor_id, is_active)

func _on_all_sensors_state_changed(is_active: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_all_sensors_state", is_active)

func _on_component_power_toggled(component_id: String, is_active: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_component_power", component_id, is_active)

func _on_transponder_toggled(is_active: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_transponder_active", is_active)

func _on_transponder_share_name_toggled(share: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_transponder_share_name", share)

func _on_transponder_share_loc_toggled(share: bool) -> void:
	var ship_node = _get_my_ship()
	if ship_node:
		ship_node.rpc_id(1, "set_transponder_share_location", share)

# ----------------------------------------------------
# Player feedback: heat fan / overheat alert / damage punch
# ----------------------------------------------------
# Live top-bar perf readout. "phys % busy" is the share of one fixed physics
# tick (1/Engine.physics_ticks_per_second) spent computing the physics step
# (server integration + every _physics_process); the idle remainder is the
# headroom a heavier physics feature (e.g. CCD) would eat into. TIME_PROCESS is
# the per-frame render/idle cost in ms. EMA-smoothed so it reads steadily.
func _update_perf_readout() -> void:
	if _perf_label == null:
		return
	var tick_period: float = 1.0 / float(max(1, Engine.physics_ticks_per_second))
	var phys_pct: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) / tick_period * 100.0
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var fps: float = Engine.get_frames_per_second()
	_perf_phys_ema = lerp(_perf_phys_ema, phys_pct, PERF_EMA)
	_perf_fps_ema = lerp(_perf_fps_ema, fps, PERF_EMA)
	var idle_pct: float = clampf(100.0 - _perf_phys_ema, 0.0, 100.0)
	_perf_label.text = "FPS %d  |  phys %d%% busy / %d%% idle  |  proc %.1f ms" % [
		int(round(_perf_fps_ema)), int(round(_perf_phys_ema)), int(round(idle_pct)), proc_ms]

func _process(delta: float) -> void:
	_update_perf_readout()

	# Coolant fan: ramp volume + pitch with heat fraction above the floor, silence below.
	if _heat_fraction > FAN_HEAT_FLOOR:
		if not sfx_fan.playing: sfx_fan.play()
		var t = clampf((_heat_fraction - FAN_HEAT_FLOOR) / (1.0 - FAN_HEAT_FLOOR), 0.0, 1.0)
		sfx_fan.volume_db = lerpf(-20.0, -2.0, t)
		sfx_fan.pitch_scale = lerpf(0.85, 1.45, t)
	elif sfx_fan.playing:
		sfx_fan.stop()

	# Damage flash fades back to transparent.
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(0.0, _flash_alpha - delta * FLASH_FADE)
		damage_flash.color.a = _flash_alpha

	# While overheating: blink the alert and throb the high-freq motor only -- a pulsing
	# buzz "alarm", deliberately unlike the balanced steering/throttle detent ticks.
	if _is_overheating:
		overheat_label.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_rumble_refresh -= delta
		if _rumble_refresh <= 0.0:
			_rumble(0.45, 0.0, 0.22)   # buzz pulse (no heavy motor); gap before re-arm -> throb
			_rumble_refresh = 0.45

func _on_player_damage(amount: float) -> void:
	sfx_impact.play()
	_flash_alpha = clampf(0.2 + amount / 200.0, 0.2, 0.55)
	# Bottom-heavy thump: low-freq "strong" motor dominant, almost no high-freq buzz, and
	# longer than a detent tick -- so a hit reads as a hit, not as crossing the helm detent.
	_rumble(0.1, clampf(0.55 + amount / 100.0, 0.55, 1.0), 0.28)

func _update_overheat(now_over: bool) -> void:
	if now_over == _is_overheating:
		return
	_is_overheating = now_over
	if now_over:
		if not sfx_alarm.playing: sfx_alarm.play()
		overheat_label.visible = true
	else:
		sfx_alarm.stop()
		overheat_label.visible = false
		_stop_rumble()

# Haptics layer on top of audio/visual: only when a controller is connected.
func _rumble(weak: float, strong: float, duration: float) -> void:
	var pads = Input.get_connected_joypads()
	if pads.is_empty(): return
	Input.start_joy_vibration(pads[0], weak, strong, duration)

func _stop_rumble() -> void:
	var pads = Input.get_connected_joypads()
	if pads.is_empty(): return
	Input.stop_joy_vibration(pads[0])




