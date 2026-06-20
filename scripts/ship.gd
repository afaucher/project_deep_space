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
	"hp_fwd_laser": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": 0.0, "arc_width": PI / 3.0, "mount_pos": Vector2(30, -7.5) },
	"hp_fwd_missile": { "type": "missile", "ammo": 10, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": 0.0, "arc_width": PI / 3.0, "mount_pos": Vector2(30, 2.5) },
	
	"hp_port_laser_1": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(17.5, -20) },
	"hp_port_tube_1": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(7.5, -30) },
	"hp_port_tube_2": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-2.5, -30) },
	"hp_port_tube_3": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-12.5, -30) },
	"hp_port_laser_2": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-22.5, -20) },

	"hp_stbd_laser_1": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(17.5, 15) },
	"hp_stbd_tube_1": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(7.5, 15) },
	"hp_stbd_tube_2": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-2.5, 15) },
	"hp_stbd_tube_3": { "type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-12.5, 15) },
	"hp_stbd_laser_2": { "type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0, "mount_pos": Vector2(-22.5, 15) }
}

var point_defense_active: bool = true

# Engineering / Subsystems
var subsystems: Dictionary = {
	"reactor": {"power": 1.0},
	"engines": {"power": 1.0},
	"weapons": {"power": 1.0},
	"sensors": {"power": 1.0}
}

var ship_components: Array = [
	# Layout relative to center (0,0). Forward +X, Right +Y
	{"id": "hull_fwd", "type": "hull", "rect": Rect2(15, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hull_aft", "type": "hull", "rect": Rect2(-30, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	
	{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 200.0, "max_health": 200.0, "density": 0.9, "heat": 0.0, "em_emission": 0.0},
	{"id": "engine_main", "type": "engines", "rect": Rect2(-35, -10, 5, 20), "health": 300.0, "max_health": 300.0, "density": 0.7, "heat": 0.0, "em_emission": 0.0},
	
	{"id": "hp_sensor_fwd", "type": "sensors", "rect": Rect2(30, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 0.4, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_sensor_omni", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 0.4, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(30, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(30, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(17.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(7.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-2.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-12.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-22.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},

	{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(17.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(7.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-2.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-12.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
	{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-22.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0}
]

var current_heat: float = 10.0
var max_heat: float = 200.0
var heat_dissipation_rate: float = 5.0
var current_heat_gen: float = 0.0
var silent_running: bool = false
var is_dead: bool = false
var em_signature: float = 0.0

func get_sys_health(sys_type: String) -> float:
	var h = 0.0
	for c in ship_components:
		if c["type"] == sys_type:
			h += max(0.0, c["health"])
	return h

func get_sys_max_health(sys_type: String) -> float:
	var h = 0.0
	for c in ship_components:
		if c["type"] == sys_type:
			h += c["max_health"]
	return h

# Legacy getters
var health: float:
	get: return get_sys_health("hull")
	set(value): pass # Obsolete, damage uses volumetric now

var base_heat: float:
	get: return current_heat

var em_noise: float:
	get: 
		if silent_running: return 1.0
		var noise = 5.0 * subsystems["reactor"]["power"]
		if point_defense_active: noise += 15.0
		for s in sensor_hardware:
			if s.get("active", true): noise += 5.0
		return noise

# Sensor Signature Profile
var cross_section: float = 50.0  # Medium size
var density: float = 90.0        # Solid armor

var sfx_engine: AudioStreamPlayer
var sfx_rcs: AudioStreamPlayer
var sfx_laser: AudioStreamPlayer
var sfx_missile: AudioStreamPlayer

func take_damage(amount: float, global_pos: Vector2 = Vector2.ZERO, global_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead: return
	
	if global_pos == Vector2.ZERO and global_dir == Vector2.ZERO:
		# Fallback for untracked damage
		for c in ship_components:
			if c["type"] == "hull":
				c["health"] -= amount / 4.0
	else:
		# Volumetric Raycast Damage
		var local_pos = to_local(global_pos)
		var local_dir = global_dir.rotated(-rotation)
		
		var remaining_damage = amount
		var step_size = 2.0
		var max_steps = 100
		var current_pos = local_pos
		
		for i in range(max_steps):
			if remaining_damage <= 0: break
			
			for comp in ship_components:
				if comp["health"] <= 0: continue
				if comp["rect"].has_point(current_pos):
					# Damping/Ablation based on density
					var dmg_absorbed = min(remaining_damage, comp["density"] * step_size * 50.0)
					if dmg_absorbed > 0:
						comp["health"] -= dmg_absorbed
						var heat_generated = dmg_absorbed * 0.1
						comp["heat"] = comp.get("heat", 0.0) + heat_generated
						current_heat += heat_generated
						remaining_damage -= dmg_absorbed
			
			current_pos += local_dir * step_size
			
	# Check death condition (reactor dead)
	if get_sys_health("reactor") <= 0.0 or get_sys_health("hull") <= 0.0:
		hulk()

func hulk() -> void:
	is_dead = true
	current_heat = 0.0
	# Broadcast a neutral ID so allies don't see it as friendly anymore?
	# Or keep owner_id but with zero emissions so it's clearly wreckage

func get_signature() -> Dictionary:
	return {
		"cross_section": cross_section,
		"heat": current_heat,
		"em_noise": em_signature,
		"density": density,
		"owner_id": int(name.replace("Ship_", "")),
		"pos": position,
		"rot": rotation,
		"vel": linear_velocity,
		"sensors": active_sensor_sweeps,
		"sensor_config": sensor_hardware,
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
		"type": "active",
		"active": true,
		"range": 40000.0,
		"arc_width": TAU,
		"num_bins": 36,
		"interval": 2.0,
		"refresh_interval": 2.0,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0,
		"em_emission": 20.0
	},
	{
		"id": "dir_high_res",
		"type": "active",
		"active": true,
		"range": 40000.0,
		"arc_width": PI / 6.0, # 30 deg cone
		"num_bins": 30, # 1 deg bins
		"interval": 0.5,
		"refresh_interval": 0.5,
		"timer": 0.0,
		"heading": 0.0, # Can be steered
		"health": 100.0,
		"em_emission": 100.0
	},
	{
		"id": "omni_short_hi_res",
		"type": "active",
		"active": true,
		"range": 5000.0,
		"arc_width": TAU,
		"num_bins": 180, # 2 degree bins
		"interval": 0.25,
		"refresh_interval": 0.25,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0,
		"em_emission": 10.0
	},
	{
		"id": "passive_em",
		"type": "passive_em",
		"active": true,
		"range": 80000.0,
		"arc_width": TAU,
		"num_bins": 360,
		"interval": 1.0,
		"refresh_interval": 1.0,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0
	},
	{
		"id": "omni_collision",
		"type": "active",
		"active": true,
		"range": 1500.0,
		"arc_width": TAU,
		"num_bins": 8,
		"interval": 0.5,
		"refresh_interval": 0.1,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0,
		"em_emission": 0.0
	}
]

var active_sensor_sweeps = {} # Map of id -> bins
var active_contacts = {}
var next_contact_id: int = 1

var _high_res_target_idx: int = 0
var _high_res_target_timer: float = 0.0

var manual_sensor_target: String = ""

@rpc("any_peer", "call_local")
func set_sensor_state(sensor_id: String, is_active: bool) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_remote_sender_id() != int(name.replace("Ship_", "")) and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
	for s in sensor_hardware:
		if s["id"] == sensor_id:
			s["active"] = is_active
			break

@rpc("any_peer", "call_local")
func set_all_sensors_state(is_active: bool) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_remote_sender_id() != int(name.replace("Ship_", "")) and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
	for s in sensor_hardware:
		s["active"] = is_active

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
	
	# Enforce absolute speed limit (Reactor Safety Governor)
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	# Time-Optimal Rotational Controller (Square-root curve braking)
	var angle_diff = wrapf(target_heading - rotation, -PI, PI)
	
	var active_engine_efficiency = (get_sys_health("engines") / max(1.0, get_sys_max_health("engines"))) * subsystems["engines"]["power"]
	var active_max_torque = (10000.0 if steering_mode == 1 else 2000.0) * active_engine_efficiency
	var active_max_omega = (2.0 if steering_mode == 1 else 0.5) * active_engine_efficiency
	
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
	
	# Pin dir_high_res scanner to forward
	for s in sensor_hardware:
		if s["id"] == "dir_high_res":
			s["heading"] = rotation
	
	# Decay and dead-reckon contacts
	var to_remove = []
	for c_id in active_contacts:
		var c = active_contacts[c_id]
		c["last_seen_timer"] += delta
		c["pos_timer"] += delta
		
		# Dead-reckon their position based on velocity
		if c.has("vel") and typeof(c["vel"]) == TYPE_VECTOR2:
			c["pos"] += c["vel"] * delta
			
		if c["last_seen_timer"] > 20.0:
			to_remove.append(c_id)
	for c_id in to_remove:
		active_contacts.erase(c_id)
	
	var bins_this_frame = []

	# --- Heat & Engineering Logic ---
	if is_multiplayer_authority() and not is_dead:
		var heat_gen = 0.0
		var reactor_heat = 2.0 * subsystems["reactor"]["power"]
		var engine_heat = abs(actual_throttle) * 10.0 * subsystems["engines"]["power"]
		engine_heat += (abs(torque) / max(1.0, active_max_torque)) * 5.0 * subsystems["engines"]["power"]
		
		heat_gen = reactor_heat + engine_heat
		current_heat_gen = heat_gen
		
		current_heat += heat_gen * delta
		current_heat -= heat_dissipation_rate * delta
		current_heat = clampf(current_heat, 0.0, max_heat)
		
		if current_heat >= max_heat:
			for c in ship_components:
				if c["id"] == "reactor":
					c["health"] -= 10.0 * delta
					
		# Update Component EM & Heat
		var current_em = 100.0 + (abs(actual_throttle) * 100.0)
		var sensor_em = 0.0
		for s in sensor_hardware:
			if s.get("active", true):
				sensor_em += s.get("em_emission", 0.0)
		
		em_signature = current_em
		
		for comp in ship_components:
			if comp["type"] == "reactor":
				comp["heat"] = 10.0 + reactor_heat
				comp["em_emission"] = 100.0
			elif comp["type"] == "engines":
				comp["heat"] = engine_heat
				comp["em_emission"] = abs(actual_throttle) * 100.0
			elif comp["type"] == "sensors":
				comp["heat"] = 5.0
				comp["em_emission"] = sensor_em
			else:
				comp["heat"] = 0.0
				comp["em_emission"] = 0.0

	# Sensor Sweeps
	var active_sensor_efficiency = (get_sys_health("sensors") / max(1.0, get_sys_max_health("sensors"))) * subsystems["sensors"]["power"]
	
	for sensor in sensor_hardware:
		if sensor["health"] <= 0.0 or active_sensor_efficiency <= 0.1:
			continue
		if not sensor.get("active", true):
			active_sensor_sweeps[sensor["id"]] = []
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
		var bin_pos = bin.get("pos", Vector2.ZERO)
		var bin_instance_id = bin.get("instance_id", -1)
		var new_id = ""
		
		if bin_instance_id != -1:
			new_id = "TRK-%03d" % (abs(bin_instance_id) % 1000)
			if active_contacts.has(new_id):
				closest_contact_id = new_id
		else:
			var closest_dist = 2000.0 # 2km correlation threshold
			for c_id in active_contacts:
				var c = active_contacts[c_id]
				var dist = c["pos"].distance_to(bin_pos)
				if dist < closest_dist:
					closest_dist = dist
					closest_contact_id = c_id
				
		if closest_contact_id != "":
			var c = active_contacts[closest_contact_id]
			var bin_angle = bin.get("bin_angle", TAU)
			var current_res = c.get("resolution", TAU)
			var time_since_pos = c.get("pos_timer", 0.0)
			
			if bin_angle <= current_res or time_since_pos > 0.3:
				c["pos"] = c["pos"].lerp(bin_pos, 0.8)
				c["vel"] = c["vel"].lerp(bin.get("vel", Vector2.ZERO), 0.8)
				c["resolution"] = bin_angle
				c["pos_timer"] = 0.0
				
				c["signature"] = {
					"cross_section": bin.get("cross_section", 0.0),
					"heat": bin.get("heat", 0.0),
					"em_noise": bin.get("em_noise", 0.0),
					"density": bin.get("density", 0.0),
					"owner_id": bin.get("owner_id", -1)
				}
				
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
						
			c["last_seen_timer"] = 0.0
		else:
			if new_id == "":
				new_id = "TRK-%03d" % next_contact_id
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
				"resolution": bin.get("bin_angle", TAU),
				"pos_timer": 0.0,
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
			
			if sensor.get("type", "active") == "passive_em":
				var em_power = sig.get("em_noise", 0.0)
				
				# Rear-aspect EM bias
				var angle_from_target = collider.position.angle_to_point(position)
				var relative_angle = angle_from_target - collider.rotation
				var rear_bias = 1.0 + 0.5 * max(0.0, cos(relative_angle + PI))
				em_power *= rear_bias
				
				# Active Sensor EM Spikes
				var target_sensors = sig.get("sensor_config", [])
				for s in target_sensors:
					if s.get("type", "") == "active" and s.get("active", true):
						var s_arc = s.get("arc_width", TAU)
						var s_heading = s.get("heading", 0.0)
						var diff = abs(wrapf(angle_from_target - s_heading, -PI, PI))
						if diff <= s_arc / 2.0:
							var s_power = s.get("em_emission", 0.0)
							em_power += s_power * (1.0 - diff/(s_arc/2.0))
				
				var received_em = em_power * (10000.0 / max(10000.0, dist))
				if received_em < 15.0:
					continue # Passive EM only detects targets above noise floor (after falloff)
			else:
				# Active sensors check line of sight
				var ray_query = PhysicsRayQueryParameters2D.create(position, collider.position)
				ray_query.exclude = [self]
				var ray_res = space_state.intersect_ray(ray_query)
				if ray_res and ray_res.collider != collider:
					continue # Blocked by obstacle
			
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
				sig["instance_id"] = collider.get_instance_id()
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
		var max_cs = -1.0
		var primary_instance_id = -1
		
		for obj in objects:
			var cs = obj.get("cross_section", 1.0)
			merged["cross_section"] += cs
			merged["heat"] += obj.get("heat", 0.0)
			merged["em_noise"] += obj.get("em_noise", 0.0)
			if obj.has("owner_id"):
				bin_owner = obj["owner_id"]
				
			if cs > max_cs:
				max_cs = cs
				primary_instance_id = obj.get("instance_id", -1)
			
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
		merged["instance_id"] = primary_instance_id
		
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
	
	# Verify hardpoint health
	var component_health = 0.0
	for comp in ship_components:
		if comp["id"] == weapon_id:
			component_health = comp["health"]
			break
	if component_health <= 0.0: return # Hardpoint destroyed!
	
	var weapon_data = weapons[weapon_id]
	var w_type = weapon_data["type"]
	
	# Validate target within arc
	if active_contacts.has(target_contact_id):
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
		# Hitscan weapons also check range
		if w_type == "laser":
			var dist = position.distance_to(real_target_pos)
			if dist > weapon_data["range"]: return
			
		var angle_to = position.angle_to_point(real_target_pos)
		
		# Weapon heading is relative to ship rotation
		var weapon_global_heading = rotation + weapon_data["heading"]
		var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)
		
		if abs(rel_angle) > weapon_data["arc_width"] / 2.0: return
	elif w_type == "laser":
		return # Lasers require target lock for hitscan logic currently

	# Consume ammo and set cooldown
	weapons[weapon_id]["ammo"] -= 1
	weapons[weapon_id]["cooldown"] = weapon_data["cooldown_max"]
	
	var global_mount_pos = position + weapon_data["mount_pos"].rotated(rotation)
	var weapon_launch_angle = rotation + weapon_data["heading"]
	
	if w_type == "laser":
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_laser.play()
			
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
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
				# Ray hits target - simulate from global_mount_pos to real_target_pos
				var hit_dir = (real_target_pos - global_mount_pos).normalized()
				body.take_damage(weapon_data["damage"], real_target_pos, hit_dir)
			elif body.has_method("get_signature"):
				body.queue_free()
				
	elif w_type == "missile":
		if multiplayer.get_unique_id() == int(name.replace("Ship_", "")):
			sfx_missile.play()
			
		var main_node = get_tree().current_scene
		if not is_instance_valid(main_node): return
		
		var Projectile = load("res://scripts/projectile.gd")
		var proj = Projectile.new()
		
		var target_profile = {}
		if active_contacts.has(target_contact_id):
			target_profile = active_contacts[target_contact_id]["signature"]
			
		proj.setup(int(name.replace("Ship_", "")), global_mount_pos, linear_velocity, weapon_launch_angle)
		proj.target_profile = target_profile
		main_node.add_child(proj, true)

func _process_point_defense() -> void:
	pass # Disabled until hardpoint-based point defense is implemented



func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode
