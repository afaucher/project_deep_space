extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var main_node: Node = null
var current_scenario_idx: int = -1
var scenario_frames: int = 0
# Relay only needs 1-2 physics ticks to propagate; this is a generous margin
# so cross-node processing order within a frame can never make this flaky.
const FRAMES_PER_SCENARIO := 90
const NUM_SCENARIOS := 7

var spawned: Array = []
# Logical-name -> Node, populated per scenario. Deliberately NOT looked up by
# Godot's own .name property: queue_free() defers actual removal, so a
# same-named node from the previous scenario can still occupy that name when
# the next scenario spawns, silently renaming the new one and breaking any
# lookup-by-.name.
var ships: Dictionary = {}

func setup(main) -> void:
	main_node = main
	print("Test test_comms_relay initialized.")
	_start_scenario(0)

func _spawn_ship(ship_name: String, pos: Vector2, tags: Array, strip_sensors: bool = false) -> Node:
	var s = Ship.new()
	s.owner_id = spawned.size() + 1
	s.name = ship_name
	s.iff_tags = tags
	s.position = pos
	if strip_sensors:
		s.ship_components = s.ship_components.filter(func(c): return c["type"] != "sensors")
	main_node.add_child(s)
	spawned.append(s)
	ships[ship_name] = s
	return s

func _set_comms_health(ship: Node, health: float) -> void:
	for c in ship.ship_components:
		if c["type"] == "comms":
			c["health"] = health

func _set_comms_powered(ship: Node, powered_on: bool) -> void:
	for c in ship.ship_components:
		if c["type"] == "comms":
			c["powered_on"] = powered_on

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	ships.clear()

func _start_scenario(idx: int) -> void:
	current_scenario_idx = idx
	scenario_frames = 0
	_cleanup()

	match idx:
		0:
			print("\n--- Scenario 1: relay shares a third contact + self-report between linked friendlies ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(10000, 0), ["TEAM_A"], true) # no sensors -- anything B knows must come via relay
			_spawn_ship("E", Vector2(2000, 3000), ["TEAM_B"]) # within A's sensors, off the A-B line so it can't block that link's own LOS check
		1:
			print("\n--- Scenario 2: blocked line-of-sight prevents relay ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(10000, 0), ["TEAM_A"], true)
			var rock = Asteroid.new()
			rock.name = "BlockingRock"
			rock.position = Vector2(5000, 0) # sits directly on the A-B line
			main_node.add_child(rock)
			spawned.append(rock)
		2:
			print("\n--- Scenario 3: non-friendly ships never link ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			# strip_sensors so C's only possible source of a contact on A is the
			# relay -- otherwise C's own sensors would directly detect A (as
			# UNIDENTIFIED, same as a hostile contact normally would) regardless
			# of whether the relay link itself is correctly gated.
			_spawn_ship("C", Vector2(10000, 0), ["TEAM_C"], true) # in range + clear LOS, but not friendly
		3:
			print("\n--- Scenario 4: destroyed comms on the receiving ship blocks the link ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(10000, 0), ["TEAM_A"], true)
			_set_comms_health(ships["B"], 0.0) # A's comms is fine, LOS/range are clear -- only B's equipment is dead
		4:
			print("\n--- Scenario 5: powered-off comms on the sending ship blocks the link ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(10000, 0), ["TEAM_A"], true)
			_set_comms_powered(ships["A"], false) # B's comms is fine and powered -- A just isn't transmitting
		5:
			print("\n--- Scenario 6: out-of-radio-range friendly ships never link ---")
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(40000, 0), ["TEAM_A"], true) # beyond comms_array's 30000 range, clear LOS, comms otherwise fully functional
		6:
			print("\n--- Scenario 7: multi-hop relay through an intermediate ship ---")
			# A-C (45000) exceeds comms range (30000) and every sensor range, so
			# C can only learn about A by relaying through B.
			_spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			_spawn_ship("B", Vector2(20000, 0), ["TEAM_A"], true)
			_spawn_ship("C", Vector2(45000, 0), ["TEAM_A"], true)
		_:
			print("\nAll comms relay scenarios passed!")
			print(">>> [TEST PASSED] test_comms_relay <<<")
			get_tree().quit(0)

func _physics_process(_delta: float) -> void:
	if current_scenario_idx < 0 or current_scenario_idx >= NUM_SCENARIOS: return
	scenario_frames += 1
	if scenario_frames < FRAMES_PER_SCENARIO: return

	var ok = false
	match current_scenario_idx:
		0: ok = _check_scenario_0()
		1: ok = _check_scenario_1()
		2: ok = _check_scenario_2()
		3: ok = _check_scenario_3()
		4: ok = _check_scenario_4()
		5: ok = _check_scenario_5()
		6: ok = _check_scenario_6()

	if not ok:
		print(">>> [TEST FAILED] test_comms_relay <<<")
		get_tree().quit(1)
		return

	_start_scenario(current_scenario_idx + 1)

# Mirrors the TRK-%03d instance_id scheme ship.gd uses for both direct sensor
# detections and relayed self-reports, so this predicts the same key either
# mechanism would use for `target`.
func _contact_for(ship: Node, target: Node) -> Dictionary:
	var target_id = "TRK-%03d" % (abs(target.get_instance_id()) % 1000)
	return ship.active_contacts.get(target_id, {})

func _check_scenario_0() -> bool:
	var a = ships["A"]
	var b = ships["B"]
	var e = ships["E"]

	var relayed_e = _contact_for(b, e)
	if relayed_e.is_empty():
		printerr("  ASSERT FAILED: B never received A's relayed detection of E.")
		return false
	if relayed_e["pos"].distance_to(e.position) > 500.0:
		printerr("  ASSERT FAILED: relayed contact for E has the wrong position: ", relayed_e["pos"])
		return false
	# Negative pair: E is on a different team and shouldn't read as friendly.
	if relayed_e["classification"] == "FRIENDLY VESSEL":
		printerr("  ASSERT FAILED: E (non-friendly) was relayed in as FRIENDLY VESSEL.")
		return false

	var self_report_a = _contact_for(b, a)
	if self_report_a.is_empty():
		printerr("  ASSERT FAILED: B never received A's self-report over comms.")
		return false
	if self_report_a["classification"] != "FRIENDLY VESSEL":
		printerr("  ASSERT FAILED: A's self-report classified as ", self_report_a["classification"], " not FRIENDLY VESSEL.")
		return false
	if self_report_a["pos"].distance_to(a.position) > 10.0:
		printerr("  ASSERT FAILED: A's self-reported position is wrong: ", self_report_a["pos"])
		return false

	print("  [PASS] B received both A's relayed detection of E and A's own self-report, correctly classified.")
	return true

func _check_scenario_1() -> bool:
	var a = ships["A"]
	var b = ships["B"]
	if not _contact_for(b, a).is_empty():
		printerr("  ASSERT FAILED: B received A's self-report despite a blocking asteroid between them.")
		return false
	print("  [PASS] Blocked line-of-sight correctly prevented the relay link.")
	return true

func _check_scenario_2() -> bool:
	var a = ships["A"]
	var c = ships["C"]
	if not _contact_for(c, a).is_empty():
		printerr("  ASSERT FAILED: C (non-friendly) received A's self-report -- relay should be IFF-gated.")
		return false
	print("  [PASS] Non-friendly ships correctly never linked.")
	return true

func _check_scenario_3() -> bool:
	var a = ships["A"]
	var b = ships["B"]
	if not _contact_for(b, a).is_empty():
		printerr("  ASSERT FAILED: B received A's self-report despite B's own comms array being destroyed.")
		return false
	print("  [PASS] Destroyed comms on the receiving ship correctly blocked the link.")
	return true

func _check_scenario_4() -> bool:
	var a = ships["A"]
	var b = ships["B"]
	if not _contact_for(b, a).is_empty():
		printerr("  ASSERT FAILED: B received A's self-report despite A's comms array being powered off.")
		return false
	print("  [PASS] Powered-off comms on the sending ship correctly blocked the link.")
	return true

func _check_scenario_5() -> bool:
	var a = ships["A"]
	var b = ships["B"]
	if not _contact_for(b, a).is_empty():
		printerr("  ASSERT FAILED: B received A's self-report despite being out of comms range.")
		return false
	print("  [PASS] Out-of-range friendly ships correctly never linked.")
	return true

func _check_scenario_6() -> bool:
	var a = ships["A"]
	var c = ships["C"]
	var relayed_a = _contact_for(c, a)
	if relayed_a.is_empty():
		printerr("  ASSERT FAILED: C never received A's self-report through the B relay (multi-hop).")
		return false
	if relayed_a["pos"].distance_to(a.position) > 500.0:
		printerr("  ASSERT FAILED: multi-hop relayed position for A is wrong: ", relayed_a["pos"])
		return false
	print("  [PASS] Multi-hop relay (A -> B -> C) correctly delivered A's self-report to C.")
	return true
