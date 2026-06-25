extends RigidBody2D
class_name Ship

const WeaponBehaviorRegistry = preload("res://scripts/components/weapon_behavior_registry.gd")

# Mass is derived from each component's rect area x density, not authored directly.
# Calibrated so the default Frigate loadout (total area 2775 x density 20.0)
# reproduces its original flat mass of 100.0 -- smaller ships built from the
# same density naturally come out lighter.
const MASS_SCALE := 100.0 / 55500.0

# Inertia is likewise derived (point-mass approximation: sum of each component's
# mass x squared distance from ship center). Calibrated so the default Frigate
# loadout's raw sum (~40422.30) reproduces its original flat inertia of 1000.0.
const INERTIA_SCALE := 1000.0 / 40422.2973

# Combat heat from take_damage() decays at this rate (per second) instead of
# being overwritten outright by the per-frame heat/EM dispatch loop below --
# see _decay_damage_heat().
const DAMAGE_HEAT_DECAY_RATE := 20.0

# A damaged engine's EM baseline still drops with health (less power, less
# output -- physically right), but damage also adds a rectified oscillation
# on top so "damaged" reads as running rough, not just quieter. Frequency
# rises with damage but stays under 1Hz even at 100% so it's a player-visible
# pulse rather than aliasing into noise against sensor refresh rates -- see
# _engine_damage_oscillation().
const ENGINE_OSC_FREQ_BASE := 0.2   # Hz, lightly-damaged flicker rate (~5s period)
const ENGINE_OSC_FREQ_RANGE := 0.6  # Hz, added at 100% damage -> max 0.8Hz (~1.25s period)
const ENGINE_OSC_GAIN := 1.0        # crest height relative to power_rating at 100% damage

# A reactor crossing from alive to destroyed fires a one-shot EM "whiteout"
# scaled to its own power_rating (so Missile's tiny capacitor and Frigate's
# full reactor both decay over the same duration, not the same magnitude --
# see _update_reactor_whiteout()).
const REACTOR_WHITEOUT_MULTIPLIER := 5.0 # crest height relative to power_rating
const REACTOR_WHITEOUT_DURATION := 1.5   # seconds to decay to zero

# Flight-control feel constants (_physics_process). Smooth mode (steering_mode
# == 0) deliberately cuts rotational authority harder than linear throttle --
# it's meant to feel like a cruise/precision mode, not just "everything at
# half power" -- so torque and max-omega get their own, smaller ratios rather
# than reusing the throttle one.
const VELOCITY_CONTROL_GAIN := 2.0    # P-gain: required_accel = v_error * this
const SMOOTH_MODE_THRUST_RATIO := 0.5 # Smooth-mode throttle cap vs Combat's full +/-1.0
const SMOOTH_MODE_TORQUE_RATIO := 0.2 # Smooth-mode torque cap vs Combat's full ship_max_torque
const SMOOTH_MODE_OMEGA_RATIO := 0.25 # Smooth-mode max-omega cap vs Combat's full max_omega
const ROTATION_TRACKING_GAIN := 10.0  # required_alpha = omega_error * this -- how aggressively torque tracks the time-optimal turn curve

# Heat-budget constants (_physics_process). max_heat/heat_dissipation_rate
# below are per-ship-class vars (Missile overrides both -- see missile.gd),
# but the formulas that feed them are shared across every ship and live here.
const REACTOR_HEAT_COEFFICIENT := 2.0 # reactor_heat = this * reactor power slider (0-1)
const OVERHEAT_DAMAGE_RATE := 10.0    # HP/sec drained from reactors while current_heat is pegged at max_heat
const PASSIVE_COMPONENT_HEAT := 0.1   # flat heat leak per powered, alive, non-hull component
const PASSIVE_COMPONENT_EM := 0.5     # flat EM leak per powered, alive, non-hull component
const REACTOR_HEAT_FLOOR := 10.0      # a reactor's own resting heat even with no load
const SENSOR_HEAT_FLOOR := 5.0        # an active sensor's own resting heat even with no load

# classify_contact() thresholds. cross-section splits "small" (ordnance-sized)
# from "large" (vessel-sized) contacts; vessels get a higher heat bar than
# ordnance because a cold-running missile/torpedo should still read as a
# threat at a lower heat signature than a cold-running ship would need to.
const ORDNANCE_CS_THRESHOLD := 10.0    # cross_section below this reads as ordnance, not a vessel
const ACTIVE_EM_THRESHOLD := 5.0       # em_noise above this means "powered and active" for any object class
const ORDNANCE_HEAT_THRESHOLD := 5.0   # heat above this flags a small (ordnance-sized) contact as active
const VESSEL_HEAT_THRESHOLD := 10.0    # heat above this flags a large (vessel-sized) contact as active
const ASTEROID_DENSITY_THRESHOLD := 250.0 # denser than this (and big enough) reads as rock, not dead metal
const ASTEROID_CS_THRESHOLD := 50.0    # minimum size to be called an asteroid rather than wreckage debris
const UNKNOWN_DENSITY_DEFAULT := 500.0 # density assumed when a signature omits the field entirely

