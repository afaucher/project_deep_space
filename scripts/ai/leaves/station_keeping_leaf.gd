extends "res://addons/beehave/nodes/leaves/action.gd"

const Steering = preload("res://scripts/ai/steering.gd")

var _hold_pos: Vector2 = Vector2.ZERO
var _initialized: bool = false

# Station Keeping: Uses RCS/engines to maintain an exact global position.
# If bumped, it steers back to its hold coordinate while dodging obstacles.
func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return SUCCESS
		
	if not _initialized:
		_hold_pos = actor.position
		_initialized = true
		
	var to_hold = _hold_pos - actor.position
	var dist = to_hold.length()
	
	var desired_vel = Vector2.ZERO
	if dist > 5.0:
		# Cruise back to station at a modest speed (e.g., 200 m/s), slowing as we get close
		desired_vel = to_hold.normalized() * min(dist * 0.5, 200.0)
		
	# Apply collision avoidance on top of our desired velocity
	var avoided_dir = Steering.steer(actor, desired_vel.normalized(), null)
	
	if avoided_dir.length() > 0.01:
		desired_vel = avoided_dir.normalized() * max(desired_vel.length(), 200.0)
		
	var steer = desired_vel - actor.linear_velocity
	
	# If we are basically on station and not moving, just hold heading.
	if steer.length() < 1.0 and desired_vel.length() < 1.0:
		actor.apply_control_input(0.0, 0.0, actor.rotation, 0, 1)
		actor.apply_rcs_input(Vector2.ZERO, 0.0)
		return SUCCESS
		
	# Command thrust to achieve the desired correction
	# We use max thrust for corrections (Steering mode 1, Linear mode 1 means target_velocity)
	# For small ships this works perfectly; for large stations RCS will do the work.
	actor.apply_control_input(0.0, steer.length(), steer.angle(), 1, 1)
	
	return SUCCESS

