extends "res://addons/beehave/nodes/leaves/action.gd"

# M12 steer_to_target: a faithful port of the legacy controller's range-band maneuver --
# close in beyond 10 km, hold station 5-10 km, back off inside 5 km -- always pointing
# the nose at the target. Posture-aware orientation (turning to bring a broadside to
# bear) is deliberately deferred to M12c; this slice only changes WEAPON employment, not
# maneuver. Returns SUCCESS every tick so the parent sequence flows on to firing.
const CLOSE_RANGE := 10000.0
const STANDOFF_RANGE := 5000.0
const APPROACH_SPEED := 800.0
const BACKOFF_SPEED := 200.0

func tick(actor: Node, blackboard) -> int:
	if not blackboard.has_value("target_pos"):
		return SUCCESS

	var target_pos = blackboard.get_value("target_pos")
	var heading = (target_pos - actor.position).angle()
	var dist = actor.position.distance_to(target_pos)

	var thrust := 0.0
	var target_vel := 0.0
	if dist > CLOSE_RANGE:
		thrust = 1.0
		target_vel = APPROACH_SPEED
	elif dist < STANDOFF_RANGE:
		thrust = -1.0
		target_vel = BACKOFF_SPEED

	# steering_mode 1 = auto-steer toward heading, linear_mode 1 = flight assist
	# (identical to the legacy controller's call).
	actor.apply_control_input(thrust, target_vel, heading, 1, 1)
	return SUCCESS
