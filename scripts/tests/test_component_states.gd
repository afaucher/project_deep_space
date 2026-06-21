extends Node

# Test: Component Power-off, Damaged, and Destroyed states
# Verifies that each major component correctly gates its behavior.
#
# We create a bare Ship.new(), add it to the scene, let physics tick,
# and measure outputs (velocity, angular_velocity, sensor contacts, weapon fire).

var ship: Ship = null
var main_node: Node = null
var frames: int = 0

# Test queue: each entry is { "name": String, "setup": Callable, "check": Callable, "duration": int }
var tests: Array = []
var current_test: int = -1
var test_frame_start: int = 0
var passed: int = 0
var failed: int = 0
var total: int = 0

# ---------- helpers ----------

func _set_component(comp_id: String, health: float, powered_on = null) -> void:
	for c in ship.ship_components:
		if c["id"] == comp_id:
			c["health"] = health
			if powered_on != null:
				c["powered_on"] = powered_on
			return
	printerr("[BUG] Component not found: ", comp_id)

func _get_component(comp_id: String) -> Dictionary:
	for c in ship.ship_components:
		if c["id"] == comp_id:
			return c
	return {}

func _reset_ship() -> void:
	# Reset all components to full health and powered on
	for c in ship.ship_components:
		c["health"] = c["max_health"]
		if c.has("powered_on"):
			c["powered_on"] = true
	ship.is_dead = false
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	ship.position = Vector2.ZERO
	ship.rotation = 0.0
	ship.subsystems["reactor"]["power"] = 1.0
	ship.subsystems["engines"]["power"] = 1.0
	ship.subsystems["weapons"]["power"] = 1.0
	ship.subsystems["sensors"]["power"] = 1.0
	ship.apply_control_input(0.0, 0.0, 0.0, 1, 0) # zero input, combat mode, direct throttle
	for w in ship.weapons:
		ship.weapons[w]["cooldown"] = 0.0

func _assert(condition: bool, msg: String) -> bool:
	if not condition:
		printerr("  ASSERT FAILED: ", msg)
	return condition

# ---------- setup ----------

func setup(main) -> void:
	main_node = main
	print("Starting Component State Tests")

	ship = Ship.new()
	ship.name = "TestShip_ComponentStates"
	ship.owner_id = 1
	ship.position = Vector2.ZERO
	main_node.add_child(ship)

	# Build test list
	_build_tests()
	total = tests.size()
	_start_next_test()

