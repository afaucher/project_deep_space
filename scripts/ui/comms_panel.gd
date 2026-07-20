extends Control

const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")

# Mirrors Ship.FIRE_STALENESS_MAX (ship.gd) -- kept as a local const rather
# than importing the Ship script here (this panel is client UI reading the
# already-filtered packet, not sim-side); see ship.gd for the rationale.
const SOS_FRESH_STALENESS := 3.0

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

# M49 -- hail protocol (design_ideas/comms_verbs.md).
signal comply_requested()
signal sos_requested(nature: String)
# Post-M51 playtest -- the contact action row moved HERE from the contacts
# panel (contact rows are prime real estate; comms is where you talk to and
# judge ships). All act on the currently SELECTED contact (selection is
# shared across panels via terminal_display's set_selected_contact_id
# fan-out). c_id is our own track id; terminal_display resolves instance ids.
# (mark_hostile_requested/unmark_hostile_requested moved to weapons_panel.gd
# alongside the standing readout -- MARK/UNMARK is a targeting-computer
# judgment call, not a comms action; this panel keeps only genuine comms
# verbs: identify/stop demands, docking, release.)
signal demand_requested(c_id: String, rung: String)
signal release_requested(c_id: String)

# HAILS section (last_hails newest-first) + honored-stop banner/COMPLY + SOS
# button + the selected-contact action row.
var hail_banner: PanelContainer
var hail_banner_label: Label
var btn_comply: Button
var btn_sos: Button
var hails_vbox: VBoxContainer
var _last_hails_rendered: Array = []
var selected_contact_id: String = ""
var action_hbox: HBoxContainer
var _hosted_docking: Control = null
var action_target_lbl: Label
var btn_demand_id: Button
var btn_demand_stop: Button
var btn_release: Button

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

	# M49 -- SOS: sends UNDER_ATTACK if a fresh HOSTILE contact exists, else
	# DISABLED. The actual nature pick happens in _on_sos_pressed() against
	# current_state, same "packet-polling, not pushed" pattern as every other
	# reader of current_state in this panel.
	btn_sos = Button.new()
	btn_sos.text = "[ SOS ]"
	btn_sos.add_theme_color_override("font_color", Color.ORANGE_RED)
	btn_sos.pressed.connect(_on_sos_pressed)
	my_vbox.add_child(btn_sos)

	# M49 -- honored-stop banner: a red bar + COMPLY button, shown only while
	# a pending STOP demand exists on the player ship (packet["pending_
	# demand"]). This is the fear moment the design wants (design_ideas/
	# comms_verbs.md) -- a STOP demand arriving from a dark, untrusted
	# contact on YOUR panel.
	hail_banner = PanelContainer.new()
	var banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.4, 0.05, 0.05, 0.9)
	hail_banner.add_theme_stylebox_override("panel", banner_style)
	hail_banner.visible = false
	top_pane.add_child(hail_banner)

	var banner_hbox = HBoxContainer.new()
	hail_banner.add_child(banner_hbox)

	hail_banner_label = Label.new()
	hail_banner_label.text = "DEMAND(STOP) RECEIVED"
	hail_banner_label.add_theme_color_override("font_color", Color.WHITE)
	hail_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_hbox.add_child(hail_banner_label)

	btn_comply = Button.new()
	btn_comply.text = "COMPLY"
	btn_comply.pressed.connect(func(): emit_signal("comply_requested"))
	banner_hbox.add_child(btn_comply)

	top_pane.add_child(HSeparator.new())

	# M49 -- HAILS: last_hails newest-first (sender name/flag, verb+rung,
	# addressed-to-me highlight).
	var hails_title = Label.new()
	hails_title.text = "HAILS"
	hails_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hails_title.add_theme_color_override("font_color", Color.ORANGE_RED)
	top_pane.add_child(hails_title)

	# Selected-contact action row (moved here from the contacts panel --
	# post-M51 playtest): who it acts on + the judgment/verb buttons.
	# Visibility rules live in _update_action_row().
	action_target_lbl = Label.new()
	action_target_lbl.text = "No contact selected"
	action_target_lbl.add_theme_font_size_override("font_size", 12)
	action_target_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	top_pane.add_child(action_target_lbl)

	action_hbox = HBoxContainer.new()
	top_pane.add_child(action_hbox)

	btn_demand_id = Button.new()
	btn_demand_id.text = "DEMAND ID"
	btn_demand_id.pressed.connect(func(): emit_signal("demand_requested", selected_contact_id, Hail.RUNG_IDENTIFY))
	action_hbox.add_child(btn_demand_id)

	btn_demand_stop = Button.new()
	btn_demand_stop.text = "DEMAND STOP"
	btn_demand_stop.pressed.connect(func(): emit_signal("demand_requested", selected_contact_id, Hail.RUNG_STOP))
	action_hbox.add_child(btn_demand_stop)

	# Request Docking / Undock sits HERE, right beside the demands -- it is
	# a peer per-track action (it already targets the SELECTED station via
	# terminal_display's _update_docking_control). Adopted now if it was
	# hosted before this panel entered the tree.
	if _pending_docking_control != null:
		action_hbox.add_child(_pending_docking_control)
		_hosted_docking = _pending_docking_control
		_pending_docking_control = null

	btn_release = Button.new()
	btn_release.text = "RELEASE"
	btn_release.pressed.connect(func(): emit_signal("release_requested", selected_contact_id))
	action_hbox.add_child(btn_release)

	hails_vbox = VBoxContainer.new()
	top_pane.add_child(hails_vbox)

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
	_update_hail_banner()
	_update_hails_list()
	_update_action_row()

