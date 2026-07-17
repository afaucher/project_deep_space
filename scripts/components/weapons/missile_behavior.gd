class_name MissileBehavior
extends "res://scripts/components/weapon_behavior.gd"

# Smaller and shorter-lived than LaserBehavior's -- a launch flash, not a
# sustained beam.
const FIRE_EM_SPIKE := 30.0
const EM_PULSE_DECAY := 15.0 # per second

# Minimum distance from ship center a missile must spawn at, so it clears the
# Frigate's hull corners (hull rects span roughly +/-30px from center, plus
# mount offset) instead of materializing inside the firing ship's own
# collision shape. SPAWN_CLEARANCE_SQ is used directly in the quadratic solve
# below rather than squaring SPAWN_CLEARANCE every call.
const SPAWN_CLEARANCE := 55.0
const SPAWN_CLEARANCE_SQ := SPAWN_CLEARANCE * SPAWN_CLEARANCE
const SPAWN_CLEARANCE_FALLBACK := SPAWN_CLEARANCE / 2.0 # used if the quadratic has no valid positive solution

# Ejection velocity added along the tube direction on top of the ship's own
# velocity -- separate from the missile's own engine thrust, just enough to
# physically clear the parent ship before the seeker/engine take over.
const LAUNCH_KICK := 200.0

func execute_fire(ship: Ship, comp: Dictionary, target_pos: Vector2, target_contact_id: String) -> void:
	_consume_default(comp)
	# Railgun-style launcher: an electromagnetic launch pulse, but no waste
	# heat the way a laser's beam generates -- deliberately no damage_heat
	# addition here (contrast with LaserBehavior.execute_fire()).
	comp["em_pulse"] = FIRE_EM_SPIKE

	if ship.multiplayer.get_unique_id() == ship.owner_id:
		ship.sfx_missile.play()

	var main_node = ship.get_tree().current_scene
	if not is_instance_valid(main_node): return

	var Missile = load("res://scripts/ships/missile.gd")
	var proj = Missile.new()

	# Add controller
	var MissileController = load("res://scripts/missile_controller.gd")
	var controller = MissileController.new()
	proj.add_child(controller)
	controller.target_id = target_contact_id
	if target_contact_id != "" and ship.active_contacts.has(target_contact_id):
		proj.active_contacts[target_contact_id] = ship.active_contacts[target_contact_id].duplicate(true)
		proj.active_contacts[target_contact_id]["pos_timer"] = 0.0

	var weapon_launch_angle = ship.rotation + comp["heading"]
	var launch_dir = Vector2.RIGHT.rotated(weapon_launch_angle)
	var rel_mount = ship.get_component_origin(comp)
	var spawn_rel = rel_mount
	if spawn_rel.length() < SPAWN_CLEARANCE:
		# Push along launch_dir until the distance from ship center is at least SPAWN_CLEARANCE
		var A = 1.0
		var B = 2.0 * rel_mount.dot(launch_dir)
		var C = rel_mount.length_squared() - SPAWN_CLEARANCE_SQ
		var discriminant = B * B - 4.0 * A * C
		if discriminant >= 0.0:
			var d = (-B + sqrt(discriminant)) / 2.0
			if d > 0.0:
				spawn_rel += launch_dir * d
			else:
				spawn_rel += launch_dir * SPAWN_CLEARANCE_FALLBACK
		else:
			spawn_rel += launch_dir * SPAWN_CLEARANCE_FALLBACK

	proj.position = ship.position + spawn_rel.rotated(ship.rotation)

	# Orient nose toward target so seeker can acquire, but kick velocity
	# out the tube direction to clear the parent ship hull
	var target_dir = (target_pos - proj.position).angle()
	proj.rotation = target_dir
	proj.name = "Missile_" + str(ship.owner_id) + "_" + str(randi())
	proj.owner_id = ship.owner_id
	proj.iff_tags = ship.iff_tags.duplicate()
	# M48 -- the missile inherits the launcher's own hostile-flag judgment (so
	# a reacquiring seeker uses the SAME standing rules the launcher would)
	# and carries the launcher's instance id so missile_controller.gd's
	# detonate() attributes warhead damage to the launcher, not the missile.
	proj.known_enemy_flags = ship.known_enemy_flags.duplicate()
	proj.launcher_instance_id = ship.get_instance_id()
	proj.linear_velocity = ship.linear_velocity + (Vector2.RIGHT.rotated(weapon_launch_angle) * LAUNCH_KICK)
	proj.add_collision_exception_with(ship)
	main_node.add_child(proj, true)

func tick(ship: Ship, comp: Dictionary, delta: float) -> void:
	comp["em_pulse"] = max(0.0, comp.get("em_pulse", 0.0) - EM_PULSE_DECAY * delta)
	comp["em_emission"] = comp.get("base_em_emission", 0.0) + comp["em_pulse"]
