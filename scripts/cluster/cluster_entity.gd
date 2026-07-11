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
# M42 -- stable string join-key for story content ("ironhold", "claim_42", ...).
# Display `name` is for humans and may change; `id` is positional bookkeeping;
# `sid` is what story/* data (characters.gd, home_cluster_overlay.gd) keys off.
# Empty ("") for entities story content never references (asteroids, patrols,
# generic beacons). See implementation_plans/m39_m44_homefront_roadmap.md,
# "Story data architecture: the overlay".
var sid: String = ""
var hull_script: Script = null      # res://scripts/ships/*.gd or asteroid.gd to instantiate on promote
var iff_tags: Array = []
var kind: int = Kind.TRAFFIC
var is_static: bool = false         # stations/beacons/wormhole never move -> skip dead-reckon

# M42 -- story overlay decorations, merged onto the record by ClusterLoader at
# load time (see load_into()'s overlay/characters params) and applied to the
# live node generically by ClusterManager._promote() (AFTER construction and
# AFTER _rebrand_port_zone). Plain data only, resolved from the character
# registry at LOAD time so ClusterManager never imports story/* -- it just
# consumes these plain fields. Empty when the entity carries no overlay entry.
#   cast: Array[Dictionary]  -- [{name, role, dialogue_path}, ...] one per
#     character stationed here; faction is resolved at PROMOTE time from the
#     node's (possibly just-rebranded) port_zone authority.
#   port_patch: Dictionary   -- merged into the node's port_zone at promote
#     (e.g. {"services": {"repairs": "free"}}).
#   component_overrides: Dictionary -- {component_id: {field: value}} merged
#     into the matching ship_components dict by "id".
var cast: Array = []
var port_patch: Dictionary = {}
var component_overrides: Dictionary = {}

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
