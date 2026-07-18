extends "res://scripts/ships/ship.gd"
class_name ArmedPinnace

# M50 -- delta hull: pirate-refit pinnace (implementation_plans/
# m50_pirate_tree_design.md "Hulls"). Same tapered-dart silhouette as the
# stock pinnace -- civilian sensors can't out it -- plus one light laser
# bolted amidships, starboard-facing.
#
# ship_variants.gd's op table (swap/tune/remove) has no ADD op, so this can't
# be a Variants.apply() delta the way pirate_lac.gd is -- see pirate_ore_
# shuttle.gd's header for the same reasoning. Composes Pinnace.design()'s
# array plus one hand-placed weapon rect in a free, edge-adjacent slot.
#
# Slot: Pinnace's rcs_main occupies x[-35,-25] y[-12,12]; nothing else in the
# hull reaches x[-35,-31] above y=12 (the aft hull taper stops at x=-35), so
# a 4x4 weapon at (-35, 12) shares rcs_main's y=12 edge without overlapping
# anything -- a hardpoint pod welded onto the RCS housing's dorsal face,
# facing +Y (starboard, per the fleet's "Forward +X, Right +Y" convention).

const Pinnace = preload("res://scripts/ships/pinnace.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

static func design() -> Array:
	var comps: Array = Pinnace.design()
	comps.append(Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.COMPACT, Vector2(-35, 12), {"id": "hp_dorsal_laser", "heading": PI / 2.0}))
	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	ship_name = "Armed Pinnace"
	max_speed = 2000.0
	max_omega = 3.0
	max_heat = 140.0
	ship_components = design()
	super()
