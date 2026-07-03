extends "res://addons/beehave/nodes/leaves/action.gd"

# M18 -- patrol/route following. Steers the actor along its patrol_route (a list
# of world-space waypoints) in cruise mode, advancing to the next waypoint on
# arrival and looping at the end. Blends in ship-ship separation so patrols don't
# slam into each other. Returns FAILURE when the actor has no route, so the parent
# selector falls through to Idle. See implementation_plans/m18_patrol_ai_design.md.

const ARRIVAL_RADIUS := 900.0    # advance to next waypoint within this (> turn radius so a heavy hull that overshoots the corner still counts as arrived)
const CRUISE_SPEED := 400.0      # steady patrol speed (velocity mode); low enough that even a frigate corners inside ARRIVAL_RADIUS
const AVOID_RADIUS := 600.0      # start steering away from a ship this close
const AVOID_WEIGHT := 2.0        # how hard separation bends the heading

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

	# Compute steering vector that cancels lateral drift (Flight Assist/Lead Pursuit).
	var desired: Vector2 = wp - actor.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	
	var desired_vel: Vector2 = (desired + _separation(actor) * AVOID_WEIGHT) * CRUISE_SPEED
	var steer: Vector2 = desired_vel - actor.linear_velocity
	
	if steer.length() < 10.0:
		# If our velocity is already correct, point the nose where we're going
		steer = desired_vel

	actor.apply_control_input(0.0, CRUISE_SPEED, steer.angle(), 1, 1)
	return SUCCESS

func _separation(actor: Node) -> Vector2:
	var sep := Vector2.ZERO
	for other in actor.get_tree().get_nodes_in_group("ships"):
		if other == actor:
			continue
		var away: Vector2 = actor.position - other.position
		var d: float = away.length()
		if d > 0.01 and d < AVOID_RADIUS:
			sep += away.normalized() * ((AVOID_RADIUS - d) / AVOID_RADIUS)
	return sep
