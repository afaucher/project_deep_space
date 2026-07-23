extends Control

# M48 -- Standings & flags (IFF v2): row color prefers standing over raw
# classification for vessels. Referenced via preload const, never bare
# class_name. (Standing/Hail preloads removed with the action buttons --
# row colors key on the literal standing strings in _STANDING_COLORS below.
# The standing text readout + MARK HOSTILE/UNMARK buttons moved to the
# weapons panel's targeting-computer section; the DEMAND ID/STOP action
# row lives in comms_panel.gd. M52d removed the RELEASE verb entirely.)

signal contact_pin_toggled(c_id: String, is_pinned: bool)
signal selection_changed(c_id: String)

# Local color map -- standing.gd is phase-1, not ours to touch, and
# scripts/utils.gd's classification_color is shared with the nav/sensor
# panels (also out of scope here), so this is its own small const.
const _STANDING_COLORS := {
	"HOSTILE": Color(0.85, 0.2, 0.2),
	"UNREPORTED": Color(0.75, 0.7, 0.25),
	"NEUTRAL": Color(0.85, 0.85, 0.85),
	"FRIENDLY": Color(0.2, 0.8, 0.2),
}

# M52 -- SOS as a generic contact attribute (calling session, 2026-07-23):
# same RGB as navigation_panel.gd's SOS_COLOR (its own local const there too
# -- this file doesn't import colors from other panels, matches the existing
# "standing.gd is phase-1, not ours to touch" convention just above). A
# contact carrying sos/sos_nature/sos_name (ship.gd's comms_inbox VERB_SOS
# branch -- only ever stamped onto a REAL, already-existing track, never a
# manufactured one, per the M41 rule) gets this instead of its usual
# standing/classification color, so a friendly-standing ship in distress
# still reads as urgent rather than blending into the ordinary green row.
const _SOS_COLOR := Color(1.0, 0.25, 0.1, 0.95)

var current_state: Dictionary = {}
var contact_panels: Dictionary = {}

# M41 -- {entry_id: {"node": Control, "has_pos": bool}} for the "Contracts"
# section below. Separate from contact_panels: contract entries are a plain
# Array off packet["contracts"] (see scripts/story/contract_feed.gd), NOT
# keyed members of the sensor `contacts` Dictionary, so they need their own
# id->node tracking for the same create/reuse/prune-stale pattern
# _update_contact_list already uses.
var contract_panels: Dictionary = {}

var main_vbox: VBoxContainer
var section_vboxes: Dictionary = {}
var section_buttons: Dictionary = {}

var selected_contact_id: String = ""

# M41 -- the currently-selected "Contracts" row's entry id (independent of
# selected_contact_id -- a contract entry is never a member of the sensor
# `contacts` dict, so it can't reuse that id space). Polled by
# terminal_display.gd the same way it already polls get_selected_contact_id(),
# and read by navigation_panel.gd (packet["selected_contract_id"]) to draw the
# same white selection bracket a selected sensor contact gets -- that IS how
# "selecting a contract focuses the nav map on it" here: this codebase has no
# camera-pan-to-point mechanism, so map "focus" already means "highlight with
# the bracket + always-on label", the same visual treatment contact selection
# gets.
var selected_contract_id: String = ""

func get_selected_contact_id() -> String:
	return selected_contact_id

func get_selected_contract_id() -> String:
	return selected_contract_id

