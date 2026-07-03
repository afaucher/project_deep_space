extends Node
class_name NavAutopilot

# M17 -- flies a nav route on behalf of its parent ship. Lead-pursuit cruise to
# each waypoint, advance on arrival, and on reaching the destination disengage and
# arrest (hand back to the pilot). Reuses apply_control_input -- no new movement
# code. The player's helm should clear `active` on manual input (UI hook). See
# implementation_plans/m17_nav_routing_design.md.

const Steering = preload("res://scripts/ai/steering.gd")

const ARRIVAL_RADIUS := 800.0
const CRUISE_SPEED := 700.0

var route: Array = []
var index: int = 0
var active: bool = false

func engage(new_route: Array) -> void:
	route = new_route
	index = 0
	active = not new_route.is_empty()

func disengage() -> void:
	active = false

func _physics_process(_delta: float) -> void:
	if not active:
		return
	var ship = get_parent()
	if ship == null or route.is_empty() or index >= route.size():
		active = false
		return

	var wp: Vector2 = route[index]
	if ship.position.distance_to(wp) < ARRIVAL_RADIUS:
		index += 1
		if index >= route.size():
			# Arrived at the destination -> disengage and arrest (velocity mode, 0).
			active = false
			ship.apply_control_input(0.0, 0.0, ship.rotation, 1, 1)
			return
		wp = route[index]

	var desired: Vector2 = wp - ship.position
	if desired.length() > 0.01:
		desired = desired.normalized()
	# Avoid obstacles en route, but never the destination we're steering to.
	var avoided: Vector2 = Steering.steer(ship, desired, route[route.size() - 1])
	var desired_vel: Vector2 = avoided.normalized() * CRUISE_SPEED
	var steer: Vector2 = desired_vel - ship.linear_velocity
	if steer.length() < 10.0:
		steer = desired_vel
	ship.apply_control_input(0.0, CRUISE_SPEED, steer.angle(), 1, 1)