# Hosts the terminal's DockingControl button (created + wired by
# terminal_display) in the action row beside DEMAND ID/STOP. Callable
# BEFORE this panel enters the tree (terminal_display wires panels prior
# to add_child, so _ready -- which builds the row -- hasn't run yet): the
# control parks in _pending_docking_control and _ready adopts it.
var _pending_docking_control: Control = null

func host_docking_control(ctrl: Control) -> void:
	ctrl.focus_mode = Control.FOCUS_NONE # don't steal the spacebar hotkey
	if action_hbox != null:
		action_hbox.add_child(ctrl)
		action_hbox.move_child(ctrl, 2) # after DEMAND ID / DEMAND STOP
		_hosted_docking = ctrl
	else:
		_pending_docking_control = ctrl

# Shared-selection sink (terminal_display's _on_selection_changed fan-out,
# same duck-typed method the sensor/contacts panels expose).
func set_selected_contact_id(c_id: String) -> void:
	selected_contact_id = c_id
	_update_action_row()

# Visibility rules (carried over from the contacts-panel buttons this row
# replaces): everything needs a selected VESSEL contact. DEMAND ID/STOP --
# always (asking is free; even a hostile can be demanded a stop). RELEASE --
# only a contact we're crediting with complied_stop. (MARK HOSTILE/UNMARK
# moved to weapons_panel.gd -- see that panel's own visibility rule.)
func _update_action_row() -> void:
	if action_target_lbl == null:
		return
	var contacts: Dictionary = current_state.get("contacts", {})
	var c: Dictionary = contacts.get(selected_contact_id, {})
	var classification: String = c.get("classification", "")
	var is_vessel: bool = classification == "UNIDENTIFIED VESSEL" or classification == "FRIENDLY VESSEL"
	var standing: String = c.get("standing", "")

	# Request Docking/Undock rides the row but with its own rule: visible for
	# a selected vessel (it targets the selected station) OR while actually
	# docked -- the Undock face must never vanish just because the selection
	# cleared. Its own refresh() handles enabled/disabled and the label flip.
	var my_ship = _get_my_ship()
	var is_docked: bool = my_ship != null and my_ship.get("docking_bay") != null

	if c.is_empty() or not is_vessel:
		action_target_lbl.text = "No vessel selected (select one in CONTACTS)"
		for b in [btn_demand_id, btn_demand_stop, btn_release]:
			b.visible = false
		if _hosted_docking != null:
			_hosted_docking.visible = is_docked
		return

	var t_name: String = c.get("transponder_name", "")
	action_target_lbl.text = "Selected: %s%s%s" % [selected_contact_id,
		(" '" + t_name + "'") if t_name != "" else "",
		(" [" + standing + "]") if standing != "" else ""]
	btn_demand_id.visible = true
	btn_demand_stop.visible = true
	btn_release.visible = c.get("complied_stop", false)
	if _hosted_docking != null:
		_hosted_docking.visible = true

