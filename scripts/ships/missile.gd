extends "res://scripts/ships/ship.gd"
class_name Missile

const MISSILE_COLLISION_RADIUS := 2.0 # tiny body, much smaller than Ship.SHIP_COLLISION_RADIUS
const MISSILE_ANGULAR_DAMP := 5.0     # ships free-spin (0.0 damp); missiles need rotation to settle so the seeker can track

func _init() -> void:
	# Clean up inherited ship collision shapes
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
			remove_child(child)
			


	# Mass and inertia derive from rect area/distance x density (see ship.gd).
	# Density is the same 20.0 used by Frigate -- same "stuff", smaller box, so
	# both come out much lighter than the old flat values. thrust_rating/
	# torque_rating on engine_main below are authored directly (not derived --
	# see the M1b doc appendix for why that breaks ship-to-ship balance), set
	# to reproduce the same accel/angular-accel ratios as before this rework.
	max_omega = 10.0 # High turn rate for missiles
	max_speed = 3000.0

	ship_components = [
		{"id": "seeker", "type": "sensors", "rect": Rect2(5, -2, 5, 4), "health": 10.0, "max_health": 10.0, "density": 20.0,
			"heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0,
			"sensor_type": "active", "active": true, "heading": 0.0, "arc_width": PI / 1.5, # 120 degree forward cone
			"range": 30000.0, "resolution": 5.0, "timer": 0.0, "refresh_interval": 0.1, "num_bins": 60},
		{"id": "warhead", "type": "hull", "rect": Rect2(-2, -3, 7, 6), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "hull_body", "type": "hull", "rect": Rect2(-10, -3, 8, 6), "health": 30.0, "max_health": 30.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0},
		{"id": "engine_main", "type": "engines", "rect": Rect2(-15, -4, 5, 8), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "power_rating": 10.0, "thrust_rating": 2991.0, "torque_rating": 435.65},
		# Tiny capacitor between hull_body and engine -- touches both at shared edges.
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(-12, -2, 2, 4), "health": 5.0, "max_health": 5.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 10.0}
	]

func _ready() -> void:
	max_heat = 500.0
	heat_dissipation_rate = 20.0
	current_heat = 10.0

	# Add custom collision shape for the tiny body
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = MISSILE_COLLISION_RADIUS
	collision.shape = shape
	add_child(collision)

	# mass comes from get_ship_mass() via super._ready(), summed from ship_components above
	super._ready()

	# Clean up any duplicate or inherited collision shapes from Ship._ready()
	for child in get_children():
		if child is CollisionShape2D and child != collision:
			child.queue_free()
			remove_child(child)

	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = MISSILE_ANGULAR_DAMP
	gravity_scale = 0.0

func setup(p_owner_id: int, p_pos: Vector2, p_vel: Vector2, initial_heading: float) -> void:
	name = "Missile_" + str(p_owner_id) + "_" + str(randi())
	owner_id = p_owner_id
	position = p_pos
	linear_velocity = p_vel
	rotation = initial_heading
