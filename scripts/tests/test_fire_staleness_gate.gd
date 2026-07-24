extends Node

# Regression -- AI fire discipline vs stale tracks (Ship.FIRE_STALENESS_MAX,
# 3s). The combat AI never looked at contact age before engaging: acquire_
# target_leaf picked the nearest UNIDENTIFIED VESSEL regardless of staleness
# and fire_opportunity_leaf shot at it, so warships burned lasers and dumped
# full missile volleys at dead-reckoned ghosts coasting toward
# CONTACT_TIMEOUT (and, before the relay echo-lock fix, at permanently
# frozen ones). Now stale tracks are gated at BOTH layers:
#   - acquisition: a track older than FIRE_STALENESS_MAX is never acquired
#   - trigger: a published blackboard target that has gone stale (or
#     vanished) since acquisition is never fired at
#
# Drives the real leaves deterministically (MANUAL-thread tree tick, same
# harness as test_ai_disengage) with hand-injected contacts, reading weapon
# ammo/cooldown scratch fields to detect whether anything actually fired.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_fire_staleness_gate

const Frigate = preload("res://scripts/ships/frigate.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const BeehaveTreeScript = preload("res://addons/beehave/nodes/beehave_tree.gd")
const AcquireTarget = preload("res://scripts/ai/leaves/acquire_target_leaf.gd")
const FireOpportunity = preload("res://scripts/ai/leaves/fire_opportunity_leaf.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _total_ammo(ship) -> int:
	var total := 0
	for w in ship.get_components_by_type("weapons"):
		total += int(w.get("ammo", 0))
	return total

func _lasers_on_cooldown(ship) -> int:
	var n := 0
	for w in ship.get_components_by_type("weapons"):
		if w.get("weapon_type", "") == "laser" and w.get("cooldown", 0.0) > 0.0:
			n += 1
	return n

func _make_ship(main, name: String, owner: int) -> Node:
	var ship = Frigate.new()
	ship.name = name
	ship.owner_id = owner
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	ship.rotation = 0.0
	main.add_child(ship)
	return ship

func setup(main) -> void:
	print("Starting Fire Staleness Gate Tests")

	# --- Scenario 1: a STALE hostile track is never acquired, never fired at ---
	var ship = _make_ship(main, "GateShip", 1)
	var tree = AITreeFactory.build_default()
	tree.process_thread = BeehaveTreeScript.ProcessThread.MANUAL
	ship.add_child(tree)

	# In-range hostile (well inside laser AND missile envelopes), but the
	# track is 4s old -- past FIRE_STALENESS_MAX (3.0).
	ship.active_contacts["TGT_STALE"] = {
		"pos": Vector2(3000, 0), "vel": Vector2.ZERO,
		"classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE",
		# M56: last_seen_at is an absolute frame stamp -- back-date it 4.0s
		# (past FIRE_STALENESS_MAX = 3.0) so Ship.contact_age() reads ~4.0
		# the instant the tree ticks below (no frame advances in between).
		"last_seen_at": Engine.get_physics_frames() - int(4.0 * Engine.physics_ticks_per_second), "pos_timer": 4.0,
	}
	var ammo_before: int = _total_ammo(ship)
	tree.tick()
	_assert(_total_ammo(ship) == ammo_before, "stale track: no missiles expended (ammo unchanged)")
	_assert(_lasers_on_cooldown(ship) == 0, "stale track: no lasers fired (nothing on cooldown)")

	# --- Scenario 2: the SAME contact, fresh, is engaged (the gate must not
	# also starve legitimate combat) ---
	ship.active_contacts["TGT_STALE"]["last_seen_at"] = Engine.get_physics_frames() - int(0.5 * Engine.physics_ticks_per_second)
	tree.tick()
	var fired_fresh: bool = _total_ammo(ship) < ammo_before or _lasers_on_cooldown(ship) > 0
	_assert(fired_fresh, "fresh track: the same contact IS engaged once its age is under the gate")
	ship.queue_free()

	# --- Scenario 3: trigger-side gate -- a target that went stale AFTER
	# acquisition is not fired at, even with a valid published blackboard
	# target. Drives the leaves directly so the blackboard state is exactly
	# "acquired last tick, stale this tick". ---
	var ship3 = _make_ship(main, "TriggerShip", 2)
	var acquire = AcquireTarget.new()
	var fire = FireOpportunity.new()
	var blackboard = load("res://addons/beehave/blackboard.gd").new()

	ship3.active_contacts["TGT_LATE"] = {
		"pos": Vector2(3000, 0), "vel": Vector2.ZERO,
		"classification": "UNIDENTIFIED VESSEL", "standing": "HOSTILE",
		"last_seen_at": Engine.get_physics_frames(), "pos_timer": 0.0,
	}
	var r = acquire.tick(ship3, blackboard)
	_assert(r == acquire.SUCCESS, "trigger-side: fresh contact is acquired")
	_assert(blackboard.get_value("target_id") == "TGT_LATE", "trigger-side: blackboard target published")

	# The track goes stale between acquisition and the trigger pull.
	ship3.active_contacts["TGT_LATE"]["last_seen_at"] = Engine.get_physics_frames() - int(3.5 * Engine.physics_ticks_per_second)
	var ammo3_before: int = _total_ammo(ship3)
	fire.tick(ship3, blackboard)
	_assert(_total_ammo(ship3) == ammo3_before, "trigger-side: stale-since-acquisition target gets no missiles")
	_assert(_lasers_on_cooldown(ship3) == 0, "trigger-side: stale-since-acquisition target gets no lasers")

	# And a vanished track (erased contact) must hold fire too, not error.
	ship3.active_contacts.erase("TGT_LATE")
	fire.tick(ship3, blackboard)
	_assert(_total_ammo(ship3) == ammo3_before, "trigger-side: a vanished track holds fire cleanly")
	ship3.queue_free()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_fire_staleness_gate <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_fire_staleness_gate <<<")
		get_tree().quit(1)
