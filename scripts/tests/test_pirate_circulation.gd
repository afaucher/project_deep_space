extends Node

# M53a Slice D -- pirate circulation (implementation_plans/m53a_economic_
# expansion.md, "Pass 4 -- Slice D" + the "Pirate circulation" section): the
# 2026-07-20 playtest's ask that pirates "bounce between available trade
# routes" and "NOT always enter the route in the same spot," plus the false-
# flag-cruise posture alternative to always-dark tradecraft. Three cheap,
# deterministic checks (no physics frames, no live ships) against the guild's
# job-assembly path directly -- pirate_guild.gd's _build_hunt_job/_staging_
# point are called repeatedly and their OUTPUT DATA inspected. Margin-based
# throughout (CLAUDE.md: "assert robustly, not on exact frames/unanimous
# sweeps" -- these are seeded-RNG spreads, not fixed values).
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_pirate_circulation

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

var main_node: Node = null
var failures: Array = []
var spawned_clusters: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Pirate Circulation (M53a Slice D) Tests")

	print("\n--- (a) Route spread: hunt points land on >= 3 distinct lanes ---")
	_test_route_spread()

	print("\n--- (b) Entry-point variance: staging spreads along the same lane ---")
	_test_entry_point_variance()

	print("\n--- (c) Posture: both dark_lurk and false_flag_cruise assemble valid jobs ---")
	_test_posture_job_shapes()

	_finish()

func _finish() -> void:
	for c in spawned_clusters:
		if is_instance_valid(c):
			c.queue_free()
	spawned_clusters.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_pirate_circulation <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_pirate_circulation <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

# The REAL authored home cluster (post M53a Slice A/B: 4 cargo lanes -- Mule
# down the beacon road, Ore Barge to Coldreach, and the two Meridian peer
# lanes to Halvorsen Claim/Corvus Yards). This is the fixture the milestone
# spec calls for ("against a built HomeCluster def/records").
func _make_home_cluster() -> Node:
	var cluster := ClusterManager.new()
	cluster.name = "HomeClusterFixture"
	main_node.add_child(cluster)
	ClusterLoader.load_into(HomeCluster.build(), cluster)
	spawned_clusters.append(cluster)
	return cluster

func _wormhole_pos(cluster) -> Vector2:
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.WORMHOLE:
			return rec.pos
	return Vector2.ZERO

# {rec.id: route Array} for every cargo lane in the cluster.
func _lane_routes(cluster) -> Dictionary:
	var out: Dictionary = {}
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.TRAFFIC:
			continue
		var behavior = rec.behavior
		if typeof(behavior) != TYPE_DICTIONARY or not behavior.get("cargo", false):
			continue
		var route: Array = behavior.get("route", [])
		if route.size() >= 2:
			out[rec.id] = route
	return out

func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Which lane (record id) a hunt point actually landed on -- nearest segment.
func _classify_lane(lane_routes: Dictionary, p: Vector2) -> int:
	var best_id := -1
	var best_d := INF
	for lane_id in lane_routes.keys():
		var route: Array = lane_routes[lane_id]
		for i in range(route.size() - 1):
			var d: float = _dist_point_to_segment(p, route[i], route[i + 1])
			if d < best_d:
				best_d = d
				best_id = lane_id
	return best_id

func _job_lane_pos(job: Dictionary) -> Vector2:
	for st in job.get("steps", []):
		if st.get("verb", "") == "SELECT_VICTIM":
			return st.get("lane_pos", Vector2.ZERO)
	return Vector2.ZERO

func _job_staging_pos(job: Dictionary) -> Vector2:
	var steps: Array = job.get("steps", [])
	if steps.is_empty():
		return Vector2.ZERO
	return steps[0].get("pos", Vector2.ZERO)

# ---------------------------------------------------------------------------
# (a) Route spread -- the Slice D gate: over N assemblies against the real
# 4-lane home cluster, hunt points spread across >= 3 distinct lanes rather
# than piling onto one (margin-based -- CLAUDE.md). The beacon road ("Mule")
# is EXPECTED to be rare/absent from the bucket -- M52a H2's hazard-clearance
# reroll self-selects the 3 non-road lanes on purpose (the milestone doc's
# own note: every point on the 15-beacon road falls inside the beacon keep-
# away). >= 3 distinct lanes over N is the actual gate, not a specific lane's
# presence.
# ---------------------------------------------------------------------------