func set_selected_contact_id(c_id: String) -> void:
	if selected_contact_id != c_id:
		selected_contact_id = c_id
		selection_changed.emit(c_id)
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("nav_next_contact") or event.is_action_pressed("nav_prev_contact"):
		var contacts = current_state.get("contacts", {})
		if contacts.is_empty(): return
		
		var pos = current_state.get("pos", Vector2.ZERO)
		
		var enemies = []
		var ships = []
		var others = []
		
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var classification = c.get("classification", "UNKNOWN")
			var dist = pos.distance_to(c.get("pos", Vector2.ZERO))
			
			if classification == "UNIDENTIFIED VESSEL":
				enemies.append({"id": c_id, "dist": dist})
			elif classification == "FRIENDLY VESSEL":
				ships.append({"id": c_id, "dist": dist})
			else:
				others.append({"id": c_id, "dist": dist})
				
		enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
		ships.sort_custom(func(a, b): return a["dist"] < b["dist"])
		others.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		var contact_list = []
		for x in enemies: contact_list.append(x["id"])
		for x in ships: contact_list.append(x["id"])
		for x in others: contact_list.append(x["id"])
			
		if contact_list.is_empty(): return
		
		var idx = contact_list.find(selected_contact_id)
		if idx == -1:
			idx = 0
		elif event.is_action_pressed("nav_next_contact"):
			idx = (idx + 1) % contact_list.size()
		else:
			idx = (idx - 1) if idx > 0 else contact_list.size() - 1
			
		set_selected_contact_id(contact_list[idx])

func _ready() -> void:
	clip_contents = true
	
	main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	var title = Label.new()
	title.text = "TACTICAL CONTACTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.GREEN)
	main_vbox.add_child(title)
	
	main_vbox.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_vbox)
	
	# M41 -- "Contracts" at the END, same header-with-count + collapse
	# affordance as the other three (this loop already builds that generically
	# per section name -- no special-casing needed here, only in the
	# count/content updater below).
	var sections = ["Enemies", "Ships", "All Contacts", "Contracts"]
	for s_name in sections:
		var btn = Button.new()
		btn.text = s_name + " (-)"
		btn.toggle_mode = true
		content_vbox.add_child(btn)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.add_child(vbox)
		
		section_vboxes[s_name] = vbox
		section_buttons[s_name] = btn
		
		btn.toggled.connect(func(pressed):
			vbox.visible = not pressed
			btn.text = s_name + (" (+)" if pressed else " (-)")
		)

func _on_contact_selected(c_id: String) -> void:
	if selected_contact_id == c_id:
		selected_contact_id = ""
	else:
		selected_contact_id = c_id
		
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])
		
	emit_signal("selection_changed", selected_contact_id)

