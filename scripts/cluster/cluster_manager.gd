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

var records: Array = []          # all ClusterEntity, live or dormant
var policy = null                # a LivenessPolicy; defaults to a bubble
var viewpoint: Vector2 = Vector2.ZERO
var live_parent: Node = null     # where live bodies are added (defaults to self)

func _init() -> void:
	policy = LivenessPolicy.new()
	policy.configure_bubble(45000.0, 60000.0)

func _ready() -> void:
	if live_parent == null:
		live_parent = self

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
		node.owner_id = rec.id
		node.iff_tags = rec.iff_tags.duplicate(true)
	# Transform before add_child (body not yet in the physics world -> no teleport
	# warning); velocities after, once it is registered.
	node.position = rec.pos
	node.rotation = rec.rot
	live_parent.add_child(node)
	node.linear_velocity = rec.vel
	node.angular_velocity = rec.ang_vel
	rec.live_node = node
	if is_ship:
		_attach_ai(rec, node)

func _attach_ai(rec, node) -> void:
	# Only autonomous hulls get a brain. The player flies itself; asteroids,
	# beacons and the wormhole have no behavior.
	if rec.kind == ClusterEntity.Kind.TRAFFIC or rec.kind == ClusterEntity.Kind.STATION:
		if node.ship_tier == ComponentSpec.Tier.STRUCTURE:
			node.add_child(AITreeFactory.build_station())
		else:
			node.add_child(AITreeFactory.build_default())

func _demote(rec) -> void:
	var node = rec.live_node
	# Read state back into the record BEFORE freeing -- queue_free is deferred, so
	# the record must become the source of truth this same frame.
	rec.pos = node.position
	rec.rot = node.rotation
	rec.vel = node.linear_velocity
	rec.ang_vel = node.angular_velocity
	rec.live_node = null
	node.queue_free()
