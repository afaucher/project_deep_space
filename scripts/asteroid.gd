extends RigidBody2D
class_name Asteroid

# Sensor Signature Profile
var cross_section: float = 600.0 # diameter; rescaled per-rock in _ready
var base_heat: float = 0.0       # Cold rock
var em_noise: float = 0.0        # No reactor
var density: float = 500.0       # Solid rock

# Rocks vary a little in size (outline v1.1 feedback). The per-rock radius is
# seeded from the rock's own QUANTIZED POSITION -- deterministic, so the same
# rock is always the same size across bubble promote/demote cycles and across
# runs, with zero spawner plumbing (matches the nav panel's rock-outline seed
# philosophy). Everything downstream reads get_bounding_radius(), so the
# collision shape, Steering avoidance margins, and the nav outline all scale
# together automatically.
const BASE_COLLISION_RADIUS := 300.0
const SIZE_VARIANCE_MIN := 0.8
const SIZE_VARIANCE_MAX := 1.15

var collision_radius: float = BASE_COLLISION_RADIUS

# So the shared avoidance layer (Steering) can find and size rocks. Ships/stations
# are in "ships"; rocks are in "obstacles". Both expose get_bounding_radius().
func get_bounding_radius() -> float:
	return collision_radius

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

	# Position-seeded size (see BASE_COLLISION_RADIUS comment). Position is
	# set by every spawner BEFORE add_child, so it's stable here; 64u grid
	# quantization keeps the seed stable under small collision drift.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(floor(position.x / 64.0)), int(floor(position.y / 64.0))))
	collision_radius = BASE_COLLISION_RADIUS * rng.randf_range(SIZE_VARIANCE_MIN, SIZE_VARIANCE_MAX)
	cross_section = collision_radius * 2.0  # sensors report the true diameter

	# Mass tracks area, inertia tracks disc scaling (r^4), normalized to the
	# long-standing authored values at the base radius.
	var scale_ratio: float = collision_radius / BASE_COLLISION_RADIUS
	mass = 5000.0 * scale_ratio * scale_ratio
	inertia = 10000.0 * pow(scale_ratio, 4.0)
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0

	# Add collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = collision_radius
	collision.shape = shape
	add_child(collision)