const ROUTE_SPREAD_SAMPLES := 200
const ROUTE_SPREAD_MIN_DISTINCT_CELLS := 8
const ROUTE_SPREAD_GRID := 60000.0

# 2026-07-26 -- REWRITTEN against map geometry instead of authored lanes.
#
# This assertion used to count how many distinct authored cargo LANES the hunt
# points landed on, and it broke for a real reason: M53d made haulers
# planner-driven, so `_cargo()` stopped emitting a "route" and the cluster
# carries zero authored lanes. The old version reported "0 cargo lanes" and
# "1 distinct lane: {-1: 200}" -- every hunt point on the wormhole fallback,
# pirates no longer distributing at all. That was a genuine gameplay
# regression hiding behind a stale test, not a test-only problem.
#
# There is no lane to classify against any more, so the property worth
# holding is the one that actually matters: hunt points must SPREAD across the
# cluster rather than collapsing onto one place. Coarse spatial cells measure
# that directly and stay meaningful whatever targeting strategy ships.
# Strategy-by-strategy comparison (spread vs hazard clearance vs plausible-
# traffic proxy) lives in test_pirate_targeting.gd.
func _test_route_spread() -> void:
	var cluster = _make_home_cluster()
	var guild = PirateGuild.new()
	var wh_pos: Vector2 = _wormhole_pos(cluster)

	var buckets: Dictionary = {}
	var at_wormhole: int = 0
	for i in range(ROUTE_SPREAD_SAMPLES):
		var job: Dictionary = guild._build_hunt_job(cluster, wh_pos)
		var lane_pos: Vector2 = _job_lane_pos(job)
		buckets[Vector2i(int(floor(lane_pos.x / ROUTE_SPREAD_GRID)), int(floor(lane_pos.y / ROUTE_SPREAD_GRID)))] = true
		if lane_pos.distance_to(wh_pos) < 1.0:
			at_wormhole += 1

	print("  hunt-point cells over %d assemblies: %d" % [ROUTE_SPREAD_SAMPLES, buckets.size()])
	_assert(buckets.size() >= ROUTE_SPREAD_MIN_DISTINCT_CELLS,
		"route spread: hunt points land in >= %d distinct %.0fk cells over %d assemblies (got %d)" %
			[ROUTE_SPREAD_MIN_DISTINCT_CELLS, ROUTE_SPREAD_GRID / 1000.0, ROUTE_SPREAD_SAMPLES, buckets.size()])
	_assert(at_wormhole == 0,
		"route spread: no hunt point degrades to the wormhole fallback (got %d/%d) -- that fallback firing IS the collapse" %
			[at_wormhole, ROUTE_SPREAD_SAMPLES])

# ---------------------------------------------------------------------------
# (b) Entry-point variance -- repeated assemblies against a SINGLE-lane
# cluster (forces the same lane every time) produce materially different
# staging points, both end-to-end (_build_hunt_job) and at the isolated
# mechanism (_staging_point called directly with a FIXED segment, proving
# the anchor itself re-rolls independently of which lane_pos happened to be
# picked -- H2's own lane-fraction reroll would already show SOME spread
# pre-fix since lane_pos is re-picked every assembly too; the fixed-segment
# call isolates the specific staging change this slice makes).
# ---------------------------------------------------------------------------

const VARIANCE_SAMPLES := 100
# Along-lane spread floor: the lane segment below spans ~204k units end to
# end; the anchor fraction stays inside [0.15, 0.85] (matching _pick_lane_
# point's own bound), so the theoretical max spread is ~142k. 40k is a
# comfortable margin above zero (the pre-fix spread, staging rigidly off
# lane_pos) while nowhere near the theoretical ceiling -- robust to run-to-
# run RNG-stream jitter.
const VARIANCE_MIN_SPREAD := 40000.0

