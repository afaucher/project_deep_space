extends RefCounted
class_name ClusterDef

# M15 -- the authored description of one cluster. Pure data in the project's
# "everything is code-built data" style (a ship is a .gd of dicts; a cluster is
# the same, one level up). ClusterLoader turns `entities` into ClusterEntity
# records; ClusterValidator checks it is well-formed. See
# implementation_plans/m15_cluster_loader_design.md.
#
# Each entry in `entities` is a Dictionary:
#   { id:int, name:String, hull:Script, kind:int (ClusterEntity.Kind),
#     pos:Vector2, iff_tags:Array, is_static:bool, behavior (opaque, optional) }

var name: String = ""
var bounds: Rect2 = Rect2()          # must sit inside the +/-500k budget
var player_start: Vector2 = Vector2.ZERO
var entities: Array = []
var beacon_edges: Array = []         # each: [beacon_id_a, beacon_id_b] -- the routing graph

func add_entity(d: Dictionary) -> void:
	entities.append(d)
