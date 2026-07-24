extends RefCounted
class_name FoamPhysics

# BOUNDARY is the physics world's edge -- past it, a live RigidBody2D (ships,
# stations, asteroids -- see apply_forces callers) gets pushed, then teleported
# toward the poles at (0, +/-BOUNDARY). It's a WORLD EXTENT, not gameplay
# tuning, so it must track the authored cluster's half-extent: home_cluster.gd's
# `def.bounds` is +/-500000 (M53a's 2x reshape), and BOUNDARY matches that here.
# If the cluster is ever rescaled again, update BOTH together -- the furthest
# M53a station (Drift Market, ~407,922 out) needs real margin inside BOUNDARY
# or it gets teleported to a pole every physics frame instead of sitting where
# home_cluster.gd authored it (confirmed the hard way: pre-fix, BOUNDARY=250000
# against the enlarged cluster pinned 4 of 6 home stations to the two poles).
const BOUNDARY := 500000.0
const TELEPORT_DEPTH := 20000.0   # behavior tuning (push-vs-teleport threshold), not world extent -- stays as-is
const FORCE_K := 1.0              # behavior tuning (push force scale), not world extent -- stays as-is

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
