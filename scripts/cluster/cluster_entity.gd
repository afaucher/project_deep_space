extends RefCounted
class_name ClusterEntity

# M14 -- the authoritative, physics-independent state of one world entity. Live or
# dormant, THIS record is the source of truth: promoting attaches a RigidBody2D
# built from it; demoting reads the body's state back here and frees the node.
# Promotion is attach/detach on this shared record -- that contract is what lets
# the liveness policy (bubble / full-sim / degraded) be swapped without touching
# the promote/demote plumbing. See implementation_plans/m14_cluster_sim_bubble_design.md
# and design_ideas/campaign_spatial_model.md.
#
# A RefCounted (not a Node) on purpose: a dormant cluster of hundreds of records
# must not cost the scene tree.

enum Kind { STATION, ASTEROID, BEACON, TRAFFIC, WORMHOLE, PLAYER }

# Identity / construction.
var id: int = -1
var name: String = ""
var hull_script: Script = null      # res://scripts/ships/*.gd or asteroid.gd to instantiate on promote
var iff_tags: Array = []
var kind: int = Kind.TRAFFIC
var is_static: bool = false         # stations/beacons/wormhole never move -> skip dead-reckon

# Kinematics -- authoritative while dormant; synced from the live body on demote.
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var rot: float = 0.0
var ang_vel: float = 0.0

# The instantiated body while live, else null.
var live_node: Node = null

# Opaque AI/behavior config handed to the hull on promote (route lists, etc.).
# Unused by M14's straight-line movers; carried now so later milestones don't
# have to reshape the record.
var behavior = null

func is_live() -> bool:
	return live_node != null and is_instance_valid(live_node)
