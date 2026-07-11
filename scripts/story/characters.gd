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
	# M43 adds "todd" (Claim 42) and the four other Drift residents here.
}

static func get_character(id: String) -> Dictionary:
	return REGISTRY.get(id, {})
