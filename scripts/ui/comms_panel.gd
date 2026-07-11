extends Control

var current_state: Dictionary = {}

var vsplit: VSplitContainer
var comms_list_vbox: VBoxContainer
var npc_buttons: Dictionary = {}

# Controls for our own transponder
var btn_active: CheckButton
var btn_share_name: CheckButton
var btn_share_loc: CheckButton
var ship_name_label: RichTextLabel

# M41 -- "Missions" section: this panel is where missions are GRANTED (via
# dialogue mutations, see aunt_stephanie.dialogue), so it's also where you
# review them. Just a text readout (title + current objective per active
# mission), NOT the contract feed -- no indicators_visible filtering here;
# muting only affects map/contacts-panel declutter, not "can I see what I
# accepted". A single Label whose .text is reset each update_data() tick
# (packet["missions"], built by main.gd) rather than rebuilding child nodes
# every tick.
var missions_label: Label

# Chat UI
var chat_panel: VBoxContainer
var chat_header: Label
var chat_log: RichTextLabel
var responses_vbox: VBoxContainer

# Active Chat State
var active_dialogue_resource: Resource
var active_chat_contact: String = ""
# M33 -- the transmitting ship's instance id for the currently-open chat (the
# station/NPC host, e.g. a port-control NPC's owner). Used to resolve an
# actual node reference for extra_game_states (see _dialogue_game_states())
# so a .dialogue mutation can call station-specific methods like
# issue_docking_grant()/request_docking_via_control(). 0 = none/unresolved.
var active_chat_source_id: int = 0

signal transponder_toggled(active: bool)
signal transponder_share_name_toggled(share: bool)
signal transponder_share_loc_toggled(share: bool)
signal transponder_custom_name_changed(new_name: String)

func _ready() -> void:
	clip_contents = true
	
	vsplit = VSplitContainer.new()
	vsplit.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vsplit)
	
	# === TOP PANE: CONTROLS & CONTACTS ===
	var top_pane = VBoxContainer.new()
	top_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_pane.custom_minimum_size.y = 200
	vsplit.add_child(top_pane)
	
	var title = Label.new()
	title.text = "COMMS & TRANSPONDERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.CYAN)
	top_pane.add_child(title)
	
	var my_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.2, 0.3, 0.8)
	my_panel.add_theme_stylebox_override("panel", style)
	top_pane.add_child(my_panel)
	
	var my_vbox = VBoxContainer.new()
	my_panel.add_child(my_vbox)
	
	ship_name_label = RichTextLabel.new()
	ship_name_label.bbcode_enabled = true
	ship_name_label.text = "[b]My Ship[/b]"
	ship_name_label.fit_content = true
	ship_name_label.name = "ShipNameLabel"
	my_vbox.add_child(ship_name_label)
	
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
	
	top_pane.add_child(HSeparator.new())

	# M41 -- Missions section: header + a small text readout, updated in
	# _update_missions_list() (called from update_data()).
	var missions_title = Label.new()
	missions_title.text = "MISSIONS"
	missions_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missions_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	top_pane.add_child(missions_title)

	missions_label = Label.new()
	missions_label.text = "(no active missions)"
	missions_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	missions_label.add_theme_font_size_override("font_size", 12)
	top_pane.add_child(missions_label)

	top_pane.add_child(HSeparator.new())

	var title2 = Label.new()
	title2.text = "LOCAL CONTACTS"
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title2.add_theme_color_override("font_color", Color.CYAN)
	top_pane.add_child(title2)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_pane.add_child(scroll)
	
	comms_list_vbox = VBoxContainer.new()
	comms_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(comms_list_vbox)
	
	var btn_broadcast = Button.new()
	btn_broadcast.text = "[ OPEN BROADCAST CHANNEL ]"
	btn_broadcast.add_theme_color_override("font_color", Color.ORANGE)
	btn_broadcast.custom_minimum_size.y = 40
	btn_broadcast.pressed.connect(_open_broadcast)
	comms_list_vbox.add_child(btn_broadcast)
	
	# === BOTTOM PANE: CHAT UI ===
	chat_panel = VBoxContainer.new()
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_panel.custom_minimum_size.y = 200
	vsplit.add_child(chat_panel)
	
	var chat_panel_bg = PanelContainer.new()
	var chat_style = StyleBoxFlat.new()
	chat_style.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	chat_style.border_width_top = 2
	chat_style.border_color = Color.CYAN
	chat_panel_bg.add_theme_stylebox_override("panel", chat_style)
	chat_panel_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_panel.add_child(chat_panel_bg)
	
	var chat_vbox = VBoxContainer.new()
	chat_panel_bg.add_child(chat_vbox)
	
	chat_header = Label.new()
	chat_header.text = "CHAT: OFFLINE"
	chat_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_header.add_theme_color_override("font_color", Color.CYAN)
	chat_vbox.add_child(chat_header)
	
	chat_vbox.add_child(HSeparator.new())
	
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_vbox.add_child(chat_log)
	
	chat_vbox.add_child(HSeparator.new())
	
	responses_vbox = VBoxContainer.new()
	chat_vbox.add_child(responses_vbox)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	
	if current_state.has("ship_name"):
		if ship_name_label:
			ship_name_label.text = "[b]" + current_state["ship_name"] + "[/b]"

	if current_state.has("engineering"):
		var eng = current_state["engineering"]
		var comps = eng.get("ship_components", [])
		for c in comps:
			if c.get("type") == "comms":
				btn_active.set_pressed_no_signal(c.get("transponder_active", true))
				btn_share_name.set_pressed_no_signal(c.get("transponder_share_name", true))
				btn_share_loc.set_pressed_no_signal(c.get("transponder_share_location", false))
				break
				
	_update_contacts_list()
	_update_missions_list()

