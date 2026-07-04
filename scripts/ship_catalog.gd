extends Node
class_name ShipCatalog

# M10 sandbox spawn catalog -- the single list of spawnable combat hulls.
# M9c ships append here -> they auto-appear in the spawn panel's dropdown.
# NOTE: referenced elsewhere via `const ShipCatalog = preload("res://scripts/ship_catalog.gd")`,
# never the bare global class name -- see m10_sandbox_spawn_design.md's CRITICAL
# class-cache note (the headless build/test path doesn't regenerate Godot's
# git-tracked global class cache, so a bare-name reference to a newly added
# class_name can fail to compile in that path).
const SPAWNABLE := [
	{ "name": "Frigate", "script": preload("res://scripts/ships/frigate.gd") },
	{ "name": "Cargo Shuttle", "script": preload("res://scripts/ships/cargo_shuttle.gd") },
	{ "name": "Light Attack Craft", "script": preload("res://scripts/ships/light_attack_craft.gd") },
	{ "name": "Destroyer", "script": preload("res://scripts/ships/destroyer.gd") },
	{ "name": "Buoy", "script": preload("res://scripts/ships/buoy.gd") },
	{ "name": "Small Station", "script": preload("res://scripts/ships/small_station.gd") },
	{ "name": "Medium Station", "script": preload("res://scripts/ships/medium_station.gd") },
	{ "name": "Freighter", "script": preload("res://scripts/ships/freighter.gd") },
	{ "name": "Pinnace", "script": preload("res://scripts/ships/pinnace.gd") },
	{ "name": "Mine", "script": preload("res://scripts/ships/mine.gd") },
	{ "name": "Defence Pod", "script": preload("res://scripts/ships/defence_pod.gd") },
	{ "name": "Asteroid Station", "script": preload("res://scripts/ships/asteroid_station.gd") },
]

# M24 -- delta variants: skins of a validated base hull (see
# design_ideas/hull_shape_grammar.md §5/§7 and
# implementation_plans/m24_delta_variants_design.md). Structurally validated
# the same way as SPAWNABLE (test_ship_designs.gd auto-enumerates this list),
# but variants are deliberately NOT added to SPAWNABLE -- they don't need a
# separate sandbox-spawn slot to be tested, and keeping the two lists distinct
# is what makes the promotion rule below legible (SPAWNABLE = roles that have
# earned a tactical-sweep verdict; VARIANTS = skins that inherit one).
#
# PROMOTION RULE (design doc §7): a variant only "promotes" into the tactical
# sweeps (and SPAWNABLE) if it changes:
#   (a) tier -- e.g. a variant that becomes MEDIUM instead of LIGHT,
#   (b) weapon-class mix -- e.g. a variant that swaps a laser for a missile
#       tube, or adds/removes an entire weapon class, or
#   (c) accel band -- leaves the base's thrust/mass ratio by more than +/-20%.
# A skin that fails all three inherits its base's tactical verdict for free --
# that's the point: sweep count tracks *roles* (a handful), not *hulls*
# (dozens of repaints). Every entry below carries a role_key documenting which
# base archetype's verdict it inherits, and a promotes_tactical_sweep flag
# recording that this milestone's audit found it does NOT promote.
#
# Neither v1 variant promotes:
#   - Pirate LAC: same tier (LIGHT), same weapon-class mix (laser + missile,
#     one of each, same as the base), and its accel change stays inside the
#     +/-20% band -- see the design's own gated assertion (thrust strictly up,
#     mass strictly down from the removed plate, accel strictly up) exercised
#     by test_ship_variants.gd item 6, but the tune-based engine bump (same
#     rect, HEAVY-mark stats) plus one dropped plate is a tune within the
#     LIGHT-tier envelope, not a new role.
#   - Ore shuttle: same tier (LIGHT), still unarmed (no weapon-class change),
#     and the density/comms tunes don't touch thrust or mass in any way that
#     shifts accel at all (accel is unchanged from the base shuttle).
const VARIANTS := [
	{
		"name": "Pirate LAC",
		"script": preload("res://scripts/ships/pirate_lac.gd"),
		"role_key": "light_attack_craft",
		"promotes_tactical_sweep": false,
	},
	{
		"name": "Ore Shuttle",
		"script": preload("res://scripts/ships/ore_shuttle.gd"),
		"role_key": "cargo_shuttle",
		"promotes_tactical_sweep": false,
	},
]

enum Team { FRIENDLY, ENEMY, PIRATE }

# Team -> iff_tags mapping. The whole sandbox-team mechanic falls out of this:
#  - FRIENDLY shares the player's own tags -> classified FRIENDLY VESSEL, AI
#    never targets it, it fights alongside the player.
#  - ENEMY shares a common tag with other enemies -> hostile to player/pirates,
#    allied to other enemies.
#  - PIRATE gets a tag unique to this spawn's owner_id -> shares with no one,
#    so pirates are hostile to everyone, including other pirates (true FFA).
static func iff_for(team: int, owner_id: int, player_tags: Array) -> Array:
	match team:
		Team.FRIENDLY:
			return player_tags.duplicate()
		Team.ENEMY:
			return ["TEAM_ENEMY"]
		Team.PIRATE:
			return ["PIRATE_" + str(owner_id)]
		_:
			return ["TEAM_ENEMY"]
