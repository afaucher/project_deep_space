extends RigidBody2D
class_name LaserHead

enum State {
	POWERED,
	COASTING,
	DEAD
}

var current_state: State = State.POWERED
var owner_id: int = 0
var damage: float = 2500.0

# Flight parameters
var thrust: float = 50000.0
var max_speed: float = 1400.0
var engine_lifetime: float = 20.0 # 20s * 1400m/s = 28,000m
var battery_lifetime: float = 60.0 # Can coast for a while after engine dies
var age: float = 0.0

var current_target_pos: Vector2 = Vector2.ZERO
var has_target: bool = false
var target_profile: Dictionary = {}

# Sensor & Signature
var cross_section: float = 1.0 # Small profile
var base_heat: float = 5.0
var em_noise: float = 10.0
var density: float = 50.0

var main_node: Node = null

# Sensor Sweep Configuration (Matches Ship's Omni Main)
var sensor = {
	"range": 28000.0, # Can see to its flight range
	"arc_width": PI / 3.0, # 60 degree forward cone
	"num_bins": 12,
	"timer": 0.0,
	"refresh_interval": 1.0 # Scans every 1 second
}

func get_signature() -> Dictionary:
	var current_heat = base_heat
	if current_state == State.POWERED:
		current_heat += 150.0 # Massive heat from engine
		
	return {
		"cross_section": cross_section,
		"heat": current_heat,
		"em_noise": em_noise,
		"density": density,
		"pos": position,
		"vel": linear_velocity,
		"owner_id": owner_id # Let ship lasers identify IFF
	}

func setup(p_owner_id: int, p_pos: Vector2, p_vel: Vector2, initial_heading: float) -> void:
	owner_id = p_owner_id
	position = p_pos
	linear_velocity = p_vel
	rotation = initial_heading
	main_node = get_tree().current_scene
	
	mass = 20.0
	inertia = 50.0
	linear_damp = 0.0
	angular_damp = 5.0
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 2.0
	collision.shape = shape
	add_child(collision)
	
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	age += delta
	
	if current_state == State.POWERED and age >= engine_lifetime:
		current_state = State.COASTING
		
	if age >= battery_lifetime:
		current_state = State.DEAD
		queue_free()
		return
		
	sensor["timer"] -= delta
	
	if sensor["timer"] <= 0.0:
		sensor["timer"] = sensor["refresh_interval"]
		var target = _run_sensor_sweep_and_find_target()
		if target != null:
			current_target_pos = target
			has_target = true
		else:
			has_target = false
			
	# Engage Laser Head if within 1,000m
	if has_target and position.distance_to(current_target_pos) <= 1000.0:
		_fire_laser(current_target_pos)
		return
		
	if current_state == State.POWERED:
		var forward = Vector2.RIGHT.rotated(rotation)
		apply_central_force(forward * thrust)
		
		if has_target:
			var angle_to = get_angle_to(current_target_pos)
			apply_torque(angle_to * 50000.0) # Much stronger torque
			
		if linear_velocity.length() > max_speed:
			linear_velocity = linear_velocity.normalized() * max_speed

func _process(delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if has_target:
		# Debug line to target
		var local_target = to_local(current_target_pos)
		draw_line(Vector2.ZERO, local_target, Color(1.0, 0.0, 0.0, 0.8), 20.0)

func _fire_laser(target_pos: Vector2) -> void:
	# Instantly damage anything near target_pos and self-destruct
	# To be perfectly accurate to user prompt: "They fire at the center of the sensor arc with the contact so it won't be perfectly accurate."
	# Target_pos is already the center of the sensor arc from the sweep logic.
	
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 100.0 # Small blast radius at the arc center
	query.shape = shape
	query.transform = Transform2D(0, target_pos)
	
	var results = space_state.intersect_shape(query, 32)
	for res in results:
		var body = res["collider"]
		if body == self: continue
		if body.has_method("take_damage"):
			body.take_damage(damage)
		elif body.has_method("get_signature"):
			body.queue_free() # Asteroids
			
	queue_free()

func _run_sensor_sweep_and_find_target():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = sensor["range"]
	query.shape = shape
	query.transform = Transform2D(0, position)
	
	var results = space_state.intersect_shape(query, 128)
	var bins = []
	for i in range(sensor["num_bins"]): bins.append([])
	
	var bin_angle = sensor["arc_width"] / float(sensor["num_bins"])
	
	for res in results:
		var body = res["collider"]
		if body == self: continue
		if not body.has_method("get_signature"): continue
		
		var sig = body.get_signature()
		# IFF check
		if sig.has("owner_id") and sig["owner_id"] == owner_id:
			continue
			
		var dist = position.distance_to(sig["pos"])
		var angle = position.angle_to_point(sig["pos"])
		var rel_angle = wrapf(angle - rotation, -PI, PI)
		
		var half_arc = sensor["arc_width"] / 2.0
		if rel_angle >= -half_arc and rel_angle <= half_arc:
			var normalized_angle = rel_angle + half_arc
			var bin_idx = int(normalized_angle / bin_angle)
			if bin_idx >= 0 and bin_idx < sensor["num_bins"]:
				sig["_raw_dist"] = dist
				bins[bin_idx].append(sig)
				
	var best_bin_idx = -1
	var highest_threat = -99999.0
	
	for i in range(sensor["num_bins"]):
		if bins[i].size() == 0: continue
		var heat = 0.0
		var em = 0.0
		var cs = 0.0
		var den = 0.0
		var dist = 0.0
		for sig in bins[i]:
			heat += sig.get("heat", 0.0)
			em += sig.get("em_noise", 0.0)
			cs += sig.get("cross_section", 1.0)
			den += sig.get("density", 0.0)
			dist += sig["_raw_dist"]
		heat /= bins[i].size()
		em /= bins[i].size()
		cs /= bins[i].size()
		den /= bins[i].size()
		dist /= bins[i].size()
		
		var threat = 0.0
		if target_profile.is_empty():
			threat = heat + em
		else:
			var heat_diff = abs(heat - target_profile.get("heat", 0.0))
			var em_diff = abs(em - target_profile.get("em_noise", 0.0))
			var cs_diff = abs(cs - target_profile.get("cross_section", 1.0))
			var den_diff = abs(den - target_profile.get("density", 0.0))
			threat = 1000.0 - (heat_diff + em_diff + cs_diff + den_diff)
			
		if threat > highest_threat:
			highest_threat = threat
			best_bin_idx = i
			
	var meets_threshold = false
	if target_profile.is_empty() and highest_threat > 5.0:
		meets_threshold = true
	elif not target_profile.is_empty() and highest_threat > 500.0:
		meets_threshold = true
		
	if best_bin_idx != -1 and meets_threshold:
		var bin_center_angle = rotation - (sensor["arc_width"] / 2.0) + (best_bin_idx * bin_angle) + (bin_angle / 2.0)
		var avg_dist = 0.0
		for sig in bins[best_bin_idx]:
			avg_dist += sig["_raw_dist"]
		avg_dist /= bins[best_bin_idx].size()
		
		return position + Vector2(avg_dist, 0).rotated(bin_center_angle)
		
	return null

func _on_body_entered(body: Node) -> void:
	if body.has_method("get_signature"):
		var sig = body.get_signature()
		if sig.has("owner_id") and sig["owner_id"] == owner_id:
			return
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
	else:
		body.queue_free()
		
	queue_free()