# M49 -- honored-stop banner: visible whenever the player ship holds a
# pending STOP demand (packet["pending_demand"], set by ship.gd's comms_inbox
# processing). Cleared the moment we COMPLY (pending_demand is cleared
# server-side) or a fresh demand replaces it.
func _update_hail_banner() -> void:
	if hail_banner == null:
		return
	var demand: Dictionary = current_state.get("pending_demand", {})
	var is_stop_demand: bool = demand.get("rung", "") == Hail.RUNG_STOP
	hail_banner.visible = is_stop_demand
	if is_stop_demand:
		var flag: String = demand.get("sender_flag", "")
		var flag_text: String = flag if flag != "" else "UNKNOWN (dark)"
		hail_banner_label.text = "DEMAND(STOP) from flag: %s" % flag_text

# M49 -- last_hails newest-first: sender name/flag, verb+rung, addressed-to-me
# highlight. Rebuilt only when the newest hail actually changed, keyed on its
# seq -- NOT on array size: last_hails is a rolling ring buffer capped at 8,
# so once full its size never changes again and a size check would freeze the
# list on the first 8 hails forever. (seq + count together also cover the
# buffer draining/reset case.)
func _update_hails_list() -> void:
	if hails_vbox == null:
		return
	var hails: Array = current_state.get("last_hails", [])
	var newest_seq: int = hails.back().get("seq", -1) if not hails.is_empty() else -1
	var rendered_seq: int = _last_hails_rendered.back().get("seq", -1) if not _last_hails_rendered.is_empty() else -1
	if newest_seq == rendered_seq and hails.size() == _last_hails_rendered.size():
		return
	_last_hails_rendered = hails.duplicate()

	for child in hails_vbox.get_children():
		child.queue_free()

	var my_ship = _get_my_ship()
	var my_iid: int = my_ship.get_instance_id() if my_ship != null else -1

	for i in range(hails.size() - 1, -1, -1):
		var hail: Dictionary = hails[i]
		var verb: String = hail.get("verb", "")
		var rung: String = hail.get("rung", "")
		var flag: String = hail.get("sender_flag", "")
		var flag_text: String = flag if flag != "" else "dark"
		var verb_text: String = verb + ("(" + rung + ")" if rung != "" else "")
		var addressed_to_me: bool = hail.get("target_iid", -1) == my_iid

		var lbl = Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.text = "%s -- flag: %s%s" % [verb_text, flag_text, " [TO YOU]" if addressed_to_me else ""]
		lbl.add_theme_color_override("font_color", Color.RED if addressed_to_me else Color(0.8, 0.8, 0.8))
		hails_vbox.add_child(lbl)

