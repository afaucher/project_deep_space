extends "res://addons/beehave/nodes/leaves/action.gd"

# M20 -- cargo run: drive a shuttle around its lane (patrol_route = station
# positions), docking at each stop, then moving on. Two states per stop:
# TRANSIT (cruise to the station) and DOCKING (yield to the station's berth while
# it captures/holds/releases us). Returns FAILURE with no route so the selector
# falls through to Idle. See implementation_plans/m20_traffic_wiring_design.md.

const Steering = preload("res://scripts/ai/steering.gd")

const DOCK_REQUEST_RADIUS := 4000.0   # raise the dock request within this of the station
const CARGO_CRUISE := 700.0           # transit speed

func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return FAILURE
	var route: Array = actor.patrol_route
	if route.is_empty():
		return FAILURE
	var idx: int = actor.patrol_index
	if idx < 0 or idx >= route.size():
		idx = 0
	var target: Vector2 = route[idx]

	if not actor.cargo_docking:
		# TRANSIT to the current station.
		if actor.position.distance_to(target) < DOCK_REQUEST_RADIUS:
			actor.cargo_docking = true
			actor.cargo_captured_seen = false
			actor.wants_dock = true
		else:
			_cruise_to(actor, target)
		return SUCCESS

	# DOCKING at the current station.
	if actor.docking_bay != null:
		# Captured -> yield: coast so the berth spring owns the motion.
		actor.cargo_captured_seen = true
		actor.apply_control_input(0.0, 0.0, actor.rotation, 0, 0)
	elif actor.cargo_captured_seen and not actor.wants_dock:
		# The bay finished its load/unload cycle and released us -> next station.
		if actor.patrol_loop:
			idx = (idx + 1) % route.size()
		else:
			idx = min(idx + 1, route.size() - 1)
		actor.patrol_index = idx
		actor.cargo_docking = false
	else:
		# Requested but not yet berthed (waiting for a free berth) -> hold near the
		# approach point rather than drifting off or ramming the station.
		actor.apply_control_input(0.0, 0.0, (target - actor.position).angle(), 1, 1)
	return SUCCESS

func _cruise_to(actor: Node, target: Vector2) -> void:
	var desired: Vector2 = target - actor.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	# Avoid obstacles in transit, but not the destination station itself.
	var avoided: Vector2 = Steering.steer(actor, desired, target)
	var desired_vel: Vector2 = avoided.normalized() * CARGO_CRUISE
	var steer: Vector2 = desired_vel - actor.linear_velocity
	if steer.length() < 10.0:
		steer = desired_vel
	actor.apply_control_input(0.0, CARGO_CRUISE, steer.angle(), 1, 1)
