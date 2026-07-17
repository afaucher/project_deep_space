extends Node
class_name ClusterManager

# M14 -- owns every ClusterEntity record and, each tick, reconciles which are live
# against a viewpoint. Live entities are physics-authoritative RigidBody2D +
# (for autonomous hulls) an AI tree; dormant entities are dead-reckoned records
# with no body, no fusion, no AI. This is what decouples map size from sim cost:
# the O(N^2) sensor-fusion sweep in ship.gd only ever runs over the *live* set,
# which the policy bounds. See implementation_plans/m14_cluster_sim_bubble_design.md.
#
# Referenced by callers via preload const, never the bare class_name, per the
# headless class-cache caveat in CLAUDE.md.

const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const PortControl = preload("res://scripts/port/port_control.gd")
const NPCProfile = preload("res://scripts/comms/npc_profile.gd")
const PORT_CONTROL_DIALOGUE = preload("res://dialogue/port_control.dialogue")

var records: Array = []          # all ClusterEntity, live or dormant
var policy = null                # a LivenessPolicy; defaults to a bubble
var viewpoint: Vector2 = Vector2.ZERO
var live_parent: Node = null     # where live bodies are added (defaults to self)
var viewpoint_node: Node = null  # if set, the live game drives viewpoint from it each frame
var cluster_def = null           # the authored ClusterDef (for the nav computer's beacon graph)

func _init() -> void:
	policy = LivenessPolicy.new()
	# policy.configure_bubble(45000.0, 60000.0)
	policy.configure_full_sim()

func _ready() -> void:
	if live_parent == null:
		live_parent = self

# In the live game the player ship is the viewpoint, so self-tick each frame.
# Tests leave viewpoint_node null and drive tick() manually for determinism.
func _physics_process(delta: float) -> void:
	if viewpoint_node != null and is_instance_valid(viewpoint_node):
		viewpoint = viewpoint_node.position
		tick(delta)

func add_record(rec) -> void:
	records.append(rec)

# Advance dormant movers, then reconcile liveness against the viewpoint. Dormant
# movers are dead-reckoned in straight lines; live bodies are left to physics.
func tick(dt: float) -> void:
	for rec in records:
		if not rec.is_live() and not rec.is_static:
			rec.pos += rec.vel * dt
	_reconcile()

func _reconcile() -> void:
	for rec in records:
		var tier: int = policy.classify(rec, viewpoint)
		var want_live: bool = (tier == LivenessPolicy.Tier.LIVE)
		if want_live and not rec.is_live():
			_promote(rec)
		elif not want_live and rec.is_live():
			_demote(rec)

func live_count() -> int:
	var n: int = 0
	for rec in records:
		if rec.is_live():
			n += 1
	return n

func _promote(rec) -> void:
	var node = rec.hull_script.new()
	node.name = "Cluster_%d" % rec.id
	# Ship-like hulls carry secure identity; asteroids/landmarks don't. Detect a
	# Ship by a method only it has, avoiding a bare `is Ship` class-name reference.
	var is_ship: bool = node.has_method("get_ship_mass")
	if is_ship:
		node.owner_id = 0 # 0 means server-owned NPC; rec.id overlaps with peer IDs
		node.iff_tags = rec.iff_tags.duplicate(true)
		node.ship_name = rec.name
		node.authority_flags = rec.authority_flags.duplicate(true)
	# Transform before add_child (body not yet in the physics world -> no teleport
	# warning); velocities after, once it is registered.
	node.position = rec.pos
	node.rotation = rec.rot
	live_parent.add_child(node)
	# Velocities only apply to physics bodies; landmarks (e.g. Wormhole, a Node2D)
	# are transform-only.
	if node is RigidBody2D:
		node.linear_velocity = rec.vel
		node.angular_velocity = rec.ang_vel
	rec.live_node = node
	# M48 -- set_transponder_flag is an RPC (call_local) that walks
	# ship_components, so it must run AFTER add_child (component list isn't
	# normalized until _ready(), which fires on entering the tree).
	if is_ship and rec.transponder_flag != "":
		node.set_transponder_flag(rec.transponder_flag)
	_rebrand_port_zone(node, rec.name)
	_apply_overlay_decorations(rec, node)
	if is_ship:
		_attach_ai(rec, node)

# A hull's port_zone/NPC identity (authority name, the port-control NPC's
# faction + display name) is baked in at construction time as a class-level
# default -- e.g. MediumStation's _init() always sets "Ironhold Control",
# historically true when only one medium station existed. The home cluster
# reuses that SAME class for three hubs (Ironhold, Drift Market, Refinery
# Prime), so every instance shares the identical literal unless rebranded
# here once the entity's real name (rec.name) is known.
#
# Without this, Ship.issue_docking_grant()'s reservation scan (ship.gd) --
# which matches outstanding grants to a station purely by `authority` STRING,
# scanning every ship in the "ships" group -- treats a grant held anywhere in
# the cluster as reserving a slip at EVERY medium station, since they all
# report the same authority + the same single docking-port id ("dock_main").
# With cargo traffic constantly cycling through hubs (home_cluster.gd's
# looping shuttles), some grant matching that shared identity is outstanding
# almost continuously, so every hub's docking request reads as permanently
# "no open berths" regardless of that hub's own actual occupancy. Rebranding
# to a per-entity authority ("<name> Control") makes the reservation scan's
# authority check correctly scope to the right station again.
#
# Duck-typed (works on any hull exposing a non-empty `port_zone`), not
# station-specific -- doesn't need updating if another controlled-hull class
# is added later.
func _rebrand_port_zone(node, entity_name: String) -> void:
	var zone = node.get("port_zone")
	if not (zone is Dictionary) or zone.is_empty():
		return
	zone["authority"] = "%s Control" % entity_name

	var npcs = node.get("available_npcs")
	if npcs == null:
		return
	for npc in npcs:
		if npc is NPCProfile and npc.default_dialogue == PORT_CONTROL_DIALOGUE:
			npc.faction = zone["authority"]
			npc.character_name = PortControl.get_controller_name(node)

