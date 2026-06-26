extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const WeaponBehaviorRegistry = preload("res://scripts/components/weapon_behavior_registry.gd")

var ship: Ship
var main_node: Node
var target_missile: Missile
var frames: int = 0
var test_frame_start: int = 0

var tests = []
var current_test: int = -1
var passed: int = 0
var failed: int = 0
var total: int = 0

func setup(main: Node) -> void:
	print("Starting Test: Damage Propagation")

	main_node = main
	ship = Ship.new()
	ship.name = "TestShip"
	ship.owner_id = 1
	ship.iff_tags = ["TEAM_A"]
	ship.position = Vector2.ZERO
	main_node.add_child(ship)

	_register_tests()
	total = tests.size()
	_start_next_test()

func _spawn_target_missile(pos: Vector2, vel: Vector2) -> Missile:
	if is_instance_valid(target_missile):
		target_missile.queue_free()
	target_missile = Missile.new()
	target_missile.name = "TargetMissile"
	target_missile.owner_id = 2
	target_missile.iff_tags = ["TEAM_B"]
	target_missile.position = pos
	target_missile.linear_velocity = vel
	main_node.add_child(target_missile)
	return target_missile

func _missile_took_damage(missile: Missile) -> bool:
	for c in missile.ship_components:
		if c["health"] < c["max_health"]:
			return true
	return false

func _reset_ship() -> void:
	ship.position = Vector2.ZERO
	ship.linear_velocity = Vector2.ZERO
	ship.rotation = 0.0
	ship.angular_velocity = 0.0
	
	for c in ship.ship_components:
		c["health"] = c.get("max_health", 100.0)
	
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
				if c["id"] == "dir_high_res":
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

	tests.append({
		"name": "Fresh Contact (No Staleness) Still Hits Normally",
		"setup": func():
			_reset_ship()
			var missile = _spawn_target_missile(Vector2(10000, 0), Vector2(500, 0))
			ship.active_contacts["TRK-TEST"] = {
				"pos": missile.position, "vel": missile.linear_velocity, "pos_timer": 0.0,
				"instance_id": missile.get_instance_id(), "classification": "INCOMING ORDNANCE", "last_seen_timer": 0.0
			},
		# Firing happens in "check" (not "setup") -- the missile's collision
		# shape isn't registered with the physics server until its _ready()
		# runs, which doesn't happen synchronously within the same setup()
		# call as add_child(). By the time "check" runs (after "duration"
		# elapsed frames), the missile is fully ready to be hit.
		"check": func():
			var weapon = ship.get_component("hp_fwd_laser")
			weapon["cooldown"] = 0.0
			weapon["ammo"] = 999
			WeaponBehaviorRegistry.get_behavior("laser").execute_fire(ship, weapon, target_missile.position, "TRK-TEST")
			return _assert(_missile_took_damage(target_missile), "A fresh (zero-staleness) contact should still hit normally.")
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
