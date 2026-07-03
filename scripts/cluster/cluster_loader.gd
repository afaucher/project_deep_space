extends RefCounted
class_name ClusterLoader

# M15 -- turn a ClusterDef's authored entity dicts into ClusterEntity records and
# hand them to a ClusterManager. No physics happens here: the manager's liveness
# policy decides what actually goes live around the player. Referenced via
# preload const per the headless class-cache caveat.

const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

static func load_into(def, manager) -> void:
	for e in def.entities:
		var rec = ClusterEntity.new()
		rec.id = e["id"]
		rec.hull_script = e["hull"]
		rec.kind = e.get("kind", ClusterEntity.Kind.TRAFFIC)
		rec.pos = e["pos"]
		var tags: Array = e.get("iff_tags", [])
		rec.iff_tags = tags.duplicate(true)
		rec.is_static = e.get("is_static", false)
		rec.behavior = e.get("behavior", null)
		manager.add_record(rec)