# M42 -- applies whatever plain, generic decorations the record was carrying
# (ClusterLoader._merge_overlay folded the story overlay onto it at load
# time -- ClusterManager never imports story/*, it just consumes plain
# fields). Called AFTER construction and AFTER _rebrand_port_zone(), per the
# roadmap's M42 section: rebrand sets authority first, the port patch below
# adds to it (must not clobber), and cast injection APPENDS to
# available_npcs (MediumStation._init() already self-appends its own
# port-control NPC -- see cluster_manager.gd's docking-bug comment above).
# No-ops cheaply for the overwhelming majority of entities (asteroids,
# patrols, unreferenced stations) that carry no overlay data.
func _apply_overlay_decorations(rec, node) -> void:
	# 1. Port patch -- merge into the node's port_zone (flat top-level merge;
	# `authority` was just set by _rebrand_port_zone above and is left alone
	# unless the patch explicitly names it, which no overlay entry does).
	if not rec.port_patch.is_empty():
		var zone = node.get("port_zone")
		if zone is Dictionary and not zone.is_empty():
			for key in rec.port_patch.keys():
				zone[key] = rec.port_patch[key]

	# 2. Cast -- append an NPCProfile per plain {name, role, dialogue_path}
	# descriptor. Faction resolves NOW (not at load) because it depends on
	# the node's (possibly just-rebranded) port_zone authority.
	if not rec.cast.is_empty():
		var npcs = node.get("available_npcs")
		if npcs != null:
			var zone2 = node.get("port_zone")
			var faction: String = "Independent"
			if zone2 is Dictionary and zone2.get("authority", "") != "":
				faction = zone2["authority"]
			for desc in rec.cast:
				var npc := NPCProfile.new()
				npc.character_name = desc.get("name", "Unknown Contact")
				npc.faction = faction
				npc.tier = NPCProfile.Tier.PUBLIC
				var dpath: String = desc.get("dialogue_path", "")
				if dpath != "" and ResourceLoader.exists(dpath):
					npc.default_dialogue = load(dpath)
				npcs.append(npc)

	# 3. Component overrides -- {component_id: {field: value}} merged into
	# the matching ship_components dict by "id". Missing-key-safe (.get())
	# per the CLAUDE.md GDScript trap -- a record targeting a component id
	# this hull doesn't have is simply skipped, never an error.
	if not rec.component_overrides.is_empty():
		var comps = node.get("ship_components")
		if comps is Array:
			for comp in comps:
				var cid: String = comp.get("id", "")
				if cid != "" and rec.component_overrides.has(cid):
					var patch: Dictionary = rec.component_overrides[cid]
					for key in patch.keys():
						comp[key] = patch[key]

func _attach_ai(rec, node) -> void:
	# Only autonomous hulls get a brain. The player flies itself; asteroids,
	# beacons and the wormhole have no behavior.
	if rec.kind != ClusterEntity.Kind.TRAFFIC and rec.kind != ClusterEntity.Kind.STATION:
		return
	if node.ship_tier == ComponentSpec.Tier.STRUCTURE:
		node.add_child(AITreeFactory.build_station())
		return
	# Mobile hull: patrol if it was handed a route (via behavior), else combat AI.
	var route = _route_from(rec.behavior)
	if route != null and route.size() > 0:
		node.patrol_route = route
		node.patrol_loop = _loop_from(rec.behavior)
		if _is_cargo(rec.behavior):
			node.add_child(AITreeFactory.build_cargo())
		else:
			node.add_child(AITreeFactory.build_patrol())
	else:
		node.add_child(AITreeFactory.build_default())

func _route_from(behavior):
	if typeof(behavior) == TYPE_DICTIONARY and behavior.has("route"):
		return behavior["route"]
	return null

func _loop_from(behavior) -> bool:
	if typeof(behavior) == TYPE_DICTIONARY:
		return behavior.get("loop", true)
	return true

func _is_cargo(behavior) -> bool:
	return typeof(behavior) == TYPE_DICTIONARY and behavior.get("cargo", false)

func _demote(rec) -> void:
	var node = rec.live_node
	# Read state back into the record BEFORE freeing -- queue_free is deferred, so
	# the record must become the source of truth this same frame.
	rec.pos = node.position
	rec.rot = node.rotation
	if node is RigidBody2D:
		rec.vel = node.linear_velocity
		rec.ang_vel = node.angular_velocity
	rec.live_node = null
	node.queue_free()
