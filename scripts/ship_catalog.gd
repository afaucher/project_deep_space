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
