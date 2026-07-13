extends RefCounted
class_name StoryCharacters

# M42 -- the character registry: static per-PERSON data, never per-instance
# state (StoryState/MissionLog own that -- see roadmap challenge #3, "no
# story or mission state on live nodes, ever"). One entry per named person;
# their .dialogue files live in dialogue/characters/. See
# implementation_plans/m39_m44_homefront_roadmap.md, "Story data architecture:
# the overlay" + "M42 -- Characters v1".
#
# Schema (one entry per character id):
#   name: String       -- display name, also what NPCProfile.character_name
#                          gets set to on injection (ClusterLoader resolves
#                          this at load time -- see cluster_loader.gd).
#   role: String        -- e.g. "mechanic". Flavor/future UI, not consumed by
#                          the mechanism yet.
#   dialogue: String    -- res:// path to the character's .dialogue file.
#   home_sid: String    -- the cluster entity slug (ClusterEntity.sid) this
#                          character is normally found at. Informational for
#                          now (the overlay entry keyed by that same sid is
#                          what actually places the cast); lets tooling later
#                          answer "where does X live" without grepping the
#                          overlay.
#
# Referenced via preload const, never the bare class_name, per the headless
# class-cache caveat (CLAUDE.md).

const REGISTRY: Dictionary = {
	"aunt_stephanie": {
		"name": "Aunt Stephanie",
		"role": "mechanic",
		"dialogue": "res://dialogue/characters/aunt_stephanie.dialogue",
		"home_sid": "ironhold",
	},
	# M43 -- the Drift residents (Todd's neighbors in the Slag Bay field).
	# "Mae & Gus" is one registry entry / one NPCProfile for the couple --
	# their .dialogue file alternates the two speakers within the single
	# conversation, which reads better than two separate hail targets on one
	# tiny home.
	"mae_and_gus": {
		"name": "Mae & Gus",
		"role": "retired miners",
		"dialogue": "res://dialogue/characters/mae_and_gus.dialogue",
		"home_sid": "hermits_rest",
	},
	"wex": {
		"name": "Wex",
		"role": "resident",
		"dialogue": "res://dialogue/characters/wex.dialogue",
		"home_sid": "deep_freeze",
	},
	"dost": {
		"name": "Dost",
		"role": "prospector",
		"dialogue": "res://dialogue/characters/dost.dialogue",
		"home_sid": "lucky_strike",
	},
	"prell": {
		"name": "Prell",
		"role": "resident",
		"dialogue": "res://dialogue/characters/prell.dialogue",
		"home_sid": "rock_bottom",
	},
	# Todd's registry entry lands in M43 so hailing Claim 42 inside his
	# collapsed comms range resolves an NPC; his .dialogue is an explicit
	# placeholder until M44 (the conversation is the arc's centerpiece and is
	# co-authored -- see the roadmap's M44 "fiction is co-authored" note).
	"todd": {
		"name": "Todd",
		"role": "cousin",
		"dialogue": "res://dialogue/characters/todd.dialogue",
		"home_sid": "claim_42",
	},
}

static func get_character(id: String) -> Dictionary:
	return REGISTRY.get(id, {})