func _make_single_lane_cluster() -> Node:
	var cluster := ClusterManager.new()
	cluster.name = "SingleLaneFixture"
	main_node.add_child(cluster)

	var wh := ClusterEntity.new()
	wh.id = 500
	wh.name = "Test Wormhole"
	wh.hull_script = Wormhole
	wh.kind = ClusterEntity.Kind.WORMHOLE
	wh.is_static = true
	wh.pos = Vector2(-20000, -60000)
	cluster.add_record(wh)

	# 2026-07-26 -- the fixture's job is to force ONE hunt segment every
	# assembly, so the staging spread being measured can only come from the
	# re-roll under test and not from a different lane being picked.
	#
	# It used to do that with a single authored cargo lane. Targeting no longer
	# reads authored routes (M53d made haulers planner-driven; see
	# PirateGuild._pick_lane_point), so the faithful translation is EXACTLY TWO
	# TRADE HUBS: with two hubs there is exactly one chord, and every strategy
	# returns a point on it. The authored lane below stays only so the LEGACY_
	# LANE_ROUTES path remains exercisable from this fixture.
	var lane := ClusterEntity.new()
	lane.id = 700
	lane.name = "Test Lane"
	lane.hull_script = CargoShuttle
	lane.kind = ClusterEntity.Kind.TRAFFIC
	lane.is_static = false
	lane.pos = Vector2(20000, 0)
	lane.behavior = {"route": [Vector2(20000, 0), Vector2(220000, 40000)], "cargo": true, "loop": true}
	cluster.add_record(lane)

	for spec in [[701, "Hub A", Vector2(20000, 0)], [702, "Hub B", Vector2(220000, 40000)]]:
		var hub := ClusterEntity.new()
		hub.id = spec[0]
		hub.name = spec[1]
		hub.kind = ClusterEntity.Kind.STATION
		hub.is_static = true
		hub.pos = spec[2]
		# Non-empty `industry` is what marks a station as a TRADE hub for
		# targeting (PirateGuild._trade_station_positions). The contents do not
		# matter here -- only that this reads as somewhere cargo goes.
		hub.industry = {"sinks": {}}
		cluster.add_record(hub)

	spawned_clusters.append(cluster)
	return cluster

# The one chord the fixture above forces, as [a, b].
func _fixture_chord() -> Array:
	return [Vector2(20000, 0), Vector2(220000, 40000)]

func _test_entry_point_variance() -> void:
	var cluster = _make_single_lane_cluster()
	var guild = PirateGuild.new()
	var wh_pos: Vector2 = _wormhole_pos(cluster)
	# The axis comes from the fixture's forced chord rather than from an
	# authored route -- targeting stopped reading routes (see the fixture note).
	var route: Array = _fixture_chord()
	var lane_dir: Vector2 = (route[1] - route[0]).normalized()

	# (b1) End-to-end: N full assemblies against the one-lane cluster.
	var projections: Array = []
	var pts: Array = []
	for i in range(VARIANCE_SAMPLES):
		var job: Dictionary = guild._build_hunt_job(cluster, wh_pos)
		var staging_pos: Vector2 = _job_staging_pos(job)
		pts.append(staging_pos)
		projections.append((staging_pos - route[0]).dot(lane_dir))

	var min_p: float = projections.min()
	var max_p: float = projections.max()
	print("  along-lane projection range over %d assemblies: %.0f .. %.0f (spread %.0f)" % [VARIANCE_SAMPLES, min_p, max_p, max_p - min_p])
	_assert(max_p - min_p >= VARIANCE_MIN_SPREAD,
		"entry-point variance (end-to-end): staging points spread >= %.0f along the lane over %d assemblies (got %.0f)" %
			[VARIANCE_MIN_SPREAD, VARIANCE_SAMPLES, max_p - min_p])

	# Sanity: not just two clustered values -- most points are pairwise
	# separated by a nontrivial margin (bucket to 2000u, count distinct
	# buckets).
	var buckets: Dictionary = {}
	for p in pts:
		var key := Vector2(round(p.x / 2000.0), round(p.y / 2000.0))
		buckets[key] = true
	var min_distinct: int = VARIANCE_SAMPLES / 4
	_assert(buckets.keys().size() >= min_distinct,
		"entry-point variance: staging points land in >= %d distinct 2000u buckets out of %d assemblies (got %d)" %
			[min_distinct, VARIANCE_SAMPLES, buckets.keys().size()])

	# (b2) Isolated mechanism: _staging_point directly, segment held FIXED
	# across every call.
	var seg_a: Vector2 = route[0]
	var seg_b: Vector2 = route[1]
	var direct_projections: Array = []
	for i in range(VARIANCE_SAMPLES):
		var sp: Vector2 = guild._staging_point(wh_pos, seg_a, seg_b)
		direct_projections.append((sp - seg_a).dot(lane_dir))
	var dmin: float = direct_projections.min()
	var dmax: float = direct_projections.max()
	print("  _staging_point direct (fixed segment) projection range: %.0f .. %.0f (spread %.0f)" % [dmin, dmax, dmax - dmin])
	_assert(dmax - dmin >= VARIANCE_MIN_SPREAD,
		"entry-point variance (isolated _staging_point, fixed segment): spread >= %.0f over %d calls (got %.0f)" %
			[VARIANCE_MIN_SPREAD, VARIANCE_SAMPLES, dmax - dmin])