func _on_contact_panel_gui_input(event: InputEvent, c_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_contact_selected(c_id)

func update_data(packet: Dictionary) -> void:
	current_state = packet
	if current_state.has("contacts"):
		_update_contact_list(current_state["contacts"])
	# M41 -- packet["contracts"] is the separate NAV-layer feed built by
	# scripts/story/contract_feed.gd (main.gd's _distribute_state) -- an
	# Array, never merged into the sensor `contacts` Dictionary above.
	_update_contracts_list(current_state.get("contracts", []))

func _update_contact_list(contacts: Dictionary) -> void:
	var my_pos = current_state.get("pos", Vector2.ZERO)
	var my_rot = current_state.get("rot", 0.0)
	var my_components = current_state.get("engineering", {}).get("ship_components", [])
	var mock_my_sig = {"rot": my_rot, "em_emitters": my_components}
		
	var enemies = []
	var ships = []
	var others = []
	
	var transponders = current_state.get("transponders", {})
	
	for c_id in contacts.keys():
		var c = contacts[c_id].duplicate(true)
		var classification = c.get("classification", "UNKNOWN")
		var instance_id = c.get("instance_id", -1)
		
		# Merge transponder data if we have it for this instance_id
		if instance_id != -1 and transponders.has(instance_id):
			var t_data = transponders[instance_id]
			c["transponder_name"] = t_data.get("name", "")
			c["transponder_flag"] = t_data.get("flag", "")
		
		c["_id"] = c_id
		c["_dist"] = my_pos.distance_to(c.get("pos", Vector2.ZERO))
		
		if classification == "UNIDENTIFIED VESSEL":
			enemies.append(c)
		elif classification == "FRIENDLY VESSEL":
			ships.append(c)
		else:
			others.append(c)
			
	enemies.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
	ships.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
	others.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
	
	# Update button headers with counts
	section_buttons["Enemies"].text = "Enemies (" + str(enemies.size()) + ")" + (" (+)" if section_buttons["Enemies"].button_pressed else " (-)")
	section_buttons["Ships"].text = "Ships (" + str(ships.size()) + ")" + (" (+)" if section_buttons["Ships"].button_pressed else " (-)")
	section_buttons["All Contacts"].text = "All Contacts (" + str(others.size()) + ")" + (" (+)" if section_buttons["All Contacts"].button_pressed else " (-)")
	
	var sorted_contacts = enemies + ships + others
	
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

			contact_panels[c_id] = {"panel": panel, "style": p_style, "header": header, "pin_btn": pin_btn, "info": info}

		# Parent to the correct section
		var classification = c.get("classification", "UNKNOWN")
		var target_vbox: VBoxContainer
		if classification == "UNIDENTIFIED VESSEL":
			target_vbox = section_vboxes["Enemies"]
		elif classification == "FRIENDLY VESSEL":
			target_vbox = section_vboxes["Ships"]
		else:
			target_vbox = section_vboxes["All Contacts"]
			
		if panel.get_parent() != target_vbox:
			if panel.get_parent():
				panel.get_parent().remove_child(panel)
			target_vbox.add_child(panel)

		# Reorder to keep sorted within section (since we add them in sorted order, we can just use move_child)
		# Wait, idx is global. We need a per-section index.
		# But since we clear/move them, the order inside target_vbox is preserved by simply doing:
		target_vbox.move_child(panel, target_vbox.get_child_count() - 1)
		
		# Update visual properties
		var classification_str = classification
		if c_id == selected_contact_id:
			p_style.bg_color = Color(0.2, 0.4, 0.2, 0.8)
		else:
			p_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			
		# M48 -- standing (an earned, per-observer judgment) takes priority
		# over raw classification for a vessel's row color when present;
		# non-vessels (ordnance/wreckage/asteroids) never carry a standing
		# ("") and fall back to the pre-M48 classification coloring.
		# M52 -- SOS takes priority over BOTH: a friendly ship calling for
		# help is more urgent than its ordinary standing color, and the row
		# should read as unmistakably distinct at a glance (matches the nav
		# map's pulsing-cross treatment for the same event).
		var is_sos: bool = c.get("sos", false)
		var standing: String = c.get("standing", "")
		var color: Color
		if is_sos:
			color = _SOS_COLOR
		elif standing != "" and _STANDING_COLORS.has(standing):
			color = _STANDING_COLORS[standing]
		else:
			color = Color(0.8, 0.8, 0.8)
			if classification_str == "FRIENDLY VESSEL": color = Color(0.2, 0.8, 0.2)
			elif classification_str == "UNIDENTIFIED VESSEL": color = Color(0.8, 0.2, 0.2)
		p_style.border_color = color
		header.add_theme_color_override("font_color", color)

		var t_name = c.get("transponder_name", "")
		var base_name = t_name if t_name != "" else c_id
		header.text = ("[SOS] " + base_name + " [" + classification_str + "]") if is_sos else (base_name + " [" + classification_str + "]")

		var dist = c["_dist"]
		var vel = c.get("vel", Vector2.ZERO)
		var speed = vel.length()
		var age_s = c.get("last_seen_timer", 0.0)

		var their_pos = c.get("pos", Vector2.ZERO)
		var hdg = wrapf(rad_to_deg((their_pos - my_pos).angle()) + 90.0, 0.0, 360.0)

		var angle_from_them_to_us = (my_pos - their_pos).angle()
		var my_em_emit = Utils.get_directional_em(mock_my_sig, angle_from_them_to_us)
		var detect_dist = my_em_emit * (10000.0 / 15.0)

		var sig = c.get("signature", {})
		var sos_line: String = ""
		if is_sos:
			var nature: String = c.get("sos_nature", "")
			sos_line = "\nSOS: %s" % (nature if nature != "" else "distress call")
		info.text = ("Dist: %s | Hdg: %03d | Spd: %.1f m/s | Age: %.1fs\nHeat: %.1f | EM: %.1f\nCS: %.1f | Den: %.1f\nOur Emit: %.1f | Det Limit: %s" + sos_line) % [
			Utils.format_dist(dist), hdg, speed, age_s, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0),
			my_em_emit, Utils.format_dist(detect_dist)
		]
		# (Standing metadata -- the "Standing: X (reason)" detail line -- moved
		# to the weapons panel's targeting-computer section alongside MARK/
		# UNMARK; see weapons_panel.gd. Row color above still keys off
		# standing when present, just no text readout here anymore.)

		# Update state without emitting signal
		pin_btn.set_pressed_no_signal(c_id in pinned_list)
		# (The M48/M49 action buttons -- MARK HOSTILE, DEMAND ID/STOP -- moved
		# to the comms panel's HAILS action row; contact rows here are
		# read-only + pin. See comms_panel.gd.)

# ---------------------------------------------------------------------------
# M41 -- "Contracts" section: one row per contract_feed.gd entry (the current
# active objective of each active, un-muted mission). Entries with pos != null
# are clickable Buttons -- selecting one highlights it on the nav map (the
# navigation_panel.gd bracket, via packet["selected_contract_id"] -- see
# selected_contract_id's comment above for why that's "focus" in this
# codebase). Entries with pos == null (e.g. TALK_TO Todd) render as plain
# non-focusing Labels -- nothing to focus the map ON. See
# implementation_plans/m39_m44_homefront_roadmap.md, "M41".
# ---------------------------------------------------------------------------
func _update_contracts_list(contracts: Array) -> void:
	var btn = section_buttons.get("Contracts", null)
	if btn == null:
		return # defensive -- Contracts section always exists after _ready(), but never assume
	btn.text = "Contracts (" + str(contracts.size()) + ")" + (" (+)" if btn.button_pressed else " (-)")

	var target_vbox: VBoxContainer = section_vboxes["Contracts"]

	var active_ids: Array = []
	for entry in contracts:
		active_ids.append(entry.get("id", ""))

	# Prune stale rows (mission progressed to a new objective id, mission
	# completed, indicators muted, ...) -- same pattern _update_contact_list
	# uses for contact_panels above.
	for e_id in contract_panels.keys():
		if not e_id in active_ids:
			var stale_node = contract_panels[e_id]["node"]
			if is_instance_valid(stale_node):
				stale_node.queue_free()
			contract_panels.erase(e_id)

	# A selection whose entry disappeared (objective advanced/completed) can't
	# stay "selected" -- nothing on the map to bracket anymore.
	if selected_contract_id != "" and not active_ids.has(selected_contract_id):
		selected_contract_id = ""

	for entry in contracts:
		var e_id: String = entry.get("id", "")
		if e_id == "":
			continue
		var pos = entry.get("pos", null)
		var has_pos: bool = pos != null
		var title: String = entry.get("title", "")
		var mission_title: String = entry.get("mission_title", "")
		var label_text: String = (mission_title + " -- " + title) if mission_title != "" else title

		if not contract_panels.has(e_id):
			var node: Control
			if has_pos:
				var row_btn := Button.new()
				row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				row_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
				row_btn.pressed.connect(_on_contract_row_pressed.bind(e_id))
				node = row_btn
			else:
				var row_lbl := Label.new()
				row_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
				node = row_lbl
			target_vbox.add_child(node)
			contract_panels[e_id] = {"node": node, "has_pos": has_pos}

		var refs: Dictionary = contract_panels[e_id]
		var row = refs["node"] # Button or Label -- untyped so .text below resolves dynamically
		target_vbox.move_child(row, target_vbox.get_child_count() - 1)

		if row is Button:
			row.text = label_text
			row.modulate = Color(1.0, 0.9, 0.4) if e_id == selected_contract_id else Color(1.0, 1.0, 1.0)
		else:
			row.text = label_text
			row.modulate = Color(0.65, 0.65, 0.65) # dimmer -- reads as "listed, not focusable"

func _on_contract_row_pressed(e_id: String) -> void:
	if selected_contract_id == e_id:
		selected_contract_id = ""
	else:
		selected_contract_id = e_id

func _draw() -> void:
	pass