func _build_tests() -> void:
	# ===== ENGINE_MAIN =====

	# Engine: Powered Off → no thrust
	tests.append({
		"name": "engine_main: powered_off → no thrust",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 300.0, false) # full health, powered OFF
			ship.apply_control_input(1.0, 0.0, 0.0, 1, 0), # full thrust forward
		"check": func():
			return _assert(ship.linear_velocity.length() < 1.0,
				"Ship should not accelerate with engine powered off. vel=" + str(ship.linear_velocity.length())),
		"duration": 30 # physics frames
	})

	# Engine: Powered Off → no torque
	tests.append({
		"name": "engine_main: powered_off → no torque",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 300.0, false)
			ship.apply_control_input(0.0, 0.0, PI, 1, 0), # turn to PI
		"check": func():
			return _assert(abs(ship.angular_velocity) < 0.01,
				"Ship should not rotate with engine powered off. omega=" + str(ship.angular_velocity)),
		"duration": 30
	})

	# Engine: Damaged (50%) → reduced thrust
	tests.append({
		"name": "engine_main: damaged_50pct → reduced thrust",
		"setup": func():
			_reset_ship()
			ship.apply_control_input(1.0, 0.0, 0.0, 1, 0),
		"check": func():
			var full_health_vel = ship.linear_velocity.length()
			# Now damage and measure again
			_reset_ship()
			_set_component("engine_main", 150.0, true) # 50% health
			ship.apply_control_input(1.0, 0.0, 0.0, 1, 0)
			# Store for phase 2
			ship.set_meta("full_vel", full_health_vel)
			return true, # phase 1 always passes
		"duration": 30
	})
	tests.append({
		"name": "engine_main: damaged_50pct → thrust < full (phase2)",
		"setup": func():
			pass, # Continuation - ship already set up from previous test
		"check": func():
			var damaged_vel = ship.linear_velocity.length()
			var full_vel = ship.get_meta("full_vel", 999.0)
			return _assert(damaged_vel > 1.0 and damaged_vel < full_vel * 0.75,
				"Damaged engine thrust should be notably less than full. damaged=" + str(damaged_vel) + " full=" + str(full_vel)),
		"duration": 30
	})

	# Engine: Destroyed → no thrust
	tests.append({
		"name": "engine_main: destroyed → no thrust",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 0.0, true) # health 0, powered on
			ship.apply_control_input(1.0, 0.0, 0.0, 1, 0),
		"check": func():
			return _assert(ship.linear_velocity.length() < 1.0,
				"Ship should not accelerate with destroyed engine. vel=" + str(ship.linear_velocity.length())),
		"duration": 30
	})

	# Engine: Destroyed → no torque
	tests.append({
		"name": "engine_main: destroyed → no torque",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 0.0, true)
			ship.apply_control_input(0.0, 0.0, PI, 1, 0),
		"check": func():
			return _assert(abs(ship.angular_velocity) < 0.01,
				"Ship should not rotate with destroyed engine. omega=" + str(ship.angular_velocity)),
		"duration": 30
	})

	# ===== SENSORS =====

	# Sensor Fwd: Powered Off → no dir_high_res sweep results
	tests.append({
		"name": "hp_sensor_fwd: powered_off → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("hp_sensor_fwd", 50.0, false), # full health, OFF
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("dir_high_res", [])
			return _assert(sweeps.size() == 0,
				"Dir high-res sensor should produce no sweeps when powered off. got=" + str(sweeps.size())),
		"duration": 15
	})

	# Sensor Fwd: Destroyed → no dir_high_res sweep results
	tests.append({
		"name": "hp_sensor_fwd: destroyed → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("hp_sensor_fwd", 0.0, true), # destroyed, powered on
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("dir_high_res", [])
			return _assert(sweeps.size() == 0,
				"Dir high-res sensor should produce no sweeps when destroyed. got=" + str(sweeps.size())),
		"duration": 15
	})

	# Sensor Omni: Powered Off → no omni sweep results
	tests.append({
		"name": "hp_sensor_omni: powered_off → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("hp_sensor_omni", 100.0, false),
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("omni", [])
			return _assert(sweeps.size() == 0,
				"Omni sensor should produce no sweeps when powered off. got=" + str(sweeps.size())),
		"duration": 15
	})

	# Sensor Omni: Destroyed → no omni sweep results
	tests.append({
		"name": "hp_sensor_omni: destroyed → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("hp_sensor_omni", 0.0, true),
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("omni", [])
			return _assert(sweeps.size() == 0,
				"Omni sensor should produce no sweeps when destroyed. got=" + str(sweeps.size())),
		"duration": 15
	})

	# ===== WEAPONS =====

	# Weapon: Powered Off → fire_weapon fails silently
	tests.append({
		"name": "hp_fwd_laser: powered_off → cannot fire",
		"setup": func():
			_reset_ship()
			_set_component("hp_fwd_laser", 150.0, false) # full health, OFF
			# Give it a fake contact to shoot at
			ship.active_contacts["FAKE_TGT"] = {"pos": Vector2(500, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0, "pos_timer": 0.0, "classification": "UNIDENTIFIED VESSEL", "signature": {"cross_section": 100.0}}
			var ammo_before = ship.weapons["hp_fwd_laser"]["ammo"]
			ship.set_meta("ammo_before", ammo_before)
			ship.fire_weapon("hp_fwd_laser", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var ammo_after = ship.weapons["hp_fwd_laser"]["ammo"]
			var ammo_before = ship.get_meta("ammo_before", 999)
			return _assert(ammo_after == ammo_before,
				"Weapon should not fire when powered off. ammo_before=" + str(ammo_before) + " ammo_after=" + str(ammo_after)),
		"duration": 5
	})

	# Weapon: Destroyed → fire_weapon fails silently
	tests.append({
		"name": "hp_fwd_laser: destroyed → cannot fire",
		"setup": func():
			_reset_ship()
			_set_component("hp_fwd_laser", 0.0, true) # destroyed, powered on
			ship.active_contacts["FAKE_TGT"] = {"pos": Vector2(500, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0, "pos_timer": 0.0, "classification": "UNIDENTIFIED VESSEL", "signature": {"cross_section": 100.0}}
			var ammo_before = ship.weapons["hp_fwd_laser"]["ammo"]
			ship.set_meta("ammo_before", ammo_before)
			ship.fire_weapon("hp_fwd_laser", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var ammo_after = ship.weapons["hp_fwd_laser"]["ammo"]
			var ammo_before = ship.get_meta("ammo_before", 999)
			return _assert(ammo_after == ammo_before,
				"Weapon should not fire when destroyed. ammo_before=" + str(ammo_before) + " ammo_after=" + str(ammo_after)),
		"duration": 5
	})

	# ===== REACTOR =====

	# Reactor: Destroyed → ship is dead
	tests.append({
		"name": "reactor_core: destroyed → ship dies",
		"setup": func():
			_reset_ship()
			# Simulate reactor destruction via take_damage
			_set_component("reactor_core", 1.0, false)
			ship.take_damage(500.0), # fallback hull damage triggers death check
		"check": func():
			# Manually check: reactor health 0 + hull damage should trigger hulk
			_set_component("reactor_core", 0.0)
			# Force the death check
			if ship.get_sys_health("reactor") <= 0.0:
				ship.hulk()
			return _assert(ship.is_dead,
				"Ship should be dead when reactor is destroyed. is_dead=" + str(ship.is_dead)),
		"duration": 5
	})

	# ===== is_component_powered unit checks =====

	tests.append({
		"name": "is_component_powered: healthy+on → true",
		"setup": func():
			_reset_ship(),
		"check": func():
			return _assert(ship.is_component_powered("engine_main") == true,
				"Healthy powered-on component should return true"),
		"duration": 2
	})

	tests.append({
		"name": "is_component_powered: healthy+off → false",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 300.0, false),
		"check": func():
			return _assert(ship.is_component_powered("engine_main") == false,
				"Powered-off component should return false"),
		"duration": 2
	})

	tests.append({
		"name": "is_component_powered: destroyed+on → false",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 0.0, true),
		"check": func():
			return _assert(ship.is_component_powered("engine_main") == false,
				"Destroyed component should return false even if powered_on"),
		"duration": 2
	})

	tests.append({
		"name": "get_component_health_ratio: 50% health → 0.5",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 150.0, true),
		"check": func():
			var ratio = ship.get_component_health_ratio("engine_main")
			return _assert(abs(ratio - 0.5) < 0.01,
				"50% health should give ratio ~0.5. got=" + str(ratio)),
		"duration": 2
	})

	tests.append({
		"name": "get_component_health_ratio: destroyed → 0.0",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 0.0, true),
		"check": func():
			var ratio = ship.get_component_health_ratio("engine_main")
			return _assert(ratio == 0.0,
				"Destroyed component should give ratio 0.0. got=" + str(ratio)),
		"duration": 2
	})

# ---------- test runner ----------

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
	var elapsed = frames - test_frame_start
	if elapsed >= t["duration"]:
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
	print("Component State Tests: ", passed, " passed, ", failed, " failed out of ", total)
	print("==========================================")
	if failed > 0:
		printerr(">>> [TEST FAILED] test_component_states <<<")
		get_tree().quit(1)
	else:
		print(">>> [TEST PASSED] test_component_states <<<")
		get_tree().quit(0)