# M49 -- SOS nature pick: UNDER_ATTACK if we hold any fresh HOSTILE contact,
# else DISABLED. Mirrors Ship._nearest_fresh_hostile_pos()'s freshness gate
# (FIRE_STALENESS_MAX) against the same "contacts" the packet already carries.
func _on_sos_pressed() -> void:
	var contacts: Dictionary = current_state.get("contacts", {})
	var nature := Hail.NATURE_DISABLED
	for c_id in contacts:
		var c: Dictionary = contacts[c_id]
		if c.get("standing", "") == Standing.HOSTILE and c.get("last_seen_timer", 999.0) <= SOS_FRESH_STALENESS:
			nature = Hail.NATURE_UNDER_ATTACK
			break
	emit_signal("sos_requested", nature)

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
	# DialogueScratch.scratch(): pre-declared assignment targets for the
	# `do x = ...` temporaries .dialogue files use. DialogueManager can only
	# assign to a name that already exists on a game state -- without this,
	# the assignment errored AFTER the right-hand side ran, so e.g. port
	# control ISSUED the grant but `outcome` stayed unset and the conversation
	# spoke the else-branch "Negative, we have no open berths" over a real
	# grant (the long-standing text/state mismatch). Rebuilt fresh per line
	# fetch, so temps can't leak between conversations; within ONE fetch (the
	# mutation -> condition -> spoken-line walk) DM holds the same array, which
	# is all the temporaries need.
	return [{"station": station, "player": player, "story": StoryState, "missions": missions}, DialogueScratch.scratch()]

func _get_my_ship() -> Node:
	var ship_node_name = "Ship_" + str(multiplayer.get_unique_id())
	return get_node_or_null("/root/Main/" + ship_node_name)

func _process_dialogue(node_id: String) -> void:
	var f = FileAccess.open("user://debug_comms.txt", FileAccess.READ_WRITE)
	if not f: f = FileAccess.open("user://debug_comms.txt", FileAccess.WRITE)
	if f: f.seek_end()
	
	if f: f.store_line("--- _process_dialogue called with " + str(node_id) + " ---")
	_clear_responses()

	if not Engine.has_singleton("DialogueManager"):
		if f: f.store_line("Error: No DialogueManager")
		chat_log.text += "\n[color=red]Error: Comms system failure.[/color]\n"
		return

	var dm = Engine.get_singleton("DialogueManager")
	var line = await dm.get_next_dialogue_line(active_dialogue_resource, node_id, _dialogue_game_states())
	
	if line != null:
		if f: f.store_line("Line received: " + line.text)
		if f: f.store_line("Next ID: " + str(line.next_id))
		chat_log.text += "\n[color=cyan][b]" + line.character + ":[/b][/color] " + line.text + "\n"
		var has_choices = false
		if f: f.store_line("Responses count: " + str(line.responses.size()))
		for resp in line.responses:
			if f: f.store_line("  Resp text: " + str(resp.text) + " is_allowed: " + str(resp.is_allowed))
			if not resp.is_allowed:
				continue
			var btn = Button.new()
			btn.text = resp.text if resp.text != "" else "[ CONTINUE ]"
			btn.pressed.connect(func(): _on_response_clicked(resp))
			responses_vbox.add_child(btn)
			has_choices = true
			
		if f: f.store_line("has_choices is " + str(has_choices))
		if not has_choices:
			if f: f.store_line("Auto-advancing to " + str(line.next_id))
			_process_dialogue(line.next_id)
	else:
		if f: f.store_line("Line is null (ended)")
		chat_log.text += "\n[color=gray]-- LINK TERMINATED BY REMOTE USER --[/color]\n"
		var btn_end = Button.new()
		btn_end.text = "[ CLOSE CHANNEL ]"
		btn_end.pressed.connect(_disconnect_chat)
		responses_vbox.add_child(btn_end)
		
	if f: f.close()

func _on_response_clicked(resp) -> void:
	if resp.text.ends_with("(Disconnect)"):
		chat_log.text += "\n[color=gray]> " + resp.text.replace(" (Disconnect)", "") + "[/color]\n"
		chat_log.text += "\n[color=gray]-- LINK TERMINATED BY LOCAL USER --[/color]\n"
		_clear_responses()
		var btn_end = Button.new()
		btn_end.text = "[ CLOSE CHANNEL ]"
		btn_end.pressed.connect(_disconnect_chat)
		responses_vbox.add_child(btn_end)
		return

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
