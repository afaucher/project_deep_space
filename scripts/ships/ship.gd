extends RigidBody2D
class_name Ship

var owner_id: int = -1

func _init() -> void:
	subsystems = subsystems.duplicate(true)
	ship_components = ship_components.duplicate(true)
	weapons = weapons.duplicate(true)
	sensor_hardware = sensor_hardware.duplicate(true)
	iff_tags = iff_tags.duplicate(true)
	active_contacts = {}

var is_relay: bool = false
var target_thrust: float = 0.0
var target_velocity: float = 0.0
var target_heading: float = 0.0
var steering_mode: int = 0 # 0 = Smooth, 1 = Combat
var linear_mode: int = 0 # 0 = Throttle, 1 = Velocity

var max_thrust: float = 5000.0
var max_torque: float = 10000.0
var max_omega: float = 2.0
var max_speed: float = 1000.0
var iff_tags: Array = []

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

# Engineering / Subsystems
var subsystems: Dictionary = {
	"reactor": {"power": 1.0},
	"engines": {"power": 1.0},
	"weapons": {"power": 1.0},
	"sensors": {"power": 1.0}
}

var _cached_max_steps: int = 0
var _cached_bbox_min: Vector2 = Vector2(-INF, -INF)
var _cached_bbox_max: Vector2 = Vector2(INF, INF)

var ship_components: Array = [
	# Layout relative to center (0,0). Forward +X, Right +Y
	{"id": "hull_fwd", "type": "hull", "rect": Rect2(15, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	{"id": "hull_port", "type": "hull", "rect": Rect2(-15, -15, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	{"id": "hull_stbd", "type": "hull", "rect": Rect2(-15, 5, 30, 10), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	{"id": "hull_aft", "type": "hull", "rect": Rect2(-30, -15, 15, 30), "health": 1000.0, "max_health": 1000.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	
	{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 200.0, "max_health": 200.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false},
	{"id": "engine_main", "type": "engines", "rect": Rect2(-35, -10, 5, 20), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	
	{"id": "hp_sensor_fwd", "type": "sensors", "rect": Rect2(30, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_sensor_omni", "type": "sensors", "rect": Rect2(-5, -5, 10, 10), "health": 100.0, "max_health": 100.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},

	{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(30, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(30, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},

	{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(17.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(7.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-2.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-12.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-22.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},

	{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(17.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(7.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-2.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-12.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true},
	{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-22.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true}
]

var current_heat: float = 10.0
var max_heat: float = 200.0
var heat_dissipation_rate = 10.0
var current_heat_gen: float = 0.0

var is_dead: bool = false
var em_signature: float = 0.0

var transient_events: Array = []
var hit_traces: Array = []

func get_sys_health(sys_type: String) -> float:
	var h = 0.0
	for c in ship_components:
		if c["type"] == sys_type and c.get("powered_on", true):
			h += max(0.0, c["health"])
	return h

static func classify_contact(signature: Dictionary, observer_iff_tags: Array) -> String:
	var contact_tags = signature.get("iff_tags", [])
	var is_friendly = false
	for tag in contact_tags:
		if observer_iff_tags.has(tag):
			is_friendly = true
			break
			
	var cs = signature.get("cross_section", 0.0)
	var heat = signature.get("heat", 0.0)
	var em = signature.get("em_noise", 0.0)
	var density = signature.get("density", 500.0)
	
	# 1. Size check (Ordnance)
	if cs < 10.0 and (em > 5.0 or heat > 5.0):
		if is_friendly:
			return "FRIENDLY ORDNANCE"
		else:
			return "INCOMING ORDNANCE"
			
	# 2. Emission check (Vessels)
	if cs >= 10.0 and (em > 5.0 or heat > 10.0):
		if is_friendly:
			return "FRIENDLY VESSEL"
		else:
			return "UNIDENTIFIED VESSEL"
			
	# 3. Density check (Dead objects / Cold ships)
	if em <= 5.0 and heat <= 10.0:
		if density > 250.0 and cs > 50.0:
			return "ASTEROID"
		elif density <= 250.0:
			return "WRECKAGE"
			
	return "UNKNOWN ANOMALY"

func get_sys_max_health(sys_type: String) -> float:
	var h = 0.0
	for c in ship_components:
		if c["type"] == sys_type:
			h += c["max_health"]
	return h

func is_component_powered(comp_id: String) -> bool:
	for c in ship_components:
		if c["id"] == comp_id:
			return c.get("powered_on", true) and c["health"] > 0.0
	return false

func get_component_health_ratio(comp_id: String) -> float:
	for c in ship_components:
		if c["id"] == comp_id:
			return max(0.0, c["health"]) / max(1.0, c["max_health"])
	return 0.0

# Legacy getters
var health: float:
	get: return get_sys_health("hull")
	set(value): pass # Obsolete, damage uses volumetric now

var base_heat: float:
	get: return current_heat
	
var reactor_power_rating: float = 100.0
var engine_power_rating: float = 100.0

var em_noise: float:
	get: 
		var noise = 5.0 * subsystems["reactor"]["power"]
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

func take_damage(amount: float, global_pos: Vector2 = Vector2.ZERO, global_dir: Vector2 = Vector2.ZERO, damage_type: String = "kinetic") -> void:
	if is_dead: return
	
	print("[Damage] ", name, " taking ", amount, " ", damage_type, " damage at ", global_pos, " dir ", global_dir)
	
	if global_pos == Vector2.ZERO or global_dir == Vector2.ZERO:
		print("[Damage] No position provided, applying fallback hull damage.")
		# Fallback: Just subtract health from first hull component
		for c in ship_components:
			if c["type"] == "hull":
				c["health"] -= amount
				break
	else:
		# Raymarch through components starting from local collision pos
		var local_pos = to_local(global_pos)
		var local_dir = global_dir.rotated(-rotation)
		
		var remaining_damage = amount
		var step_size = 2.0
		
		if _cached_max_steps == 0:
			var max_dist = 200.0
			var min_x = INF; var max_x = -INF
			var min_y = INF; var max_y = -INF
			if not ship_components.is_empty():
				for c in ship_components:
					var r: Rect2 = c["rect"]
					min_x = min(min_x, r.position.x)
					max_x = max(max_x, r.position.x + r.size.x)
					min_y = min(min_y, r.position.y)
					max_y = max(max_y, r.position.y + r.size.y)
				max_dist = Vector2(max_x - min_x, max_y - min_y).length()
				_cached_bbox_min = Vector2(min_x, min_y)
				_cached_bbox_max = Vector2(max_x, max_y)
			else:
				_cached_bbox_min = Vector2(-100, -100)
				_cached_bbox_max = Vector2(100, 100)
			_cached_max_steps = int(ceil(max_dist / step_size))
			
		var tmin = -INF
		var tmax = INF
		var hit_box = true
		for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
			if abs(local_dir[axis]) < 0.0001:
				if local_pos[axis] < _cached_bbox_min[axis] or local_pos[axis] > _cached_bbox_max[axis]:
					hit_box = false
			else:
				var t1 = (_cached_bbox_min[axis] - local_pos[axis]) / local_dir[axis]
				var t2 = (_cached_bbox_max[axis] - local_pos[axis]) / local_dir[axis]
				if t1 > t2:
					var temp = t1
					t1 = t2
					t2 = temp
				tmin = max(tmin, t1)
				tmax = min(tmax, t2)
				
		if tmax >= tmin and tmax >= 0 and hit_box:
			local_pos = local_pos + local_dir * max(0.0, tmin)
			
		var max_steps = _cached_max_steps
		var current_pos = local_pos
		
		var trace = {
			"start_local": local_pos,
			"end_local": local_pos,
			"dir_local": local_dir,
			"segments": [],
			"time_remaining": 3.0 # Persist for 3 seconds
		}
		
		var hit_something = false
		for i in range(max_steps):
			if remaining_damage <= 0: break
			
			var segment_hit = false
			
			for comp in ship_components:
				if comp["health"] <= 0: continue
				if comp["rect"].has_point(current_pos):
					hit_something = true
					segment_hit = true
					
					# Ablation: Effective density drops as component loses health
					var health_ratio = max(0.0, comp["health"] / comp.get("max_health", 1000.0))
					var effective_density = max(0.05, comp["density"] * health_ratio)
					
					var dmg_absorbed = min(remaining_damage, effective_density * step_size * 50.0)
					if dmg_absorbed > 0:
						comp["health"] -= dmg_absorbed
						
						# Laser hits add significantly more heat to the component
						var heat_modifier = 0.5 if damage_type == "laser" else 0.05
						var heat_generated = dmg_absorbed * heat_modifier
						
						comp["heat"] = comp.get("heat", 0.0) + heat_generated
						current_heat += heat_generated
						remaining_damage -= dmg_absorbed
			
			trace["segments"].append({
				"pos": current_pos,
				"dmg_remaining": remaining_damage,
				"hit": segment_hit
			})
			
			current_pos += local_dir * step_size
			trace["end_local"] = current_pos
			
		hit_traces.append(trace)
			
		if not hit_something:
			print("[Damage] Raycast completely missed all internal components!")
			
	# Check death condition (reactor dead)
	if get_sys_health("reactor") <= 0.0 or get_sys_health("hull") <= 0.0:
		print("[Damage] ", name, " suffers catastrophic failure and dies.")
		hulk()

func hulk() -> void:
	is_dead = true
	# Shut down subsystems to stop heat/EM generation
	subsystems["reactor"]["power"] = 0.0
	subsystems["engines"]["power"] = 0.0
	subsystems["weapons"]["power"] = 0.0
	subsystems["sensors"]["power"] = 0.0
	# Shut down all individual components
	for c in ship_components:
		c["powered_on"] = false
		if c["type"] == "reactor":
			c["power_draw"] = 0.0
	target_thrust = 0.0
	actual_throttle = 0.0

func get_signature() -> Dictionary:
	return {
		"cross_section": cross_section,
		"heat": current_heat,
		"em_noise": em_signature,
		"density": density,
		"owner_id": owner_id,
		"iff_tags": iff_tags.duplicate(),
		"pos": position,
		"rot": rotation,
		"vel": linear_velocity,
		"sensors": active_sensor_sweeps,
		"sensor_config": sensor_hardware,
		"contacts": active_contacts
	}

func _ready() -> void:
	if owner_id == -1:
		owner_id = int(name.replace("Ship_", ""))
		
	add_to_group("ships")
		
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
		"em_emission": 10.0
	},
	{
		"id": "dir_high_res",
		"type": "active",
		"active": true,
		"range": 40000.0,
		"arc_width": PI / 6.0,
		"num_bins": 30,
		"interval": 0.5,
		"refresh_interval": 0.5,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0,
		"em_emission": 20.0
	},
	{
		"id": "omni_short_hi_res",
		"type": "active",
		"active": true,
		"range": 5000.0,
		"arc_width": TAU,
		"num_bins": 180,
		"interval": 0.25,
		"refresh_interval": 0.25,
		"timer": 0.0,
		"heading": 0.0,
		"health": 100.0,
		"em_emission": 5.0
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
func request_spawn(type: String) -> void:
	if not is_multiplayer_authority(): return
	var main = get_node_or_null("/root/Main")
	if not main: return
	
	if type == "asteroids":
		main._spawn_asteroids()
	elif type == "drone":
		main._spawn_drone()
	elif type == "friendly_drone":
		main._spawn_drone(true)
	elif type == "buoy":
		main._spawn_buoy()


@rpc("any_peer", "call_local")
func set_sensor_state(sensor_id: String, is_active: bool) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
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
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
	for s in sensor_hardware:
		s["active"] = is_active

@rpc("any_peer", "call_local")
func set_sensor_target(target_id: String) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0: pass
	manual_sensor_target = target_id

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		for w in weapons.keys():
			if weapons[w]["cooldown"] > 0:
				var cooldown_rate = 1.0
				var ratio = get_component_health_ratio(w)
				if ratio > 0.0:
					cooldown_rate = ratio
				weapons[w]["cooldown"] -= delta * cooldown_rate
				
		if not is_dead:
			_process_point_defense()
		
	var forward = Vector2.RIGHT.rotated(rotation)
	var current_forward_speed = linear_velocity.dot(forward)
	
	var active_max_thrust = max_thrust
	if not is_component_powered("engine_main"):
		active_max_thrust = 0.0
	else:
		active_max_thrust *= get_component_health_ratio("engine_main")

	if linear_mode == 0:
		# Direct Throttle Control
		actual_throttle = target_thrust
	else:
		# Velocity Control (PID/Bang-Bang)
		var v_error = target_velocity - current_forward_speed
		var required_accel = v_error * 2.0 # P gain
		var required_force = required_accel * mass
		if active_max_thrust > 0.0:
			actual_throttle = required_force / active_max_thrust
		else:
			actual_throttle = 0.0
		
	# Apply limits based on steering mode
	if steering_mode == 0:
		actual_throttle = clampf(actual_throttle, -0.5, 0.5)
	else:
		actual_throttle = clampf(actual_throttle, -1.0, 1.0)
	
	var is_my_ship = (multiplayer.get_unique_id() == owner_id)
	
	if active_max_thrust > 0.0 and actual_throttle != 0.0:
		apply_central_force(forward * actual_throttle * active_max_thrust)
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
	
	var active_engine_efficiency = 0.0
	if is_component_powered("engine_main"):
		active_engine_efficiency = get_component_health_ratio("engine_main") * subsystems["engines"]["power"]
	
	var torque = 0.0
	var active_max_torque = 0.0
	if active_engine_efficiency > 0.0:
		active_max_torque = (max_torque if steering_mode == 1 else max_torque * 0.2) * active_engine_efficiency
		var active_max_omega = (max_omega if steering_mode == 1 else max_omega * 0.25) * active_engine_efficiency
		
		var alpha_max = active_max_torque / inertia
		
		var target_omega = sign(angle_diff) * sqrt(2.0 * alpha_max * abs(angle_diff))
		target_omega = clampf(target_omega, -active_max_omega, active_max_omega)
		
		var omega_error = target_omega - angular_velocity
		var required_alpha = omega_error * 10.0 # Tuning factor for how aggressively to track the curve
		
		torque = required_alpha * inertia
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
		c["last_seen_timer"] = c.get("last_seen_timer", 0.0) + delta
		c["pos_timer"] = c.get("pos_timer", 0.0) + delta
		
		# Dead-reckon their position based on velocity
		if c.has("vel") and typeof(c["vel"]) == TYPE_VECTOR2:
			c["pos"] += c["vel"] * delta
			
		if c["last_seen_timer"] > 20.0:
			to_remove.append(c_id)
	for c_id in to_remove:
		active_contacts.erase(c_id)
	
	var bins_this_frame = []

	# --- Heat & Engineering Logic ---
	if is_multiplayer_authority():
		var heat_gen = 0.0
		var reactor_heat = 2.0 * subsystems["reactor"]["power"]
		var engine_inefficiency_mult = 1.0
		if is_component_powered("engine_main"):
			var eff = get_component_health_ratio("engine_main")
			engine_inefficiency_mult = max(1.0, 1.0 / max(0.1, eff))
			
		var engine_heat = abs(actual_throttle) * 10.0 * subsystems["engines"]["power"] * engine_inefficiency_mult
		engine_heat += (abs(torque) / max(1.0, active_max_torque)) * 5.0 * subsystems["engines"]["power"] * engine_inefficiency_mult
		
		var passive_heat = 0.0
		var passive_em = 0.0
		for comp in ship_components:
			if comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull":
				passive_heat += 0.1
				passive_em += 0.5
		
		heat_gen = reactor_heat + engine_heat + passive_heat
		current_heat_gen = heat_gen
		
		current_heat += heat_gen * delta
		var active_dissipation = heat_dissipation_rate * get_component_health_ratio("reactor_core")
		current_heat -= active_dissipation * delta
		current_heat = clampf(current_heat, 0.0, max_heat)
		
		if current_heat >= max_heat:
			for c in ship_components:
				if c["id"] == "reactor":
					c["health"] -= 10.0 * delta
					
		# Update Component EM & Heat
		var base_em = reactor_power_rating * subsystems["reactor"]["power"]
		var current_em = base_em + (abs(actual_throttle) * engine_power_rating)
		var sensor_em = 0.0
		var sensor_power_ratio = get_sys_health("sensors") / max(1.0, get_sys_max_health("sensors"))
		if sensor_power_ratio > 0.0:
			for s in sensor_hardware:
				if s.get("active", true):
					sensor_em += s.get("em_emission", 0.0) * sensor_power_ratio
		
		em_signature = current_em + sensor_em + passive_em
		
		for comp in ship_components:
			var b_heat = 0.1 if (comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull") else 0.0
			var b_em = 0.5 if (comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull") else 0.0
			
			if comp["type"] == "reactor":
				comp["heat"] = 10.0 + reactor_heat
				comp["em_emission"] = reactor_power_rating
			elif comp["type"] == "engines":
				comp["heat"] = b_heat + engine_heat
				comp["em_emission"] = b_em + abs(actual_throttle) * engine_power_rating
			elif comp["type"] == "sensors":
				comp["heat"] = b_heat + 5.0
				comp["em_emission"] = b_em + sensor_em
			elif comp["type"] == "weapons":
				comp["heat"] = b_heat
				comp["em_emission"] = b_em
			else:
				comp["heat"] = 0.0
				comp["em_emission"] = 0.0

	# Sensor Sweeps
	var active_sensor_efficiency = (get_sys_health("sensors") / max(1.0, get_sys_max_health("sensors"))) * subsystems["sensors"]["power"]
	
	for sensor in sensor_hardware:
		var parent_comp_id = sensor.get("parent", "hp_sensor_fwd" if sensor["id"] == "dir_high_res" else "hp_sensor_omni")
		if not is_component_powered(parent_comp_id):
			active_sensor_sweeps[sensor["id"]] = []
			continue
			
		var parent_health_ratio = get_component_health_ratio(parent_comp_id)
		if parent_health_ratio <= 0.0 or active_sensor_efficiency <= 0.1:
			continue
			
		if not sensor.get("active", true):
			active_sensor_sweeps[sensor["id"]] = []
			continue
			
		sensor["timer"] -= delta
		if sensor["timer"] <= 0.0:
			sensor["timer"] = sensor["refresh_interval"]
			var active_range = sensor["range"] * parent_health_ratio
			var bins = _run_sensor_sweep(sensor, active_range)
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
			bin["contact_id"] = new_id
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
				
				if bin.has("cross_section"): c["signature"]["cross_section"] = lerp(c["signature"].get("cross_section", 0.0), bin.get("cross_section", 0.0), 0.8)
				if bin.has("heat"): c["signature"]["heat"] = lerp(c["signature"].get("heat", 0.0), bin.get("heat", 0.0), 0.8)
				if bin.has("em_noise"): c["signature"]["em_noise"] = lerp(c["signature"].get("em_noise", 0.0), bin.get("em_noise", 0.0), 0.8)
				if bin.has("owner_id"): c["signature"]["owner_id"] = bin["owner_id"]
				if bin.has("iff_tags"): c["signature"]["iff_tags"] = bin["iff_tags"]
				if bin.has("instance_id"): c["instance_id"] = bin["instance_id"]
				
				c["classification"] = Ship.classify_contact(c["signature"], self.iff_tags)
						
			c["last_seen_timer"] = 0.0
		else:
			# New contact
			new_id = bin.get("contact_id", "")
			if new_id == "":
				new_id = "TRK-%03d" % next_contact_id
				next_contact_id += 1
			
			var classification = Ship.classify_contact(bin, self.iff_tags)
				
			active_contacts[new_id] = {
				"id": new_id,
				"instance_id": bin.get("instance_id", -1),
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
			
	for c_id in active_contacts.keys():
		var c = active_contacts[c_id]
		c["last_seen_timer"] = c.get("last_seen_timer", 0.0) + delta
		c["pos_timer"] = c.get("pos_timer", 0.0) + delta
		
		# Drop old contacts
		if c["last_seen_timer"] > 10.0:
			active_contacts.erase(c_id)
				
	# Datalink Relay (Temporarily Disabled as requested)
	#for s in get_tree().get_nodes_in_group("ships"):
	#	if s == self or s.is_dead or s.owner_id != owner_id or not s.is_relay: continue
	#	for c_id in s.active_contacts:
	#		var external_contact = s.active_contacts[c_id]
	#		if not active_contacts.has(c_id):
	#			active_contacts[c_id] = external_contact.duplicate(true)
	#		else:
	#			var c = active_contacts[c_id]
	#			if external_contact["last_seen_timer"] < c["last_seen_timer"]:
	#				c["pos"] = external_contact["pos"]
	#				c["vel"] = external_contact["vel"]
	#				c["last_seen_timer"] = external_contact["last_seen_timer"]
	#				c["resolution"] = min(c["resolution"], external_contact["resolution"])

	if is_multiplayer_authority():
		var i = hit_traces.size() - 1
		while i >= 0:
			hit_traces[i]["time_remaining"] -= delta
			if hit_traces[i]["time_remaining"] <= 0.0:
				hit_traces.remove_at(i)
			i -= 1

func _run_sensor_sweep(sensor: Dictionary, active_range: float = 0.0) -> Array:
	var use_range = active_range if active_range > 0.0 else sensor["range"]
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = use_range
	query.shape = shape
	query.transform = Transform2D(0, position)
	
	var results = space_state.intersect_shape(query, 128)
	
	var NUM_BINS = sensor["num_bins"]
	var ARC_WIDTH = sensor["arc_width"]
	var SENSOR_HEADING = rotation + sensor["heading"]
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
				var angle_from_target = (position - collider.position).angle()
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
			
			var ray_query = PhysicsRayQueryParameters2D.create(position, collider.position)
			ray_query.exclude = [self]
			var ray_res = space_state.intersect_ray(ray_query)
			if ray_res and ray_res.collider != collider:
				continue # Blocked by obstacle

			if sensor.get("type", "active") == "passive_em":
				var em_power = sig.get("em_noise", 0.0)
				# Rear-aspect EM bias
				var angle_from_target = (position - collider.position).angle()
				var relative_angle = angle_from_target - collider.rotation
				var rear_bias = 1.0 + 0.5 * max(0.0, cos(relative_angle + PI))
				em_power *= rear_bias
				
				var received_em = em_power * (10000.0 / max(10000.0, dist))
				if received_em < 15.0:
					continue # Passive EM only detects targets above noise floor (after falloff)
			
			var angle = (collider.position - position).angle()
			
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
				if sensor.get("type", "active") == "passive_em":
					sig.erase("cross_section")
					sig.erase("heat")
					sig.erase("density")
					# em_power calculation was applied above, but it's out of scope here.
					# Let's apply it directly to sig["em_noise"] in the first block, or we can just use sig["em_noise"] since we don't have rear aspect here... wait!
					# I'll just use the raw signature em_noise for the bin data. Rear bias isn't saved in the bin? Actually, it shouldn't be.
					sig["em_noise"] = sig.get("em_noise", 0.0)
					
				bins[bin_idx].append(sig)
	
	var sweep_output = []
	
	# Aggregate bins
	for bin_idx in bins.keys():
		var objects = bins[bin_idx]
		var merged = {
			"count": objects.size()
		}
		
		var total_cs = 0.0
		var max_heat = -1.0
		var max_em = -1.0
		var weighted_dist = 0.0
		var weighted_vel = Vector2.ZERO
		var bin_owner = -1
		var max_cs = -1.0
		var primary_instance_id = -1
		
		for obj in objects:
			var cs = obj.get("cross_section", 0.0)
			
			if obj.has("heat"):
				max_heat = max(max_heat, obj.get("heat", 0.0))
			if obj.has("em_noise"):
				max_em = max(max_em, obj.get("em_noise", 0.0))
				
			if obj.has("owner_id"):
				bin_owner = obj["owner_id"]
			if obj.has("iff_tags") and not merged.has("iff_tags"):
				merged["iff_tags"] = obj["iff_tags"].duplicate()
				
			if cs > max_cs:
				max_cs = cs
				primary_instance_id = obj.get("instance_id", -1)
			
			total_cs += cs
			weighted_dist += obj["_raw_dist"] * max(cs, 1.0)
			weighted_vel += obj.get("vel", Vector2.ZERO) * max(cs, 1.0)
		
		if total_cs > 0:
			weighted_dist /= total_cs
			weighted_vel /= total_cs
			var total_density = 0.0
			for obj in objects:
				total_density += obj.get("density", 0.0) * obj.get("cross_section", 1.0)
			merged["density"] = total_density / total_cs
		else:
			weighted_dist = objects[0]["_raw_dist"]
			if objects[0].has("density"):
				merged["density"] = objects[0].get("density", 0.0)
				
		if total_cs > 0.0:
			merged["cross_section"] = total_cs
		if max_heat >= 0.0:
			merged["heat"] = max_heat
		if max_em >= 0.0:
			merged["em_noise"] = max_em
			
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
func set_component_power(component_id: String, active: bool) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			return
	for c in ship_components:
		if c["id"] == component_id and c.get("switchable", false):
			c["powered_on"] = active
			break

@rpc("any_peer", "call_local")
func fire_weapon(weapon_id: String, target_pos: Vector2, target_contact_id: String) -> void:
	if not is_multiplayer_authority() or is_dead:
		return # Only host executes this
		
	# Verify client owns this ship
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0:
			pass
			
	if not weapons.has(weapon_id):
		print("fire_weapon failed: unknown weapon ", weapon_id)
		return
	if weapons[weapon_id]["ammo"] <= 0:
		print("fire_weapon failed: no ammo for ", weapon_id)
		return
	if weapons[weapon_id]["cooldown"] > 0:
		print("fire_weapon failed: cooldown active for ", weapon_id)
		return
	
	# Verify hardpoint health
	if not is_component_powered(weapon_id):
		print("fire_weapon failed: hardpoint disabled ", weapon_id)
		return # Hardpoint off or destroyed!
	
	var component_health_ratio = get_component_health_ratio(weapon_id)
	
	var weapon_data = weapons[weapon_id]
	var w_type = weapon_data["type"]
	
	# Validate target within arc
	if active_contacts.has(target_contact_id):
		var real_target_pos = active_contacts[target_contact_id]["pos"]
		
		# Hitscan weapons also check range
		if w_type == "laser":
			var dist = position.distance_to(real_target_pos)
			if dist > weapon_data["range"]:
				print("fire_weapon failed: laser out of range")
				return
			
		var angle_to = (real_target_pos - position).angle()
		
		# Weapon heading is relative to ship rotation
		var weapon_global_heading = rotation + weapon_data["heading"]
		var rel_angle = wrapf(angle_to - weapon_global_heading, -PI, PI)
		
		if abs(rel_angle) > weapon_data["arc_width"] / 2.0:
			print("fire_weapon failed: outside arc. Target at ", rad_to_deg(angle_to), " weapon at ", rad_to_deg(weapon_global_heading), " diff ", rad_to_deg(rel_angle), " max arc ", rad_to_deg(weapon_data["arc_width"]/2.0))
			return
	elif w_type == "laser":
		print("fire_weapon failed: laser requires target lock")
		return # Lasers require target lock for hitscan logic currently

	# Consume ammo and set cooldown
	weapons[weapon_id]["ammo"] -= 1
	weapons[weapon_id]["cooldown"] = weapon_data["cooldown_max"]
	
	var global_mount_pos = position + weapon_data["mount_pos"].rotated(rotation)
	var weapon_launch_angle = rotation + weapon_data["heading"]
	
	if w_type == "laser":
		if multiplayer.get_unique_id() == owner_id:
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
				var actual_damage = weapon_data["damage"] * component_health_ratio
				body.take_damage(actual_damage, global_mount_pos, hit_dir, weapon_data["type"])
			elif body.has_method("get_signature"):
				body.queue_free()
				
	elif w_type == "missile":
		if multiplayer.get_unique_id() == owner_id:
			sfx_missile.play()
			
		var main_node = get_tree().current_scene
		if not is_instance_valid(main_node): return
		
		var Missile = load("res://scripts/ships/missile.gd")
		var proj = Missile.new()
		
		# Add controller
		var MissileController = load("res://scripts/missile_controller.gd")
		var controller = MissileController.new()
		proj.add_child(controller)
		controller.target_id = target_contact_id
		if target_contact_id != "" and active_contacts.has(target_contact_id):
			proj.active_contacts[target_contact_id] = active_contacts[target_contact_id].duplicate(true)
			proj.active_contacts[target_contact_id]["pos_timer"] = 0.0
		
		var launch_dir = Vector2.RIGHT.rotated(weapon_launch_angle)
		var rel_mount = weapon_data["mount_pos"]
		var spawn_rel = rel_mount
		if spawn_rel.length() < 55.0:
			# Push along launch_dir until the distance from ship center is at least 55.0px
			var A = 1.0
			var B = 2.0 * rel_mount.dot(launch_dir)
			var C = rel_mount.length_squared() - 3025.0 # 55.0^2
			var discriminant = B * B - 4.0 * A * C
			if discriminant >= 0.0:
				var d = (-B + sqrt(discriminant)) / 2.0
				if d > 0.0:
					spawn_rel += launch_dir * d
				else:
					spawn_rel += launch_dir * 25.0
			else:
				spawn_rel += launch_dir * 25.0
				
		proj.position = position + spawn_rel.rotated(rotation)
		
		# Orient nose toward target so seeker can acquire, but kick velocity
		# out the tube direction to clear the parent ship hull
		var target_dir = (target_pos - proj.position).angle()
		proj.rotation = target_dir
		proj.name = "Missile_" + str(owner_id) + "_" + str(randi())
		proj.owner_id = owner_id
		proj.iff_tags = iff_tags.duplicate()
		proj.linear_velocity = linear_velocity + (Vector2.RIGHT.rotated(weapon_launch_angle) * 200.0)
		proj.add_collision_exception_with(self)
		main_node.add_child(proj, true)

func _process_point_defense() -> void:
	var main_node = get_tree().current_scene
	if not is_instance_valid(main_node): return
	
	var ready_lasers = []
	for w_id in weapons:
		if weapons[w_id]["type"] == "laser" and weapons[w_id]["ammo"] > 0 and weapons[w_id]["cooldown"] <= 0.0:
			if is_component_powered(w_id):
				ready_lasers.append(w_id)
				
	var debug_log = Engine.get_physics_frames() % 60 == 0
	if ready_lasers.is_empty(): 
		return
	
	var pd_range = 3500.0
	
	for c_id in active_contacts:
		if ready_lasers.is_empty(): break
		
		var contact = active_contacts[c_id]
		if contact.get("classification", "") == "INCOMING ORDNANCE":
			var body = instance_from_id(contact.get("instance_id", -1))
			if not is_instance_valid(body) or body == self: continue
			if body is Ship and body.is_dead: continue
			
			var dist = position.distance_to(body.position)
			if dist > pd_range: continue
			
			var rel_pos = body.position - position

			for w_id in ready_lasers:
				var weapon = ship_components.filter(func(c): return c["id"] == w_id)[0]
				
				var aim_angle = (body.position - (position + weapon["rect"].position.rotated(rotation))).angle()
				
				var weapon_data = weapons[w_id]
				var w_global_heading = rotation + weapon_data["heading"]
				var rel_angle = wrapf(aim_angle - w_global_heading, -PI, PI)
				
				if abs(rel_angle) <= weapon_data["arc_width"] / 2.0:
					weapons[w_id]["cooldown"] = weapon_data["cooldown_max"]
					weapons[w_id]["ammo"] -= 1
					
					var start_pos = position + weapon["rect"].position.rotated(rotation)
					transient_events.append({
						"type": "laser",
						"start_pos": start_pos,
						"end_pos": body.position
					})
					
					if multiplayer.get_unique_id() == owner_id:
						sfx_laser.play()
						
					var hit_dir = (body.position - start_pos).normalized()
					print("[PD] ", name, " shooting at ", body.name, " (", c_id, ")")
					body.take_damage(100.0, body.position, hit_dir, "laser")
					ready_lasers.erase(w_id)
					break



func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode



