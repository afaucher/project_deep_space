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

var weapons = {
	"laser_head": {
		"ammo": 10,
		"cooldown": 0.0,
		"cooldown_max": 5.0
	},
	"ship_laser": {
		"ammo": 999,
		"cooldown": 0.0,
		"cooldown_max": 1.0,
		"range": 4000.0,
		"arc_width": PI / 3.0, # 60 degrees forward
		"damage": 500.0
	}
}

var point_defense_active: bool = true

# Sensor Signature Profile
var cross_section: float = 50.0  # Medium size
var base_heat: float = 10.0      # Idle systems
var em_noise: float = 5.0        # Comms/Reactor hum
var density: float = 90.0        # Solid armor

var health: float = 5000.0
var is_dead: bool = false

var sfx_engine: AudioStreamPlayer
var sfx_rcs: AudioStreamPlayer
var sfx_laser: AudioStreamPlayer
var sfx_missile: AudioStreamPlayer

func take_damage(amount: float) -> void:
	if is_dead: return
	health -= amount
	if health <= 0:
		hulk()

func hulk() -> void:
	is_dead = true
	base_heat = 0.0
	em_noise = 0.0
	# Broadcast a neutral ID so allies don't see it as friendly anymore?
	# Or keep owner_id but with zero emissions so it's clearly wreckage

