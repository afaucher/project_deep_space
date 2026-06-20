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

# Sensor Signature Profile
var cross_section: float = 50.0  # Medium size
var base_heat: float = 10.0      # Idle systems
var em_noise: float = 5.0        # Comms/Reactor hum
var density: float = 90.0        # Solid armor

func get_signature() -> Dictionary:
	# Heat spikes when thrusting
	var current_heat = base_heat + (abs(actual_throttle) * 100.0)
	return {
		"pos": position,
		"rot": rotation,
		"vel": linear_velocity,
		"sensors": active_sensor_sweeps,
		"contacts": active_contacts
	}

func _ready() -> void:
	mass = 100.0
	inertia = 1000.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # No drag in space
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0 # No drag in space
	
	# Add collision shape so raycasts can hit the ship
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 50.0
	collision.shape = shape
	add_child(collision)

var sensor_hardware = [
	{
		"id": "omni_main",
		"range": 40000.0,
		"arc_width": TAU,
		"num_bins": 36,
		"interval": 2.0,
		"refresh_interval": 2.0,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0
	},
	{
		"id": "dir_high_res",
		"range": 40000.0,
		"arc_width": PI / 6.0, # 30 deg cone
		"num_bins": 30, # 1 deg bins
		"interval": 0.5,
		"refresh_interval": 0.5,
		"timer": 0.0,
		"heading": 0.0, # Can be steered
		"health": 100.0
	},
	{
		"id": "omni_short_hi_res",
		"range": 5000.0,
		"arc_width": TAU,
		"num_bins": 180, # 2 degree bins
		"interval": 0.25,
		"refresh_interval": 0.25,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0
	}
]

var active_sensor_sweeps = {} # Map of id -> bins
var active_contacts = {}
var next_contact_id: int = 1

var _high_res_target_idx: int = 0
var _high_res_target_timer: float = 0.0

