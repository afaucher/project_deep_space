extends Control

const UIStyle = preload("res://scripts/ui/ui_style.gd")

# M48 -- Standings & flags (IFF v2): row color prefers standing over raw
# classification for vessels. Referenced via preload const, never bare
# class_name. (Standing/Hail preloads removed with the action buttons --
# row colors key on the literal standing strings in _STANDING_COLORS below.
# The standing text readout + MARK HOSTILE/UNMARK buttons moved to the
# weapons panel's targeting-computer section; the DEMAND ID/STOP action
# row lives in comms_panel.gd. M52d removed the RELEASE verb entirely.)

signal contact_pin_toggled(c_id: String, is_pinned: bool)
signal selection_changed(c_id: String)

# Row colours and the SOS colour used to live here as local consts, each with
# a comment explaining that the other modules' colours were "not ours to
# touch". That politeness is precisely how three surfaces ended up with three
# different rules (playtest A2): this panel's precedence was correct, while the
# nav map and helm dial keyed off classification alone and drew every neutral
# station red. Both tables now live in utils.gd behind Utils.contact_color, and
# every surface reads that one function.

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
		
		# Cycle order follows the DISPLAYED section order, so tabbing walks the
		# list the way it looks. This block used to carry its own third copy of
		# the classification bucketing rule -- which meant tabbing treated
		# every neutral station as an enemy even after the visible list stopped
		# doing so. Same table now (Utils.CONTACT_SECTIONS / contact_section).
		var by_section: Dictionary = {}
		for s_name in Utils.CONTACT_SECTIONS:
			by_section[s_name] = []
		for c_id in contacts.keys():
			var c = contacts[c_id]
			var dist = pos.distance_to(c.get("pos", Vector2.ZERO))
			var s_name: String = Utils.contact_section(c)
			if by_section.has(s_name):
				by_section[s_name].append({"id": c_id, "dist": dist})

		var contact_list = []
		for s_name in Utils.CONTACT_SECTIONS:
			var bucket: Array = by_section[s_name]
			bucket.sort_custom(func(a, b): return a["dist"] < b["dist"])
			for x in bucket:
				contact_list.append(x["id"])
			
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
	
	main_vbox.add_child(UIStyle.panel_title("TACTICAL CONTACTS", UIStyle.ACCENT_CONTACTS))
	
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
	# Contact sections and their order come from Utils.CONTACT_SECTIONS, which
	# is the SAME table that decides row colour (Utils.contact_section /
	# contact_color both derive from Utils.contact_tier). Keeping a parallel
	# list here is what let the old bucketing rule drift away from the colour
	# rule in the first place -- playtest A2.
	#
	# "Contracts" is appended locally and deliberately: it holds contract-feed
	# entries, not contacts, so it has no tier and belongs to this panel alone.
	var sections: Array = Utils.CONTACT_SECTIONS.duplicate()
	sections.append("Contracts")
	# UIStyle.list_section owns the fold affordance and the "(+)/(-)" marker --
	# a section holding an unbounded list folds, one holding a fixed readout
	# does not (design_ideas/2026-07-27-ui_style_guide.md §2.1). The comms
	# panel's HAILS/CONTRACTS/LOCAL CONTACTS use the same helper.
	for s_name in sections:
		var sec: Dictionary = UIStyle.list_section(s_name, UIStyle.ACCENT_CONTACTS)
		content_vbox.add_child(sec["button"])
		content_vbox.add_child(sec["content"])
		section_vboxes[s_name] = sec["content"]
		section_buttons[s_name] = sec["button"]

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
	# (my_rot / ship_components were only ever read to build a fake signature for
	# the per-row emissions estimate; that moved to the targeting computer.)


	# Bucketed by Utils.contact_section -- the SAME function that parents each
	# row below and that drives the tab-cycle order. This block used to bucket
	# on classification alone, which meant the A2 contradiction survived inside
	# the file that fixed A2: a reporting NEUTRAL station's ROW filed under
	# "All Contacts" while its COUNT incremented "Enemies", so the panel drew
	# "Enemies (4)" above an empty Enemies section. It also meant "Alerts" --
	# added with the A2 fix -- never got a count at all, on the one section
	# holding CAUTION contacts and distress calls.
	var buckets: Dictionary = {}
	for s_name in Utils.CONTACT_SECTIONS:
		buckets[s_name] = []

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
		
		buckets[Utils.contact_section(c)].append(c)

	# Sorted within each section, then concatenated in display order -- so
	# every section is genuinely distance-ordered. The old concatenation
	# (enemies + ships + others) handed "All Contacts" neutrals-by-distance
	# followed by wreckage-by-distance, i.e. two runs rather than one list.
	var sorted_contacts: Array = []
	for s_name in Utils.CONTACT_SECTIONS:
		var bucket: Array = buckets[s_name]
		bucket.sort_custom(func(a, b): return a["_dist"] < b["_dist"])
		# Counts come from the same buckets that place the rows, so a header
		# can no longer contradict the section under it. Every section in
		# CONTACT_SECTIONS gets one -- including Alerts, which had none.
		UIStyle.set_list_section_title(section_buttons[s_name],
			"%s (%d)" % [s_name, bucket.size()])
		sorted_contacts.append_array(bucket)
	
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
			# One row shape for an entity listed anywhere -- the hails list
			# builds its rows from the same helper. bg/border colour are
			# re-set every update below; this establishes the geometry.
			p_style = UIStyle.row_style(Color.WHITE, false)
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
			info.add_theme_font_size_override("font_size", UIStyle.FONT_DETAIL)
			vbox.add_child(info)

			contact_panels[c_id] = {"panel": panel, "style": p_style, "header": header, "pin_btn": pin_btn, "info": info}

		# Parent to the correct section
		var classification = c.get("classification", "UNKNOWN")
		var target_vbox: VBoxContainer = section_vboxes[Utils.contact_section(c)]
			
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
		# Shared with the hails section (Utils.ROW_BG*) so a ship looks the same
		# in both lists -- playtest C3.
		p_style.bg_color = Utils.ROW_BG_SELECTED if c_id == selected_contact_id else Utils.ROW_BG
			
		# M48 -- standing (an earned, per-observer judgment) takes priority
		# over raw classification for a vessel's row color when present;
		# non-vessels (ordnance/wreckage/asteroids) never carry a standing
		# ("") and fall back to the pre-M48 classification coloring.
		# M52 -- SOS takes priority over BOTH: a friendly ship calling for
		# help is more urgent than its ordinary standing color, and the row
		# should read as unmistakably distinct at a glance (matches the nav
		# map's pulsing-cross treatment for the same event).
		# A2 (2026-07-27): this precedence was already CORRECT and is now the
		# shared rule -- Utils.contact_color -- so the nav map and helm dial
		# inherit it instead of each keying off classification alone. The local
		# tables moved to utils.gd with it.
		var is_sos: bool = c.get("sos", false)
		var color: Color = Utils.contact_color(c)
		p_style.border_color = color
		header.add_theme_color_override("font_color", color)

		var t_name = c.get("transponder_name", "")
		# M52 follow-up (implementation_plans/m52_sos_as_contact.md): an
		# unresolved "DISTRESS CALL" contact (no real transponder/sensor
		# data at all) has no transponder_name to merge -- fall back to the
		# name the distress call itself claimed (sos_name, stamped by
		# ship.gd from the caller's own transponder data at send time)
		# before finally falling back to the bare track id, so the row
		# shows a real name instead of "TRK-xxx" whenever the caller
		# self-identified.
		var sos_name: String = c.get("sos_name", "") if is_sos else ""
		var base_name: String = t_name if t_name != "" else sos_name
		var label: String = Utils.entity_label(c_id, base_name,
			c.get("transponder_flag", ""), classification_str)
		header.text = ("[SOS] " + label) if is_sos else label

		var dist = c["_dist"]
		var vel = c.get("vel", Vector2.ZERO)
		var speed = vel.length()
		var age_s = Ship.contact_age(c, 0.0)

		var their_pos = c.get("pos", Vector2.ZERO)
		var hdg = wrapf(rad_to_deg((their_pos - my_pos).angle()) + 90.0, 0.0, 360.0)

		# "Our Emit" / "Det Limit" used to be here, on EVERY row. Both were raw
		# inputs to a question neither of them asked out loud -- "can this ship
		# see me?" -- and answering it meant comparing two numbers in your head,
		# per contact, continuously. It is now one stated verdict on the ONE
		# contact you are actually working (the targeting computer's
		# counter-detection line, weapons_panel.gd), computed by
		# Utils.counter_detection, which also fixed the quiet-hull case this
		# copy got wrong.
		var sig = c.get("signature", {})
		var sos_line: String = ""
		if is_sos:
			var nature: String = c.get("sos_nature", "")
			sos_line = "\nSOS: %s" % (nature if nature != "" else "distress call")
		info.text = ("Dist: %s | Hdg: %03d | Spd: %.1f m/s | Age: %.1fs\nHeat: %.1f | EM: %.1f\nCS: %.1f | Den: %.1f" + sos_line) % [
			Utils.format_dist(dist), hdg, speed, age_s, sig.get("heat", 0.0), sig.get("em_noise", 0.0), sig.get("cross_section", 1.0), sig.get("density", 0.0)
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
	UIStyle.set_list_section_title(btn, "Contracts (" + str(contracts.size()) + ")")

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
