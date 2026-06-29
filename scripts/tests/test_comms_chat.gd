extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const NPCProfile = preload("res://scripts/comms/npc_profile.gd")

var main_node: Node
var spawned: Array[Node] = []

const FRAMES_PER_SCENARIO = 30
var scenario_frames: int = 0
var current_scenario_idx: int = -1
const NUM_SCENARIOS = 1

func setup(main) -> void:
	main_node = main
	print("Test test_comms_chat initialized.")
	_start_scenario(0)

func _spawn_ship(ship_name: String, pos: Vector2, tags: Array) -> Node:
	var s = Ship.new()
	s.owner_id = spawned.size() + 1
	s.name = ship_name
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _start_scenario(idx: int) -> void:
	current_scenario_idx = idx
	scenario_frames = 0
	_cleanup()

	match idx:
		0:
			print("\n--- Scenario 1: Ship B broadcasts NPC profile via transponder, Ship A receives it ---")
			var ship_a = _spawn_ship("A", Vector2(0, 0), ["TEAM_A"])
			var ship_b = _spawn_ship("B", Vector2(5000, 0), ["TEAM_B"])
			
			# Inject an NPC to Ship B
			var test_npc = NPCProfile.new()
			test_npc.character_name = "Admiral Test"
			test_npc.faction = "Test Faction"
			test_npc.tier = 0 # PUBLIC
			ship_b.available_npcs.append(test_npc)
		_:
			print("\nAll comms chat scenarios passed!")
			print(">>> [TEST PASSED] test_comms_chat <<<")
			get_tree().quit(0)

func _physics_process(_delta: float) -> void:
	if current_scenario_idx < 0 or current_scenario_idx >= NUM_SCENARIOS: return
	scenario_frames += 1
	if scenario_frames < FRAMES_PER_SCENARIO: return

	var ok = false
	match current_scenario_idx:
		0: ok = _check_scenario_0()

	if not ok:
		print(">>> [TEST FAILED] test_comms_chat <<<")
		get_tree().quit(1)
		return

	_start_scenario(current_scenario_idx + 1)

func _check_scenario_0() -> bool:
	var ship_a = spawned[0]
	var ship_b = spawned[1]
	
	var transponders_a = ship_a.active_transponders
	
	var b_id = ship_b.get_instance_id()
	if not transponders_a.has(b_id):
		printerr("  ASSERT FAILED: Ship A did not receive Ship B's transponder.")
		return false
		
	var b_data = transponders_a[b_id]
	if not b_data.has("npcs"):
		printerr("  ASSERT FAILED: Transponder data does not contain 'npcs' field.")
		return false
		
	var npcs = b_data["npcs"]
	var found = false
	for npc in npcs:
		if npc["name"] == "Admiral Test" and npc["faction"] == "Test Faction":
			found = true
			
	if not found:
		printerr("  ASSERT FAILED: Ship A did not receive Admiral Test via Ship B's transponder.")
		return false

	print("  [PASS] Ship A successfully received Ship B's broadcasted NPCs over transponders.")
	return true
