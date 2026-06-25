class_name MissileBehavior
extends "res://scripts/components/weapon_behavior.gd"

func execute_fire(ship: Ship, comp: Dictionary, target_pos: Vector2, target_contact_id: String) -> void:
	_consume_default(comp)

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
	if spawn_rel.length() < 55.0:
		# Push along launch_dir until the distance from ship center is at least 55.0px
		var A = 1.0
		var B = 2.0 * rel_mount.dot(launch_dir)
		var C = rel_mount.length_squared() - 3025.0 # 55.0^2
		var discriminant = B * B - 4.0 * A * C
		if discriminant >= 0.0:
			var d = (-B + sqrt(discriminant)) / 2.0
			if d > 0.0:
				spawn_rel += launch_dir * d
			else:
				spawn_rel += launch_dir * 25.0
		else:
			spawn_rel += launch_dir * 25.0

	proj.position = ship.position + spawn_rel.rotated(ship.rotation)

	# Orient nose toward target so seeker can acquire, but kick velocity
	# out the tube direction to clear the parent ship hull
	var target_dir = (target_pos - proj.position).angle()
	proj.rotation = target_dir
	proj.name = "Missile_" + str(ship.owner_id) + "_" + str(randi())
	proj.owner_id = ship.owner_id
	proj.iff_tags = ship.iff_tags.duplicate()
	proj.linear_velocity = ship.linear_velocity + (Vector2.RIGHT.rotated(weapon_launch_angle) * 200.0)
	proj.add_collision_exception_with(ship)
	main_node.add_child(proj, true)
