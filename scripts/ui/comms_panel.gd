extends Control

const DialogueScratch = preload("res://scripts/dialogue_scratch.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")

# (A local SOS_FRESH_STALENESS const mirroring Ship.FIRE_STALENESS_MAX lived
# here, justified as avoiding an import of Ship -- while the one line that used
# it already called Ship.contact_age(). Self-refuting, so the copy is gone.)

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

# M49 -- hail protocol (design_ideas/comms_verbs.md). M52d renamed
# comply_requested -> acknowledge_requested with the COMPLY -> ACKNOWLEDGE
# verb rename (the button declares receipt; compliance stays behavioral).
# Revised in review: ACKNOWLEDGE and stopping are DECOUPLED -- a player
# might acknowledge while still running, hoping to buy time, so
# acknowledging must never force compliance. stop_requested is the
# separate "actually comply" action (Ship.engage_dead_stop) -- the
# "autopilot" half of the split.
signal acknowledge_requested()
signal stop_requested()
# M52 -- SOS becomes an actual toggle (implementation_plans/
# m52_sos_as_contact.md item 4), wired to Ship.set_sos_active instead of a
# one-shot fire-and-forget -- `active` mirrors the CheckButton's new state,
# `nature` is only meaningful when active is true (re-evaluated fresh on
# every toggle-ON press, see _on_sos_toggled below).
signal sos_toggled(active: bool, nature: String)
# Post-M51 playtest -- the contact action row moved HERE from the contacts
# panel (contact rows are prime real estate; comms is where you talk to and
# judge ships). All act on the currently SELECTED contact (selection is
# shared across panels via terminal_display's set_selected_contact_id
# fan-out). c_id is our own track id; terminal_display resolves instance ids.
# (mark_hostile_requested/unmark_hostile_requested moved to weapons_panel.gd
# alongside the standing readout -- MARK/UNMARK is a targeting-computer
# judgment call, not a comms action; this panel keeps only genuine comms
# verbs: identify/stop demands, docking. M52d removed the RELEASE verb
# entirely (design revised in review -- see hail.gd), so there is no
# release_requested signal anymore; a demand/hold ends when the issuer
# stops refreshing it, not by anyone pressing a button.)
signal demand_requested(c_id: String, rung: String)

