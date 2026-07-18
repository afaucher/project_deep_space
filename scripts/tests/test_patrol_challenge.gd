extends Node

# M49 -- patrol DEMAND(IDENTIFY) flow (design_ideas/comms_verbs.md's
# "Patrol" policy, challenge_leaf.gd). A dark (non-reporting) vessel contact
# inside a station's controlled space gets challenged; relighting its
# transponder within the ~20s window resolves the challenge quietly and the
# contact reads NEUTRAL; a dark contact OUTSIDE any zone is never challenged
# at all. No standing change from the challenge itself (IDENTIFY is never
# coercion, per comms_verbs.md's "one rule that keys on the rung"), and no
# shooting (an UNREPORTED contact was never a valid Engage target anyway).
#
# `await get_tree().physics_frame` live-ship style, same as test_drift_
# residents.gd/test_honored_stop.gd -- settle loops with generous timeouts,
# never exact frames (Godot 2D physics/timing isn't bit-deterministic
# run-to-run, CLAUDE.md).
#
# The "station" here is a plain Ship with port_zone hand-set directly (a
# lighter stand-in than a full MediumStation -- challenge_leaf's controlled-
# space gate only calls get_port_zone()/reads .position, both of which any
# Ship provides; the milestone doesn't need the docking-bay machinery a real
# station hull drags in).

const Frigate = preload("res://scripts/ships/frigate.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Hail = preload("res://scripts/comms/hail.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var ship = Frigate.new()
	ship.name = ship_name
	ship.owner_id = owner
	ship.iff_tags = tags
	ship.position = pos
	main_node.add_child(ship)
	spawned.append(ship)
	return ship

func _find_contact(observer, target: Node) -> Dictionary:
	var tid: int = target.get_instance_id()
	for c_id in observer.active_contacts:
		var c: Dictionary = observer.active_contacts[c_id]
		if c.get("instance_id", -1) == tid:
			return c
	return {}

func setup(main) -> void:
	main_node = main
	print("Starting Patrol Challenge (M49) Tests")

	# A zone-declaring stand-in "station" (see header) -- radius 8000, centered
	# at the origin.
	var station = _make_ship("Station", 600, Vector2.ZERO, ["TEAM_CONTROL"])
	station.port_zone = {"radius": 8000.0, "authority": "TestControl"}

	var patrol = _make_ship("Patrol", 601, Vector2(3000, 2000), ["TEAM_PATROL"])
	var patrol_tree: Node = AITreeFactory.build_patrol()
	patrol.add_child(patrol_tree)

	# Dark (transponder off), well INSIDE the station's 8000u zone.
	var dark_ship = _make_ship("DarkInZone", 602, Vector2(3000, 0), ["TEAM_DARK"])
	dark_ship.set_transponder_active(false)

	# Dark, but OUTSIDE any zone (>8000 from the station, still in the
	# patrol's sensor + comms range) -- must never be challenged.
	var outside_ship = _make_ship("DarkOutsideZone", 603, Vector2(20000, 2000), ["TEAM_DARK2"])
	outside_ship.set_transponder_active(false)

	var ammo_before: int = 0
	for w in patrol.get_components_by_type("weapons"):
		ammo_before += int(w.get("ammo", 0))

	# --- Phase 1: the in-zone dark ship gets DEMAND(IDENTIFY) within a few
	# seconds; no standing change; no shooting. ---
	var challenged := false
	for i in range(600): # up to 10s (30-tick scan gate + sensor correlation)
		await main_node.get_tree().physics_frame
		if dark_ship.pending_demand.get("rung", "") == Hail.RUNG_IDENTIFY and dark_ship.pending_demand.get("sender_iid", -1) == patrol.get_instance_id():
			challenged = true
			break
	_assert(challenged, "in-zone dark contact gets a DEMAND(IDENTIFY) from the patrol within the timeout (pending_demand=%s)" % str(dark_ship.pending_demand))

	var patrol_view: Dictionary = _find_contact(patrol, dark_ship)
	_assert(patrol_view.get("standing", "") == Standing.UNREPORTED,
		"IDENTIFY never changes standing -- patrol still reads the dark ship as UNREPORTED (got '%s')" % patrol_view.get("standing", ""))

	var ammo_after: int = 0
	for w in patrol.get_components_by_type("weapons"):
		ammo_after += int(w.get("ammo", 0))
	_assert(ammo_after == ammo_before, "patrol never fired on the challenged contact (ammo unchanged)")

	# --- Phase 2: relight within the window -> resolved, reads NEUTRAL. ---
	dark_ship.set_transponder_active(true)

	var resolved := false
	var reads_neutral := false
	for i in range(300): # up to 5s
		await main_node.get_tree().physics_frame
		var bb = patrol_tree.blackboard
		if bb.get_value("challenge_resolved", {}).has(_trk_for(dark_ship)):
			resolved = true
		var pv: Dictionary = _find_contact(patrol, dark_ship)
		if pv.get("standing", "") == Standing.NEUTRAL:
			reads_neutral = true
		if resolved and reads_neutral:
			break
	_assert(resolved, "relighting within the window marks the challenge resolved on the patrol's own blackboard")
	_assert(reads_neutral, "the relit contact reads NEUTRAL to the patrol")

	# --- Phase 3: a dark ship outside any zone is never challenged. ---
	var never_challenged: bool = outside_ship.pending_demand.is_empty()
	var bb_final = patrol_tree.blackboard
	var outside_trk: String = _trk_for(outside_ship)
	var was_tracked_as_challenge: bool = (bb_final.get_value("challenged", {}).has(outside_trk)
		or bb_final.get_value("challenge_resolved", {}).has(outside_trk)
		or bb_final.get_value("challenge_ignored", {}).has(outside_trk))
	_assert(never_challenged and not was_tracked_as_challenge,
		"a dark contact outside any controlled zone is never challenged (pending_demand=%s, tracked_by_challenge=%s)" % [str(outside_ship.pending_demand), was_tracked_as_challenge])

	_finish()

func _trk_for(ship: Node) -> String:
	return "TRK-%03d" % (abs(ship.get_instance_id()) % 1000)

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_patrol_challenge <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_patrol_challenge <<<")
		get_tree().quit(1)
