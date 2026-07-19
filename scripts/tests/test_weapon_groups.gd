extends Node

# M12a: weapon groups & massed fire (capability layer).
# Verifies (1) get_weapon_groups buckets the frigate's hardpoints into fwd/port/stbd by
# mount bearing, (2) fire_group launches every bearing weapon in the group in a SINGLE
# call/tick (the massed volley that saturates PD), and (3) a group that does not bear
# fires nothing. Uses a synthetic injected contact so the test exercises the group API
# directly, independent of the sensor pipeline.
const Frigate = preload("res://scripts/ships/frigate.gd")

func setup(main) -> void:
	print("Test test_weapon_groups initialized.")
	var failures: Array = []

	var ship = Frigate.new()
	ship.name = "GroupShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	ship.rotation = 0.0 # forward +X, +Y starboard, -Y port
	main.add_child(ship)

	# --- 1. Grouping ---
	var groups = ship.get_weapon_groups()
	if groups.get("fwd", []).size() != 2:
		failures.append("fwd group size %d != 2 (%s)" % [groups.get("fwd", []).size(), groups.get("fwd", [])])
	if groups.get("port", []).size() != 5:
		failures.append("port group size %d != 5 (%s)" % [groups.get("port", []).size(), groups.get("port", [])])
	if groups.get("stbd", []).size() != 5:
		failures.append("stbd group size %d != 5 (%s)" % [groups.get("stbd", []).size(), groups.get("stbd", [])])
	if not (groups.get("fwd", []).has("hp_fwd_laser") and groups.get("fwd", []).has("hp_fwd_missile")):
		failures.append("fwd group missing expected forward weapons: %s" % [groups.get("fwd", [])])

	# --- 2. Massed fire: the whole port battery volleys in one call ---
	# Synthetic locked contact to port (-Y), inside the port lasers' 4 km range.
	var port_pos = Vector2(0, -2500)
	ship.active_contacts["TGT_PORT"] = {"pos": port_pos, "vel": Vector2.ZERO}

	var port_ids = groups["port"]
	# Lasers are reactor-powered, not ammo-fed (no "ammo" field at all -- see
	# ship.gd's normalization / weapon_behavior.gd) -- "did it fire" for those
	# is read off cooldown (0 -> cooldown_max the instant it fires) instead of
	# an ammo decrement, same distinction test_fire_staleness_gate.gd draws.
	var before := {}
	for wid in port_ids:
		var w = ship.get_component(wid)
		before[wid] = {"ammo": w.get("ammo", -1), "cooldown": w.get("cooldown", 0.0)}

	var status = ship.get_group_status("port", "TGT_PORT")
	if status["ready"] != 5 or status["total"] != 5:
		failures.append("get_group_status(port) = %s, expected ready 5 / total 5" % [status])

	var fired = ship.fire_group("port", port_pos, "TGT_PORT")
	if fired != 5:
		failures.append("fire_group(port) fired %d, expected 5 (full broadside in one tick)" % fired)

	for wid in port_ids:
		var w = ship.get_component(wid)
		if w.get("weapon_type", "") == "laser":
			if w.get("cooldown", 0.0) <= before[wid]["cooldown"]:
				failures.append("port laser %s cooldown %.2f did not advance (did not fire in volley)" % [wid, w.get("cooldown", 0.0)])
		else:
			var after = w.get("ammo", -1)
			if after != before[wid]["ammo"] - 1:
				failures.append("port weapon %s ammo %d, expected %d (did not fire in volley)" % [wid, after, before[wid]["ammo"] - 1])

	# --- 3. A group that does not bear fires nothing ---
	var fired_stbd = ship.fire_group("stbd", port_pos, "TGT_PORT")
	if fired_stbd != 0:
		failures.append("fire_group(stbd) fired %d at a PORT target, expected 0 (out of arc)" % fired_stbd)

	ship.queue_free()

	if failures.is_empty():
		print("Weapon groups OK: fwd/port/stbd correct; port volley fired 5 in one tick; stbd out-of-arc held fire.")
		print(">>> [TEST PASSED] test_weapon_groups <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  ASSERT FAILED: ", f)
		print(">>> [TEST FAILED] test_weapon_groups <<<")
		get_tree().quit(1)
