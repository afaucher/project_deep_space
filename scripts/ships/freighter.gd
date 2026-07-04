extends "res://scripts/ships/ship.gd"
class_name Freighter

# M27 -- HEAVY-tier civilian hauler. Spine + two outboard cargo pods (the
# "spine + pods" archetype -- design_ideas/hull_shape_grammar.md §2); the
# silhouette IS the role -- cargo mass is carried far off the centerline, so
# high rotational inertia (ponderous turning) falls out of the layout for
# free, same idea as the destroyer's zipper flanks being visibly broadside-
# heavy. Unarmed, dockable. Targets (design_ideas/ship_parameter_table.md M27
# pre-step): mass ~300, accel ~8-12, max_speed ~400, HEAVY handling band.
#
# Authored with HullBuilder.frame() (spine box + both pods) and
# HullBuilder.mirror_y() (port strut/pod mirrored off the stbd side) -- see
# file header note on grammar friction below.
#
# static func design() + thin _init() per fleet convention (M24 refactor on
# cargo_shuttle.gd) -- design() returns the exact authored array so a future
# delta variant can compose off it via Variants.apply() without inheriting
# Freighter's _init() directly.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")

# ---------------------------------------------------------------------------
# Grammar friction notes (per M27 plan -- report every place the grammar
# couldn't express something):
#  - cargo_bay / living_quarters have NO Parts family (Parts.families() is
#    laser/missile/engine/rcs/reactor/sensor/comms/hull only) -- authored as
#    raw dicts. This is a real gap: HullBuilder only builds hull-family
#    shells, and Parts has no capacity-component factory at all.
#  - The engine's thrust/torque needed for the ~10 accel target sit BELOW the
#    HEAVY Parts engine bands entirely (Parts HEAVY engine COMPACT mark alone
#    is 10500 thrust -- 3x this hull's mass-appropriate ~3200) and below the
#    component_spec.gd HEAVY engine band floor (10000) -- a raw-stat engine
#    dict was used instead of Parts.make("engine", ...), same as every
#    hand-authored ship's engine today. This produces an expected (not a
#    grammar bug) HEAVY-tier engine band WARNING, called out in the report:
#    the HEAVY engine band was calibrated against combat hulls (destroyer),
#    not a ponderous unarmed hauler an order of magnitude lighter -- same
#    "band is advisory for lightweight civilians" pattern already noted in
#    ship_parameter_table.md pattern #5 for LIGHT-tier civilians.
# ---------------------------------------------------------------------------

static func design() -> Array:
	var comps: Array = []

	# --- SPINE: frame(Rect2(-30,-11,90,22), 6, hp) -----------------------
	# Houses reactor/comms/sensor/rcs/living_quarters in its interior cavity
	# (x -24..54, y -5..5); engine bolted to the aft face, nose cap to fwd.
	comps.append_array(HullBuilder.frame(Rect2(-30, -11, 90, 22), 6.0, 2000.0, {"id_prefix": "spine"}))

	comps.append({"id": "engine_main", "type": "engines", "rect": Rect2(-42, -11, 12, 22), "health": 300.0, "max_health": 300.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 90.0, "thrust_rating": 3200.0, "torque_rating": 7000.0})

	comps.append({"id": "hull_nose", "type": "hull", "rect": Rect2(60, -7, 8, 14), "health": 500.0, "max_health": 500.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	comps.append({"id": "reactor_core", "type": "reactor", "rect": Rect2(-24, -5, 12, 10), "health": 260.0, "max_health": 260.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 260.0})

	comps.append({"id": "comms_array", "type": "comms", "rect": Rect2(-12, -5, 6, 10), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 42000.0})

	comps.append({"id": "omni_main", "type": "sensors", "rect": Rect2(-6, -5, 6, 10), "health": 90.0, "max_health": 90.0, "density": 20.0, "heat": 0.0, "base_em_emission": 9.0, "em_emission": 9.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 30000.0, "arc_width": TAU, "num_bins": 40, "refresh_interval": 1.5, "timer": 0.0, "heading": 0.0})

	comps.append({"id": "rcs_main", "type": "rcs", "rect": Rect2(0, -5, 8, 10), "health": 200.0, "max_health": 200.0, "density": 20.0, "thrust_rating": 4500.0, "torque_rating": 4500.0})

	# Small crew complement -- freighters run lean crews, unlike the pinnace's
	# 30-passenger cabin. 46x10 = 460 area, inside the new HEAVY living_quarters
	# band [300, 9000] (see component_spec.gd).
	comps.append({"id": "living_quarters_main", "type": "living_quarters", "rect": Rect2(8, -5, 46, 10), "health": 460.0, "max_health": 460.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	# --- STBD STRUT + POD -------------------------------------------------
	var strut_stbd: Dictionary = {"id": "strut_stbd", "type": "hull", "rect": Rect2(10, 11, 18, 8), "health": 400.0, "max_health": 400.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}
	comps.append(strut_stbd)

	var pod_stbd: Array = HullBuilder.frame(Rect2(3, 19, 64, 48), 6.0, 1800.0, {"id_prefix": "pod_stbd"})
	comps.append_array(pod_stbd)

	var cargo_bay_stbd: Dictionary = {"id": "cargo_bay_stbd", "type": "cargo_bay", "rect": Rect2(9, 25, 52, 36), "health": 1872.0, "max_health": 1872.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}
	comps.append(cargo_bay_stbd)

	# --- PORT STRUT + POD (mirror_y of stbd -- port<->stbd token swap on id) --
	comps.append_array(HullBuilder.mirror_y([strut_stbd]))
	comps.append_array(HullBuilder.mirror_y(pod_stbd))
	comps.append_array(HullBuilder.mirror_y([cargo_bay_stbd]))

	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.HEAVY
	max_speed = 400.0
	max_omega = 0.8
	max_heat = 220.0
	dockable = true   # HEAVY civilian hauler -- can be captured by a station berth
	ship_components = design()
	super()
	ship_name = "Bulk Freighter"
