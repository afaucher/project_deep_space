extends RigidBody2D
class_name Asteroid

# Sensor Signature Profile
var cross_section: float = 600.0 # Huge size (diameter)
var base_heat: float = 0.0       # Cold rock
var em_noise: float = 0.0        # No reactor
var density: float = 500.0       # Solid rock

const COLLISION_RADIUS := 300.0  # matches the collision circle below

# So the shared avoidance layer (Steering) can find and size rocks. Ships/stations
# are in "ships"; rocks are in "obstacles". Both expose get_bounding_radius().
func get_bounding_radius() -> float:
	return COLLISION_RADIUS

func get_signature() -> Dictionary:
	return {
		"cross_section": cross_section,
		"heat": base_heat,
		"em_noise": em_noise,
		"density": density,
		"vel": linear_velocity 
	}

func _ready() -> void:
	add_to_group("obstacles")   # so Steering avoidance can see rocks
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
	shape.radius = COLLISION_RADIUS
	collision.shape = shape
	add_child(collision)
