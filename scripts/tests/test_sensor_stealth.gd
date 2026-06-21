extends Node

const Ship = preload("res://scripts/ship.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var ship_a: Ship
var ship_b: Ship
var asteroid: Asteroid

var main_scene: Node
var frames: int = 0
var test_frame_start: int = 0

var tests = []
var current_test: int = -1
var passed: int = 0
var failed: int = 0
var total: int = 0

func setup(main_node: Node) -> void:
	print("Starting Test: Sensor Stealth & Occlusion")
	main_scene = main_node
	_register_tests()
	total = tests.size()
	_start_next_test()

func _reset_scene() -> void:
	if is_instance_valid(ship_a): ship_a.queue_free()
	if is_instance_valid(ship_b): ship_b.queue_free()
	if is_instance_valid(asteroid): asteroid.queue_free()
	
	ship_a = Ship.new()
	ship_a.name = "ShipA_Observer"
	ship_a.owner_id = 1
	ship_a.iff_tags = ["TEAM_A"]
	ship_a.position = Vector2(-2000, 0)
	ship_a.rotation = 0.0
	main_scene.add_child(ship_a)
	
	ship_b = Ship.new()
	ship_b.name = "ShipB_Target"
	ship_b.owner_id = 2
	ship_b.iff_tags = ["TEAM_B"]
	ship_b.position = Vector2(2000, 0)
	ship_b.rotation = PI
	main_scene.add_child(ship_b)
	
	asteroid = Asteroid.new()
	asteroid.name = "TestAsteroid"
	asteroid.position = Vector2(0, 10000)
	main_scene.add_child(asteroid)
	
	# Ensure active sensors are scanning and timers reset
	for s in ship_a.sensor_hardware:
		s["timer"] = 0.0 # Force immediate sweep
		if s["type"] == "active":
			s["active"] = true
			s["range"] = 15000.0 # Make sure they can see far enough

func _assert(condition: bool, msg: String) -> bool:
	if not condition:
		printerr("    FAILED: ", msg)
		return false
	return true

func _register_tests() -> void:
	tests.append({
		"name": "Line of Sight Clear (Baseline)",
		"setup": func():
			_reset_scene(),
		"check": func():
			var has_sweep_hit = false
			for arr in ship_a.active_sensor_sweeps.values():
				for hit in arr:
					if hit.get("instance_id") == ship_b.get_instance_id():
						has_sweep_hit = true
			return _assert(has_sweep_hit, "Ship A should see Ship B with clear line of sight.")
	})
	
	tests.append({
		"name": "Asteroid Occlusion (Active Radar Blocked)",
		"setup": func():
			_reset_scene()
			if is_instance_valid(asteroid): asteroid.queue_free()
			asteroid = Asteroid.new()
			asteroid.position = Vector2(0, 0) # Move directly between them
			main_scene.add_child(asteroid),
		"check": func():
			var has_sweep_hit = false
			for arr in ship_a.active_sensor_sweeps.values():
				for hit in arr:
					if hit.get("instance_id") == ship_b.get_instance_id():
						has_sweep_hit = true
			return _assert(not has_sweep_hit, "Ship A's active sensors should be blocked by the asteroid.")
	})
	
	tests.append({
		"name": "Passive EM Detection",
		"setup": func():
			_reset_scene()
			for s in ship_a.sensor_hardware:
				if s["type"] == "active":
					s["active"] = false
			ship_b.subsystems["reactor"]["power"] = 1.0
			ship_b.point_defense_active = true, # Pushes EM noise +15 above 15.0 threshold
		"check": func():
			var has_sweep_hit = false
			for arr in ship_a.active_sensor_sweeps.values():
				for hit in arr:
					if hit.get("instance_id") == ship_b.get_instance_id():
						has_sweep_hit = true
			return _assert(has_sweep_hit, "Ship A should passively detect Ship B's EM noise.")
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
	var duration = t.get("duration", 90) # 90 frames to ensure passive EM (1.0s interval) sweeps at least once AFTER initial setup
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
	print("Sensor Stealth Tests: ", passed, " passed, ", failed, " failed out of ", total)
	print("==========================================")
	if failed > 0:
		printerr(">>> [TEST FAILED] test_sensor_stealth <<<")
		get_tree().quit(1)
	else:
		print(">>> [TEST PASSED] test_sensor_stealth <<<")
		get_tree().quit(0)