# M41 -- packet["missions"] is built by main.gd's _distribute_state() as
# [{title, objective_text}, ...] straight off the player ship's MissionLog
# (active_missions() + get_active_objective() per mission) -- plain data,
# same cadence as every other packet field this panel already reads.
func _update_missions_list() -> void:
	if missions_label == null:
		return
	var missions: Array = current_state.get("missions", [])
	if missions.is_empty():
		missions_label.text = "(no active missions)"
		return
	var lines: Array = []
	for m in missions:
		lines.append("%s: %s" % [m.get("title", ""), m.get("objective_text", "")])
	missions_label.text = "\n".join(lines)

func _update_contacts_list() -> void:
	var transponders = current_state.get("transponders", {})
	var ledger = current_state.get("comms_ledger", {"vouched": [], "ephemeral": []})
	var my_pos = current_state.get("pos", Vector2.ZERO)
	
	var active_keys = []
	
	for t_id in transponders.keys():
		var t_data = transponders[t_id]
		var npcs = t_data.get("npcs", [])
		
		for npc in npcs:
			var is_known = false
			if npc.get("tier", 0) == 0:
				is_known = true
			else:
				for v in ledger["vouched"]:
					if v["name"] == npc["name"]: is_known = true
				for e in ledger["ephemeral"]:
					if e["name"] == npc["name"]: is_known = true
					
			if not is_known:
				continue
				
			var char_name = npc.get("name", "Unknown")
			var uid = str(t_id) + "_" + char_name
			active_keys.append(uid)
			
			if not npc_buttons.has(uid):
				var btn = Button.new()
				btn.custom_minimum_size.y = 40
				btn.text = char_name + " (" + npc.get("faction", "") + ")"
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				
				var path = npc.get("dialogue_path", "")
				var source_id: int = int(t_id)
				btn.pressed.connect(func(): _start_dialogue(path, char_name, source_id))
				
				comms_list_vbox.add_child(btn)
				npc_buttons[uid] = btn
	
	for k in npc_buttons.keys():
		if not k in active_keys:
			var btn = npc_buttons[k]
			if is_instance_valid(btn):
				btn.queue_free()
			npc_buttons.erase(k)

func _open_broadcast() -> void:
	active_chat_contact = "BROADCAST"
	active_dialogue_resource = null
	active_chat_source_id = 0
	chat_header.text = "CHAT: OPEN BROADCAST CHANNEL"
	chat_log.text = "[color=orange]-- MONITORING OPEN FREQUENCIES --[/color]\n"
	_clear_responses()
	
	var btn_disconnect = Button.new()
	btn_disconnect.text = "[ DISCONNECT ]"
	btn_disconnect.pressed.connect(_disconnect_chat)
	responses_vbox.add_child(btn_disconnect)

