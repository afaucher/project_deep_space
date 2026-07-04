extends "res://scripts/ships/ship.gd"
class_name OreShuttle

# M24 -- delta variant: ore-hauler skin of the cargo shuttle. Same box,
# heavier plating, shorter-legged comms. See
# implementation_plans/m24_delta_variants_design.md and
# design_ideas/hull_shape_grammar.md §5.
#
# Extends ship.gd DIRECTLY (not CargoShuttle) and preloads the base for
# design() -- GDScript parent _init ordering makes subclass mutation of an
# already-built ship_components array fragile, so variants compose the base's
# design() array via Variants.apply() instead of inheriting _init(). See
# ship_variants.gd file header. Because this bypasses CargoShuttle's _init(),
# `dockable = true` (a CargoShuttle _init field, not a design() component
# field) must be set again here explicitly -- it does NOT come along for free.
#
# Deltas (all STATS_ONLY -- no remove ops, no re-validation needed beyond the
# routine catalog re-run every ship gets):
#  - tune every hull component's "density" up from 20.0 (standard) to 35.0
#    (Parts.HULL_DENSITY's "armored" mark) -- heavier plating reads as more
#    mass (test item 7: mass > base shuttle) and more damage-soak, same
#    density/health coupling every hand-authored hull in the fleet uses.
#  - tune comms_array's range down (shorter-legged civilian radio -- an ore
#    hauler works its belt, it doesn't need the base shuttle's trade-route
#    reach).

const Variants = preload("res://scripts/components/ship_variants.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

# Every hull component id in CargoShuttle.design() -- tuned individually since
# Variants' v1 op table has no "tune all matching type" op (each op names one
# component id). Listed explicitly rather than discovered at runtime so this
# file documents exactly which plates get the armor mark, same spirit as the
# rest of the fleet's hand-authored arrays.
const HULL_COMPONENT_IDS := ["hull_port", "hull_stbd", "hull_fwd", "hull_fill_port", "hull_fill_stbd"]

const ARMORED_DENSITY: float = 35.0  # Parts.HULL_DENSITY[Mark.HEAVY] -- see parts_catalog.gd

static func design() -> Array:
	var ops: Array = []
	for id in HULL_COMPONENT_IDS:
		ops.append({"tune": id, "field": "density", "value": ARMORED_DENSITY})
	# 12000, not lower: LIGHT comms band floor is 10000 (component_spec.gd) --
	# a variant tune must stay in-band or it defeats the catalog discipline
	# (caught in M24 validation; test_ship_variants now asserts band-clean).
	ops.append({"tune": "comms_array", "field": "range", "value": 12000.0})
	return Variants.apply(CargoShuttle.design(), ops)

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	ship_name = "Ore Shuttle"
	max_speed = 1000.0
	max_omega = 2.0
	max_heat = 150.0
	dockable = true   # M19: civilian hauler -- CargoShuttle sets this in its own
	                  # _init(), which this variant does not inherit; must be
	                  # re-set explicitly here (see file header).
	ship_components = design()
	super()
