extends Node
class_name MissileController

var ship: RigidBody2D
var target_id: String = ""
var age: float = 0.0

func _ready() -> void:
	ship = get_parent()
	if not ship or not ship.has_method("apply_control_input"):
		set_physics_process(false)
		push_error("MissileController must be a child of a Ship")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	if ship.is_dead: return
	
	age += delta
	if age > 15.0:
		# Run out of fuel, self-destruct or go inert
		ship.hulk()
		return
		
	if target_id == "" or not ship.active_contacts.has(target_id):
		# No target, fly straight
		ship.apply_control_input(1.0, 0.0, ship.rotation, 0, 0)
		return
		
	var target = ship.active_contacts[target_id]
	var target_pos = target["pos"]
	var target_vel = target["vel"]
	
	# Proportional Navigation (simplified lead pursuit)
	var rel_pos = target_pos - ship.position
	var dist = rel_pos.length()
	var time_to_impact = max(dist / max(ship.linear_velocity.length(), 1.0), 0.1)
	var intercept_point = target_pos + (target_vel * time_to_impact)
	
	var desired_heading = ship.position.angle_to_point(intercept_point)
	
	# Full thrust, steer towards intercept point
	ship.apply_control_input(1.0, 0.0, desired_heading, 0, 0)
	
	# Warhead detonate logic
	if dist < 300.0:
		detonate()

func detonate() -> void:
	if ship.is_dead: return
	
	if target_id != "" and ship.active_contacts.has(target_id):
		var target_pos = ship.active_contacts[target_id]["pos"]
		var space_state = ship.get_world_2d().direct_space_state
		var query = PhysicsRayQueryParameters2D.create(ship.position, target_pos)
		var result = space_state.intersect_ray(query)
		
		# Draw the laser beam (fire and forget visual)
		var main_node = ship.get_tree().current_scene
		if main_node and main_node.has_method("draw_laser"):
			main_node.draw_laser(ship.position, target_pos)
			
		if result and result.collider.has_method("take_damage") and result.collider != ship:
			var hit_dir = (result.collider.position - ship.position).normalized()
			# Missiles are laser-heads, so they deal laser damage (which applies extreme heat)
			result.collider.take_damage(250.0, ship.position, hit_dir, "laser")
			
	# Destroy missile
	ship.hulk()
	ship.queue_free()