# M52d -- HAILS section restructured (implementation_plans/m52d_hail_ux.md
# item 4): ONE list of VESSEL entries (was: a selected-contact action row +
# a flat message list). A vessel appears if it's the selected contact, we
# sent it a hail (sent_hails, new in the packet), or it hailed us. Each
# entry: header (track id + name + flag), its to/from hail traffic, and the
# applicable action buttons -- all built from build_vessel_entries(), a pure
# function over packet data so the grouping is testable headless
# (test_comms_panel_hails.gd, same widget-level pattern as
# test_controls_menu_ui.gd). Plus the honored-stop banner (ACKNOWLEDGE /
# HELD state) and the SOS button.
var hail_banner: PanelContainer
var hail_banner_label: Label
var btn_acknowledge: Button
var btn_stop: Button
var btn_sos: CheckButton
var hails_title: Label
var hails_vbox: VBoxContainer
var _last_entries_rendered: Array = []
var _entry_nodes: Dictionary = {} # c_id -> {header, traffic, actions_hbox, buttons: {..}}
var selected_contact_id: String = ""
var _hosted_docking: Control = null
var _docking_fallback_row: HBoxContainer = null
# Test seam: headless widget tests have no /root/Main/Ship_<peer> node to
# resolve, so they set this to the instance id last_hails' target_iid uses.
var my_iid_override: int = -1

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

	# M49 -- SOS: sends UNDER_ATTACK if a fresh HOSTILE contact exists, else
	# DISABLED. The actual nature pick happens in _on_sos_toggled() against
	# current_state, same "packet-polling, not pushed" pattern as every other
	# reader of current_state in this panel. Deliberately plain -- just
	# another comm control alongside Share Name/Share Location (calling
	# session, 2026-07-23: the old standalone "[ SOS ]" button in ORANGE_RED
	# read as a special, separately-important mechanic; SOS is meant to be
	# ordinary infrastructure now, not a big red panic button). M52 follow-up
	# (implementation_plans/m52_sos_as_contact.md item 4): a CheckButton, not
	# a one-shot Button -- SOS is now a heartbeat the player turns on and off,
	# matching Share Name/Share Location's own control type.
	btn_sos = CheckButton.new()
	btn_sos.text = "SOS"
	btn_sos.toggled.connect(_on_sos_toggled)
	hbox1.add_child(btn_sos)

	my_vbox.add_child(hbox1)

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

	# M52d -- ACKNOWLEDGE (renamed from COMPLY) and STOP are separate buttons
	# (design revised in review): the playtest's original confusion was
	# exactly "do I stop? is the button just for fun?", so a SECOND vague
	# button would be worse than the bug this fixes -- each tooltip states
	# its own contract explicitly. ACKNOWLEDGE never stops the ship (a
	# player might acknowledge while still running, hoping to buy time);
	# STOP is the deliberate choice to comply (Ship.engage_dead_stop).
	btn_acknowledge = Button.new()
	btn_acknowledge.text = "ACKNOWLEDGE"
	btn_acknowledge.tooltip_text = "ACKNOWLEDGE — confirm receipt only. Does not stop your ship."
	btn_acknowledge.pressed.connect(func(): emit_signal("acknowledge_requested"))
	banner_hbox.add_child(btn_acknowledge)

	btn_stop = Button.new()
	btn_stop.text = "STOP"
	btn_stop.tooltip_text = "STOP — actually hold station and comply. Weapons cold while held. Moving again voids it."
	btn_stop.pressed.connect(func(): emit_signal("stop_requested"))
	banner_hbox.add_child(btn_stop)

	top_pane.add_child(HSeparator.new())

	# M52d -- HAILS: one vessel-grouped list (see the state block above).
	hails_title = Label.new()
	hails_title.text = "HAILS"
	hails_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hails_title.add_theme_color_override("font_color", Color.ORANGE_RED)
	top_pane.add_child(hails_title)

	hails_vbox = VBoxContainer.new()
	top_pane.add_child(hails_vbox)

	# Fallback home for the hosted docking control while no vessel entry is
	# selected -- the Undock face must never vanish just because the
	# selection cleared (same rule the old action row had). Adopt the control
	# now if it was hosted before this panel entered the tree.
	_docking_fallback_row = HBoxContainer.new()
	top_pane.add_child(_docking_fallback_row)
	if _pending_docking_control != null:
		_docking_fallback_row.add_child(_pending_docking_control)
		_hosted_docking = _pending_docking_control
		_pending_docking_control = null

	top_pane.add_child(HSeparator.new())

	# M41 -- Missions section: header + a small text readout, updated in
	# _update_missions_list() (called from update_data()).
	#
	# Playtest E: player-facing strings say CONTRACTS. The code layer stays
	# "mission" (MissionLog/MissionCatalog/packet["missions"]) -- renaming that
	# was explicitly deferred because contract_feed.gd already exists as its own
	# concept and collapsing the two names in code risks conflating them.
	#
	# Worth noting this is NOT two names for two things at the UI level either:
	# ContractFeed.build() walks the MissionLog's ACTIVE missions, so the
	# contacts panel's "Contracts" section is the nav-layer view of exactly what
	# this section grants. One concept, and now one word for it.
	var missions_title = Label.new()
	missions_title.text = "CONTRACTS"
	missions_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missions_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	top_pane.add_child(missions_title)

	missions_label = Label.new()
	missions_label.text = "(no active contracts)"
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
	
	# Playtest D1: the "[ OPEN BROADCAST CHANNEL ]" button is gone. It opened an
	# empty room -- set a chat header, printed one static "MONITORING OPEN
	# FREQUENCIES" line and a DISCONNECT button, and stopped. Nothing anywhere
	# read "BROADCAST" as an active_chat_contact and it never called
	# Hail.send_broadcast(), so there was no channel behind it to monitor.
	# Hail.send_broadcast() itself is untouched -- it is comms substrate with
	# real callers (SOS), it just never had anything to do with this button.

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
	_update_vessel_list()

# Hosts the terminal's DockingControl button (created + wired by
# terminal_display). M52d: it rides the SELECTED vessel's entry row in the
# vessel list (docking is a per-track action aimed at the selected station);
# _rebuild_vessel_list reparents it on every rebuild, with
# _docking_fallback_row as its home while nothing is selected (the Undock
# face must never vanish mid-dock). Callable BEFORE this panel enters the
# tree (terminal_display wires panels prior to add_child, so _ready hasn't
# run yet): the control parks in _pending_docking_control and _ready adopts
# it.
var _pending_docking_control: Control = null

func host_docking_control(ctrl: Control) -> void:
	ctrl.focus_mode = Control.FOCUS_NONE # don't steal the spacebar hotkey
	if _docking_fallback_row != null:
		_docking_fallback_row.add_child(ctrl)
		_hosted_docking = ctrl
	else:
		_pending_docking_control = ctrl

# Shared-selection sink (terminal_display's _on_selection_changed fan-out,
# same duck-typed method the sensor/contacts panels expose).
func set_selected_contact_id(c_id: String) -> void:
	selected_contact_id = c_id
	_update_vessel_list()

# M49/M52d -- honored-stop banner, two faces:
#   HELD -- while compelled_stop is active, say so explicitly ("HELD --
#   stopped for <ship>") instead of leaving the player to infer the
#   throttle override; no button -- the hold ends on its own once the
#   issuer stops refreshing it (the RELEASE verb is gone entirely, design
#   revised in review; see hail.gd/ship.gd).
#   Pending demand -- shows for ANY rung (STOP or IDENTIFY): ACKNOWLEDGE is
#   always available (design revised in review: acknowledging means "I
#   heard you," not "I'm complying," so it applies to any demand, not just
#   STOP). STOP only appears for a STOP-rung demand -- there's nothing to
#   "stop" in response to an IDENTIFY. Cleared when the issuer's heartbeat
#   goes quiet (M52d expiry) or a fresh demand replaces it; pressing
#   ACKNOWLEDGE alone does NOT clear it (the demand stays open until
#   genuinely complied with or it lapses).
func _update_hail_banner() -> void:
	if hail_banner == null:
		return
	var compelled: Dictionary = current_state.get("compelled_stop", {})
	if not compelled.is_empty():
		hail_banner.visible = true
		btn_acknowledge.visible = false
		btn_stop.visible = false
		hail_banner_label.text = "HELD — stopped for %s" % _vessel_display_name(compelled.get("issuer_iid", -1))
		return
	var demand: Dictionary = current_state.get("pending_demand", {})
	if demand.is_empty():
		hail_banner.visible = false
		btn_acknowledge.visible = false
		btn_stop.visible = false
		return
	var rung: String = demand.get("rung", "")
	hail_banner.visible = true
	btn_acknowledge.visible = true
	# STOP hidden pending autopilot design (parked -- see design_ideas/).
	# engage_dead_stop() still exists and is used by AI; just no player button.
	btn_stop.visible = false
	var flag: String = demand.get("sender_flag", "")
	var flag_text: String = flag if flag != "" else "UNKNOWN (dark)"
	hail_banner_label.text = "DEMAND(%s) from flag: %s" % [rung, flag_text]

# Short display handle for a vessel by instance id: claimed transponder name,
# else its track id in our contacts, else "vessel".
func _vessel_display_name(iid: int) -> String:
	var t: Dictionary = current_state.get("transponders", {}).get(iid, {})
	if t.get("name", "") != "":
		return "\"%s\"" % t.get("name")
	var contacts: Dictionary = current_state.get("contacts", {})
	for c_id in contacts:
		if contacts[c_id].get("instance_id", -1) == iid:
			return c_id
	return "vessel"

# M52d -- incoming-hail alert hook (terminal_display calls this off the
# "hail" transient event): flash the HAILS header so a demand landing in a
# panel you aren't looking at is still noticeable.
func flash_hails_alert() -> void:
	if hails_title == null:
		return
	var tw := create_tween()
	for i in range(3):
		tw.tween_property(hails_title, "modulate", Color(3.0, 0.3, 0.3), 0.15)
		tw.tween_property(hails_title, "modulate", Color.WHITE, 0.15)

# ---------------------------------------------------------------------------
# M52d -- vessel-grouped HAILS list (implementation_plans/m52d_hail_ux.md
# item 4). build_vessel_entries is PURE (packet data in, display dicts out)
# so the grouping/qualification rules are testable headless without a ship
# or a frame tick; _update_vessel_list/_rebuild_vessel_list are the thin
# Control glue on top.
# ---------------------------------------------------------------------------

# One entry per vessel that is (a) the selected contact, (b) a vessel we
# sent a directed hail to, or (c) a vessel that hailed US directly. Entry:
# {c_id, iid, name, flag, selected, known_contact, traffic:[..]} ordered
# selected-first then by c_id. Traffic lines are that vessel's
# directed exchanges with us, oldest first: "> them" = ours, "< them" =
# theirs. No "[TO YOU]" tag -- being listed under the vessel already says so.
func build_vessel_entries(contacts: Dictionary, transponders: Dictionary,
		last_hails: Array, sent_hails: Array, selected_id: String, my_iid: int) -> Array:
	var by_iid: Dictionary = {} # iid -> entry-in-progress
	var iid_to_cid: Dictionary = {}
	for c_id in contacts:
		var inst: int = contacts[c_id].get("instance_id", -1)
		if inst != -1:
			iid_to_cid[inst] = c_id

	# Reason (a): the selected contact, if it's a vessel we hold a track on.
	var sel: Dictionary = contacts.get(selected_id, {})
	var sel_class: String = sel.get("classification", "")
	if not sel.is_empty() and (sel_class == "UNIDENTIFIED VESSEL" or sel_class == "FRIENDLY VESSEL"):
		var sel_iid: int = sel.get("instance_id", -1)
		by_iid[sel_iid] = _blank_entry(selected_id, sel_iid)

	# Reason (b): vessels we sent a directed hail to.
	for sh in sent_hails:
		var t_iid: int = sh.get("target_iid", -1)
		if t_iid == -1:
			continue
		if not by_iid.has(t_iid):
			by_iid[t_iid] = _blank_entry(iid_to_cid.get(t_iid, Ship.track_id(t_iid)), t_iid)

	# Reason (c): vessels that hailed US directly.
	for h in last_hails:
		if h.get("target_iid", -1) != my_iid:
			continue
		var s_iid: int = h.get("sender_iid", -1)
		if s_iid == -1 or s_iid == my_iid:
			continue
		if not by_iid.has(s_iid):
			by_iid[s_iid] = _blank_entry(iid_to_cid.get(s_iid, Ship.track_id(s_iid)), s_iid)
		# A hail's stamped flag is the freshest read we have on a sender that
		# may not be transponding now.
		if by_iid[s_iid]["flag"] == "":
			by_iid[s_iid]["flag"] = h.get("sender_flag", "")

	# Fill in identity + per-vessel traffic + action gating.
	for iid in by_iid:
		var e: Dictionary = by_iid[iid]
		var t: Dictionary = transponders.get(iid, {})
		if t.get("name", "") != "":
			e["name"] = t.get("name")
		if t.get("flag", "") != "" and e["flag"] == "":
			e["flag"] = t.get("flag")
		e["selected"] = e["c_id"] == selected_id and selected_id != ""
		var c: Dictionary = contacts.get(e["c_id"], {})
		e["known_contact"] = not c.is_empty()
		# Traffic, buffer order (oldest first) -- theirs to us, then ours to
		# them interleaved per source buffer (both are small rings).
		for h2 in last_hails:
			if h2.get("sender_iid", -1) == iid and h2.get("target_iid", -1) == my_iid:
				e["traffic"].append("< %s" % _verb_text(h2))
		for sh2 in sent_hails:
			if sh2.get("target_iid", -1) == iid:
				e["traffic"].append("> %s" % _verb_text(sh2))

	var entries: Array = by_iid.values()
	entries.sort_custom(func(a, b):
		if a["selected"] != b["selected"]:
			return a["selected"]
		return a["c_id"] < b["c_id"])
	return entries

