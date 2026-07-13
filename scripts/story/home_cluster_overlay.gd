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
#     dict by "id". Production users (M43): Claim 42's collapsed
#     comms_array.range (Todd's damaged transmitter) and the two anonymous
#     homes' transponder_share_name=false. Also exercised against a
#     synthetic entry by test_story_overlay.gd.
#
# Referenced via preload const, never the bare class_name, per the headless
# class-cache caveat (CLAUDE.md).

const OVERLAY: Dictionary = {
	"ironhold": {
		"cast": ["aunt_stephanie"],
		"port": {"services": {"repairs": "free"}},
	},
	# M43 -- the Drift homes (all five in the Slag Bay field, see
	# home_cluster.gd). Three flavors of presence on the sensor/comms picture,
	# giving the check_on_todd search its two kinds of silence:
	#   - NAMED (Hermit's Rest, The Deep Freeze): normal transponders, the
	#     chatty neighbors and breadcrumb source.
	#   - ANONYMOUS (Lucky Strike, Rock Bottom): transponder_share_name off --
	#     they broadcast "UNKNOWN" (ship.gd's get_active_transponder_data) but
	#     comms are healthy, so hailing them WORKS and they answer (tersely).
	#     Won't talk... much. False positives for the elimination search.
	#   - SILENT (Claim 42/Todd): comms range collapsed 30k -> 1.5k (damaged
	#     transmitter, per the roadmap's M43 decision note). Unnamed AND
	#     unhailable at normal range -- CAN'T talk. Dead air is the tell.
	"hermits_rest": {
		"cast": ["mae_and_gus"],
	},
	"deep_freeze": {
		"cast": ["wex"],
	},
	"lucky_strike": {
		"cast": ["dost"],
		"component_overrides": {"comms_array": {"transponder_share_name": false}},
	},
	"rock_bottom": {
		"cast": ["prell"],
		"component_overrides": {"comms_array": {"transponder_share_name": false}},
	},
	"claim_42": {
		"cast": ["todd"],
		"component_overrides": {"comms_array": {"range": 1500.0}},
	},
}

static func get_entry(sid: String) -> Dictionary:
	return OVERLAY.get(sid, {})
