extends "res://scripts/ships/ship.gd"
class_name Mine

# M27 -- DRONE-tier space mine. 5-rect plus silhouette (the "plus" archetype --
# design_ideas/hull_shape_grammar.md §2): a compact functional core (reactor,
# engine, rcs, laser, sensors) with 4 hull arms stamped around it via
# HullBuilder.rotate_90 -- rotate_90's first real consumer outside its own
# synthetic unit tests (see grammar-friction note below).
#
# Targets (design_ideas/ship_parameter_table.md M27 pre-step row): mass ~4,
# DRONE tier, single laser (DRONE STANDARD mark, 150 dmg / 2200 range),
# passive_em + a small always-on active short-range sensor satisfying
# PD-coherence (refresh <= 0.5s, bins >= 36), a TINY station-keeping engine
# (DRONE tier requires an engine per the validator's mobility rule; handling
# stays inside the DRONE band [0,200]/[0,3] -- this hull never really "flies",
# the engine exists to satisfy the structural rule and to arrest any drift).
#
# Low EM posture: per the plan, "run dark" (an authored low-power/passive-only
# mode the mine can drop into once no contact is nearby) is explicitly FUTURE
# WORK, not built here. This milestone's mine always runs its reactor + one
# small active short-range sensor, so its EM floor is low-but-nonzero, not
# zero (see ship_parameter_table.md's "designed to run dark long-term (future
# work)" signature note for this hull).
#
# static func design() + thin _init() per fleet convention.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

# ---------------------------------------------------------------------------
# Grammar friction notes (per M27 plan -- report every place the grammar
# couldn't express something):
#  - rotate_90 itself worked cleanly for the 4 hull arms (author the +X arm
#    once, stamp n=1..3 for the other 3 faces) -- Rect2's exact-90-degree
#    corner rotation (HullBuilder._rotate_point_90) reproduces axis-aligned
#    rects with no drift, so the 4 arms are exact copies of what hand-rotated
#    Rect2 math would have produced. BUT rotate_90 rotates about the world
#    origin, so it only stamps a face-flush "plus" if the core's footprint is
#    symmetric under 90-degree rotation about that origin -- getting there
#    required deliberately squaring the core's bounding box (see below), not
#    just wiring the 6 catalog parts together at their natural sizes.
#  - The functional core (reactor/engine/rcs/laser/sensor x2) is NOT itself a
#    HullBuilder shape -- Parts.make() covers every one of those families, but
#    there is no builder for "pack N differently-sized functional components
#    into a square core block". The 6 parts' natural catalog footprints
#    (engine 5x5, laser 4x4, reactor 3x3, rcs 2x2, sensor 2x2 x2) don't tile
#    into a square on their own -- two small hull filler shims
#    (hull_fill_ne, hull_fill_se) were needed to both bridge gaps between
#    parts AND square off the core's outer boundary to exactly (-5,-5,10,10)
#    so all 4 rotate_90 arm copies land flush against it. This is the same
#    "fill shim" idiom LAC uses (hull_fill_port/hull_fill_stbd) for a
#    different reason (there: filling a taper gap; here: forcing rotational
#    symmetry) -- arguably a case for a future
#    "pack_square(parts, target_size)" builder, noted as friction rather than
#    invented ad hoc.
#  - health_per_area under-healths these tiny DRONE shims/arms (area 4-15 at
#    DRONE STANDARD hpa 1.5 -> health 6-22.5; the DRONE hull band floor is 10)
#    -- same open decision already flagged in hull_shape_grammar.md §9 from
#    LAC's fill shims. Followed the fleet's existing workaround: a flat
#    band-floor-respecting health per shim/arm rather than area * hpa.
#  - passive_em and the short-range active sensor both come from
#    Parts.make("sensor", ..., {"sensor_kind": ...}) -- the sensor family's
#    two relevant sub-kinds (passive_em, omni_pd) cover this hull's PD-
#    coherence needs exactly; no override friction.
# ---------------------------------------------------------------------------

