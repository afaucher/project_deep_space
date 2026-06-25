class_name LaserBehavior
extends "res://scripts/components/weapon_behavior.gd"

const FIRE_EM_SPIKE := 50.0
const EM_PULSE_DECAY := 25.0 # per second

# Waste heat from firing reuses Ship's damage_heat/_decay_damage_heat
# mechanism (same "burst now, decay over time" shape as a combat hit) rather
# than a second parallel decay system.
const FIRE_HEAT_SPIKE := 15.0

func can_fire(ship: Ship, comp: Dictionary, target_contact_id: String) -> bool:
	if not super.can_fire(ship, comp, target_contact_id):
		return false
	if not ship.active_contacts.has(target_contact_id):
		return false # Lasers require target lock for hitscan logic currently
	var real_target_pos = ship.active_contacts[target_contact_id]["pos"]
	var dist = ship.position.distance_to(real_target_pos)
	return dist <= comp["range"]

func execute_fire(ship: Ship, comp: Dictionary, target_pos: Vector2, target_contact_id: String) -> void:
	_consume_default(comp)
	comp["em_pulse"] = FIRE_EM_SPIKE
	comp["damage_heat"] = comp.get("damage_heat", 0.0) + FIRE_HEAT_SPIKE

	if ship.multiplayer.get_unique_id() == ship.owner_id:
		ship.sfx_laser.play()

	var real_target_pos = ship.active_contacts[target_contact_id]["pos"]
	var global_mount_pos = ship.position + ship.get_component_origin(comp).rotated(ship.rotation)
	var component_health_ratio = ship.get_component_health_ratio(comp["id"])

	# Find the actual body
	var space_state = ship.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 50.0
	query.shape = shape
	query.transform = Transform2D(0, real_target_pos)

	var results = space_state.intersect_shape(query, 32)
	for res in results:
		var body = res["collider"]
		if body == ship: continue
		if body.has_method("take_damage"):
			# Ray hits target - simulate from global_mount_pos to real_target_pos
			var hit_dir = (real_target_pos - global_mount_pos).normalized()
			var actual_damage = comp["damage"] * component_health_ratio
			body.take_damage(actual_damage, global_mount_pos, hit_dir, comp["weapon_type"])
		elif body.has_method("get_signature"):
			body.queue_free()

func tick(ship: Ship, comp: Dictionary, delta: float) -> void:
	comp["em_pulse"] = max(0.0, comp.get("em_pulse", 0.0) - EM_PULSE_DECAY * delta)
	comp["em_emission"] = comp["base_em_emission"] + comp["em_pulse"]
