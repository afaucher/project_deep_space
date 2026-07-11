extends RefCounted
class_name ContractFeed

# M41 -- Objective indicators: contracts are NAV-layer data. A "contract" is
# NAV knowledge (a known coordinate/area/place -- the same knowledge family as
# destinations, beacon routes, and docking lanes), NEVER a sensor detection.
# This file assembles that feed; it is consumed by navigation_panel.gd
# (markers + off-screen arrows + the GO_TO_AREA ring), contacts_panel.gd (the
# "Contracts" section) and main.gd's nav_destinations(). It must NEVER be
# injected into ship.contacts or any sensor/fusion path -- correlation would
# fuse real blips into it and decay it like a stale track; nav knowledge
# doesn't decay. See implementation_plans/m39_m44_homefront_roadmap.md,
# "M41 -- Objective indicators: contracts are NAV-layer data".
#
# build(mission_log, cluster_manager) walks a MissionLog's ACTIVE missions
# (skipping any with indicators_visible == false) and emits ONE plain
# Dictionary entry per mission for its CURRENT active objective
# (MissionLog.get_active_objective) -- a mission with no active objective
# (all complete, or the mission itself isn't ACTIVE) emits nothing.
#
# Entry shape: {id, title, kind, pos, radius, mission_id, mission_title}
#   id            String   -- "<mission_id>:<objective_id>", unique across the
#                             whole feed (an objective id alone can repeat
#                             across different mission definitions).
#   title         String   -- the objective's short functional text (what to
#                             do), e.g. "Search the Slag Bay field".
#   kind          String   -- the objective's kind (GO_TO_AREA/TALK_TO/DELIVER/...).
#   pos           Vector2 or null -- a known world position, OR null. null is
#                             DELIBERATE, not a missing-data bug: TALK_TO Todd
#                             has no known position (finding him IS the
#                             gameplay) -- an entry with pos == null is still
#                             LISTED (contacts/comms panels) but draws no map
#                             marker. Never invent a position to fill this in.
#   radius        float    -- > 0.0 only for GO_TO_AREA (the search area's
#                             radius); 0.0 for every other kind.
#   mission_id    String   -- the owning mission's id.
#   mission_title String   -- the owning mission's title (convenience for
#                             panels that want "<mission> -- <objective>"
#                             without a second lookup; not part of the
#                             roadmap's minimal shape but purely additive).
#
# Position resolution (this is why resolution lives HERE and not in
# MissionLog, which must stay free of cluster knowledge -- roadmap: "keep it
# free of cluster knowledge"):
#   GO_TO_AREA  -> target.center directly (the objective already carries its
#                  own area).
#   otherwise   -> if target.marker_sid is set, resolve it against
#                  cluster_manager's records (ClusterEntity.sid / .pos --
#                  records are the truth for both live AND dormant entities,
#                  so this works whether the target station is currently
#                  promoted or not). No match, empty sid, or no
#                  cluster_manager -> null.
#
# Referenced via preload const, never the bare class_name, per the headless
# class-cache caveat (CLAUDE.md).

const KIND_GO_TO_AREA := "GO_TO_AREA"

static func build(mission_log, cluster_manager) -> Array:
	var out: Array = []
	if mission_log == null:
		return out

	for mission in mission_log.active_missions():
		if mission.get("indicators_visible", true) == false:
			continue

		var mission_id: String = mission.get("id", "")
		var obj: Dictionary = mission_log.get_active_objective(mission_id)
		if obj.is_empty():
			continue

		out.append(_entry_for(mission, obj, cluster_manager))

	return out

static func _entry_for(mission: Dictionary, obj: Dictionary, cluster_manager) -> Dictionary:
	var kind: String = obj.get("kind", "")
	var target: Dictionary = obj.get("target", {})
	var mission_id: String = mission.get("id", "")
	var obj_id: String = obj.get("id", "")

	var pos = null
	var radius: float = 0.0

	if kind == KIND_GO_TO_AREA:
		pos = target.get("center", Vector2.ZERO)
		radius = target.get("radius", 0.0)
	else:
		var marker_sid: String = target.get("marker_sid", "")
		if marker_sid != "":
			pos = _resolve_sid(marker_sid, cluster_manager)

	return {
		"id": "%s:%s" % [mission_id, obj_id],
		"title": obj.get("text", ""),
		"kind": kind,
		"pos": pos,
		"radius": radius,
		"mission_id": mission_id,
		"mission_title": mission.get("title", ""),
	}

# Resolves a marker_sid to a world position via ClusterManager's records
# (rec.sid, rec.pos -- the record is the source of truth whether the entity
# is currently live/promoted or dormant/dead-reckoned). Returns null (never
# Vector2.ZERO -- that would silently look like "the origin") for a missing
# cluster_manager, an empty sid, or no matching record.
static func _resolve_sid(sid: String, cluster_manager):
	if cluster_manager == null or sid == "":
		return null
	var records: Array = cluster_manager.get("records") if cluster_manager.get("records") != null else []
	for rec in records:
		if rec.sid == sid:
			return rec.pos
	return null
