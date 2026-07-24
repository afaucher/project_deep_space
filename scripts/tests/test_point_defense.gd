extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")

var f_ship
var e_missile
var main_node
var frame: int = 0
var unit_tests_started: bool = false
var missile_scenario_started: bool = false
var missile_scenario_start_frame: int = 0

func setup(main) -> void:
	print("Test test_point_defense initialized.")
	main_node = main

func _physics_process(_delta: float) -> void:
	frame += 1

	if not unit_tests_started:
		if frame < 2: # let the physics server settle before any spatial queries
			return
		unit_tests_started = true
		if not _run_unit_tests(main_node):
			printerr(">>> [TEST FAILED] Point defense unit tests failed.")
			get_tree().quit(1)
			return
		_start_missile_scenario()
		return

	if not missile_scenario_started:
		return

	# A missile is genuinely neutralized in exactly these ways:
	#   - freed / queued for deletion (already gone),
	#   - is_dead (reactor or both hulls destroyed -> vaporize/hulk),
	#   - warhead component destroyed -> dudded: missile_controller.detonate() gates
	#     its damage on warhead health, so a warhead-dead missile expends harmlessly.
	# (Before that detonate() gate existed, warhead_dead did NOT actually stop the
	# missile and this check over-credited PD -- see warhead_laser_special_case.md.)
	var warhead_dead = false
	if is_instance_valid(e_missile):
		for c in e_missile.ship_components:
			if c["id"] == "warhead" and c["health"] <= 0.0:
				warhead_dead = true
				break

	if not is_instance_valid(e_missile) or e_missile.is_queued_for_deletion() or e_missile.is_dead or warhead_dead:
		print(">>> [TEST PASSED] Point defense destroyed or neutralized missile.")
		get_tree().quit(0)

	if is_instance_valid(e_missile) and e_missile.position.distance_to(f_ship.position) < 50:
		print(">>> [TEST FAILED] Missile hit the ship.")
		get_tree().quit(1)

	if frame - missile_scenario_start_frame >= 300:
		print(">>> [TEST FAILED] Timeout. Missile Pos: ", e_missile.position)
		get_tree().quit(1)

func _start_missile_scenario() -> void:
	# Add Friendly Ship
	f_ship = Ship.new()
	f_ship.name = "FriendlyShip"
	f_ship.owner_id = 1
	f_ship.iff_tags = ["TEAM_A"]
	f_ship.position = Vector2(0, 0)
	main_node.add_child(f_ship)
	# Target ship (Hostile)
	e_missile = Missile.new()
	e_missile.name = "Missile_2"
	e_missile.owner_id = 2
	e_missile.iff_tags = ["TEAM_B"]
	e_missile.position = Vector2(0, -800)
	e_missile.rotation = PI / 2.0 # Point DOWN at the friendly ship
	main_node.add_child(e_missile)

	# Set velocity on missile since it's a RigidBody2D
	e_missile.linear_velocity = Vector2(0, 500)

	missile_scenario_start_frame = frame
	missile_scenario_started = true

# ---------- M3 unit tests: target prioritization + weapon-range selection ----------
#
# These call _process_point_defense() directly against a throwaway ship with
# hand-built active_contacts entries instead of running a full sensor+physics
# sim -- deterministic single-tick snapshots of the prioritization logic
# itself, rather than an emergent outcome of a multi-second engagement.

func _assert(condition: bool, msg: String) -> bool:
	if not condition:
		printerr("  ASSERT FAILED: ", msg)
	return condition

func _run_unit_tests(main) -> bool:
	var ok = true
	ok = _test_sort_by_range(main) and ok
	ok = _test_sort_by_shots_fired(main) and ok
	ok = _test_weapon_selection_by_range(main) and ok
	ok = _test_multiple_lasers_concentrate_on_one_target(main) and ok
	return ok

func _make_test_ship(main) -> Node:
	var ship = Ship.new()
	ship.name = "PDUnitTestShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	ship.rotation = 0.0
	main.add_child(ship)
	return ship

func _make_dummy_target(main, pos: Vector2) -> Node2D:
	var dummy = Node2D.new()
	dummy.position = pos
	main.add_child(dummy)
	return dummy

func _add_incoming_contact(ship, c_id: String, body: Node2D, shots_fired: int = 0) -> void:
	ship.active_contacts[c_id] = {
		"pos": body.position,
		"vel": Vector2.ZERO,
		"classification": "INCOMING ORDNANCE",
		"instance_id": body.get_instance_id(),
		"last_seen_at": Engine.get_physics_frames(),
		"pos_timer": 0.0,
		"pd_shots_fired": shots_fired,
	}

# Only hp_fwd_laser's arc covers dead-ahead (heading 0, +/-30deg) on a stock
# Frigate, so both dummy targets below are reachable by exactly one weapon --
# isolating "which target gets the single available shot" from any
# weapon-selection question.
func _test_sort_by_range(main) -> bool:
	var ship = _make_test_ship(main)
	var near = _make_dummy_target(main, Vector2(1000, 0))
	var far = _make_dummy_target(main, Vector2(3000, 0))
	_add_incoming_contact(ship, "near", near)
	_add_incoming_contact(ship, "far", far)

	ship._process_point_defense()

	var ok = _assert(ship.active_contacts["near"]["pd_shots_fired"] == 1,
		"Closer target should be engaged first. near shots=" + str(ship.active_contacts["near"]["pd_shots_fired"]))
	ok = _assert(ship.active_contacts["far"]["pd_shots_fired"] == 0,
		"Farther target shouldn't be engaged this tick while a closer one is unaddressed. far shots=" + str(ship.active_contacts["far"]["pd_shots_fired"])) and ok

	ship.queue_free()
	near.queue_free()
	far.queue_free()
	return ok

func _test_sort_by_shots_fired(main) -> bool:
	var ship = _make_test_ship(main)
	var already_shot = _make_dummy_target(main, Vector2(1000, 0))
	var fresh = _make_dummy_target(main, Vector2(1000, 100)) # slightly farther, but never shot at
	_add_incoming_contact(ship, "already_shot", already_shot, 1)
	_add_incoming_contact(ship, "fresh", fresh, 0)

	ship._process_point_defense()

	var ok = _assert(ship.active_contacts["fresh"]["pd_shots_fired"] == 1,
		"Un-shot target should take priority over an already-engaged one even if slightly farther. fresh shots=" + str(ship.active_contacts["fresh"]["pd_shots_fired"]))
	ok = _assert(ship.active_contacts["already_shot"]["pd_shots_fired"] == 1,
		"Already-engaged target shouldn't get a second shot while a fresh one is waiting. already_shot shots=" + str(ship.active_contacts["already_shot"]["pd_shots_fired"])) and ok

	ship.queue_free()
	already_shot.queue_free()
	fresh.queue_free()
	return ok

# Give a second laser the same forward arc as hp_fwd_laser so both can reach
# either target, then make hp_fwd_laser short-ranged. The closer target
# should get the short laser, reserving the long-range one for the target
# only it can reach.
func _test_weapon_selection_by_range(main) -> bool:
	var ship = _make_test_ship(main)
	ship.get_component("hp_fwd_laser")["range"] = 1500.0
	ship.get_component("hp_port_laser_1")["heading"] = 0.0
	ship.get_component("hp_port_laser_1")["arc_width"] = PI / 3.0
	ship.get_component("hp_port_laser_1")["range"] = 4000.0

	var near = _make_dummy_target(main, Vector2(1000, 0)) # in range of both
	var far = _make_dummy_target(main, Vector2(3000, 0))  # only the long-range one can reach
	_add_incoming_contact(ship, "near", near)
	_add_incoming_contact(ship, "far", far)

	ship._process_point_defense()

	var ok = _assert(ship.get_component("hp_fwd_laser")["cooldown"] > 0.0,
		"Short-range laser should fire on the target in range of both.")
	ok = _assert(ship.get_component("hp_port_laser_1")["cooldown"] > 0.0,
		"Long-range laser should fire on the target only it can reach.") and ok

	ship.queue_free()
	near.queue_free()
	far.queue_free()
	return ok

# Regression test for the single-missile PD-effectiveness bug: with only one
# target and multiple ready lasers, the per-target assignment loop used to
# stop after handing the target its one highest-priority laser, leaving any
# remaining ready lasers idle for the tick even though nothing else needed
# them. All ready lasers that can reach the lone target should fire on it.
func _test_multiple_lasers_concentrate_on_one_target(main) -> bool:
	var ship = _make_test_ship(main)
	ship.get_component("hp_port_laser_1")["heading"] = 0.0
	ship.get_component("hp_port_laser_1")["arc_width"] = PI / 3.0

	var lone = _make_dummy_target(main, Vector2(1000, 0))
	_add_incoming_contact(ship, "lone", lone)

	ship._process_point_defense()

	var ok = _assert(ship.get_component("hp_fwd_laser")["cooldown"] > 0.0,
		"hp_fwd_laser should fire on the lone target.")
	ok = _assert(ship.get_component("hp_port_laser_1")["cooldown"] > 0.0,
		"hp_port_laser_1 should ALSO fire on the lone target instead of sitting idle.") and ok
	ok = _assert(ship.active_contacts["lone"]["pd_shots_fired"] == 2,
		"Lone target should take a shot from every reachable ready laser this tick. shots=" + str(ship.active_contacts["lone"]["pd_shots_fired"])) and ok

	ship.queue_free()
	lone.queue_free()
	return ok
