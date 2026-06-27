extends Node
class_name MissileController

# Guidance-law tuning. FUEL_LIFETIME bounds effective engagement range/time
# together with the missile's own max_speed; the lock-related thresholds
# trade lock stability against how easy a target is to break lock by breaking
# sensor contact.
const FUEL_LIFETIME := 15.0          # seconds before self-destruct ("ran out of fuel")
const COMBAT_DEBUG := false          # gate verbose [Missile] lifecycle traces
const LOCK_LOSS_STALENESS := 5.0     # seconds an existing lock's contact can go unrefreshed before it's dropped
const ACQUISITION_FRESHNESS := 1.0   # seconds a contact must have been refreshed within to be eligible for a *new* lock (stricter than keeping one)
const LEAD_TIME_CAP := 0.7           # seconds -- caps how far ahead proportional-nav aims so the missile doesn't cross the target's path
const VELOCITY_STEER_THRESHOLD := 10.0 # below this velocity error, steer directly at the intercept point instead of the desired-velocity vector
const SEEKER_EDGE_MARGIN := 10.0     # degrees of margin kept off the seeker's edge so the target doesn't fall out of FOV next frame
const SEEKER_FALLBACK_HALF_ARC := PI / 3.0 # used only if no seeker component is found (shouldn't happen in practice)
const PROXIMITY_FUSE_RANGE := 100.0  # distance at which the warhead detonates
const WARHEAD_DAMAGE := 250.0

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
	if age > FUEL_LIFETIME:
		# Run out of fuel, self-destruct or go inert
		if COMBAT_DEBUG: print("[Missile] Out of fuel looking for target")
		ship.hulk()
		return
		
	# Check if current target is valid
	var current_target_valid = false
	if target_id != "" and ship.active_contacts.has(target_id):
		var contact = ship.active_contacts[target_id]
		if contact.get("pos_timer", 0.0) <= LOCK_LOSS_STALENESS:
			current_target_valid = true
			
	if not current_target_valid:
		if target_id != "":
			if COMBAT_DEBUG: print("[Missile] Lost lock on target cid: ", target_id)
			target_id = ""
			
		# Find closest hostile target in own sensors
		var best_dist = 999999.0
		var new_target = ""
		
		for c_id in ship.active_contacts:
			var contact = ship.active_contacts[c_id]
			var classification = contact.get("classification", "")
			if classification != "UNIDENTIFIED VESSEL" and classification != "INCOMING ORDNANCE":
				continue
			if contact.get("pos_timer", 0.0) > ACQUISITION_FRESHNESS:
				continue # Need a fresh contact to acquire lock
				
			var dist_to = ship.position.distance_to(contact["pos"])
			if dist_to < best_dist:
				best_dist = dist_to
				new_target = c_id
				
		if new_target != "":
			target_id = new_target
			if COMBAT_DEBUG: print("[Missile] Acquired new target cid: ", target_id)
			
	if target_id == "":
		# No target and no fallback, fly straight
		ship.apply_control_input(1.0, 0.0, ship.rotation, 1, 0)
		return
		
	var target = ship.active_contacts[target_id]
	var target_pos = target["pos"]
	var target_vel = target["vel"]
	
	# Proportional Navigation (simplified lead pursuit)
	var rel_pos = target_pos - ship.position
	var rel_vel = target_vel - ship.linear_velocity
	var closing_vel = -rel_pos.normalized().dot(rel_vel)
	
	var time_to_impact = 0.0
	if closing_vel > 0.0:
		time_to_impact = rel_pos.length() / closing_vel
	else:
		time_to_impact = rel_pos.length() / max(1.0, ship.linear_velocity.length())
		
	# Cap the lead time so the missile doesn't aim too far ahead and cross the target's path
	time_to_impact = min(time_to_impact, LEAD_TIME_CAP)
		
	var intercept_pos = target_pos + (target_vel * time_to_impact)
	
	var desired_vel = (intercept_pos - ship.position).normalized() * ship.max_speed
	var vel_error = desired_vel - ship.linear_velocity
	var desired_heading = ship.rotation
	if vel_error.length() > VELOCITY_STEER_THRESHOLD:
		desired_heading = vel_error.angle()
	else:
		desired_heading = (intercept_pos - ship.position).angle()
	
	# Clamp heading to keep target within seeker cone
	var angle_to_target = rel_pos.angle()
	var seeker_half_arc = SEEKER_FALLBACK_HALF_ARC
	for s in ship.get_components_by_type("sensors"):
		if s["id"] == "seeker":
			seeker_half_arc = s["arc_width"] / 2.0
			break
	var max_lead = max(0.1, seeker_half_arc - deg_to_rad(SEEKER_EDGE_MARGIN))
	var lead_angle_diff = wrapf(desired_heading - angle_to_target, -PI, PI)
	lead_angle_diff = clampf(lead_angle_diff, -max_lead, max_lead)
	desired_heading = angle_to_target + lead_angle_diff
	
	# Full thrust, steer in the drift-compensated direction
	ship.apply_control_input(1.0, 0.0, desired_heading, 1, 0)
	
	# Warhead detonate logic
	if rel_pos.length() < PROXIMITY_FUSE_RANGE:
		detonate()

func detonate() -> void:
	if ship.is_dead: return
	
	if target_id != "" and ship.active_contacts.has(target_id):
		var target_pos = ship.active_contacts[target_id]["pos"]
		var space_state = ship.get_world_2d().direct_space_state
		var dir = (target_pos - ship.position).normalized()
		var end_pos = ship.position + dir * 2000.0 # Extend ray well past the target
		var query = PhysicsRayQueryParameters2D.create(ship.position, end_pos)
		var result = space_state.intersect_ray(query)
		
		# Draw the laser beam (fire and forget visual)
		var main_node = ship.get_tree().current_scene
		if main_node and main_node.has_method("draw_laser"):
			main_node.draw_laser(ship.position, target_pos)
			
		if COMBAT_DEBUG: print("[Missile] Firing laser warhead at target: ", target_id, " from ", ship.position, " to ", target_pos)
			
		if result and result.collider.has_method("take_damage") and result.collider != ship:
			var hit_dir = (result.collider.position - ship.position).normalized()
			# Missiles are laser-heads, so they deal laser damage (which applies extreme heat)
			result.collider.take_damage(WARHEAD_DAMAGE, result.position, hit_dir, "laser")
			
	# Destroy missile
	ship.hulk()
	ship.queue_free()