func get_signature() -> Dictionary:
	# Heat spikes when thrusting
	var current_heat = base_heat
	if not is_dead:
		current_heat += (abs(actual_throttle) * 100.0)
		
	return {
		"cross_section": cross_section,
		"heat": current_heat,
		"em_noise": em_noise,
		"density": density,
		"owner_id": int(name.replace("Ship_", "")),
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
	
	sfx_engine = AudioStreamPlayer.new()
	var e_stream = load("res://assets/audio/engine.wav")
	if e_stream and e_stream is AudioStreamWAV: e_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sfx_engine.stream = e_stream
	add_child(sfx_engine)
	
	sfx_rcs = AudioStreamPlayer.new()
	var r_stream = load("res://assets/audio/rcs.wav")
	if r_stream and r_stream is AudioStreamWAV: r_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sfx_rcs.stream = r_stream
	add_child(sfx_rcs)
	
	sfx_laser = AudioStreamPlayer.new()
	sfx_laser.stream = load("res://assets/audio/laser.wav")
	add_child(sfx_laser)
	
	sfx_missile = AudioStreamPlayer.new()
	sfx_missile.stream = load("res://assets/audio/missile_launch.wav")
	add_child(sfx_missile)

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

var manual_sensor_target: String = ""

@rpc("any_peer", "call_local")
func set_sensor_target(target_id: String) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_remote_sender_id() != int(name.replace("Ship_", "")) and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0: pass
	manual_sensor_target = target_id

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	if is_multiplayer_authority():
		for w in weapons.keys():
			if weapons[w]["cooldown"] > 0:
				weapons[w]["cooldown"] -= delta
		
		if point_defense_active:
			_process_point_defense()
			
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
	
	var is_my_ship = (multiplayer.get_unique_id() == int(name.replace("Ship_", "")))
	
	if actual_throttle != 0.0:
		apply_central_force(forward * actual_throttle * max_thrust)
		if is_my_ship and not sfx_engine.playing:
			sfx_engine.play()
	else:
		if sfx_engine.playing:
			sfx_engine.stop()
		
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
	
	if abs(torque) > 100.0:
		if is_my_ship and not sfx_rcs.playing:
			sfx_rcs.play()
	else:
		if sfx_rcs.playing:
			sfx_rcs.stop()
	
	# Auto-steer dir_high_res scanner based on omni_main contacts
	var target_heading_val = rotation # Default to forward
	
	if manual_sensor_target != "" and active_contacts.has(manual_sensor_target):
		target_heading_val = position.angle_to_point(active_contacts[manual_sensor_target]["pos"])
	elif active_sensor_sweeps.has("omni_main"):
		var omni_bins = active_sensor_sweeps["omni_main"]
		var enemy_bearings = []
		for bin in omni_bins:
			if bin.get("heat", 0.0) > 5.0 or bin.get("em_noise", 0.0) > 5.0:
				var angle = position.angle_to_point(bin["pos"])
				enemy_bearings.append(angle)
		
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
	
	# Decay and dead-reckon contacts
	var to_remove = []
	for c_id in active_contacts:
		var c = active_contacts[c_id]
		c["last_seen_timer"] += delta
		
		# Dead-reckon their position based on velocity
		if c.has("vel") and typeof(c["vel"]) == TYPE_VECTOR2:
			c["pos"] += c["vel"] * delta
			
		if c["last_seen_timer"] > 20.0:
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
			c["pos"] = c["pos"].lerp(bin_pos, 0.8)
			c["vel"] = c["vel"].lerp(bin.get("vel", Vector2.ZERO), 0.8)
				
			c["signature"] = {
				"cross_section": bin.get("cross_section", 0.0),
				"heat": bin.get("heat", 0.0),
				"em_noise": bin.get("em_noise", 0.0),
				"density": bin.get("density", 0.0),
				"owner_id": bin.get("owner_id", -1)
			}
			c["last_seen_timer"] = 0.0
			
			if c["signature"]["heat"] > 5.0 or c["signature"]["em_noise"] > 5.0:
				if c["signature"].get("owner_id", -1) == int(name.replace("Ship_", "")):
					c["classification"] = "FRIENDLY ORDNANCE"
				else:
					c["classification"] = "UNIDENTIFIED VESSEL"
			else:
				# TODO: Revisit classification matrix when we have a richer body of objects
				if c["signature"].get("density", 500.0) <= 150.0:
					c["classification"] = "WRECKAGE"
				else:
					c["classification"] = "ASTEROID"
		else:
			var new_id = "TRK-%03d" % next_contact_id
			next_contact_id += 1
			
			var owner_id = bin.get("owner_id", -1)
			var classification = "ASTEROID"
			if bin.get("heat", 0.0) > 5.0 or bin.get("em_noise", 0.0) > 5.0:
				if owner_id == int(name.replace("Ship_", "")):
					classification = "FRIENDLY ORDNANCE"
				else:
					classification = "UNIDENTIFIED VESSEL"
			else:
				# TODO: Revisit classification matrix when we have a richer body of objects
				if bin.get("density", 500.0) <= 150.0:
					classification = "WRECKAGE"
				
			active_contacts[new_id] = {
				"id": new_id,
				"pos": bin_pos,
				"vel": bin.get("vel", Vector2.ZERO),
				"signature": {
					"cross_section": bin.get("cross_section", 0.0),
					"heat": bin.get("heat", 0.0),
					"em_noise": bin.get("em_noise", 0.0),
					"density": bin.get("density", 0.0),
					"owner_id": owner_id
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
		var weighted_vel = Vector2.ZERO
		var bin_owner = -1
		
		for obj in objects:
			var cs = obj.get("cross_section", 1.0)
			merged["cross_section"] += cs
			merged["heat"] += obj.get("heat", 0.0)
			merged["em_noise"] += obj.get("em_noise", 0.0)
			if obj.has("owner_id"):
				bin_owner = obj["owner_id"]
			
			total_cs += cs
			weighted_dist += obj["_raw_dist"] * cs
			weighted_vel += obj.get("vel", Vector2.ZERO) * cs
		
		if total_cs > 0:
			weighted_dist /= total_cs
			weighted_vel /= total_cs
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
		
		# Cheat velocity with noise
		var noisy_vel = weighted_vel * (1.0 + randf_range(-0.05, 0.05))
		noisy_vel = noisy_vel.rotated(randf_range(-0.05, 0.05))
		merged["vel"] = noisy_vel
		
		merged["bin_idx"] = bin_idx
		merged["bin_angle"] = BIN_ANGLE
		merged["sensor_heading"] = SENSOR_HEADING
		merged["sensor_arc_width"] = ARC_WIDTH
		merged["sensor_range"] = sensor["range"]
		merged["sensor_id"] = sensor["id"]
		merged["owner_id"] = bin_owner
		
		sweep_output.append(merged)
		
	return sweep_output

@rpc("any_peer", "call_local")
func fire_weapon(weapon_id: String, target_pos: Vector2, target_contact_id: String) -> void:
	if not is_multiplayer_authority():
		return # Only host executes this
		
	# Verify client owns this ship
	if multiplayer.get_remote_sender_id() != int(name.replace("Ship_", "")) and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
			
	if not weapons.has(weapon_id): return
	if weapons[weapon_id]["ammo"] <= 0: return
	if weapons[weapon_id]["cooldown"] > 0: return
	
	if weapon_id == "ship_laser":
		if not active_contacts.has(target_contact_id): return
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
		# Hitscan weapon, must be within arc and range
		var dist = position.distance_to(real_target_pos)
		if dist > weapons["ship_laser"]["range"]: return
		
		var angle_to = position.angle_to_point(real_target_pos)
		var rel_angle = wrapf(angle_to - rotation, -PI, PI)
		if abs(rel_angle) > weapons["ship_laser"]["arc_width"] / 2.0: return
		
		weapons[weapon_id]["ammo"] -= 1
		weapons[weapon_id]["cooldown"] = weapons[weapon_id]["cooldown_max"]
		
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_laser.play()
		
		# Find the actual body
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 50.0
		query.shape = shape
		query.transform = Transform2D(0, real_target_pos)
		
		var results = space_state.intersect_shape(query, 32)
		for res in results:
			var body = res["collider"]
			if body == self: continue
			if body.has_method("take_damage"):
				body.take_damage(weapons["ship_laser"]["damage"])
			elif body.has_method("get_signature"):
				body.queue_free()
	
	elif weapon_id == "laser_head":
		weapons[weapon_id]["ammo"] -= 1
		weapons[weapon_id]["cooldown"] = weapons[weapon_id]["cooldown_max"]
		
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_missile.play()
		
		var main_node = get_tree().current_scene
		if not is_instance_valid(main_node): return
		
		var Projectile = load("res://scripts/projectile.gd")
		var proj = Projectile.new()
		
		var spawn_pos = position + Vector2(100, 0).rotated(rotation)
		var initial_vel = linear_velocity
		
		var target_profile = {}
		var launch_angle = rotation
		if active_contacts.has(target_contact_id):
			target_profile = active_contacts[target_contact_id]["signature"]
			launch_angle = position.angle_to_point(active_contacts[target_contact_id]["pos"])
		
		proj.setup(int(name.replace("Ship_", "")), spawn_pos, initial_vel, launch_angle)
		proj.target_profile = target_profile
		main_node.add_child(proj)

func _process_point_defense() -> void:
	if weapons["ship_laser"]["cooldown"] > 0: return
	
	# Scan for incoming projectiles within 4000m
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = weapons["ship_laser"]["range"]
	query.shape = shape
	query.transform = Transform2D(0, position)
	
	var results = space_state.intersect_shape(query, 128)
	for res in results:
		var body = res["collider"]
		if body == self: continue
		if body is LaserHead:
			var sig = body.get_signature()
			if sig.has("owner_id") and sig["owner_id"] != int(name.replace("Ship_", "")):
				# It is hostile.
				# Verify it's within the laser's firing arc
				var angle_to = position.angle_to_point(body.position)
				var rel_angle = wrapf(angle_to - rotation, -PI, PI)
				if abs(rel_angle) <= weapons["ship_laser"]["arc_width"] / 2.0:
					# Fire point defense
					weapons["ship_laser"]["cooldown"] = weapons["ship_laser"]["cooldown_max"]
					if body.has_method("take_damage"):
						body.take_damage(weapons["ship_laser"]["damage"])
					else:
						body.queue_free()
					break # Can only shoot one per cooldown



func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode
