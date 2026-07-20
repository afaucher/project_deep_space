extends RefCounted
class_name FoamPhysics

const BOUNDARY := 250000.0
const TELEPORT_DEPTH := 20000.0
const FORCE_K := 1.0

static func apply_forces(body: RigidBody2D) -> void:
	var result = calculate_forces(body.global_position, body.mass)
	if result.teleport:
		body.global_position = result.new_pos
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
	elif result.force != Vector2.ZERO:
		body.apply_central_force(result.force)

static func calculate_forces(pos: Vector2, mass: float) -> Dictionary:
	var result = {
		"teleport": false,
		"new_pos": pos,
		"force": Vector2.ZERO
	}
	
	var dist = pos.length()
	var depth = 0.0
	if dist > BOUNDARY:
		depth = dist - BOUNDARY
	
	if depth > 0.0:
		if depth > TELEPORT_DEPTH:
			var pole_y = -BOUNDARY + 5000.0 if pos.y < 0.0 else BOUNDARY - 5000.0
			result.teleport = true
			result.new_pos = Vector2(0.0, pole_y)
			return result
			
		var pole_y = -BOUNDARY if pos.y < 0.0 else BOUNDARY
		var target_pos = Vector2(0.0, pole_y)
		var force_dir = (target_pos - pos).normalized()
		var force_mag = depth * mass * FORCE_K
		result.force = force_dir * force_mag
		
	return result