func _blank_entry(c_id: String, iid: int) -> Dictionary:
	return {"c_id": c_id, "iid": iid, "name": "", "flag": "", "selected": false,
		"known_contact": false, "traffic": []}

func _verb_text(hail: Dictionary) -> String:
	var verb: String = hail.get("verb", "")
	var rung: String = hail.get("rung", "")
	return verb + ("(" + rung + ")" if rung != "" else "")

# Header per the playtest's ask: track id + claimed name + flag.
func entry_header_text(e: Dictionary) -> String:
	var name_part: String = " \"%s\"" % e["name"] if e["name"] != "" else ""
	var flag_part: String = e["flag"] if e["flag"] != "" else "dark"
	return "%s%s — %s" % [e["c_id"], name_part, flag_part]

func _update_vessel_list() -> void:
	if hails_vbox == null:
		return
	var my_ship = _get_my_ship()
	var my_iid: int = my_ship.get_instance_id() if my_ship != null else my_iid_override
	var entries: Array = build_vessel_entries(
		current_state.get("contacts", {}),
		current_state.get("transponders", {}),
		current_state.get("last_hails", []),
		current_state.get("sent_hails", []),
		selected_contact_id, my_iid)
	if entries != _last_entries_rendered:
		_last_entries_rendered = entries.duplicate(true)
		_rebuild_vessel_list(entries)
	# Dock-state can change with an unchanged entry list (e.g. capture
	# completes while nothing is selected) -- keep the fallback-parked
	# control's Undock face live every tick, not just on rebuilds.
	if _hosted_docking != null and _hosted_docking.get_parent() == _docking_fallback_row:
		var my_ship_dock = _get_my_ship()
		_hosted_docking.visible = my_ship_dock != null and my_ship_dock.get("docking_bay") != null

