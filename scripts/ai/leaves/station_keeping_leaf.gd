extends "res://addons/beehave/nodes/leaves/action.gd"

# Station Keeping: Uses RCS to arrest any translational drift and maintain current heading.
func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return SUCCESS
		
	# Hold current heading using standard control input (which utilizes RCS torque if no engines)
	actor.apply_control_input(0.0, 0.0, actor.rotation, 0, 1)
	
	# Oppose current linear velocity to arrest drift
	var drift_vel = actor.linear_velocity
	var rcs_dir = Vector2.ZERO
	if drift_vel.length_squared() > 0.1:
		rcs_dir = -drift_vel # apply_rcs_input will clamp length squared if > 1
		
	actor.apply_rcs_input(rcs_dir, 0.0)
	
	return SUCCESS
