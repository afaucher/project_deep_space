extends Node

# M52d -- comms panel HAILS restructure (implementation_plans/m52d_hail_ux.md
# item 4): ONE vessel-grouped list. Widget-level test in the
# test_controls_menu_ui.gd / test_weapons_panel_standing.gd style: instantiate
# the real Control, feed it fixture packets, assert on the entry nodes and
# banner it actually built. build_vessel_entries() is pure over packet data,
# so the grouping/qualification rules are asserted directly too.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_comms_panel_hails

const CommsPanel = preload("res://scripts/ui/comms_panel.gd")
const Hail = preload("res://scripts/comms/hail.gd")

const MY_IID := 111

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _fixture_contacts() -> Dictionary:
	return {
		"TRK-001": {"instance_id": 201, "classification": "FRIENDLY VESSEL",
			"pos": Vector2(1000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0},
		"TRK-002": {"instance_id": 202, "classification": "UNIDENTIFIED VESSEL",
			"pos": Vector2(2000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0,
			"complied_stop": true},
		# A tracked STRUCTURE-ish contact that never hailed and isn't
		# selected -- must NOT appear in the list.
		"TRK-009": {"instance_id": 209, "classification": "STATION",
			"pos": Vector2(9000, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0},
	}

func _fixture_transponders() -> Dictionary:
	return {
		201: {"name": "Hauler Joe", "flag": "FEDERATION", "npcs": []},
		202: {"name": "Rust Bucket", "flag": "JOLLY_ROGER", "npcs": []},
	}

func _fixture_last_hails() -> Array:
	return [
		# Directed at us -- qualifies TRK-002.
		{"verb": Hail.VERB_DEMAND, "rung": Hail.RUNG_STOP, "seq": 5,
			"sender_iid": 202, "target_iid": MY_IID, "sender_flag": "JOLLY_ROGER"},
		# Overheard (addressed to someone else) -- must NOT create an entry.
		{"verb": Hail.VERB_DEMAND, "rung": Hail.RUNG_STOP, "seq": 6,
			"sender_iid": 204, "target_iid": 999, "sender_flag": ""},
	]

func _fixture_sent_hails() -> Array:
	# We hailed a vessel we hold NO contact record for (iid 203) -- it still
	# gets an entry (tracking what we sent), with actions disabled.
	return [{"verb": Hail.VERB_DEMAND, "rung": Hail.RUNG_IDENTIFY, "target_iid": 203, "seq": 4}]

func _packet(overrides: Dictionary = {}) -> Dictionary:
	var p := {
		"contacts": _fixture_contacts(),
		"transponders": _fixture_transponders(),
		"last_hails": _fixture_last_hails(),
		"sent_hails": _fixture_sent_hails(),
		"pending_demand": {},
		"compelled_stop": {},
	}
	for k in overrides:
		p[k] = overrides[k]
	return p

func setup(main) -> void:
	print("=== test_comms_panel_hails: vessel grouping, headers, actions, banner ===")

	var panel = CommsPanel.new()
	panel.my_iid_override = MY_IID
	main.add_child(panel)

	_test_builder_rules(panel)
	_test_rendered_entries(panel)
	_test_banner_states(panel)

	if failures.is_empty():
		print(">>> [TEST PASSED] test_comms_panel_hails <<<")
		get_tree().quit(0)
	else:
		for msg in failures:
			printerr("  ASSERT FAILED: ", msg)
		printerr(">>> [TEST FAILED] test_comms_panel_hails <<<")
		get_tree().quit(1)

# --- The pure builder: qualification, identity, ordering, traffic ------------
func _test_builder_rules(panel) -> void:
	print("\n--- build_vessel_entries: grouping and qualification rules ---")
	var entries: Array = panel.build_vessel_entries(
		_fixture_contacts(), _fixture_transponders(),
		_fixture_last_hails(), _fixture_sent_hails(), "TRK-001", MY_IID)

	_assert(entries.size() == 3, "exactly 3 entries (selected + hailed-us + we-hailed), got %d" % entries.size())

	var ids: Array = entries.map(func(e): return e["c_id"])
	_assert(not ids.has("TRK-009"), "an unselected, silent contact is NOT listed")
	_assert(not ids.has("TRK-204"), "an overheard hail (addressed to someone else) creates NO entry")

	_assert(entries[0]["c_id"] == "TRK-001" and entries[0]["selected"], "selected vessel sorts first")
	_assert(ids.has("TRK-002"), "a vessel that hailed us is listed")
	_assert(ids.has("TRK-203"), "a vessel we hailed is listed under its derived track id")

	for e in entries:
		match e["c_id"]:
			"TRK-001":
				_assert(panel.entry_header_text(e) == "TRK-001 \"Hauler Joe\" — FEDERATION",
					"selected header: track + name + flag, got '%s'" % panel.entry_header_text(e))
				_assert(e["traffic"].is_empty(), "selected-only vessel has no traffic lines")
			"TRK-002":
				_assert(panel.entry_header_text(e) == "TRK-002 \"Rust Bucket\" — JOLLY_ROGER",
					"hailer header: track + name + flag, got '%s'" % panel.entry_header_text(e))
				_assert(e["traffic"] == ["< DEMAND(STOP)"],
					"their demand shows as inbound traffic, got %s" % str(e["traffic"]))
				_assert(e["known_contact"], "tracked vessel -> actions enabled")
			"TRK-203":
				_assert(panel.entry_header_text(e) == "TRK-203 — dark",
					"no-transponder header reads dark, got '%s'" % panel.entry_header_text(e))
				_assert(e["traffic"] == ["> DEMAND(IDENTIFY)"],
					"our sent demand shows as outbound traffic, got %s" % str(e["traffic"]))
				_assert(not e["known_contact"], "hail-only vessel (no track) -> actions disabled")

# --- The rendered widget: entry nodes, button state, no [TO YOU] -------------
func _test_rendered_entries(panel) -> void:
	print("\n--- rendered list: entry nodes, buttons, casing ---")
	panel.set_selected_contact_id("TRK-001")
	panel.update_data(_packet())

	_assert(panel._entry_nodes.size() == 3, "3 entry node groups rendered, got %d" % panel._entry_nodes.size())
	_assert(panel._entry_nodes.has("TRK-001") and panel._entry_nodes.has("TRK-002") and panel._entry_nodes.has("TRK-203"),
		"entries keyed by track id")

	if panel._entry_nodes.has("TRK-002"):
		var n2: Dictionary = panel._entry_nodes["TRK-002"]
		_assert(n2["header"].text == "TRK-002 \"Rust Bucket\" — JOLLY_ROGER", "rendered header matches builder")
		_assert(not n2["header"].text.contains("[TO YOU]"), "no [TO YOU] tag anywhere")
		_assert(n2["buttons"]["demand_id"].text == "DEMAND ID" and n2["buttons"]["demand_stop"].text == "DEMAND STOP",
			"action buttons use consistent casing")
		_assert(not n2["buttons"]["demand_stop"].disabled, "tracked vessel: DEMAND STOP enabled")
		_assert(not n2["buttons"].has("release"), "no RELEASE button anywhere (verb removed entirely, M52d)")
	if panel._entry_nodes.has("TRK-203"):
		_assert(panel._entry_nodes["TRK-203"]["buttons"]["demand_id"].disabled, "untracked vessel: actions disabled")

	# Button press routes the ENTRY's track id (not the selected one).
	var demanded: Array = []
	panel.demand_requested.connect(func(c_id, rung): demanded.append([c_id, rung]))
	panel._entry_nodes["TRK-002"]["buttons"]["demand_stop"].pressed.emit()
	_assert(demanded == [["TRK-002", Hail.RUNG_STOP]],
		"pressing an entry's DEMAND STOP emits for THAT vessel, got %s" % str(demanded))

	# Selection change regroups: nothing selected -> TRK-001 drops out.
	panel.set_selected_contact_id("")
	_assert(not panel._entry_nodes.has("TRK-001"), "deselected: selected-only vessel drops from the list")
	_assert(panel._entry_nodes.has("TRK-002"), "hailer remains listed regardless of selection")

# --- Banner: ACKNOWLEDGE vs STOP (decoupled) vs HELD face -------------------
func _test_banner_states(panel) -> void:
	print("\n--- banner: DEMAND+ACKNOWLEDGE/STOP vs HELD (decoupled, design revised in review) ---")
	_assert(panel.btn_acknowledge.text == "ACKNOWLEDGE", "button text is ACKNOWLEDGE (renamed from COMPLY)")
	_assert(panel.btn_acknowledge.tooltip_text.begins_with("ACKNOWLEDGE — confirm receipt only"),
		"ACKNOWLEDGE's tooltip is explicit that it does NOT stop the ship")
	_assert(panel.btn_stop.text == "STOP", "the STOP button node still exists (engage_dead_stop still used by AI)")

	# STOP is hidden for ALL rungs -- parked pending autopilot/helm design
	# (dead-stop-as-autopilot was decided to belong under helm control, not
	# a standalone comms button; see design_ideas/).
	panel.update_data(_packet({"pending_demand": {"rung": Hail.RUNG_STOP, "seq": 9,
		"sender_iid": 202, "sender_flag": "JOLLY_ROGER", "target_iid": MY_IID}}))
	_assert(panel.hail_banner.visible, "pending STOP demand: banner shows")
	_assert(panel.btn_acknowledge.visible, "pending STOP demand: ACKNOWLEDGE button shows")
	_assert(not panel.btn_stop.visible, "STOP button parked/hidden even for a STOP-rung demand")
	_assert(panel.hail_banner_label.text == "DEMAND(STOP) from flag: JOLLY_ROGER",
		"banner names the demanding flag, got '%s'" % panel.hail_banner_label.text)

	# An IDENTIFY-rung demand shows ONLY ACKNOWLEDGE -- nothing to "stop" for.
	panel.update_data(_packet({"pending_demand": {"rung": Hail.RUNG_IDENTIFY, "seq": 10,
		"sender_iid": 202, "sender_flag": "JOLLY_ROGER", "target_iid": MY_IID}}))
	_assert(panel.hail_banner.visible, "pending IDENTIFY demand: banner shows")
	_assert(panel.btn_acknowledge.visible, "pending IDENTIFY demand: ACKNOWLEDGE button shows (acknowledge is rung-agnostic)")
	_assert(not panel.btn_stop.visible, "pending IDENTIFY demand: no STOP button (nothing to stop for)")
	_assert(panel.hail_banner_label.text == "DEMAND(IDENTIFY) from flag: JOLLY_ROGER",
		"banner names the demand's actual rung, got '%s'" % panel.hail_banner_label.text)

	panel.update_data(_packet({"compelled_stop": {"issuer_iid": 202, "demand_seq": 9, "heartbeat_timer": 0.0}}))
	_assert(panel.hail_banner.visible, "compelled: banner shows the held state")
	_assert(not panel.btn_acknowledge.visible, "compelled: no ACKNOWLEDGE button")
	_assert(not panel.btn_stop.visible, "compelled: no STOP button (already engaged)")
	_assert(panel.hail_banner_label.text == "HELD — stopped for \"Rust Bucket\"",
		"held state names the issuer, got '%s'" % panel.hail_banner_label.text)

	panel.update_data(_packet())
	_assert(not panel.hail_banner.visible, "no demand, no hold: banner hidden")
