extends "res://scripts/ships/ship.gd"
class_name Missile

func _init() -> void:
	# Clean up inherited ship collision shapes
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
			remove_child(child)
			
	cross_section = 2.0
	reactor_power_rating = 10.0 # Small battery reactor for active seeker
	engine_power_rating = 10.0 # Small thruster EM signature

	max_thrust = 10000.0 # Very fast
	max_torque = 2500.0 # Prevent overcorrection/spinning
	max_omega = 10.0 # High turn rate for missiles
	max_speed = 3000.0

	ship_components = [
		{"id": "seeker", "type": "sensors", "rect": Rect2(5, -2, 5, 4), "health": 10.0, "max_health": 10.0, "density": 0.2,
			"heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0,
			"sensor_type": "active", "active": true, "heading": 0.0, "arc_width": PI / 1.5, # 120 degree forward cone
			"range": 30000.0, "resolution": 5.0, "timer": 0.0, "refresh_interval": 0.1, "num_bins": 60},
		{"id": "warhead", "type": "hull", "rect": Rect2(-2, -3, 7, 6), "health": 20.0, "max_health": 20.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0},
		{"id": "hull_body", "type": "hull", "rect": Rect2(-10, -3, 8, 6), "health": 30.0, "max_health": 30.0, "density": 0.5, "heat": 0.0, "em_emission": 0.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-15, -4, 5, 8), "health": 20.0, "max_health": 20.0, "density": 0.8, "heat": 0.0, "em_emission": 0.0}
	]

func _ready() -> void:
	# Small mass, low inertia
	mass = 20.0
	inertia = 50.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 5.0
	
	max_heat = 500.0
	heat_dissipation_rate = 20.0
	current_heat = 10.0
	
	# Add custom collision shape for the tiny body
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 2.0
	collision.shape = shape
	add_child(collision)
	
	# We DO NOT call super() because Ship._ready() sets mass=1000 and adds huge colliders
	# Wait, actually Ship._ready() doesn't add huge colliders, it adds one based on max component extents.
	# Let's call super._ready() first, then overwrite mass, inertia, and damping.
	super._ready()
	
	# Clean up any duplicate or inherited collision shapes from Ship._ready()
	for child in get_children():
		if child is CollisionShape2D and child != collision:
			child.queue_free()
			remove_child(child)
			
	mass = 20.0
	inertia = 50.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 5.0
	gravity_scale = 0.0

func setup(p_owner_id: int, p_pos: Vector2, p_vel: Vector2, initial_heading: float) -> void:
	name = "Missile_" + str(p_owner_id) + "_" + str(randi())
	owner_id = p_owner_id
	position = p_pos
	linear_velocity = p_vel
	rotation = initial_heading
