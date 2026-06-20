extends RigidBody2D
class_name Bouy

var cross_section: float = 10.0
var base_heat: float = 50.0 # High heat so it looks like a ship to sensors
var em_noise: float = 50.0
var density: float = 20.0
var health: float = 100.0
var is_dead: bool = false

func get_signature() -> Dictionary:
	return {
		"cross_section": cross_section,
		"heat": base_heat,
		"em_noise": em_noise,
		"density": density,
		"pos": position,
		"vel": linear_velocity,
		"owner_id": 999 # Hostile/Neutral IFF
	}

func take_damage(amount: float) -> void:
	if is_dead: return
	health -= amount
	if health <= 0:
		hulk()

func hulk() -> void:
	is_dead = true
	base_heat = 0.0
	em_noise = 0.0

func _ready() -> void:
	mass = 50.0
	inertia = 100.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 10.0
	collision.shape = shape
	add_child(collision)
