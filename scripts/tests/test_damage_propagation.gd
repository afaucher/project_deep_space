extends Node

const Ship = preload("res://scripts/ships/frigate.gd")

var ship: Ship
var frames: int = 0
var test_frame_start: int = 0

var tests = []
var current_test: int = -1
var passed: int = 0
var failed: int = 0
var total: int = 0

func setup(main_node: Node) -> void:
	print("Starting Test: Damage Propagation")
	
	ship = Ship.new()
	ship.name = "TestShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	main_node.add_child(ship)
	
	_register_tests()
	total = tests.size()
	_start_next_test()

func _reset_ship() -> void:
	ship.position = Vector2.ZERO
	ship.linear_velocity = Vector2.ZERO
	ship.rotation = 0.0
	ship.angular_velocity = 0.0
	
	for c in ship.ship_components:
		c["health"] = c.get("max_health", 100.0)
	
	ship.subsystems["reactor"]["power"] = 1.0
	ship.actual_throttle = 0.0
	ship.is_dead = false

func _assert(condition: bool, msg: String) -> bool:
	if not condition:
		printerr("    FAILED: ", msg)
		return false
	return true

func _register_tests() -> void:
	tests.append({
		"name": "Fallback Hull Damage",
		"setup": func():
			_reset_ship()
			# take_damage without pos/dir falls back to hull
			ship.take_damage(50.0),
		"check": func():
			# Find the first hull component
			var hull_hp = 1000.0
			for c in ship.ship_components:
				if c["type"] == "hull":
					hull_hp = c["health"]
					break
			return _assert(hull_hp < 1000.0, "Hull should have taken fallback damage")
	})
	
	tests.append({
		"name": "Directional Hit (Fwd Sensor)",
		"setup": func():
			_reset_ship()
			# Shoot ship from directly in front
			var hit_pos = ship.position + Vector2(100.0, 0.0)
			var hit_dir = Vector2(-1.0, 0.0) # hitting nose
			ship.take_damage(100.0, hit_pos, hit_dir, "laser"),
		"check": func():
			var fwd_sensor_hp = 50.0
			for c in ship.ship_components:
				if c["id"] == "hp_sensor_fwd":
					fwd_sensor_hp = c["health"]
					break
			return _assert(fwd_sensor_hp < 50.0, "Forward sensor should take damage when hit from front. HP=" + str(fwd_sensor_hp))
	})
	
	tests.append({
		"name": "Directional Hit (Aft Engine)",
		"setup": func():
			_reset_ship()
			# Shoot ship from directly behind
			var hit_pos = ship.position + Vector2(-100.0, 0.0)
			var hit_dir = Vector2(1.0, 0.0) # hitting tail
			ship.take_damage(100.0, hit_pos, hit_dir, "laser"),
		"check": func():
			var engine_hp = 300.0
			for c in ship.ship_components:
				if c["id"] == "engine_main":
					engine_hp = c["health"]
					break
			return _assert(engine_hp < 300.0, "Engine should take damage when hit from behind. HP=" + str(engine_hp))
	})

func _start_next_test() -> void:
	current_test += 1
	if current_test >= tests.size():
		_finish()
		return
	var t = tests[current_test]
	print("[", current_test + 1, "/", total, "] ", t["name"])
	t["setup"].call()
	test_frame_start = frames

func _physics_process(_delta: float) -> void:
	frames += 1
	if current_test < 0 or current_test >= tests.size():
		return

	var t = tests[current_test]
	var duration = t.get("duration", 2)
	var elapsed = frames - test_frame_start
	if elapsed >= duration:
		var result = t["check"].call()
		if result:
			print("  PASS")
			passed += 1
		else:
			print("  FAIL")
			failed += 1
		_start_next_test()

func _finish() -> void:
	print("")
	print("==========================================")
	print("Damage Propagation Tests: ", passed, " passed, ", failed, " failed out of ", total)
	print("==========================================")
	if failed > 0:
		printerr(">>> [TEST FAILED] test_damage_propagation <<<")
		get_tree().quit(1)
	else:
		print(">>> [TEST PASSED] test_damage_propagation <<<")
		get_tree().quit(0)
