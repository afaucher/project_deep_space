extends Node

# M14 acceptance -- the sim bubble. Proves the promote/demote contract and, above
# all, that the *live* entity count (and therefore the O(N^2) fusion cost) stays
# bounded no matter how big the cluster is. Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_cluster_bubble
#
# Sync phases (bubble/hysteresis, bounded-count) run in setup(); the momentum
# round-trip and the +/-500k physics smoke need real physics frames, so they
# finalize in _physics_process after a short coast. Pass marker per CLAUDE.md.

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var main_node: Node = null
var failures: Array = []
var frames_waited: int = 0
var finished: bool = false

# Phase A / D live objects, set up in setup(), finalized in _physics_process.
var man_a = null
var rec_a = null
var man_d = null
var rec_d = null

const COAST_FRAMES := 12
const MOMENTUM_VEL := Vector2(50.0, 0.0)
const SMOKE_ORIGIN := Vector2(240000.0, 0.0)
const SMOKE_VEL := Vector2(30.0, 0.0)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func _mk(id: int, pos: Vector2, hull: Script, kind: int, is_static: bool, vel: Vector2 = Vector2.ZERO):
	var e = ClusterEntity.new()
	e.id = id
	e.hull_script = hull
	e.kind = kind
	e.is_static = is_static
	e.pos = pos
	e.vel = vel
	return e

func setup(main) -> void:
	main_node = main
	print("Starting Cluster Sim Bubble Tests")

	_test_bubble_and_hysteresis()
	_test_bounded_live_count()
	_setup_async_phases()   # momentum + smoke; finalized in _physics_process

# ---------------------------------------------------------------------------
# Phase B: bubble membership + hysteresis (synchronous -- pure policy/bookkeeping).
# ---------------------------------------------------------------------------
func _test_bubble_and_hysteresis() -> void:
	var m = ClusterManager.new()
	var pol = LivenessPolicy.new()
	pol.configure_bubble(10000.0, 15000.0)
	m.policy = pol
	main_node.add_child(m)

	var r0 = _mk(10, Vector2(0, 0), Asteroid, ClusterEntity.Kind.ASTEROID, true)
	var r5 = _mk(11, Vector2(5000, 0), Asteroid, ClusterEntity.Kind.ASTEROID, true)
	var r12 = _mk(12, Vector2(12000, 0), Asteroid, ClusterEntity.Kind.ASTEROID, true)
	var r20 = _mk(13, Vector2(20000, 0), Asteroid, ClusterEntity.Kind.ASTEROID, true)
	for r in [r0, r5, r12, r20]:
		m.add_record(r)

	m.viewpoint = Vector2.ZERO
	m.tick(0.0)
	_assert(r0.is_live() and r5.is_live(), "B: entities within promote_r should be live")
	_assert(not r12.is_live() and not r20.is_live(), "B: entities beyond promote_r should stay dormant")

	# r12 is at 12000 -- between promote_r (10000) and demote_r (15000). Dormant, it
	# must NOT be live from the origin; but once promoted it must STAY live there.
	m.viewpoint = Vector2(3000, 0)   # dist to r12 = 9000 < promote_r -> promotes
	m.tick(0.0)
	_assert(r12.is_live(), "B: r12 should promote once within promote_r")

	m.viewpoint = Vector2.ZERO        # dist to r12 = 12000: > promote_r, < demote_r
	m.tick(0.0)
	_assert(r12.is_live(), "B: hysteresis -- r12 must stay live between promote_r and demote_r")

	m.viewpoint = Vector2(-4000, 0)   # dist to r12 = 16000 > demote_r -> demotes
	m.tick(0.0)
	_assert(not r12.is_live(), "B: r12 should demote past demote_r")

	m.viewpoint = Vector2(1e9, 0)     # clear all before teardown
	m.tick(0.0)
	m.queue_free()

# ---------------------------------------------------------------------------
# Phase C: bounded live-count. Sweep the viewpoint edge-to-edge across a big
# arena; the live count must stay small AND be independent of total record count
# at fixed density. live-count is the proxy for fusion cost (which is ~live^2).
# ---------------------------------------------------------------------------
func _test_bounded_live_count() -> void:
	# Same spacing (density), 10x the extent/count. If the bubble works, the peak
	# live-count is set by local density + radius, not by how many records exist.
	var small_live: int = _sweep_peak_live(40, 2500.0, 30000.0, 45000.0)
	var large_live: int = _sweep_peak_live(400, 2500.0, 30000.0, 45000.0)

	_assert(large_live <= 60, "C: live-count must stay bounded under a full-arena sweep (got %d)" % large_live)
	_assert(abs(large_live - small_live) <= 8,
		"C: live-count must be independent of total N at fixed density (small=%d, large=%d)" % [small_live, large_live])

