extends "res://addons/beehave/nodes/leaves/action.gd"

const Steering = preload("res://scripts/ai/steering.gd")

var _hold_pos: Vector2 = Vector2.ZERO
var _hold_rot: float = 0.0
var _initialized: bool = false

# Station Keeping: Uses RCS/engines to maintain an exact global position AND
# attitude. Mobile ships will dodge obstacles and return to their hold
# coordinate. Massive structures will simply soak hits and re-center.
#
# Attitude matters as much as position: a station's DockingBay berth poses
# rotate with the hull, so a station left spinning (e.g. clipped by a cargo
# shuttle) turns every capture into an endless orbit-chase -- the servo drags
# the ship after a berth that never stops moving, CAPTURING never settles,
# and the berth pool wedges shut ("no open berths" forever). Holding the
# INITIAL rotation (not actor.rotation, which spins along with the hull and
# holds nothing) is what lets the attitude controller actively despin.
func tick(actor: Node, _blackboard) -> int:
	if actor == null:
		return SUCCESS

	if not _initialized:
		_hold_pos = actor.position
		_hold_rot = actor.rotation
		_initialized = true
		
	var to_hold = _hold_pos - actor.position
	var dist = to_hold.length()
	
	var desired_vel = Vector2.ZERO
	if dist > 5.0:
		# Cruise back to station at a modest speed, slowing as we get close
		desired_vel = to_hold.normalized() * min(dist * 0.1, 100.0)
		
	# Apply collision avoidance on top of our desired velocity, but only for mobile 
	# ships. Large structures (like AsteroidStations and Hubs) are too massive to dodge.
	var avoid_vec = Vector2.ZERO
	if actor.get("ship_tier") != null and actor.ship_tier != 4: # 4 is ComponentSpec.Tier.STRUCTURE
		avoid_vec = Steering._avoidance(actor, Vector2.INF)["vec"]
	
	if avoid_vec.length() > 0.1:
		# Use a stronger dodge velocity so slow-accelerating ships clear in time
		var combined = desired_vel.normalized() + avoid_vec
		desired_vel = combined.normalized() * max(desired_vel.length(), 400.0)
		
	var steer = desired_vel - actor.linear_velocity
	
	# If we are basically on station and not moving, hold the ORIGINAL
	# attitude (never actor.rotation -- that target spins with the hull and
	# corrects nothing; see the despin note above).
	if steer.length() < 1.0 and desired_vel.length() < 1.0:
		actor.apply_control_input(0.0, 0.0, _hold_rot, 0, 1)
		actor.apply_rcs_input(Vector2.ZERO, 0.0)
		return SUCCESS
		
	# Command thrust to achieve the desired correction
	# We use max thrust for corrections (Steering mode 1, Linear mode 1 means target_velocity)
	# For small ships this works perfectly; for large stations RCS will do the work.
	var thrust_speed = max(steer.length(), desired_vel.length())
	if Engine.get_process_frames() % 60 == 0:
		print("[", actor.name, "] steer: ", steer, " desired: ", desired_vel, " thrust_spd: ", thrust_speed, " v: ", actor.linear_velocity, " pos: ", actor.position)
		
	var s_mode = 1 if avoid_vec.length() > 0.1 else 0
	
	var angle_diff = wrapf(steer.angle() - actor.rotation, -PI, PI)
	if abs(angle_diff) > PI / 4.0:
		# We are facing the wrong way. Turn first without thrusting to avoid cross-coupling errors.
		# Using LinearMode 0 (Direct Throttle) with 0.0 thrust to guarantee we just turn.
		actor.apply_control_input(0.0, 0.0, steer.angle(), s_mode, 0)
	else:
		actor.apply_control_input(0.0, thrust_speed, steer.angle(), s_mode, 1)
		
	if actor.get("ship_tier") != null and actor.ship_tier == 4: # ComponentSpec.Tier.STRUCTURE
		actor.apply_rcs_input(steer.normalized(), 0.0)
	
	return SUCCESS