func _start_dialogue(path: String, char_name: String, source_id: int = 0) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return

	active_chat_contact = char_name
	active_chat_source_id = source_id
	active_dialogue_resource = load(path)
	chat_header.text = "CHAT: " + char_name.to_upper()
	chat_log.text = "[color=cyan]-- ENCRYPTED LINK ESTABLISHED --[/color]\n"

	_process_dialogue("start")

# M33 -- extra_game_states for the DialogueManager call: a single Dictionary
# whose keys become identifiers a .dialogue mutation/condition can reference
# directly (e.g. `station.request_docking_via_control(player)`,
# `station.get_port_zone()`). "station" resolves the NPC's transmitting ship
# via its instance id (same instance_from_id() pattern navigation_panel.gd
# already uses to turn a broadcast id back into a live node -- valid here
# because comms_panel and the ships it's rendering share one process; only
# cross-peer state goes through the RPC packet layer). "player" is this
# client's own ship (same _get_my_ship() lookup terminal_display.gd uses).
# Both may be null (source freed mid-chat, or no local ship yet) -- a
# mutation that calls a method on a null state simply won't resolve, same
# failure mode DialogueManager already has for any missing state value.
#
# M39 -- "story" (the StoryState autoload) and "missions" (the player ship's
# MissionLog, null-safe) join the same surface, per the roadmap's "keep ONE
# pattern" rule (challenge #6): dialogue reaches game systems only through
# objects handed in extra_game_states, never autoload lookups inside
# .dialogue files. StoryState IS an autoload, but .dialogue files still refer
# to it as "story" from this dict like everything else -- the autoload
# wiring is an implementation detail of comms_panel, not something a
# .dialogue file should know about directly.
func _dialogue_game_states() -> Array:
	var station = instance_from_id(active_chat_source_id) if active_chat_source_id != 0 else null
	if station != null and not is_instance_valid(station):
		station = null
	var player = _get_my_ship()
	var missions = player.mission_log if player != null else null
	return [{"station": station, "player": player, "story": StoryState, "missions": missions}]

func _get_my_ship() -> Node:
	var ship_node_name = "Ship_" + str(multiplayer.get_unique_id())
	return get_node_or_null("/root/Main/" + ship_node_name)

func _process_dialogue(node_id: String) -> void:
	_clear_responses()

	if not Engine.has_singleton("DialogueManager"):
		chat_log.text += "\n[color=red]Error: Comms system failure.[/color]\n"
		return

	var dm = Engine.get_singleton("DialogueManager")
	var line = await dm.get_next_dialogue_line(active_dialogue_resource, node_id, _dialogue_game_states())
	
	if line != null:
		chat_log.text += "\n[color=cyan][b]" + line.character + ":[/b][/color] " + line.text + "\n"
		for resp in line.responses:
			# M42 -- DialogueManager's get_next_dialogue_line() does NOT filter
			# line.responses by a `- Response [if cond /]` gate itself: every
			# response line.responses ID compiles into the array regardless,
			# each carrying an `is_allowed` bool set from evaluating its own
			# condition (see dialogue_manager.gd's _get_responses()/
			# _check_condition() -- filtering is left to the caller, normally
			# DialogueResponsesMenu's `hide_failed_responses`). This panel
			# builds its own buttons directly, so it must do that filtering
			# itself, or a gated response (e.g. aunt_stephanie.dialogue's
			# mission-offer/status-check pair) would show unconditionally.
			if not resp.is_allowed:
				continue
			var btn = Button.new()
			btn.text = resp.text
			btn.pressed.connect(func(): _on_response_clicked(resp))
			responses_vbox.add_child(btn)
	else:
		chat_log.text += "\n[color=gray]-- LINK TERMINATED BY REMOTE USER --[/color]\n"
		var btn_end = Button.new()
		btn_end.text = "[ END TRANSMISSION ]"
		btn_end.pressed.connect(_disconnect_chat)
		responses_vbox.add_child(btn_end)

func _on_response_clicked(resp) -> void:
	chat_log.text += "\n[color=gray]> " + resp.text + "[/color]\n"
	_process_dialogue(resp.next_id)

func _clear_responses() -> void:
	for child in responses_vbox.get_children():
		child.queue_free()

func _disconnect_chat() -> void:
	active_chat_contact = ""
	active_dialogue_resource = null
	active_chat_source_id = 0
	chat_header.text = "CHAT: OFFLINE"
	chat_log.text = ""
	_clear_responses()