# ---------------------------------------------------------------------------
# (c) Posture -- both dark_lurk and false_flag_cruise must show up within a
# bounded number of draws (P(missing either in 60 draws) is negligible at
# the guild's 40/60 split) and each must assemble the RIGHT step shape:
# dark_lurk keeps the pre-hunt AWAIT{clear}+GO_DARK; false_flag_cruise has
# neither, staying lit into SELECT_VICTIM. BOTH must still carry the intact
# exfil tail (GO_DARK -> GO_TO{exfil} -> AWAIT{track_quiet} -> RELIGHT ->
# EXIT_AT{exit}) -- laundering depends on it regardless of posture.
#
# Skipped here (per the milestone's own "bonus, not required" carve-out): a
# live behavioral proof that a false-flag pirate actually REACHES DEMAND_STOP
# while lit. That needs a full e2e physics sim in test_pirate_ambush.gd's
# style (spawn hulls, run real ticks, watch a witness's sensor read) -- a
# second one of those is a real wall-clock/fragility cost for a check this
# job-data test already covers structurally: the false_flag_cruise job never
# contains a pre-hunt GO_DARK, so INTERCEPT/DEMAND_STOP mechanically CAN'T
# run dark for that posture (job_steps.gd's verb executors don't branch on
# posture at all -- they just run whichever step the job handed them, per
# the "missions are data" design).
# ---------------------------------------------------------------------------

const POSTURE_DRAW_ATTEMPTS := 60

func _test_posture_job_shapes() -> void:
	var cluster = _make_home_cluster()
	var guild = PirateGuild.new()
	var wh_pos: Vector2 = _wormhole_pos(cluster)

	var seen: Dictionary = {}
	for i in range(POSTURE_DRAW_ATTEMPTS):
		var job: Dictionary = guild._build_hunt_job(cluster, wh_pos)
		var posture: String = job.get("posture", "")
		if not seen.has(posture):
			seen[posture] = job
		if seen.has("dark_lurk") and seen.has("false_flag_cruise"):
			break

	_assert(seen.has("dark_lurk"), "posture roll produced at least one dark_lurk job within %d draws" % POSTURE_DRAW_ATTEMPTS)
	_assert(seen.has("false_flag_cruise"), "posture roll produced at least one false_flag_cruise job within %d draws" % POSTURE_DRAW_ATTEMPTS)

	if seen.has("dark_lurk"):
		_assert_dark_lurk_shape(seen["dark_lurk"])
	if seen.has("false_flag_cruise"):
		_assert_false_flag_shape(seen["false_flag_cruise"])

func _verbs(job: Dictionary) -> Array:
	var out: Array = []
	for st in job.get("steps", []):
		out.append(st.get("verb", ""))
	return out