func _rebuild_vessel_list(entries: Array) -> void:
	# The hosted docking control survives rebuilds by reparenting -- pull it
	# out BEFORE the children are freed.
	if _hosted_docking != null and _hosted_docking.get_parent() != null:
		_hosted_docking.get_parent().remove_child(_hosted_docking)
	for child in hails_vbox.get_children():
		child.queue_free()
	_entry_nodes.clear()

	var my_ship = _get_my_ship()
	var is_docked: bool = my_ship != null and my_ship.get("docking_bay") != null
	var docking_hosted := false

	if entries.is_empty():
		var none = Label.new()
		none.text = "(no vessels -- select one in CONTACTS, or await a hail)"
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		hails_vbox.add_child(none)

	for e in entries:
		# Playtest C3: the hails list follows the tactical contacts' visual
		# language -- a bordered row per vessel, the selected one filled, and
		# the SAME colour rule (Utils.contact_color) so a ship reads identically
		# in both lists. Previously every row was a bare label, cyan when
		# selected and white otherwise, which told you nothing about the ship
		# and did not match the contacts panel at all.
		var e_contact: Dictionary = current_state.get("contacts", {}).get(e["c_id"], {})
		var row_color: Color = Utils.contact_color(e_contact) if not e_contact.is_empty() else Color(0.7, 0.7, 0.7)

		var entry_panel = PanelContainer.new()
		var e_style = StyleBoxFlat.new()
		e_style.bg_color = Utils.ROW_BG_SELECTED if e["selected"] else Utils.ROW_BG
		e_style.border_color = row_color
		e_style.set_border_width_all(1)
		e_style.set_content_margin_all(4)
		entry_panel.add_theme_stylebox_override("panel", e_style)
		hails_vbox.add_child(entry_panel)

		var entry_box = VBoxContainer.new()
		entry_panel.add_child(entry_box)

		var header = Label.new()
		header.text = entry_header_text(e)
		header.autowrap_mode = TextServer.AUTOWRAP_WORD
		header.add_theme_color_override("font_color", row_color)
		entry_box.add_child(header)

		var traffic_labels: Array = []
		for line in e["traffic"]:
			var lbl = Label.new()
			lbl.text = "  " + line
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6) if line.begins_with("<") else Color(0.7, 0.85, 1.0))
			entry_box.add_child(lbl)
			traffic_labels.append(lbl)

		# Action row: consistent button style/casing across every verb (the
		# playtest called out the caps/prose mix). Demands are free to ask of
		# any tracked vessel. Buttons stay disabled for a hail-only entry we
		# hold no track on (nothing to aim the send at). M52d removed the
		# RELEASE verb/button entirely -- a demand/hold ends on its own once
		# the issuer stops refreshing it, nobody presses a button for it.
		var actions = HBoxContainer.new()
		entry_box.add_child(actions)
		var c_id: String = e["c_id"]

		var b_id = Button.new()
		b_id.text = "DEMAND ID"
		b_id.disabled = not e["known_contact"]
		b_id.pressed.connect(func(): emit_signal("demand_requested", c_id, Hail.RUNG_IDENTIFY))
		actions.add_child(b_id)

		var b_stop = Button.new()
		b_stop.text = "DEMAND STOP"
		b_stop.disabled = not e["known_contact"]
		b_stop.pressed.connect(func(): emit_signal("demand_requested", c_id, Hail.RUNG_STOP))
		actions.add_child(b_stop)

		# The docking control rides the SELECTED vessel's row (it targets the
		# selected station via terminal_display's _update_docking_control).
		if e["selected"] and _hosted_docking != null:
			actions.add_child(_hosted_docking)
			_hosted_docking.visible = true
			docking_hosted = true

		_entry_nodes[c_id] = {"header": header, "traffic": traffic_labels,
			"actions_hbox": actions,
			"buttons": {"demand_id": b_id, "demand_stop": b_stop}}

	# No selected entry took the docking control: park it in the fallback
	# row, visible only while actually docked (the Undock face rule).
	if _hosted_docking != null and not docking_hosted:
		_docking_fallback_row.add_child(_hosted_docking)
		_hosted_docking.visible = is_docked

# M49 -- SOS nature pick: UNDER_ATTACK if we hold any fresh HOSTILE contact,
# else DISABLED, using the same FIRE_STALENESS_MAX freshness gate against
# the "contacts" the packet already carries. M52 follow-up
# (implementation_plans/m52_sos_as_contact.md item 4): re-evaluated on
# every toggle-ON press (not just once) -- a player toggling SOS off and
# back on later might have a different nature by then. Toggling OFF picks
# "DISABLED" here too, but it's inert -- set_sos_active (M52 passive sync,
# implementation_plans/m52_sos_passive_sync.md) writes it to sos_nature
# regardless, and datalink_relay's reconciliation only ever reads
# sos_nature while sos_active is true.
func _on_sos_toggled(pressed: bool) -> void:
	var nature := Hail.NATURE_DISABLED
	if pressed:
		var contacts: Dictionary = current_state.get("contacts", {})
		for c_id in contacts:
			var c: Dictionary = contacts[c_id]
			if c.get("standing", "") == Standing.HOSTILE and Ship.contact_age(c) <= Ship.FIRE_STALENESS_MAX:
				nature = Hail.NATURE_UNDER_ATTACK
				break
	emit_signal("sos_toggled", pressed, nature)

# M41 -- packet["missions"] is built by main.gd's _distribute_state() as
# [{title, objective_text}, ...] straight off the player ship's MissionLog
# (active_missions() + get_active_objective() per mission) -- plain data,
# same cadence as every other packet field this panel already reads.
func _update_missions_list() -> void:
	if missions_label == null:
		return
	var missions: Array = current_state.get("missions", [])
	if missions.is_empty():
		missions_label.text = "(no active contracts)"
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
