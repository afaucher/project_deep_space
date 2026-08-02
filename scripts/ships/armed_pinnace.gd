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
	# 2026-08-02 -- a listening array, the refit's second illegal addition.
	#
	# WHY: measured, campaign piracy lands ZERO takes, and the dominant failure
	# is ENCOUNTER -- 8 of ~13 hunts ended having seen nobody
	# (implementation_plans/m51_pirate_guild_design.md). The stock pinnace's
	# only sensor is an active 20,000u omni, which is WORSE than the
	# CargoShuttle's 22,000: the predator could not see as far as its prey, on
	# ~300,000u lanes. That is the binding constraint, not speed (the hull does
	# 2000 against a shuttle's 1000) and not hunt duration (already A/B'd to
	# 900s for a single take).
	#
	# WHY PASSIVE specifically, rather than a bigger active dish:
	#   * It fits the tradecraft. A hull whose whole method is going dark should
	#     LISTEN, not ping.
	#   * It is self-limiting in exactly the right way. passive_em fires only
	#     when received EM clears PASSIVE_EM_NOISE_FLOOR after directional and
	#     distance falloff, so it hears a loud target (a hauler running an
	#     active dish, a transponder and a reactor) a long way off and CANNOT
	#     see a dark ship at all. The prey's own noise is what betrays it --
	#     which hands haulers a real counter-tactic instead of handing pirates
	#     omniscience.
	#   * It reads less, not just further: ship.gd erases cross_section, heat
	#     and density from a passive contact. The pirate learns something is
	#     out there, not precisely what.
	#
	# RANGE sits deliberately between the tiers: civilians carry no passive at
	# all, the Frigate carries 80,000. Half a warship's reach is the "better
	# than a hauler, not a warship" band.
	#
	# em 0.0 -- listening does not emit. Placed at the mirror of the dorsal
	# laser, sharing rcs_main's y=-12 edge by the same free-slot reasoning as
	# the laser above (see header).
	comps.append({
		"id": "passive_array", "type": "sensors", "rect": Rect2(-35, -16, 4, 4),
		"health": 25.0, "max_health": 25.0, "density": 20.0, "heat": 0.0,
		"base_em_emission": 0.0, "em_emission": 0.0,
		"switchable": true, "powered_on": true,
		"sensor_type": "passive_em", "active": true, "range": 45000.0,
		"arc_width": TAU, "num_bins": 180, "refresh_interval": 1.0,
		"timer": 0.0, "heading": 0.0,
	})
	return comps

func _init() -> void:
	ship_tier = ComponentSpec.Tier.LIGHT
	ship_name = "Armed Pinnace"
	max_speed = 2000.0
	max_omega = 3.0
	max_heat = 140.0
	ship_components = design()
	super()
