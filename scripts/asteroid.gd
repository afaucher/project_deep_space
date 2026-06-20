extends RigidBody2D
class_name Asteroid

# Sensor Signature Profile
var cross_section: float = 300.0 # Huge size
var base_heat: float = 0.0       # Cold rock
var em_noise: float = 0.0        # No reactor
var density: float = 100.0       # Solid rock

func get_signature() -> Dictionary:
	return {
		"cross_section": cross_section,
		"heat": base_heat,
		"em_noise": em_noise,
		"density": density,
		"vel": linear_velocity 
	}

func _ready() -> void:
	mass = 5000.0
	inertia = 10000.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	
	# Add collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 300.0
	collision.shape = shape
	add_child(collision)
