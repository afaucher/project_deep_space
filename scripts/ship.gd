extends RigidBody2D
class_name Ship

var target_thrust: float = 0.0
var target_velocity: float = 0.0
var target_heading: float = 0.0
var steering_mode: int = 0 # 0 = Smooth, 1 = Combat
var linear_mode: int = 0 # 0 = Throttle, 1 = Velocity

var max_thrust: float = 5000.0
var max_torque: float = 5000.0
var max_speed: float = 1000.0

var actual_throttle: float = 0.0

func _ready() -> void:
	mass = 100.0
	inertia = 1000.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # No drag in space
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0 # No drag in space

func _physics_process(_delta: float) -> void:
	var forward = Vector2.RIGHT.rotated(rotation)
	var current_forward_speed = linear_velocity.dot(forward)
	
	if linear_mode == 0:
		# Direct Throttle Control
		actual_throttle = target_thrust
	else:
		# Velocity Control (PID/Bang-Bang)
		# Calculate thrust required to reach target_velocity.
		# Since mass is 100 and max_thrust is 5000, max acceleration is 50.
		# A simple proportional controller:
		var v_error = target_velocity - current_forward_speed
		var required_accel = v_error * 2.0 # P gain
		var required_force = required_accel * mass
		actual_throttle = required_force / max_thrust
		actual_throttle = clampf(actual_throttle, -1.0, 1.0)
	
	if actual_throttle != 0.0:
		apply_central_force(forward * actual_throttle * max_thrust)
		
	# Enforce absolute speed limit (Reactor Safety Governor)
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	# Time-Optimal Rotational Controller (Square-root curve braking)
	var angle_diff = wrapf(target_heading - rotation, -PI, PI)
	
	# Differentiate power/speed limits based on mode
	var active_max_torque = 10000.0 if steering_mode == 1 else 2000.0
	var active_max_omega = 2.0 if steering_mode == 1 else 0.5
	
	var alpha_max = active_max_torque / inertia
	
	# Calculate the ideal velocity to arrive at the target exactly
	var target_omega = sign(angle_diff) * sqrt(2.0 * alpha_max * abs(angle_diff))
	target_omega = clampf(target_omega, -active_max_omega, active_max_omega)
	
	# Use a proportional controller to track the ideal velocity curve smoothly without jitter
	var omega_error = target_omega - angular_velocity
	var required_alpha = omega_error * 10.0 # Tuning factor for how aggressively to track the curve
	
	var torque = required_alpha * inertia
	torque = clampf(torque, -active_max_torque, active_max_torque)
	
	apply_torque(torque)

func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode
