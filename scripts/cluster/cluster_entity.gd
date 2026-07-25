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

# M48 -- Standings & flags (IFF v2). transponder_flag is the record's
# declared allegiance (Standing.FLAG_DRIFT / FLAG_CIVILIAN / ...), applied
# to the live hull via Ship.set_transponder_flag() at promote (an RPC that
# walks ship_components, so it must run AFTER add_child -- see _promote()).
# authority_flags is the plain per-ship field consumed later by M49's
# DEMAND_SURRENDER rules (patrols get it; unread until then). Both are
# authored data on the record, same as iff_tags, so they survive repeated
# demote/promote cycles for free.
var transponder_flag: String = ""
var authority_flags: Array = []

# M52b -- the flag(s) this entity is personally deputized to issue/enforce
# ENFORCEABLE warrants for (design_ideas/warrants.md's "Issuing authority").
# Authored the same way as authority_flags above (stations/patrols get it in
# home_cluster.gd; everyone else stays empty by the Ship-side field default,
# including the player -- the campaign's militia framing's empty-list start
# state). Applied to the live hull at promote(), same as authority_flags.
var warrant_authority: Array = []

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

# M53b Pass 1b -- the per-station docking registry (design_ideas/mail_network.md
# "Docking registry (per station)"). Lives HERE, not on the live Ship node,
# because the RECORD is the source of truth across a demote/promote cycle
# (same contract as pos/vel/rot above) and because under BUBBLE most stations
# are dormant most of the time -- a copy that only existed on the live node
# would be unreadable exactly when the mail fog needs it. Ship.record_docking_
# event() / Ship.get_docking_registry() write/read here via a weak reference
# when a record is attached (see Ship.cluster_record_ref), falling back to a
# local array on bare Ships (sandbox, tests) that never get promoted at all.
# Meaningless (never appended to) on a non-station record, same as the fields
# above. See implementation_plans/m53c_demand_routing.md "Phase 0".
var docking_registry: Array = []
var registry_seq: int = 0

# Opaque AI/behavior config handed to the hull on promote (route lists, etc.).
# Unused by M14's straight-line movers; carried now so later milestones don't
# have to reshape the record.
var behavior = null

func is_live() -> bool:
	return live_node != null and is_instance_valid(live_node)