func _sweep_peak_live(count: int, spacing: float, pr: float, dr: float) -> int:
	var m = ClusterManager.new()
	var pol = LivenessPolicy.new()
	pol.configure_bubble(pr, dr)
	m.policy = pol
	main_node.add_child(m)

	var half: float = (count - 1) * spacing * 0.5
	for i in range(count):
		var x: float = -half + i * spacing
		m.add_record(_mk(20000 + i, Vector2(x, 0), Asteroid, ClusterEntity.Kind.ASTEROID, true))

	var peak: int = 0
	var steps: int = 20
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		m.viewpoint = Vector2(lerpf(-half, half, t), 0.0)
		m.tick(0.0)
		peak = maxi(peak, m.live_count())

	m.viewpoint = Vector2(1e9, 0)   # demote everything before teardown
	m.tick(0.0)
	m.queue_free()
	return peak

# ---------------------------------------------------------------------------
# Phase A (momentum round-trip) + Phase D (+/-500k physics smoke). Both need real
# physics integration, so promote here and finalize after COAST_FRAMES.
# ---------------------------------------------------------------------------
func _setup_async_phases() -> void:
	# A: a lone frigate coasting at MOMENTUM_VEL, kept live by a tight bubble.
	man_a = ClusterManager.new()
	var pol_a = LivenessPolicy.new()
	pol_a.configure_bubble(1000.0, 2000.0)
	man_a.policy = pol_a
	main_node.add_child(man_a)
	rec_a = _mk(1, Vector2.ZERO, Frigate, ClusterEntity.Kind.PLAYER, false, MOMENTUM_VEL)
	man_a.add_record(rec_a)
	man_a.viewpoint = Vector2.ZERO
	man_a.tick(0.0)
	_assert(rec_a.is_live(), "A: frigate should promote at the viewpoint")
	if rec_a.is_live():
		var v: Vector2 = rec_a.live_node.linear_velocity
		_assert(v.distance_to(MOMENTUM_VEL) < 1.0, "A: promoted body should carry the record's velocity")

	# D: a frigate parked at +/-240k, kept live (full sim) to prove stable physics
	# out at the edge of the playable boundary (Foam boundary is 250k).
	man_d = ClusterManager.new()
	var pol_d = LivenessPolicy.new()
	pol_d.configure_full_sim()
	man_d.policy = pol_d
	main_node.add_child(man_d)
	rec_d = _mk(2, SMOKE_ORIGIN, Frigate, ClusterEntity.Kind.PLAYER, false, SMOKE_VEL)
	man_d.add_record(rec_d)
	man_d.tick(0.0)
	_assert(rec_d.is_live(), "D: +/-240k body should be live under full-sim")
	if rec_d.is_live():
		var p: Vector2 = rec_d.live_node.position
		_assert(is_finite(p.x) and is_finite(p.y), "D: +/-240k body position must be finite on promote")

func _physics_process(_delta: float) -> void:
	if finished or main_node == null:
		return
	frames_waited += 1
	if frames_waited < COAST_FRAMES:
		return
	finished = true

	# A: demote the coasting frigate and verify momentum survived the round-trip.
	man_a.viewpoint = Vector2(1e9, 0)
	man_a.tick(0.0)
	_assert(not rec_a.is_live(), "A: frigate should demote once the viewpoint leaves")
	_assert(rec_a.vel.distance_to(MOMENTUM_VEL) < 1.0,
		"A: velocity must be preserved across a dormancy round-trip (got %s)" % str(rec_a.vel))
	_assert(rec_a.pos.x > 1.0, "A: body should have advanced under physics while live (got x=%.3f)" % rec_a.pos.x)
	_assert(is_finite(rec_a.pos.x) and is_finite(rec_a.pos.y), "A: round-tripped position must be finite")

	# D: after coasting at +/-240k, physics must still be sane (finite, moved +x).
	if rec_d.is_live():
		var dp: Vector2 = rec_d.live_node.position
		var dv: Vector2 = rec_d.live_node.linear_velocity
		_assert(is_finite(dp.x) and is_finite(dp.y), "D: +/-240k position must stay finite after coasting")
		_assert(dp.x > SMOKE_ORIGIN.x, "D: +/-240k body should have moved +x under physics")
		_assert(is_finite(dv.x) and is_finite(dv.y), "D: +/-240k velocity must stay finite")

	_finalize()

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_cluster_bubble <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_cluster_bubble <<<")
		get_tree().quit(1)
