extends "res://scripts/ships/ship.gd"
class_name PirateOreShuttle

# M50 -- delta hull: pirate-refit ore shuttle (implementation_plans/
# m50_pirate_tree_design.md "Hulls"). Same silhouette as the ore shuttle --
# sensors can't out it, that's the point of hunting under cover -- plus one
# mining laser bolted onto the nose. Short range, real damage (the classic
# desperation refit).
#
# ship_variants.gd's op table (swap/tune/remove) has no ADD op -- a new
# weapon isn't a mutation of an EXISTING component id, so this can't be
# expressed as a Variants.apply() delta over OreShuttle the way pirate_lac.gd
# is over LightAttackCraft. Instead this composes OreShuttle.design()'s
# array (already a Variants.apply() delta over CargoShuttle -- see ore_
# shuttle.gd) plus one hand-placed weapon rect in a free, edge-adjacent slot,
# same "author a standalone design()" approach the M50 plan calls for when
# the op table can't express the delta.
#
# Slot: OreShuttle's hull_fwd occupies x[5,15] y[-5,5] (CargoShuttle's
# nose). x[15,19] y[-2.5,1.5] is empty and shares hull_fwd's x=15 edge --
# mounting the laser there (forward-heading) reads as "welded onto the bow"
# without touching any existing component's geometry. Validator confirmed
# clean (overlap/connectivity) by test_ship_designs; PD coherence is a
# WARNING only (the shuttle's 1.5s search sensor is too slow to aim it --
# expected for a scavenged hauler, not a purpose-built PD mount).

const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")

static func design() -> Array:
	var comps: Array = OreShuttle.design()
	comps.append(Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.COMPACT, Vector2(15, -2.5), {"id": "mining_laser", "heading": 0.0}))
	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	ship_name = "Pirate Ore Shuttle"
	max_speed = 1000.0
	max_omega = 2.0
	max_heat = 150.0
	ship_components = design()
	super()