func _assert_dark_lurk_shape(job: Dictionary) -> void:
	var verbs: Array = _verbs(job)
	var select_idx: int = verbs.find("SELECT_VICTIM")
	var clear_idx: int = -1
	var first_dark_idx: int = -1
	for i in range(select_idx):
		var st: Dictionary = job["steps"][i]
		if clear_idx == -1 and st.get("verb", "") == "AWAIT" and st.get("condition", "") == "clear":
			clear_idx = i
		if first_dark_idx == -1 and st.get("verb", "") == "GO_DARK":
			first_dark_idx = i
	_assert(clear_idx != -1 and first_dark_idx != -1 and clear_idx < first_dark_idx and first_dark_idx < select_idx,
		"dark_lurk: pre-hunt AWAIT{clear} -> GO_DARK -> SELECT_VICTIM, in order (clear@%d dark@%d hunt@%d)" % [clear_idx, first_dark_idx, select_idx])
	_assert(verbs.count("GO_DARK") == 2, "dark_lurk: exactly two GO_DARK steps (pre-hunt + post-take), got %d" % verbs.count("GO_DARK"))
	_assert_shared_exfil_tail(job, "dark_lurk")

func _assert_false_flag_shape(job: Dictionary) -> void:
	var verbs: Array = _verbs(job)
	var select_idx: int = verbs.find("SELECT_VICTIM")
	var pre_hunt_dark := false
	for i in range(select_idx):
		var st: Dictionary = job["steps"][i]
		if st.get("verb", "") == "GO_DARK" or (st.get("verb", "") == "AWAIT" and st.get("condition", "") == "clear"):
			pre_hunt_dark = true
	_assert(select_idx == 1, "false_flag_cruise: SELECT_VICTIM immediately follows the staging GO_TO (index 1, got %d)" % select_idx)
	_assert(not pre_hunt_dark, "false_flag_cruise: no pre-hunt AWAIT{clear}/GO_DARK before SELECT_VICTIM")
	_assert(verbs.count("GO_DARK") == 1, "false_flag_cruise: exactly one GO_DARK step (the post-take exfil dark, none pre-hunt), got %d" % verbs.count("GO_DARK"))
	_assert_shared_exfil_tail(job, "false_flag_cruise")

# Both postures: from the FIRST GO_DARK found at/after SELECT_VICTIM onward,
# the tail must be GO_DARK -> GO_TO{label=exfil} -> AWAIT{track_quiet} ->
# RELIGHT{from_kit} -> EXIT_AT{label=exit}, verbatim.
func _assert_shared_exfil_tail(job: Dictionary, label: String) -> void:
	var steps: Array = job.get("steps", [])
	var verbs: Array = _verbs(job)
	var select_idx: int = verbs.find("SELECT_VICTIM")
	var tail_dark_idx: int = -1
	for i in range(select_idx, verbs.size()):
		if verbs[i] == "GO_DARK":
			tail_dark_idx = i
			break
	_assert(tail_dark_idx != -1, "%s: a GO_DARK exists after SELECT_VICTIM (the exfil dark)" % label)
	if tail_dark_idx == -1:
		return
	var tail: Array = verbs.slice(tail_dark_idx)
	_assert(tail == ["GO_DARK", "GO_TO", "AWAIT", "RELIGHT", "EXIT_AT"],
		"%s: exfil tail is GO_DARK->GO_TO->AWAIT->RELIGHT->EXIT_AT verbatim (got %s)" % [label, str(tail)])
	if tail.size() == 5:
		_assert(steps[tail_dark_idx + 1].get("label", "") == "exfil", "%s: exfil GO_TO carries label 'exfil'" % label)
		_assert(steps[tail_dark_idx + 2].get("condition", "") == "track_quiet", "%s: AWAIT condition is track_quiet" % label)
		_assert(steps[tail_dark_idx + 3].get("from_kit", false) == true, "%s: RELIGHT draws from_kit" % label)
		_assert(steps[tail_dark_idx + 4].get("label", "") == "exit", "%s: EXIT_AT carries label 'exit'" % label)
