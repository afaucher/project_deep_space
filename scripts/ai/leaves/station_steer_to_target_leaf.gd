extends "res://addons/beehave/nodes/leaves/action.gd"

# Steers a station towards its primary target without translating towards it.
# Arrests any translational drift.
func tick(actor: Node, blackboard: Blackboard) -> int:
	if actor == null:
		return SUCCESS
		
	var target_c_id = blackboard.get_value("primary_target_c_id", -1)
	if target_c_id == -1 or not actor.active_contacts.has(target_c_id):
		return FAILURE
		
	var contact = actor.active_contacts[target_c_id]
	var target_pos = contact["pos"]
	
	# Determine desired heading
	var to_target = target_pos - actor.position
	var target_heading = to_target.angle()
	
	# Rotate towards target but do NOT translate (throttle=0)
	actor.apply_control_input(0.0, 0.0, target_heading, 0, 1)
	
	# Oppose current linear velocity to arrest drift
	var drift_vel = actor.linear_velocity
	var rcs_dir = Vector2.ZERO
	if drift_vel.length_squared() > 0.1:
		rcs_dir = -drift_vel # apply_rcs_input will normalize if length > 1
		
	actor.apply_rcs_input(rcs_dir, 0.0)
	
	return SUCCESS