static func design() -> Array:
	var comps: Array = []

	# --- FUNCTIONAL CORE, squared to exactly (-5,-5,10,10) -----------------
	# NW quadrant: engine, DRONE COMPACT mark (5x5, exact quadrant fit) --
	# tiny station-keeping thruster, bolted to the aft (-X) face by
	# convention (engines' active face is always -X regardless of heading --
	# see ship_design_validator.gd's _active_face_dir).
	comps.append(Parts.make("engine", ComponentSpec.Tier.DRONE, Parts.Mark.COMPACT,
		Vector2(-5, -5), {"id": "engine_main"}))

	# NE quadrant: laser (DRONE STANDARD mark, 150 dmg / 2200 range per
	# parts_catalog.gd), forward-facing (+X). Laser is 4x4, one unit
	# narrower than the 5-wide quadrant -- hull_fill_ne bridges the gap to
	# engine's edge (x=0) so laser stays connected without touching engine
	# directly.
	comps.append({"id": "hull_fill_ne", "type": "hull", "rect": Rect2(0, -5, 1, 4), "health": 15.0, "max_health": 15.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})
	comps.append(Parts.make("laser", ComponentSpec.Tier.DRONE, Parts.Mark.STANDARD,
		Vector2(1, -5), {"id": "laser_main", "heading": 0.0}))

	# SW quadrant: reactor (DRONE COMPACT, 3x3) stacked over rcs (DRONE
	# COMPACT, 2x2) -- together span the same 5-tall quadrant as engine
	# above them, touching engine along the shared y=0 edge.
	comps.append(Parts.make("reactor", ComponentSpec.Tier.DRONE, Parts.Mark.COMPACT,
		Vector2(-5, 0), {"id": "reactor_core"}))
	comps.append(Parts.make("rcs", ComponentSpec.Tier.DRONE, Parts.Mark.COMPACT,
		Vector2(-5, 3), {"id": "rcs_main"}))

	# SE quadrant: passive EM sensor (bearing-only, no active emission) +
	# the small always-on active short-range sensor (PD-coherence --
	# omni_pd sub-kind: refresh_interval well under the validator's 0.5s
	# ceiling, num_bins well over its 36 floor, per
	# ship_design_validator.gd's PD_SENSOR_* consts), stacked, plus a hull
	# filler squaring this quadrant's outer edge to y=5 (needed so the +Y
	# arm below has a flush face to attach to).
	comps.append(Parts.make("sensor", ComponentSpec.Tier.DRONE, Parts.Mark.COMPACT,
		Vector2(0, 0), {"id": "sensor_active_short", "sensor_kind": "omni_pd"}))
	comps.append(Parts.make("sensor", ComponentSpec.Tier.DRONE, Parts.Mark.COMPACT,
		Vector2(0, 2), {"id": "sensor_passive", "sensor_kind": "passive_em"}))
	comps.append({"id": "hull_fill_se", "type": "hull", "rect": Rect2(2, 0, 3, 5), "health": 22.0, "max_health": 22.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	# --- HULL PLUS: one arm, rotate_90 x4 ----------------------------------
	# Core is now an exact square, (-5,-5,10,10) -- symmetric under 90-degree
	# rotation about the origin, so one arm authored on the +X face (core
	# edge x=5, spanning the core's full y -2..2 center band) and stamped via
	# rotate_90 lands flush against all 4 faces.
	var arm: Array = [{"id": "arm_hull", "type": "hull", "rect": Rect2(5.0, -2.0, 1.5, 4.0), "health": 12.0, "max_health": 12.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}]

	for n in range(4):
		var rotated: Array = HullBuilder.rotate_90(arm, n)
		for c in rotated:
			c["id"] = "%s_%d" % [c["id"], n]
		comps.append_array(rotated)

	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.DRONE
	max_speed = 150.0
	max_omega = 1.5
	max_heat = 90.0
	ship_components = design()
	super()
	ship_name = "Mine"