# Sensor fusion / contact tracking (_physics_process contact decay + correlate-tracks).
const CONTACT_TIMEOUT := 20.0          # seconds with no fresh detection before a tracked contact is dropped
const CONTACT_CORRELATION_RANGE := 2000.0 # max distance (no instance_id match) to fuse a new blip into an existing contact instead of starting a new one
const CONTACT_RESOLUTION_STALE_TIME := 0.3 # seconds since the last position update before a coarser-resolution bin is allowed to override position anyway
const CONTACT_FUSION_SMOOTHING := 0.8  # lerp weight toward each new reading -- shared by pos/vel/cross_section/heat/em_noise so none of them drift out of sync with the others
const PASSIVE_EM_NOISE_FLOOR := 15.0   # received EM (after range/direction falloff) below this is undetectable by passive sensors
const EM_FALLOFF_REFERENCE_DISTANCE := 10000.0 # distance at which received EM starts dropping below the broadcast value
const SENSOR_VELOCITY_NOISE := 0.05    # +/- fractional magnitude and +/- radian jitter applied to a sensor's reported target velocity

# take_damage() raymarch / damage-soak constants.
const DAMAGE_RAYMARCH_STEP := 2.0      # px per step along the hit ray when distributing damage across internal components
const MIN_EFFECTIVE_DENSITY := 0.05    # floor so a destroyed (0-health) component still has some soak, not an instant pass-through
const DAMAGE_ABSORPTION_PER_DENSITY := 50.0 # dmg_absorbed per step = effective_density * DAMAGE_RAYMARCH_STEP * this
const LASER_HEAT_MODIFIER := 0.5       # fraction of absorbed laser damage converted to component heat
const KINETIC_HEAT_MODIFIER := 0.05    # fraction of absorbed non-laser damage converted to component heat -- lasers run 10x hotter per point of damage

const SHIP_COLLISION_RADIUS := 50.0    # physical hit/collision circle radius -- separate from the cross_section sensor stat

# Point-defense engagement range. Currently a flat number rather than derived
# from the PD laser component's own authored `range` (4000.0) -- TODO:
# revisit as part of a future point-defense rework so this can't silently
# drift out of sync with the weapon data it's supposed to represent.
const PD_RANGE := 3500.0

const RCS_SFX_TORQUE_THRESHOLD := 100.0 # torque above this plays the RCS thruster sound cue

const HIT_TRACE_DURATION := 3.0 # seconds a damage-raymarch trace lingers for the engineering panel's spatial view to fade out

var owner_id: int = -1

func _init() -> void:
	subsystems = subsystems.duplicate(true)
	ship_components = ship_components.duplicate(true)
	iff_tags = iff_tags.duplicate(true)
	active_contacts = {}

var is_relay: bool = false
var target_thrust: float = 0.0
var target_velocity: float = 0.0
var target_heading: float = 0.0
var steering_mode: int = 0 # 0 = Smooth, 1 = Combat
var linear_mode: int = 0 # 0 = Throttle, 1 = Velocity

var max_omega: float = 2.0
var max_speed: float = 1000.0
var iff_tags: Array = []

var actual_throttle: float = 0.0

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

	{"id": "reactor_core", "type": "reactor", "rect": Rect2(-15, -5, 10, 10), "health": 200.0, "max_health": 200.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 100.0},
	{"id": "engine_main", "type": "engines", "rect": Rect2(-35, -10, 5, 20), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 100.0, "thrust_rating": 5000.0, "torque_rating": 10000.0},

	# Sensors: each logical sensor is its own physical hardpoint (1:1), replacing the old
	# hp_sensor_fwd/hp_sensor_omni boxes that pooled 5 sensors behind a guessed "parent" id.
	{"id": "dir_high_res", "type": "sensors", "rect": Rect2(30, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 20.0, "em_emission": 20.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 40000.0, "arc_width": PI / 6.0, "num_bins": 30, "refresh_interval": 0.5, "timer": 0.0, "heading": 0.0},
	{"id": "omni_main", "type": "sensors", "rect": Rect2(-5, -5, 5, 5), "health": 40.0, "max_health": 40.0, "density": 20.0, "heat": 0.0, "base_em_emission": 10.0, "em_emission": 10.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 40000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 2.0, "timer": 0.0, "heading": 0.0},
	{"id": "omni_short_hi_res", "type": "sensors", "rect": Rect2(0, -5, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 5.0, "em_emission": 5.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 5000.0, "arc_width": TAU, "num_bins": 180, "refresh_interval": 0.25, "timer": 0.0, "heading": 0.0},
	{"id": "passive_em", "type": "sensors", "rect": Rect2(-5, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"sensor_type": "passive_em", "active": true, "range": 80000.0, "arc_width": TAU, "num_bins": 360, "refresh_interval": 1.0, "timer": 0.0, "heading": 0.0},
	{"id": "omni_collision", "type": "sensors", "rect": Rect2(0, 0, 5, 5), "health": 20.0, "max_health": 20.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 1500.0, "arc_width": TAU, "num_bins": 8, "refresh_interval": 0.1, "timer": 0.0, "heading": 0.0},

	# Weapons: ammo/cooldown/range/damage/heading/arc_width folded in from the old `weapons` Dict.
	# "mount_pos" dropped — origin is derived via get_component_origin() == rect.position.
	{"id": "hp_fwd_laser", "type": "weapons", "rect": Rect2(30, -7.5, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": 0.0, "arc_width": PI / 3.0},
	{"id": "hp_fwd_missile", "type": "weapons", "rect": Rect2(30, 2.5, 15, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 10, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": 0.0, "arc_width": PI / 3.0},

	{"id": "hp_port_laser_1", "type": "weapons", "rect": Rect2(17.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_port_tube_1", "type": "weapons", "rect": Rect2(7.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_port_tube_2", "type": "weapons", "rect": Rect2(-2.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_port_tube_3", "type": "weapons", "rect": Rect2(-12.5, -30, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_port_laser_2", "type": "weapons", "rect": Rect2(-22.5, -20, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": -PI / 2.0, "arc_width": PI / 2.0},

	{"id": "hp_stbd_laser_1", "type": "weapons", "rect": Rect2(17.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_stbd_tube_1", "type": "weapons", "rect": Rect2(7.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_stbd_tube_2", "type": "weapons", "rect": Rect2(-2.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_stbd_tube_3", "type": "weapons", "rect": Rect2(-12.5, 15, 5, 15), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "missile", "ammo": 5, "cooldown": 0.0, "cooldown_max": 5.0, "range": 28000.0, "heading": PI / 2.0, "arc_width": PI / 2.0},
	{"id": "hp_stbd_laser_2", "type": "weapons", "rect": Rect2(-22.5, 15, 5, 5), "health": 150.0, "max_health": 150.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
		"weapon_type": "laser", "ammo": 999, "cooldown": 0.0, "cooldown_max": 1.0, "range": 4000.0, "damage": 500.0, "heading": PI / 2.0, "arc_width": PI / 2.0}
]

# Per-ship-class heat budget (overridden by Missile -- see missile.gd). These
# are vars, not consts, specifically so each ship class can have its own
# thermal envelope; the Frigate baseline values below were picked so a
# fully-loaded reactor (REACTOR_HEAT_COEFFICIENT * 1.0 power) plus full-burn
# engines roughly fills max_heat over several seconds of sustained combat,
# not so fast overheat punishes a single alpha strike, not so slow it's never
# a real constraint.
var current_heat: float = 10.0 # ambient starting heat, same order as REACTOR_HEAT_FLOOR
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
	var density = signature.get("density", UNKNOWN_DENSITY_DEFAULT)

	# 1. Size check (Ordnance)
	if cs < ORDNANCE_CS_THRESHOLD and (em > ACTIVE_EM_THRESHOLD or heat > ORDNANCE_HEAT_THRESHOLD):
		if is_friendly:
			return "FRIENDLY ORDNANCE"
		else:
			return "INCOMING ORDNANCE"

	# 2. Emission check (Vessels)
	if cs >= ORDNANCE_CS_THRESHOLD and (em > ACTIVE_EM_THRESHOLD or heat > VESSEL_HEAT_THRESHOLD):
		if is_friendly:
			return "FRIENDLY VESSEL"
		else:
			return "UNIDENTIFIED VESSEL"

	# 3. Density check (Dead objects / Cold ships)
	if em <= ACTIVE_EM_THRESHOLD and heat <= VESSEL_HEAT_THRESHOLD:
		if density > ASTEROID_DENSITY_THRESHOLD and cs > ASTEROID_CS_THRESHOLD:
			return "ASTEROID"
		elif density <= ASTEROID_DENSITY_THRESHOLD:
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

func get_components_by_type(type: String) -> Array:
	return ship_components.filter(func(c): return c["type"] == type)

func get_component(comp_id: String) -> Dictionary:
	for c in ship_components:
		if c["id"] == comp_id:
			return c
	return {}

func get_component_origin(comp: Dictionary) -> Vector2:
	return comp["rect"].position

# M1b: mass and power rating are summed from components instead of being flat
# ship-level constants, so a "dual reactor"/"dual engine" ship degrades to
# whatever's still alive instead of needing special-casing.
func get_ship_mass() -> float:
	var total = 0.0
	for c in ship_components:
		var area = c["rect"].size.x * c["rect"].size.y
		total += area * c["density"] * MASS_SCALE
	return total

# Point-mass approximation: treats each component as a point mass at its rect
# centroid, ignores each box's own rotational inertia about its own center.
# Close enough for "roughly the right shape" -- not meant to be exact physics.
func get_ship_inertia() -> float:
	var total = 0.0
	for c in ship_components:
		var area = c["rect"].size.x * c["rect"].size.y
		var mass = area * c["density"] * MASS_SCALE
		var centroid = c["rect"].position + c["rect"].size / 2.0
		total += mass * centroid.length_squared()
	return total * INERTIA_SCALE

# Generic "sum a rating field across components of a type" helper -- powers
# get_total_power_rating, get_ship_max_thrust, get_ship_max_torque, etc.
# Weighted by health and gated by powered state, same as get_sys_health.
func get_total_rating(sys_type: String, field: String) -> float:
	var total = 0.0
	for c in ship_components:
		if c["type"] == sys_type and is_component_powered(c["id"]):
			total += c.get(field, 0.0) * get_component_health_ratio(c["id"])
	return total

func get_max_rating(sys_type: String, field: String) -> float:
	var total = 0.0
	for c in ship_components:
		if c["type"] == sys_type:
			total += c.get(field, 0.0)
	return total

func get_total_power_rating(sys_type: String) -> float:
	return get_total_rating(sys_type, "power_rating")

func get_max_power_rating(sys_type: String) -> float:
	return get_max_rating(sys_type, "power_rating")

# thrust_rating/torque_rating are authored per-engine-component fields, summed
# the same way power_rating is -- not derived from area/density, since that
# breaks ship-to-ship balance ratios that were deliberately tuned (see M1b
# appendix). A dual-engine ship's total degrades correctly if one dies.
func get_ship_max_thrust() -> float:
	return get_total_rating("engines", "thrust_rating")

func get_ship_max_torque() -> float:
	return get_total_rating("engines", "torque_rating")

# This engine's own share of the ship-wide throttle/torque heat -- apportioned
# by its share of total live thrust, with its own (not the fleet-wide) health
# ratio driving inefficiency. Reduces to "ship-wide heat, thrust_share = 1.0"
# for any ship with exactly one engine (every ship today).
func _engine_heat_contribution(comp: Dictionary, throttle: float, applied_torque: float, max_torque_now: float, ship_max_thrust: float) -> float:
	if not is_component_powered(comp["id"]) or ship_max_thrust <= 0.0:
		return 0.0
	var ratio = get_component_health_ratio(comp["id"])
	var inefficiency = max(1.0, 1.0 / max(0.1, ratio))
	var thrust_share = (comp.get("thrust_rating", 0.0) * ratio) / ship_max_thrust
	var h = abs(throttle) * 10.0 * subsystems["engines"]["power"] * inefficiency * thrust_share
	h += (abs(applied_torque) / max(1.0, max_torque_now)) * 5.0 * subsystems["engines"]["power"] * inefficiency * thrust_share
	return h

# Same fix as _engine_heat_contribution, for reactors: apportion the ship-wide
# slider-driven reactor heat by each reactor's share of total live power_rating
# instead of pooling the same value into every reactor component.
func _reactor_heat_contribution(comp: Dictionary, reactor_heat_total: float, ship_reactor_rating: float) -> float:
	if not is_component_powered(comp["id"]) or ship_reactor_rating <= 0.0:
		return 0.0
	var ratio = get_component_health_ratio(comp["id"])
	var reactor_share = (comp.get("power_rating", 0.0) * ratio) / ship_reactor_rating
	return reactor_heat_total * reactor_share

# Rectified, damage-scaled oscillation added on top of an engine's
# proportional-to-health EM baseline. Zero at full health; amplitude AND
# frequency both rise with damage (see ENGINE_OSC_* above). Phase is its own
# running accumulator (not wall-clock time) so the stutter restarts cleanly
# whenever a fresh injury starts it back up, instead of phase depending on
# how long the ship has existed.
func _engine_damage_oscillation(comp: Dictionary, health_ratio: float, delta: float) -> float:
	var damage_ratio = 1.0 - health_ratio
	if damage_ratio <= 0.0:
		comp["em_osc_phase"] = 0.0
		return 0.0
	var osc_freq = ENGINE_OSC_FREQ_BASE + damage_ratio * ENGINE_OSC_FREQ_RANGE
	var phase = comp.get("em_osc_phase", 0.0) + TAU * osc_freq * delta
	comp["em_osc_phase"] = phase
	return absf(sin(phase)) * damage_ratio * comp.get("power_rating", 0.0) * ENGINE_OSC_GAIN

# One-shot "reactor destroyed" EM whiteout: triggers once when health crosses
# from alive to dead, then decays over REACTOR_WHITEOUT_DURATION regardless of
# reactor size (a fixed decay-per-second constant would make bigger reactors'
# pulses linger longer for no reason).
func _update_reactor_whiteout(comp: Dictionary, delta: float) -> float:
	if comp.get("_prev_health", comp["health"]) > 0.0 and comp["health"] <= 0.0:
		var magnitude = comp.get("power_rating", 0.0) * REACTOR_WHITEOUT_MULTIPLIER
		comp["em_pulse"] = magnitude
		comp["_em_pulse_decay_rate"] = magnitude / REACTOR_WHITEOUT_DURATION
	comp["_prev_health"] = comp["health"]
	var pulse = max(0.0, comp.get("em_pulse", 0.0) - comp.get("_em_pulse_decay_rate", 0.0) * delta)
	comp["em_pulse"] = pulse
	return pulse

# Decays a component's combat-damage heat burst (from take_damage()) and
# returns the remaining amount so callers can add it on top of their own
# steady-state heat instead of it being clobbered outright.
func _decay_damage_heat(comp: Dictionary, delta: float) -> float:
	var damage_heat = max(0.0, comp.get("damage_heat", 0.0) - DAMAGE_HEAT_DECAY_RATE * delta)
	comp["damage_heat"] = damage_heat
	return damage_heat

# EM emission pattern is a function of component type, not an authored field:
# sensors and weapons already carry their own heading/arc_width (used for
# sensing/engagement arcs), so they emit directionally through that same
# cone for free. Everything else (reactor, engine, passive leakage) has no
# natural facing and stays omnidirectional.
func _is_directional_emitter(comp: Dictionary) -> bool:
	return comp["type"] == "sensors" or comp["type"] == "weapons"

# How much of one component's em_emission a receiver at angle_from_target
# (world-space angle from the receiver back to the emitting ship) actually
# sees, given the emitting ship's rotation. Omni sources use the existing
# rear-aspect dipole bias; directional sources (sensors/weapons) fall off
# across their own mount arc, same shape as the old sensor-only cone code.
func _received_em_power(comp: Dictionary, target_rotation: float, angle_from_target: float) -> float:
	var em_emission = comp.get("em_emission", 0.0)
	if em_emission <= 0.0:
		return 0.0
	if not _is_directional_emitter(comp):
		var relative_angle = angle_from_target - target_rotation
		var rear_bias = 1.0 + 0.5 * max(0.0, cos(relative_angle + PI))
		return em_emission * rear_bias
	var comp_heading = target_rotation + comp.get("heading", 0.0)
	var arc = comp.get("arc_width", TAU)
	var diff = abs(wrapf(angle_from_target - comp_heading, -PI, PI))
	if diff > arc / 2.0:
		return 0.0
	return em_emission * (1.0 - diff / (arc / 2.0))

# Sums received EM across every emitter a target's get_signature() exposes,
# replacing the old "one rear-biased scalar + sensor_config-only cone spikes"
# split with one consistent per-component pass.
func _total_received_em(sig: Dictionary, angle_from_target: float) -> float:
	var target_rotation = sig.get("rot", 0.0)
	var total = 0.0
	for comp in sig.get("em_emitters", []):
		total += _received_em_power(comp, target_rotation, angle_from_target)
	return total

# Fraction of rated power currently available for sys_type (0 if no such
# components exist). Reduces to is_component_powered(id) ? health_ratio : 0
# when there's exactly one component of that type, so it's a drop-in
# replacement for the old single-hardcoded-id checks.
func get_power_ratio(sys_type: String) -> float:
	var max_rating = get_max_power_rating(sys_type)
	if max_rating <= 0.0:
		return 0.0
	return get_total_power_rating(sys_type) / max_rating

# Legacy getters
var health: float:
	get: return get_sys_health("hull")
	set(value): pass # Obsolete, damage uses volumetric now

var base_heat: float:
	get: return current_heat

var em_noise: float:
	get:
		var noise = 5.0 * subsystems["reactor"]["power"]
		for s in get_components_by_type("sensors"):
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
		var step_size = DAMAGE_RAYMARCH_STEP
		
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
			"time_remaining": HIT_TRACE_DURATION
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
					var effective_density = max(MIN_EFFECTIVE_DENSITY, comp["density"] * health_ratio)

					var dmg_absorbed = min(remaining_damage, effective_density * step_size * DAMAGE_ABSORPTION_PER_DENSITY)
					if dmg_absorbed > 0:
						comp["health"] -= dmg_absorbed

						# Laser hits add significantly more heat to the component
						var heat_modifier = LASER_HEAT_MODIFIER if damage_type == "laser" else KINETIC_HEAT_MODIFIER
						var heat_generated = dmg_absorbed * heat_modifier
						
						# Burst lives in its own field and decays over time (see
						# _decay_damage_heat) instead of comp["heat"], which the
						# per-frame dispatch loop below recomputes from scratch.
						comp["damage_heat"] = comp.get("damage_heat", 0.0) + heat_generated
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
		"sensor_config": get_components_by_type("sensors"),
		"em_emitters": get_components_by_type("reactor") + get_components_by_type("engines") + get_components_by_type("sensors") + get_components_by_type("weapons"),
		"contacts": active_contacts
	}

func _ready() -> void:
	if owner_id == -1:
		owner_id = int(name.replace("Ship_", ""))
		
	add_to_group("ships")

	mass = get_ship_mass()
	inertia = get_ship_inertia()
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0 # No drag in space
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0 # No drag in space
	
	# Add collision shape so raycasts can hit the ship
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = SHIP_COLLISION_RADIUS
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
	for s in get_components_by_type("sensors"):
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
	for s in get_components_by_type("sensors"):
		s["active"] = is_active

@rpc("any_peer", "call_local")
func set_sensor_target(target_id: String) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_remote_sender_id() != owner_id and multiplayer.get_remote_sender_id() != 1:
		if multiplayer.get_remote_sender_id() != 0: pass
	manual_sensor_target = target_id

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		for w in get_components_by_type("weapons"):
			if w["cooldown"] > 0:
				var cooldown_rate = 1.0
				var ratio = get_component_health_ratio(w["id"])
				if ratio > 0.0:
					cooldown_rate = ratio
				w["cooldown"] -= delta * cooldown_rate
				
		if not is_dead:
			_process_point_defense()
		
	var forward = Vector2.RIGHT.rotated(rotation)
	var current_forward_speed = linear_velocity.dot(forward)
	
	var active_max_thrust = get_ship_max_thrust()

	if linear_mode == 0:
		# Direct Throttle Control
		actual_throttle = target_thrust
	else:
		# Velocity Control (PID/Bang-Bang)
		var v_error = target_velocity - current_forward_speed
		var required_accel = v_error * VELOCITY_CONTROL_GAIN
		var required_force = required_accel * mass
		if active_max_thrust > 0.0:
			actual_throttle = required_force / active_max_thrust
		else:
			actual_throttle = 0.0
		
	# Apply limits based on steering mode
	if steering_mode == 0:
		actual_throttle = clampf(actual_throttle, -SMOOTH_MODE_THRUST_RATIO, SMOOTH_MODE_THRUST_RATIO)
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
	
	var engine_power_slider = subsystems["engines"]["power"]
	var ship_max_torque = get_ship_max_torque()

	var torque = 0.0
	var active_max_torque = 0.0
	if ship_max_torque > 0.0 and engine_power_slider > 0.0:
		active_max_torque = (ship_max_torque if steering_mode == 1 else ship_max_torque * SMOOTH_MODE_TORQUE_RATIO) * engine_power_slider
		var active_max_omega = (max_omega if steering_mode == 1 else max_omega * SMOOTH_MODE_OMEGA_RATIO) * get_power_ratio("engines") * engine_power_slider
		
		var alpha_max = active_max_torque / inertia
		
		var target_omega = sign(angle_diff) * sqrt(2.0 * alpha_max * abs(angle_diff))
		target_omega = clampf(target_omega, -active_max_omega, active_max_omega)
		
		var omega_error = target_omega - angular_velocity
		var required_alpha = omega_error * ROTATION_TRACKING_GAIN
		
		torque = required_alpha * inertia
		torque = clampf(torque, -active_max_torque, active_max_torque)
		
		apply_torque(torque)
	
	if abs(torque) > RCS_SFX_TORQUE_THRESHOLD:
		if is_my_ship and not sfx_rcs.playing:
			sfx_rcs.play()
	else:
		if sfx_rcs.playing:
			sfx_rcs.stop()
	
	# Pin dir_high_res scanner to forward
	for s in get_components_by_type("sensors"):
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
			
		if c["last_seen_timer"] > CONTACT_TIMEOUT:
			to_remove.append(c_id)
	for c_id in to_remove:
		active_contacts.erase(c_id)
	
	var bins_this_frame = []

	# --- Heat & Engineering Logic ---
	if is_multiplayer_authority():
		var heat_gen = 0.0
		var reactor_heat = REACTOR_HEAT_COEFFICIENT * subsystems["reactor"]["power"]
		var ship_reactor_rating = get_total_power_rating("reactor")
		var ship_max_thrust = get_ship_max_thrust()

		var total_reactor_heat = 0.0
		for rct in get_components_by_type("reactor"):
			total_reactor_heat += _reactor_heat_contribution(rct, reactor_heat, ship_reactor_rating)

		var total_engine_heat = 0.0
		for eng in get_components_by_type("engines"):
			total_engine_heat += _engine_heat_contribution(eng, actual_throttle, torque, active_max_torque, ship_max_thrust)

		var passive_heat = 0.0
		var passive_em = 0.0
		for comp in ship_components:
			if comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull":
				passive_heat += PASSIVE_COMPONENT_HEAT
				passive_em += PASSIVE_COMPONENT_EM

		heat_gen = total_reactor_heat + total_engine_heat + passive_heat
		current_heat_gen = heat_gen
		
		current_heat += heat_gen * delta
		var active_dissipation = heat_dissipation_rate * get_power_ratio("reactor")
		current_heat -= active_dissipation * delta
		current_heat = clampf(current_heat, 0.0, max_heat)
		
		if current_heat >= max_heat:
			for c in ship_components:
				if c["type"] == "reactor":
					c["health"] -= OVERHEAT_DAMAGE_RATE * delta

		# Update Component EM & Heat
		var base_em = get_total_power_rating("reactor") * subsystems["reactor"]["power"]
		var current_em = base_em + (abs(actual_throttle) * get_total_power_rating("engines"))
		var sensor_em = 0.0
		var sensor_power_ratio = get_sys_health("sensors") / max(1.0, get_sys_max_health("sensors"))
		if sensor_power_ratio > 0.0:
			for s in get_components_by_type("sensors"):
				if s.get("active", true):
					sensor_em += s.get("base_em_emission", 0.0) * sensor_power_ratio
		
		for comp in ship_components:
			var b_heat = PASSIVE_COMPONENT_HEAT if (comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull") else 0.0
			var b_em = PASSIVE_COMPONENT_EM if (comp.get("powered_on", true) and comp.get("health", 0.0) > 0.0 and comp["type"] != "hull") else 0.0

			if comp["type"] == "reactor":
				comp["heat"] = REACTOR_HEAT_FLOOR + _reactor_heat_contribution(comp, reactor_heat, ship_reactor_rating) + _decay_damage_heat(comp, delta)
				comp["em_emission"] = comp.get("power_rating", 0.0) * get_component_health_ratio(comp["id"]) + _update_reactor_whiteout(comp, delta)
			elif comp["type"] == "engines":
				comp["heat"] = b_heat + _engine_heat_contribution(comp, actual_throttle, torque, active_max_torque, ship_max_thrust) + _decay_damage_heat(comp, delta)
				var engine_health_ratio = get_component_health_ratio(comp["id"])
				comp["em_emission"] = b_em + abs(actual_throttle) * comp.get("power_rating", 0.0) * engine_health_ratio + _engine_damage_oscillation(comp, engine_health_ratio, delta)
			elif comp["type"] == "sensors":
				comp["heat"] = b_heat + SENSOR_HEAT_FLOOR + _decay_damage_heat(comp, delta)
				comp["em_emission"] = b_em + comp.get("base_em_emission", 0.0) * sensor_power_ratio
			elif comp["type"] == "weapons":
				comp["heat"] = b_heat + _decay_damage_heat(comp, delta)
				WeaponBehaviorRegistry.get_behavior(comp["weapon_type"]).tick(self, comp, delta)
				comp["em_emission"] += b_em
			else:
				# Hull and other non-generating types have no steady-state heat
				# of their own, but still carry combat-damage burst + decay.
				comp["heat"] = _decay_damage_heat(comp, delta)
				comp["em_emission"] = 0.0

		# Computed after the loop above so weapon fire pulses (just updated by
		# WeaponBehavior.tick()) are reflected the same frame instead of lagging
		# by one tick.
		var weapon_em = 0.0
		for w in get_components_by_type("weapons"):
			weapon_em += w.get("em_emission", 0.0)
		em_signature = current_em + sensor_em + passive_em + weapon_em

	# Sensor Sweeps
	var active_sensor_efficiency = (get_sys_health("sensors") / max(1.0, get_sys_max_health("sensors"))) * subsystems["sensors"]["power"]
	
	for sensor in get_components_by_type("sensors"):
		if not is_component_powered(sensor["id"]):
			active_sensor_sweeps[sensor["id"]] = []
			continue

		var sensor_health_ratio = get_component_health_ratio(sensor["id"])
		if sensor_health_ratio <= 0.0 or active_sensor_efficiency <= 0.1:
			continue

		if not sensor.get("active", true):
			active_sensor_sweeps[sensor["id"]] = []
			continue

		sensor["timer"] -= delta
		if sensor["timer"] <= 0.0:
			sensor["timer"] = sensor["refresh_interval"]
			var active_range = sensor["range"] * sensor_health_ratio
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
			var closest_dist = CONTACT_CORRELATION_RANGE
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
			
			if bin_angle <= current_res or time_since_pos > CONTACT_RESOLUTION_STALE_TIME:
				c["pos"] = c["pos"].lerp(bin_pos, CONTACT_FUSION_SMOOTHING)
				c["vel"] = c["vel"].lerp(bin.get("vel", Vector2.ZERO), CONTACT_FUSION_SMOOTHING)
				c["resolution"] = bin_angle
				c["pos_timer"] = 0.0

				if bin.has("cross_section"): c["signature"]["cross_section"] = lerp(c["signature"].get("cross_section", 0.0), bin.get("cross_section", 0.0), CONTACT_FUSION_SMOOTHING)
				if bin.has("heat"): c["signature"]["heat"] = lerp(c["signature"].get("heat", 0.0), bin.get("heat", 0.0), CONTACT_FUSION_SMOOTHING)
				if bin.has("em_noise"): c["signature"]["em_noise"] = lerp(c["signature"].get("em_noise", 0.0), bin.get("em_noise", 0.0), CONTACT_FUSION_SMOOTHING)
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
	var origin = position + get_component_origin(sensor).rotated(rotation)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = use_range
	query.shape = shape
	query.transform = Transform2D(0, origin)

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
			
			var dist = origin.distance_to(collider.position)

			var ray_query = PhysicsRayQueryParameters2D.create(origin, collider.position)
			ray_query.exclude = [self]
			var ray_res = space_state.intersect_ray(ray_query)
			if ray_res and ray_res.collider != collider:
				continue # Blocked by obstacle

			# Heat (sig["heat"]) intentionally has NO distance/direction falloff
			# model, unlike EM above -- an active sensor that detects the target
			# at all (range/arc/LOS) reports its true current_heat unmodified.
			# This is a deliberate scope cut for now, not an oversight: give heat
			# the same observation-fidelity treatment as EM later if it's wanted.
			if sensor.get("sensor_type", "active") == "passive_em":
				# Sums every emitter's own contribution (omni rear-bias or
				# directional cone falloff per _received_em_power) instead of
				# one rear-biased scalar plus a sensor-only cone bolt-on.
				var angle_from_target = (origin - collider.position).angle()
				var em_power = _total_received_em(sig, angle_from_target)

				var received_em = em_power * (EM_FALLOFF_REFERENCE_DISTANCE / max(EM_FALLOFF_REFERENCE_DISTANCE, dist))
				if received_em < PASSIVE_EM_NOISE_FLOOR:
					continue # Passive EM only detects targets above noise floor (after falloff)

				# Report what was actually received (direction + distance
				# falloff applied), not the raw broadcast value -- otherwise
				# the directional model only ever gated detection, never what
				# gets classified/displayed once detected.
				sig["em_noise"] = received_em

			var angle = (collider.position - origin).angle()

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
				if sensor.get("sensor_type", "active") == "passive_em":
					sig.erase("cross_section")
					sig.erase("heat") # passive EM doesn't sense heat at all, by design
					sig.erase("density")
					# sig["em_noise"] is already the received (direction +
					# distance falloff applied) value set above.
					
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
		merged["pos"] = origin + Vector2(weighted_dist, 0).rotated(bin_center_angle)
		
		# Cheat velocity with noise
		var noisy_vel = weighted_vel * (1.0 + randf_range(-SENSOR_VELOCITY_NOISE, SENSOR_VELOCITY_NOISE))
		noisy_vel = noisy_vel.rotated(randf_range(-SENSOR_VELOCITY_NOISE, SENSOR_VELOCITY_NOISE))
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
			
	var weapon_data = get_component(weapon_id)
	if weapon_data.is_empty():
		print("fire_weapon failed: unknown weapon ", weapon_id)
		return

	var behavior = WeaponBehaviorRegistry.get_behavior(weapon_data["weapon_type"])
	if not behavior.can_fire(self, weapon_data, target_contact_id):
		print("fire_weapon failed: cannot fire ", weapon_id)
		return

	behavior.execute_fire(self, weapon_data, target_pos, target_contact_id)

func _process_point_defense() -> void:
	var main_node = get_tree().current_scene
	if not is_instance_valid(main_node): return
	
	var ready_lasers = []
	for w in get_components_by_type("weapons"):
		if w["weapon_type"] == "laser" and w["ammo"] > 0 and w["cooldown"] <= 0.0:
			if is_component_powered(w["id"]):
				ready_lasers.append(w["id"])
				
	if ready_lasers.is_empty():
		return

	var pd_range = PD_RANGE
	var behavior = WeaponBehaviorRegistry.get_behavior("laser")

	for c_id in active_contacts:
		if ready_lasers.is_empty(): break

		var contact = active_contacts[c_id]
		if contact.get("classification", "") == "INCOMING ORDNANCE":
			var body = instance_from_id(contact.get("instance_id", -1))
			if not is_instance_valid(body) or body == self: continue
			if body is Ship and body.is_dead: continue

			var dist = position.distance_to(body.position)
			if dist > pd_range: continue

			for w_id in ready_lasers:
				var weapon_data = get_component(w_id)

				if behavior.can_fire(self, weapon_data, c_id):
					var start_pos = position + get_component_origin(weapon_data).rotated(rotation)
					behavior.execute_fire(self, weapon_data, body.position, c_id)

					transient_events.append({
						"type": "laser",
						"start_pos": start_pos,
						"end_pos": body.position
					})

					print("[PD] ", name, " shooting at ", body.name, " (", c_id, ")")
					ready_lasers.erase(w_id)
					break



func apply_control_input(thrust: float, t_vel: float, heading: float, s_mode: int, l_mode: int) -> void:
	target_thrust = clampf(thrust, -1.0, 1.0)
	target_velocity = clampf(t_vel, -max_speed, max_speed)
	target_heading = heading
	steering_mode = s_mode
	linear_mode = l_mode



