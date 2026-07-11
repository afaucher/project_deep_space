extends RefCounted
class_name HomeClusterOverlay

# M42 -- per-entity story decorations for the home cluster, keyed by the
# entity's sid (ClusterEntity.sid / home_cluster.gd's authored slugs). Merged
# into ClusterEntity records by ClusterLoader at load time (see
# cluster_loader.gd's load_into() overlay/characters params); applied to live
# nodes generically by ClusterManager._promote() (record-carried identity --
# the SAME pattern as the port-authority rebrand, see cluster_manager.gd's
# _rebrand_port_zone() comment, extended from "who's in charge" to "who's
# aboard and what shape this instance is in"). See
# implementation_plans/m39_m44_homefront_roadmap.md, "Story data architecture:
# the overlay" + "M42 -- Characters v1".
#
# Three decoration kinds, all optional per entry:
#   cast: Array[String]
#     Character registry ids (story/characters.gd -> scripts/story/characters.gd)
#     stationed at this entity. ClusterLoader resolves each id into a plain
#     {name, role, dialogue_path} descriptor on the RECORD at load time --
#     ClusterManager never imports story/*, it just builds NPCProfiles from
#     plain fields.
#   port: Dictionary
#     Merged into the node's port_zone at promote, AFTER _rebrand_port_zone
#     sets `authority` -- a patch adds fields like `services` without
#     clobbering the per-instance authority rebrand.
#   component_overrides: Dictionary
#     {component_id: {field: value}} merged into the matching ship_components
#     dict by "id". No production entry yet -- M43's Todd (collapsed
#     comms_array.range on Claim 42, per the roadmap's "Drift residents &
#     the silent home" section) is the first real user; the mechanism ships
#     and is exercised by test_story_overlay.gd's synthetic entry NOW so it
#     isn't unproven code waiting on M43.
#
# Referenced via preload const, never the bare class_name, per the headless
# class-cache caveat (CLAUDE.md).

const OVERLAY: Dictionary = {
	"ironhold": {
		"cast": ["aunt_stephanie"],
		"port": {"services": {"repairs": "free"}},
	},
	# M43 adds "claim_42" (Todd, component_overrides: {comms_array: {range:
	# 1500.0}}) and the other four homes' residents here.
}

static func get_entry(sid: String) -> Dictionary:
	return OVERLAY.get(sid, {})