func _physics_process(delta: float) -> void:
	var forward = Vector2.RIGHT.rotated(rotation)
	var current_forward_speed = linear_velocity.dot(forward)
	
	if linear_mode == 0:
		# Direct Throttle Control
		actual_throttle = target_thrust
	else:
		# Velocity Control (PID/Bang-Bang)
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
	
	var active_max_torque = 10000.0 if steering_mode == 1 else 2000.0
	var active_max_omega = 2.0 if steering_mode == 1 else 0.5
	
	var alpha_max = active_max_torque / inertia
	
	var target_omega = sign(angle_diff) * sqrt(2.0 * alpha_max * abs(angle_diff))
	target_omega = clampf(target_omega, -active_max_omega, active_max_omega)
	
	var omega_error = target_omega - angular_velocity
	var required_alpha = omega_error * 10.0 # Tuning factor for how aggressively to track the curve
	
	var torque = required_alpha * inertia
	torque = clampf(torque, -active_max_torque, active_max_torque)
	
	apply_torque(torque)
	
	# Auto-steer dir_high_res scanner based on omni_main contacts
	if active_sensor_sweeps.has("omni_main"):
		var omni_bins = active_sensor_sweeps["omni_main"]
		var enemy_bearings = []
		for bin in omni_bins:
			if bin.get("heat", 0.0) > 5.0 or bin.get("em_noise", 0.0) > 5.0:
				var angle = position.angle_to_point(bin["pos"])
				enemy_bearings.append(angle)
		
		var target_heading_val = rotation # Default to forward
		if enemy_bearings.size() > 0:
			_high_res_target_timer += delta
			if _high_res_target_timer > 3.0: # dwell time
				_high_res_target_timer -= 3.0
				_high_res_target_idx += 1
				
			if _high_res_target_idx >= enemy_bearings.size():
				_high_res_target_idx = 0
			
			target_heading_val = enemy_bearings[_high_res_target_idx]
			
		for s in sensor_hardware:
			if s["id"] == "dir_high_res":
				s["heading"] = target_heading_val
	
	# Decay contacts
	var to_remove = []
	for c_id in active_contacts:
		var c = active_contacts[c_id]
		c["last_seen_timer"] += delta
		if c["last_seen_timer"] > 10.0:
			to_remove.append(c_id)
	for c_id in to_remove:
		active_contacts.erase(c_id)
	
	var bins_this_frame = []

	# Sensor Sweeps
	for sensor in sensor_hardware:
		if sensor["health"] <= 0.0:
			continue
			
		sensor["timer"] -= delta
		if sensor["timer"] <= 0.0:
			sensor["timer"] = sensor["refresh_interval"]
			var bins = _run_sensor_sweep(sensor)
			active_sensor_sweeps[sensor["id"]] = bins
			bins_this_frame.append_array(bins)
			
	# Correlate tracks
	for bin in bins_this_frame:
		var closest_contact_id = ""
		var closest_dist = 2000.0 # 2km correlation threshold
		var bin_pos = bin.get("pos", Vector2.ZERO)
		
		for c_id in active_contacts:
			var c = active_contacts[c_id]
			var dist = c["pos"].distance_to(bin_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_contact_id = c_id
				
		if closest_contact_id != "":
			var c = active_contacts[closest_contact_id]
			var old_pos = c["pos"]
			c["pos"] = c["pos"].lerp(bin_pos, 0.8)
			
			if c["last_seen_timer"] > 0.01:
				var inst_vel = (c["pos"] - old_pos) / c["last_seen_timer"]
				c["vel"] = c["vel"].lerp(inst_vel, 0.5)
				
			c["signature"] = {
				"cross_section": bin.get("cross_section", 0.0),
				"heat": bin.get("heat", 0.0),
				"em_noise": bin.get("em_noise", 0.0),
				"density": bin.get("density", 0.0)
			}
			c["last_seen_timer"] = 0.0
			
			if c["signature"]["heat"] > 5.0 or c["signature"]["em_noise"] > 5.0:
				c["classification"] = "UNIDENTIFIED VESSEL"
			else:
				c["classification"] = "ASTEROID"
		else:
			var new_id = "TRK-%03d" % next_contact_id
			next_contact_id += 1
			
			var classification = "ASTEROID"
			if bin.get("heat", 0.0) > 5.0 or bin.get("em_noise", 0.0) > 5.0:
				classification = "UNIDENTIFIED VESSEL"
				
			active_contacts[new_id] = {
				"id": new_id,
				"pos": bin_pos,
				"vel": Vector2.ZERO,
				"signature": {
					"cross_section": bin.get("cross_section", 0.0),
					"heat": bin.get("heat", 0.0),
					"em_noise": bin.get("em_noise", 0.0),
					"density": bin.get("density", 0.0)
				},
				"last_seen_timer": 0.0,
				"classification": classification
			}

func _run_sensor_sweep(sensor: Dictionary) -> Array:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = sensor["range"]
	query.shape = shape
	query.transform = Transform2D(0, position)
	
	var results = space_state.intersect_shape(query, 128)
	
	var NUM_BINS = sensor["num_bins"]
	var ARC_WIDTH = sensor["arc_width"]
	var SENSOR_HEADING = sensor["heading"]
	var BIN_ANGLE = ARC_WIDTH / float(NUM_BINS)
	
	var bins = {}
	
	for hit in results:
		var collider = hit.collider
		if collider == self:
			continue
		
		if collider.has_method("get_signature"):
			var sig = collider.get_signature()
			var dist = position.distance_to(collider.position)
			var angle = position.angle_to_point(collider.position)
			
			var rel_angle = wrapf(angle - SENSOR_HEADING, -PI, PI)
			var half_arc = ARC_WIDTH / 2.0
			
			if rel_angle >= -half_arc and rel_angle <= half_arc:
				var cone_local_angle = rel_angle + half_arc
				var bin_idx = int(cone_local_angle / BIN_ANGLE)
				if bin_idx >= NUM_BINS: bin_idx = NUM_BINS - 1
				if bin_idx < 0: bin_idx = 0
				
				if not bins.has(bin_idx):
					bins[bin_idx] = []
				
				sig["_raw_pos"] = collider.position
				sig["_raw_dist"] = dist
				bins[bin_idx].append(sig)
	
	var sweep_output = []
	
	# Aggregate bins
	for bin_idx in bins.keys():
		var objects = bins[bin_idx]
		var merged = {
			"cross_section": 0.0,
			"heat": 0.0,
			"em_noise": 0.0,
			"density": 0.0,
			"count": objects.size()
		}
		
		var total_cs = 0.0
		var weighted_dist = 0.0
		
		for obj in objects:
			var cs = obj.get("cross_section", 1.0)
			merged["cross_section"] += cs
			merged["heat"] += obj.get("heat", 0.0)
			merged["em_noise"] += obj.get("em_noise", 0.0)
			
			total_cs += cs
			weighted_dist += obj["_raw_dist"] * cs
		
		if total_cs > 0:
			weighted_dist /= total_cs
			var total_density = 0.0
			for obj in objects:
				total_density += obj.get("density", 0.0) * obj.get("cross_section", 1.0)
			merged["density"] = total_density / total_cs
		else:
			weighted_dist = objects[0]["_raw_dist"]
			merged["density"] = objects[0].get("density", 0.0)
			
		var bin_center_angle = SENSOR_HEADING - (ARC_WIDTH / 2.0) + (bin_idx * BIN_ANGLE) + (BIN_ANGLE / 2.0)
		merged["distance"] = weighted_dist
		merged["pos"] = position + Vector2(weighted_dist, 0).rotated(bin_center_angle)
		merged["bin_idx"] = bin_idx
		merged["bin_angle"] = BIN_ANGLE
		merged["sensor_heading"] = SENSOR_HEADING
		merged["sensor_arc_width"] = ARC_WIDTH
		merged["sensor_range"] = sensor["range"]
		merged["sensor_id"] = sensor["id"]
		
		sweep_output.append(merged)
		
	return sweep_output


func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode
