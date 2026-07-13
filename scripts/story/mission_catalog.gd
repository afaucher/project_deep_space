extends RefCounted
class_name MissionCatalog

# M42 -- mission definitions by id, looked up by MissionLog.start_mission_by_id()
# so a .dialogue mutation can grant a mission with
#   do missions.start_mission_by_id("check_on_todd")
# instead of an inline Dictionary literal -- DialogueManager mutation
# expressions don't reliably parse nested dict literals (the roadmap's
# challenge #6 / test_story_dialogue.gd's canned_mission() precedent already
# worked around this the same way, one level up). See
# implementation_plans/m39_m44_homefront_roadmap.md, "M44" for the full arc
# this mission belongs to.
#
# Objective `target` Vector2/float fields are plain-serializable (roadmap
# challenge #4). Objective `text` fields are short functional UI strings --
# NOT character prose -- describing what to do, shown in the (future, M41)
# contracts/missions UI.
#
# Referenced via preload const, never the bare class_name, per the headless
# class-cache caveat (CLAUDE.md).

const MISSIONS: Dictionary = {
	"check_on_todd": {
		"id": "check_on_todd",
		"title": "Check on Todd",
		"giver": "aunt_stephanie",
		"objectives": [
			{
				"id": "search_field",
				"kind": "GO_TO_AREA",
				"text": "Search the Slag Bay field",
				# Slag Bay's asteroid field (home_cluster.gd) -- expanded to
				# 16k for M43 so all five Drift homes fit inside the search
				# area. Todd's home, Claim 42, sits on the far spinward edge
				# at (159000, 99000), ~14.2k out.
				"target": {"center": Vector2(150000, 110000), "radius": 16000.0},
			},
			{
				"id": "talk_todd",
				"kind": "TALK_TO",
				"text": "Talk to Todd",
				"target": {"npc": "Todd"},
			},
			{
				"id": "deliver_present",
				"kind": "DELIVER",
				"text": "Deliver the present to Aunt Stephanie",
				# M41 -- marker_sid resolves this objective's contract-feed
				# position via ClusterManager records (see contract_feed.gd) --
				# Aunt Stephanie is stationed at Ironhold (characters.gd's
				# home_sid). TALK_TO Todd intentionally carries no marker_sid:
				# his position is unknown; finding him IS the gameplay.
				"target": {"item": "stephanies_present", "npc": "Aunt Stephanie", "marker_sid": "ironhold"},
			},
		],
	},
}

static func get_mission(id: String) -> Dictionary:
	return MISSIONS.get(id, {})
