extends "res://scripts/ships/ship.gd"
class_name Pinnace

# M27 -- LIGHT-tier fast personal/passenger carrier. Tapered dart (the
# "tapered dart" archetype -- design_ideas/hull_shape_grammar.md §2, same
# family as the LAC's winged dart but a single continuous taper profile
# rather than wing slabs). Unarmed AND unarmored on purpose (thin/no hull
# plating IS the point -- see design_ideas/ship_designs.md's "pinnance" entry
# and the M27 plan): most of the hull's rect area is functional/cabin
# volume, not armor plating, so honest coverage warnings on the little hull
# it has are accepted rather than re-wrapped (see EXPECTED_LAYOUT_WARNINGS in
# test_ship_designs.gd for the frozen, reviewed set).
#
# Ten stations along the spine (x -55..55, each 10 wide), width tapering
# bow-to-midship-to-stern -- the widest stations (living_quarters, amidships)
# carry the 30-passenger cabin (AREA_PER_PERSON=40 -> 1200 area total, split
# across 3 stations of 400 each). Targets
# (design_ideas/ship_parameter_table.md M27 pre-step): fast (max_speed ~2000,
# accel ~80), LIGHT handling band.
#
# static func design() + thin _init() per fleet convention.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")

# ---------------------------------------------------------------------------
# Grammar friction notes (per M27 plan):
#  - living_quarters has no Parts family (same gap noted in freighter.gd) --
#    authored as raw dicts, split across 3 stations rather than one factory
#    call.
#  - taper() alone can't express a profile with functional-component stations
#    interleaved between hull stations (it always emits hull dicts for every
#    slice) -- the nose/aft hull runs use taper() for their two contiguous
#    hull stations each, but the sensor/cabin/comms/reactor/rcs stations in
#    between are necessarily raw dicts sized to match the SAME station
#    geometry (same width, same tapering half-height) so the dart profile
#    stays one continuous, gap-free silhouette. A hypothetical
#    "taper_with_slots(widths, slot_component_by_index)" helper would close
#    this gap for future radial/tapered hulls that mix hull and function
#    per-station.
# ---------------------------------------------------------------------------

static func design() -> Array:
	var comps: Array = []

	# --- BOW (+X, fleet convention): sensor station (narrowest) -----------
	comps.append({"id": "sensor_fwd", "type": "sensors", "rect": Rect2(45, -4, 10, 8), "health": 55.0, "max_health": 55.0, "density": 20.0, "heat": 0.0, "base_em_emission": 7.0, "em_emission": 7.0, "switchable": true, "powered_on": true,
		"sensor_type": "active", "active": true, "range": 20000.0, "arc_width": TAU, "num_bins": 36, "refresh_interval": 1.5, "timer": 0.0, "heading": 0.0})

	# --- NOSE HULL TAPER (two stations, widths 14 -> 22) ------------------
	comps.append_array(HullBuilder.taper(25.0, 45.0, [22.0, 14.0], {"id_prefix": "hull_nose"}))

	# --- CABIN: 3 living_quarters stations, 400 area each (1200 total = --
	# 30 pax @ AREA_PER_PERSON 40) ------------------------------------------
	comps.append({"id": "living_quarters_1", "type": "living_quarters", "rect": Rect2(15, -20, 10, 40), "health": 512.0, "max_health": 512.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})
	comps.append({"id": "living_quarters_2", "type": "living_quarters", "rect": Rect2(5, -20, 10, 40), "health": 512.0, "max_health": 512.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})
	comps.append({"id": "living_quarters_3", "type": "living_quarters", "rect": Rect2(-5, -20, 10, 40), "health": 512.0, "max_health": 512.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false})

	# --- COMMS station ------------------------------------------------------
	comps.append({"id": "comms_array", "type": "comms", "rect": Rect2(-15, -17, 10, 34), "health": 90.0, "max_health": 90.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "range": 20000.0})

	# --- REACTOR station ------------------------------------------------------
	comps.append({"id": "reactor_core", "type": "reactor", "rect": Rect2(-25, -15, 10, 30), "health": 140.0, "max_health": 140.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false, "power_rating": 55.0})

	# --- RCS station (station-keeping / attitude) ---------------------------
	comps.append({"id": "rcs_main", "type": "rcs", "rect": Rect2(-35, -12, 10, 24), "health": 180.0, "max_health": 180.0, "density": 20.0, "thrust_rating": 900.0, "torque_rating": 900.0})

	# --- AFT HULL TAPER (two stations, widths 20 -> 14) --------------------
	comps.append_array(HullBuilder.taper(-55.0, -35.0, [14.0, 20.0], {"id_prefix": "hull_aft"}))

	# --- ENGINE, bolted to the very aft (-X) face (outside the taper --
	# envelope, same idiom as cargo_shuttle.gd/light_attack_craft.gd's
	# engine_main -- exhaust points -X/aft). Oversized thrust-to-mass on
	# purpose -- that's what makes the pinnace fast (same pattern as the LAC
	# per ship_parameter_table.md pattern #2).
	comps.append({"id": "engine_main", "type": "engines", "rect": Rect2(-69, -6, 14, 12), "health": 160.0, "max_health": 160.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true, "power_rating": 70.0, "thrust_rating": 8800.0, "torque_rating": 14000.0})

	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	max_speed = 2000.0
	max_omega = 3.0
	max_heat = 140.0
	ship_components = design()
	super()
	ship_name = "Pinnace"
