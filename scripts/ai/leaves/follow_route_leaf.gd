extends "res://addons/beehave/nodes/leaves/action.gd"

# M18 -- patrol/route following. Steers along patrol_route in cruise mode,
# advancing to the next waypoint on arrival and looping at the end. Ship/obstacle
# avoidance comes from the shared Steering layer (see
# design_ideas/collision_avoidance.md). Returns FAILURE with no route so the
# parent selector falls through to Idle.

const Steering = preload("res://scripts/ai/steering.gd")

const ARRIVAL_RADIUS := 900.0    # advance to next waypoint within this
const CRUISE_SPEED := 400.0      # steady patrol speed (velocity mode)

func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return FAILURE
	var route: Array = actor.patrol_route
	if route.is_empty():
		return FAILURE

	var idx: int = actor.patrol_index
	if idx < 0 or idx >= route.size():
		idx = 0
	var wp: Vector2 = route[idx]

	# Arrived -> advance (loop, or clamp at the end for a one-shot route).
	if actor.position.distance_to(wp) < ARRIVAL_RADIUS:
		if actor.patrol_loop:
			idx = (idx + 1) % route.size()
		else:
			idx = min(idx + 1, route.size() - 1)
		actor.patrol_index = idx
		wp = route[idx]

	# Heading toward the waypoint, bent by avoidance, then drift-cancelled (lead
	# pursuit) so momentum doesn't carry the hull wide of the corner.
	var desired: Vector2 = wp - actor.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	var avoided: Vector2 = Steering.steer(actor, desired, null)
	var desired_vel: Vector2 = avoided.normalized() * CRUISE_SPEED
	var steer: Vector2 = desired_vel - actor.linear_velocity
	if steer.length() < 10.0:
		steer = desired_vel
	actor.apply_control_input(0.0, CRUISE_SPEED, steer.angle(), 1, 1)
	return SUCCESS
