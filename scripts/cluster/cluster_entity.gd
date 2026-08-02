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

# M57 -- the incident log: this entity's own append-only record of things that
# HAPPENED TO OR NEAR IT (design_ideas/2026-08-01-patrol_director_and_reporting.md
# §4c, "verdict vs evidence"). Same storage contract as docking_registry above
# and for the same reasons, so read that comment first; the differences are:
#
#   * NOT station-only. Every entity is a source of its own experience -- a
#     hauler robbed in deep space writes here, on its own record, because there
#     is no station out there and the victim IS the witness. So unlike
#     docking_registry, this is meaningful on a ship record.
#   * ENTRIES CARRY A POSITION. That is the entire point: a warrant is a
#     VERDICT (keyed, overwriting, O(1) for compute_standing -- leave it alone),
#     while an incident is EVIDENCE, one immutable record per occurrence, and
#     you can always re-derive a verdict from evidence but never recover
#     evidence from a verdict. Aggregation/recency/clustering is the READING
#     director's policy, never baked in here.
#
# Entry shape: {"seq": int, "stamp": int, "kind": String, "subject_name":
# String, "subject_flag": String, "pos": Vector2, "reporter": String}. Written
# only via Ship.record_incident() / SourceLog.append_entry -- see
# scripts/mail/source_log.gd for why seq is never rewound on a trim.
var incident_log: Array = []
var incident_seq: int = 0

# M58 -- this entity's mailbag: source_id -> {version, confirmed_at}. What it
# KNOWS, as opposed to incident_log above, which is what it WITNESSED.
#
# Holds no content -- see scripts/mail/mailbag.gd. Every source's log is
# globally reachable on its own record; this vector of integers is what clamps
# a holder's reads of them, and that clamp is the entire fog model. So this
# field is small and stays small: it grows with the number of sources heard of,
# never with the number of facts.
#
# On the record for the same reason as the two logs above (canonical across
# demote, readable while dormant) -- and here it matters more, because a
# dormant station that lost its mailbag would silently re-learn the world for
# free the moment it woke up.
var mailbag: Dictionary = {}

# M53c Phase A -- the station economy (design_ideas/station_economy.md "The
# state"). Lives HERE for the same reason docking_registry does: the RECORD is
# canonical across demote/promote, and under BUBBLE most stations are dormant
# most of the time, so a copy that only existed on a live node would be
# unreadable exactly when a director needs to tick it or a party needs to read
# it. Both empty on every non-station record (asteroids, beacons, traffic --
# same as docking_registry above).
#
#   stocks: holder_key -> commodity -> bin {stock, capacity, target, surplus_line}
#   market: holder_key -> commodity -> policy (Phase B fills this; declared
#     now so the shape exists and nothing has to reshape the record later)
#
# "self" is the station's own bins. ANY OTHER KEY is a party's stockpile AT
# THIS LOCATION -- the keying is (location, holder), never per-station-only
# (design doc's trap 5: get this wrong and party-held stockpiles, hoarding,
# and competing prices at one port are all foreclosed).
#
# INDUSTRY IS A SEPARATE FIELD (`industry` below), deliberately NOT extra keys
# inside stocks["self"]. Two reasons: it keeps `stocks` type-HOMOGENEOUS
# (holder -> commodity -> bin, always, so `for c in stocks[h]` can never hand a
# caller an Array where it expected a bin), and industry belongs to the STATION,
# not to a holder -- a party's stockpile at this location never runs converters.
#
# Bins are FULLY POPULATED for all four Commodity.ALL classes at load, zeros
# included, for every holder key that exists at all -- CLAUDE.md's trap is
# that a missing Dictionary[key] access aborts the rest of that frame's
# function, and this is a two-level nested lookup. Guaranteeing the inner
# (commodity) level means callers only ever need a .get() guard on the OUTER
# (holder) level. See implementation_plans/m53c_demand_routing.md "Phase A".
var stocks: Dictionary = {}
var market: Dictionary = {}

# M53c Phase A -- this station's INDUSTRY, station-level (not per-holder):
#   {"converters": [ {in: {...}, out: {...}, rate: float, state: int, achieved: float}, ... ],
#    "sinks":      { <Commodity> -> lots_per_hour },   # population upkeep; NEVER stops
#    "sources":    { <Commodity> -> lots_per_hour } }  # SCAFFOLDING for mining traffic
# Throughput is DERIVED from this plus bin state, never authored as a net rate
# (design_ideas/station_economy.md "Converters: throughput is derived, not
# authored"). Empty on a station with no authored industry, and on every
# non-station record.
var industry: Dictionary = {}

# Opaque AI/behavior config handed to the hull on promote (route lists, etc.).
# Unused by M14's straight-line movers; carried now so later milestones don't
# have to reshape the record.
var behavior = null

func is_live() -> bool:
	return live_node != null and is_instance_valid(live_node)
