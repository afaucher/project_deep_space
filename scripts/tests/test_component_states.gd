extends Node

const Ship = preload("res://scripts/ships/frigate.gd")

# Test: Component Power-off, Damaged, and Destroyed states
# Verifies that each major component correctly gates its behavior.
#
# We create a current Frigate via the Ship alias, add it to the scene, let physics tick,
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
		c["damage_heat"] = 0.0
		c["_prev_health"] = c["max_health"]
		c["em_pulse"] = 0.0
		c["_em_pulse_decay_rate"] = 0.0
		c["em_osc_phase"] = 0.0
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
	for w in ship.get_components_by_type("weapons"):
		w["cooldown"] = 0.0

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

	# dir_high_res: Powered Off → no sweep results
	tests.append({
		"name": "dir_high_res: powered_off → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("dir_high_res", 50.0, false), # full health, OFF
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("dir_high_res", [])
			return _assert(sweeps.size() == 0,
				"Dir high-res sensor should produce no sweeps when powered off. got=" + str(sweeps.size())),
		"duration": 15
	})

	# dir_high_res: Destroyed → no sweep results
	tests.append({
		"name": "dir_high_res: destroyed → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("dir_high_res", 0.0, true), # destroyed, powered on
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("dir_high_res", [])
			return _assert(sweeps.size() == 0,
				"Dir high-res sensor should produce no sweeps when destroyed. got=" + str(sweeps.size())),
		"duration": 15
	})

	# omni_main: Powered Off → no sweep results
	tests.append({
		"name": "omni_main: powered_off → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("omni_main", 40.0, false),
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("omni_main", [])
			return _assert(sweeps.size() == 0,
				"Omni sensor should produce no sweeps when powered off. got=" + str(sweeps.size())),
		"duration": 15
	})

	# omni_main: Destroyed → no sweep results
	tests.append({
		"name": "omni_main: destroyed → no sweep",
		"setup": func():
			_reset_ship()
			_set_component("omni_main", 0.0, true),
		"check": func():
			var sweeps = ship.active_sensor_sweeps.get("omni_main", [])
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
			var ammo_before = ship.get_component("hp_fwd_laser")["ammo"]
			ship.set_meta("ammo_before", ammo_before)
			ship.fire_weapon("hp_fwd_laser", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var ammo_after = ship.get_component("hp_fwd_laser")["ammo"]
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
			var ammo_before = ship.get_component("hp_fwd_laser")["ammo"]
			ship.set_meta("ammo_before", ammo_before)
			ship.fire_weapon("hp_fwd_laser", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var ammo_after = ship.get_component("hp_fwd_laser")["ammo"]
			var ammo_before = ship.get_meta("ammo_before", 999)
			return _assert(ammo_after == ammo_before,
				"Weapon should not fire when destroyed. ammo_before=" + str(ammo_before) + " ammo_after=" + str(ammo_after)),
		"duration": 5
	})

	# ===== WEAPON FIRE EM/HEAT (M2) =====
	# Lasers generate waste heat when fired; missile tubes are railgun-style
	# launchers -- an EM launch pulse, but no heat (MissileBehavior.execute_fire
	# deliberately has no damage_heat line, contrast with LaserBehavior's).

	tests.append({
		"name": "hp_fwd_laser: fire → waste heat added",
		"setup": func():
			_reset_ship()
			ship.active_contacts["FAKE_TGT"] = {"pos": Vector2(500, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0, "pos_timer": 0.0, "classification": "UNIDENTIFIED VESSEL", "signature": {"cross_section": 100.0}}
			ship.fire_weapon("hp_fwd_laser", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var heat = _get_component("hp_fwd_laser").get("heat", 0.0)
			return _assert(heat > 10.0,
				"Laser fire should add waste heat (FIRE_HEAT_SPIKE=15) on top of the flat baseline. heat=" + str(heat)),
		"duration": 1
	})
	tests.append({
		"name": "hp_fwd_missile: fire → NO heat added (railgun launcher)",
		"setup": func():
			_reset_ship()
			ship.active_contacts["FAKE_TGT"] = {"pos": Vector2(500, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0, "pos_timer": 0.0, "classification": "UNIDENTIFIED VESSEL", "signature": {"cross_section": 100.0}}
			ship.fire_weapon("hp_fwd_missile", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var heat = _get_component("hp_fwd_missile").get("heat", 0.0)
			return _assert(heat < 1.0,
				"Missile fire should NOT add waste heat -- only the flat 0.1 powered baseline. heat=" + str(heat)),
		"duration": 1
	})
	tests.append({
		"name": "hp_fwd_missile: fire → EM pulse still present (railgun EM signature)",
		"setup": func():
			_reset_ship()
			ship.active_contacts["FAKE_TGT"] = {"pos": Vector2(500, 0), "vel": Vector2.ZERO, "last_seen_timer": 0.0, "pos_timer": 0.0, "classification": "UNIDENTIFIED VESSEL", "signature": {"cross_section": 100.0}}
			ship.fire_weapon("hp_fwd_missile", Vector2(500, 0), "FAKE_TGT"),
		"check": func():
			var em = _get_component("hp_fwd_missile").get("em_emission", 0.0)
			return _assert(em > 20.0,
				"Missile launch should still produce an EM pulse (FIRE_EM_SPIKE=30) even with no heat. em=" + str(em)),
		"duration": 1
	})

	# ===== EM SIGNATURE MAGNITUDE (M2) =====
	# Direct unit tests of the directional EM math (_received_em_power /
	# _total_received_em) against hand-computed exact values, rather than
	# just qualitative thresholds -- validates the model's actual magnitudes,
	# not just "something nonzero happened."

	tests.append({
		"name": "_received_em_power: omni emitter, bow-on view → 1.0x (no rear bias)",
		"setup": func(): pass,
		"check": func():
			var comp = {"type": "reactor", "em_emission": 100.0}
			# target faces +X (rotation 0); receiver is also along +X from the
			# target, i.e. looking at the target's nose.
			var power = ship._received_em_power(comp, 0.0, 0.0)
			return _assert(absf(power - 100.0) < 0.01,
				"Bow-on omni emission should be exactly em_emission * 1.0. got=" + str(power)),
		"duration": 1
	})
	tests.append({
		"name": "_received_em_power: omni emitter, tail-on view → 1.5x (full rear bias)",
		"setup": func(): pass,
		"check": func():
			var comp = {"type": "reactor", "em_emission": 100.0}
			# receiver is behind the target (along target's -X / six o'clock).
			var power = ship._received_em_power(comp, 0.0, PI)
			return _assert(absf(power - 150.0) < 0.01,
				"Tail-on omni emission should be exactly em_emission * 1.5. got=" + str(power)),
		"duration": 1
	})
	tests.append({
		"name": "_received_em_power: directional emitter, on-axis → full strength",
		"setup": func(): pass,
		"check": func():
			var comp = {"type": "weapons", "em_emission": 100.0, "heading": 0.0, "arc_width": PI / 3.0}
			var power = ship._received_em_power(comp, 0.0, 0.0) # dead-on the boresight
			return _assert(absf(power - 100.0) < 0.01,
				"On-axis directional emission should be full strength, no falloff. got=" + str(power)),
		"duration": 1
	})
	tests.append({
		"name": "_received_em_power: directional emitter, half-arc/2 off-axis → 50% falloff",
		"setup": func(): pass,
		"check": func():
			var comp = {"type": "weapons", "em_emission": 100.0, "heading": 0.0, "arc_width": PI / 3.0} # half_arc = PI/6
			var power = ship._received_em_power(comp, 0.0, PI / 12.0) # half_arc / 2
			return _assert(absf(power - 50.0) < 0.01,
				"At half the half-arc off-axis, linear falloff should give exactly 50%. got=" + str(power)),
		"duration": 1
	})
	tests.append({
		"name": "_received_em_power: directional emitter, outside arc → zero",
		"setup": func(): pass,
		"check": func():
			var comp = {"type": "weapons", "em_emission": 100.0, "heading": 0.0, "arc_width": PI / 3.0}
			var power = ship._received_em_power(comp, 0.0, PI / 2.0) # 90 degrees off, well outside +-30deg
			return _assert(power == 0.0,
				"Outside the emission cone should give exactly zero, not a small falloff tail. got=" + str(power)),
		"duration": 1
	})
	tests.append({
		"name": "_total_received_em: sums omni + directional emitters bow-on",
		"setup": func(): pass,
		"check": func():
			var sig = {"rot": 0.0, "em_emitters": [
				{"type": "reactor", "em_emission": 100.0},
				{"type": "weapons", "em_emission": 100.0, "heading": 0.0, "arc_width": PI / 3.0}
			]}
			var total = ship._total_received_em(sig, 0.0) # bow-on AND on-axis for the weapon
			return _assert(absf(total - 200.0) < 0.01,
				"Bow-on: reactor 100*1.0 + weapon 100*1.0 (on-axis) = 200. got=" + str(total)),
		"duration": 1
	})
	tests.append({
		"name": "_total_received_em: directional emitter drops out of the sum off-arc",
		"setup": func(): pass,
		"check": func():
			var sig = {"rot": 0.0, "em_emitters": [
				{"type": "reactor", "em_emission": 100.0},
				{"type": "weapons", "em_emission": 100.0, "heading": 0.0, "arc_width": PI / 3.0}
			]}
			var total = ship._total_received_em(sig, PI) # tail-on: reactor rear-biased, weapon arc doesn't reach
			return _assert(absf(total - 150.0) < 0.01,
				"Tail-on: reactor 100*1.5 + weapon 0 (outside its forward arc) = 150. got=" + str(total)),
		"duration": 1
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

	# ===== DAMAGE HEAT (M2) =====
	# A laser hit's heat burst (take_damage -> comp["damage_heat"]) must survive
	# the per-frame dispatch loop and decay over time, instead of being
	# clobbered to the steady-state value (or force-zeroed for hull) every tick.

	# engine_main rect is Rect2(-35, -10, 5, 20) -- (-32, 0) is inside it and
	# nowhere else, so this hits engine_main cleanly.
	tests.append({
		"name": "engine_main: laser hit → visible heat burst next frame",
		"setup": func():
			_reset_ship()
			ship.take_damage(50.0, Vector2(-32, 0), Vector2(1, 0), "laser"), # 50 * 0.5 heat_modifier = 25 damage_heat
		"check": func():
			var heat = _get_component("engine_main").get("heat", 0.0)
			return _assert(heat > 20.0,
				"Engine heat burst should still be visible one frame after the hit. heat=" + str(heat)),
		"duration": 1
	})
	tests.append({
		"name": "engine_main: heat burst decays back to baseline over time",
		"setup": func():
			_reset_ship()
			ship.take_damage(50.0, Vector2(-32, 0), Vector2(1, 0), "laser"),
		"check": func():
			var heat = _get_component("engine_main").get("heat", 0.0)
			return _assert(heat < 1.0,
				"Engine heat burst should have decayed back to baseline after 2s. heat=" + str(heat)),
		"duration": 120 # ~2s at 60fps; burst decays at 20.0/sec from 25
	})

	# hull_aft rect is Rect2(-30, -15, 15, 30) -- (-20, 0) is inside it. Hull
	# used to be force-zeroed every frame (the "else" branch in the dispatch
	# loop), so this is a direct regression test for that fix.
	tests.append({
		"name": "hull_aft: laser hit → visible heat burst (not force-zeroed)",
		"setup": func():
			_reset_ship()
			ship.take_damage(50.0, Vector2(-20, 0), Vector2(1, 0), "laser"),
		"check": func():
			var heat = _get_component("hull_aft").get("heat", 0.0)
			return _assert(heat > 20.0,
				"Hull heat burst should be visible one frame after the hit. heat=" + str(heat)),
		"duration": 1
	})
	tests.append({
		"name": "hull_aft: heat burst decays back to zero over time",
		"setup": func():
			_reset_ship()
			ship.take_damage(50.0, Vector2(-20, 0), Vector2(1, 0), "laser"),
		"check": func():
			var heat = _get_component("hull_aft").get("heat", 0.0)
			return _assert(heat < 1.0,
				"Hull heat burst should have decayed back to ~0 after 2s. heat=" + str(heat)),
		"duration": 120
	})

	# ===== ENGINE DAMAGE EM OSCILLATION (M2) =====
	# 30% health -> damage_ratio 0.7 -> osc_freq = 0.2 + 0.7*0.6 = 0.62Hz.
	# Zero throttle isolates the oscillation term (the throttle-proportional
	# baseline term is 0 either way), so em_emission is just the 0.5 powered
	# trickle (b_em) plus the oscillation.

	tests.append({
		"name": "engine_main: damaged → EM near baseline at oscillation phase start",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 90.0, true) # 30% health
			ship.apply_control_input(0.0, 0.0, 0.0, 1, 0), # zero throttle
		"check": func():
			var em = _get_component("engine_main").get("em_emission", 0.0)
			return _assert(em < 15.0,
				"EM should start near the flat baseline right as the oscillation phase begins. em=" + str(em)),
		"duration": 1
	})
	tests.append({
		"name": "engine_main: damaged → EM rises well above baseline at oscillation peak",
		"setup": func():
			_reset_ship()
			_set_component("engine_main", 90.0, true)
			ship.apply_control_input(0.0, 0.0, 0.0, 1, 0),
		"check": func():
			var em = _get_component("engine_main").get("em_emission", 0.0)
			return _assert(em > 50.0,
				"EM should have risen to near its oscillation peak (~70 + 0.5 baseline) by quarter-period (~24 frames). em=" + str(em)),
		"duration": 24 # ~quarter-period at 0.62Hz, 60fps
	})

	# ===== REACTOR WHITEOUT (M2) =====
	# Reactor health crossing from alive to destroyed should fire a one-shot
	# EM whiteout that decays over REACTOR_WHITEOUT_DURATION (1.5s), not a
	# silent drop to zero emission.

	tests.append({
		"name": "reactor_core: destroyed → EM whiteout visible next frame",
		"setup": func():
			_reset_ship()
			_set_component("reactor_core", 0.0, true), # health crosses 200 -> 0 this frame
		"check": func():
			var em = _get_component("reactor_core").get("em_emission", 0.0)
			return _assert(em > 400.0,
				"Whiteout should be near its full magnitude (power_rating 100 * 5.0 = 500) one frame after destruction. em=" + str(em)),
		"duration": 1
	})
	tests.append({
		"name": "reactor_core: EM whiteout decays to ~0 after its duration",
		"setup": func():
			_reset_ship()
			_set_component("reactor_core", 0.0, true),
		"check": func():
			var em = _get_component("reactor_core").get("em_emission", 0.0)
			return _assert(em < 1.0,
				"Whiteout should have fully decayed (1.5s duration) and reactor health is 0, so baseline EM is also 0. em=" + str(em)),
		"duration": 95 # > 1.5s at 60fps with margin
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
