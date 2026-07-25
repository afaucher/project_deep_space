extends Node

# M53b Pass 2 -- the traffic guild director (implementation_plans/
# m53bc_traffic_guild.md "Pass 2"). Manual cluster.tick() drive (no physics
# frames needed -- the guild is pure ledger + policy tick, deterministic
# under the FAST test config), same style as test_pirate_guild.gd. A
# synthetic cluster carries a wormhole, the two road-terminus stations
# (Ironhold/Drift Market, by NAME -- what TrafficGuild's config reads), two
# FLAG_DRIFT authored cargo lanes and one FLAG_MERIDIAN lane -- everything
# the director is honestly allowed to read (its own members' nodes, and the
# records array's public geometry). Covers:
#   (a) adoption folds the authored lanes in on first tick
#   (b) adoption is idempotent (a second policy pass doesn't double-count)
#   (c) a killed hauler is replenished on the SAME route, record retired
#   (d) freighter lifecycle: itinerary shape, civilian job tree, departure
#   (e) population cap respected (hard_cap bounds roster pressure)
#   (f) determinism under a seed
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_traffic_guild

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const TrafficGuild = preload("res://scripts/directors/traffic_guild.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Standing = preload("res://scripts/combat/standing.gd")

# Fast config per CLAUDE.md/the design doc -- config is data, so tuning it for
# test speed is legitimate, not a test backdoor.
const FAST_CONFIG := {
	"policy_period": 0.5,
	"presumed_lost_delay": 2.0,
	"population_targets": {Standing.FLAG_DRIFT: 2, Standing.FLAG_MERIDIAN: 1},
	"hauler_arrival_window": [1.0, 2.0],
	"relief_name": "Relief Hauler",
	"freighter_target": 1,
	"freighter_arrival_window": [1.0, 2.0],
	"freighter_hull": CargoShuttle,
	"freighter_flag": Standing.FLAG_CIVILIAN,
	"freighter_name": "Transient Freighter",
	"road_terminus_a": "Ironhold",
	"road_terminus_b": "Drift Market",
	"hard_cap": 10,
}

const WORMHOLE_POS := Vector2(-5000, 0)
const IRONHOLD_POS := Vector2(0, 0)
const DRIFT_MARKET_POS := Vector2(400000, 80000)
const COLDREACH_POS := Vector2(-70000, 90000)
const MERIDIAN_POS := Vector2(-280000, -260000)

const MULE_ROUTE := [IRONHOLD_POS, DRIFT_MARKET_POS]
const ORE_BARGE_ROUTE := [IRONHOLD_POS, COLDREACH_POS]
const MERIDIAN_ROUTE := [IRONHOLD_POS, MERIDIAN_POS]

var main_node: Node = null
var failures: Array = []
var spawned_clusters: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# ---------------------------------------------------------------------------
# Cluster fixture -- a wormhole, the two named road termini, two DRIFT cargo
# lanes and one MERIDIAN cargo lane (mirrors home_cluster.gd's 700/701/702
# shape closely enough to exercise per-flag adoption honestly).
# ---------------------------------------------------------------------------

func _make_cluster() -> Node:
	var cluster := ClusterManager.new()
	cluster.name = "TestCluster"
	main_node.add_child(cluster)

	var wh := ClusterEntity.new()
	wh.id = 500
	wh.name = "Nexus Wormhole"
	wh.hull_script = Wormhole
	wh.kind = ClusterEntity.Kind.WORMHOLE
	wh.is_static = true
	wh.pos = WORMHOLE_POS
	cluster.add_record(wh)

	var ironhold := ClusterEntity.new()
	ironhold.id = 1
	ironhold.name = "Ironhold"
	ironhold.hull_script = MediumStation
	ironhold.kind = ClusterEntity.Kind.STATION
	ironhold.is_static = true
	ironhold.pos = IRONHOLD_POS
	ironhold.iff_tags = ["TEAM_DRIFT_TEST"]
	ironhold.transponder_flag = Standing.FLAG_DRIFT
	cluster.add_record(ironhold)

	var drift_market := ClusterEntity.new()
	drift_market.id = 2
	drift_market.name = "Drift Market"
	drift_market.hull_script = MediumStation
	drift_market.kind = ClusterEntity.Kind.STATION
	drift_market.is_static = true
	drift_market.pos = DRIFT_MARKET_POS
	drift_market.iff_tags = ["TEAM_DRIFT_TEST"]
	drift_market.transponder_flag = Standing.FLAG_DRIFT
	cluster.add_record(drift_market)

	var mule := ClusterEntity.new()
	mule.id = 700
	mule.name = "Mule"
	mule.hull_script = CargoShuttle
	mule.kind = ClusterEntity.Kind.TRAFFIC
	mule.is_static = false
	mule.pos = MULE_ROUTE[0]
	mule.iff_tags = ["TEAM_DRIFT_TEST"]
	mule.transponder_flag = Standing.FLAG_DRIFT
	mule.behavior = {"route": MULE_ROUTE, "loop": true, "cargo": true}
	cluster.add_record(mule)

	var ore_barge := ClusterEntity.new()
	ore_barge.id = 701
	ore_barge.name = "Ore Barge"
	ore_barge.hull_script = CargoShuttle
	ore_barge.kind = ClusterEntity.Kind.TRAFFIC
	ore_barge.is_static = false
	ore_barge.pos = ORE_BARGE_ROUTE[0]
	ore_barge.iff_tags = ["TEAM_DRIFT_TEST"]
	ore_barge.transponder_flag = Standing.FLAG_DRIFT
	ore_barge.behavior = {"route": ORE_BARGE_ROUTE, "loop": true, "cargo": true}
	cluster.add_record(ore_barge)

	var meridian := ClusterEntity.new()
	meridian.id = 702
	meridian.name = "Meridian Runner"
	meridian.hull_script = OreShuttle
	meridian.kind = ClusterEntity.Kind.TRAFFIC
	meridian.is_static = false
	meridian.pos = MERIDIAN_ROUTE[0]
	meridian.iff_tags = ["TEAM_MERIDIAN_TEST"]
	meridian.transponder_flag = Standing.FLAG_MERIDIAN
	meridian.behavior = {"route": MERIDIAN_ROUTE, "loop": true, "cargo": true}
	cluster.add_record(meridian)

	spawned_clusters.append(cluster)
	return cluster

func _find_rec(cluster, record_id: int):
	for r in cluster.records:
		if r.id == record_id:
			return r
	return null

# Same "vanished via an external despawn" splice test_pirate_guild.gd uses:
# removes the record AND frees whatever live node it had, mirroring what
# ClusterManager._reconcile() does the tick after an EXIT_AT queue_free.
func _vanish_record(cluster, record_id: int) -> void:
	for i in range(cluster.records.size()):
		if cluster.records[i].id == record_id:
			var rec = cluster.records[i]
			cluster.records.remove_at(i)
			if rec.live_node != null and is_instance_valid(rec.live_node):
				rec.live_node.queue_free()
			return

func _advance_until_member_state(guild, record_id: int, target_states: Array, cluster, period: float, max_ticks: int) -> bool:
	for i in range(max_ticks):
		if guild.members.has(record_id) and target_states.has(guild.members[record_id].get("state", -1)):
			return true
		cluster.tick(period)
	return guild.members.has(record_id) and target_states.has(guild.members[record_id].get("state", -1))

func _advance_until_freighter_state(guild, record_id: int, target_states: Array, cluster, period: float, max_ticks: int) -> bool:
	for i in range(max_ticks):
		if guild.freighters.has(record_id) and target_states.has(guild.freighters[record_id].get("state", -1)):
			return true
		cluster.tick(period)
	return guild.freighters.has(record_id) and target_states.has(guild.freighters[record_id].get("state", -1))

func _wait_for_any_freighter(guild, cluster, period: float, max_ticks: int) -> int:
	for i in range(max_ticks):
		for rid in guild.freighters.keys():
			if guild.freighters[rid].get("state", -1) == TrafficGuild.FreighterState.ACTIVE:
				var rec = _find_rec(cluster, rid)
				if rec != null and rec.is_live():
					return rid
		cluster.tick(period)
	return -1

# ---------------------------------------------------------------------------

func setup(main) -> void:
	DebugSettings.set_choice("traffic_guild_log", DebugSettings.TrafficGuildLog.ON)
	main_node = main
	print("Starting Traffic Guild (M53b Pass 2) Tests")

	print("\n--- (a) Adoption folds the authored lanes in ---")
	_test_adoption()

	print("\n--- (b) Adoption is idempotent ---")
	_test_adoption_idempotent()

	print("\n--- (c) Killed hauler replenished on the same route ---")
	_test_replenish_same_route()

	print("\n--- (d) Freighter lifecycle ---")
	_test_freighter_lifecycle()

	print("\n--- (e) Population cap respected ---")
	_test_population_cap()

	print("\n--- (f) Determinism ---")
	_test_determinism()

	print("\n--- (g) Civilian job tree generalization (structural gap fix) ---")
	_test_civilian_job_tree_and_pirate_untouched()

	_finish()

# ---------------------------------------------------------------------------
# (a) Adoption: one policy pass folds all three authored lanes in as ACTIVE
# members under the right flag/route, and (targets matching the adopted
# count exactly) schedules no extra arrivals.
# ---------------------------------------------------------------------------

func _test_adoption() -> void:
	var cluster = _make_cluster()
	var guild = TrafficGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]

	cluster.tick(period)

	_assert(guild.members.size() == 3, "(a) all three authored lanes adopted (got %d)" % guild.members.size())
	_assert(guild.members.has(700) and guild.members[700]["flag"] == Standing.FLAG_DRIFT,
		"(a) Mule (700) adopted under FLAG_DRIFT")
	_assert(guild.members.has(700) and guild.members[700]["route"] == MULE_ROUTE,
		"(a) Mule's route matches the authored lane exactly")
	_assert(guild.members.has(701) and guild.members[701]["route"] == ORE_BARGE_ROUTE,
		"(a) Ore Barge (701) adopted with its own route")
	_assert(guild.members.has(702) and guild.members[702]["flag"] == Standing.FLAG_MERIDIAN,
		"(a) Meridian Runner (702) adopted under FLAG_MERIDIAN")
	for rid in [700, 701, 702]:
		_assert(guild.members[rid]["state"] == TrafficGuild.MemberState.ACTIVE, "(a) record %d is ACTIVE" % rid)
	var hauler_arrivals := 0
	for arrival in guild.arrivals:
		if arrival.get("kind", "") == "hauler":
			hauler_arrivals += 1
	_assert(hauler_arrivals == 0,
		"(a) hauler targets already satisfied by adoption -- no extra hauler arrivals scheduled (got %d; freighter arrivals are separate)" % hauler_arrivals)

# ---------------------------------------------------------------------------
# (b) Idempotent: a second (and third) policy pass must not re-adopt or
# double-count -- members.size() stays 3, and the cluster gains no duplicate
# records for 700/701/702.
# ---------------------------------------------------------------------------

func _test_adoption_idempotent() -> void:
	var cluster = _make_cluster()
	var guild = TrafficGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]

	cluster.tick(period)
	var after_first: int = guild.members.size()
	cluster.tick(period)
	cluster.tick(period)

	_assert(guild.members.size() == after_first, "(b) member count unchanged after repeated policy passes (%d -> %d)" % [after_first, guild.members.size()])
	var count_700 := 0
	for rec in cluster.records:
		if rec.id == 700:
			count_700 += 1
	_assert(count_700 == 1, "(b) exactly one record still carries id 700 (no duplicate spawn), got %d" % count_700)

# ---------------------------------------------------------------------------
# (c) Kill the adopted Mule -> OVERDUE -> LOST after the delay -> record
# erased, losses incremented -> a replacement arrives serving the EXACT SAME
# route, under the same flag, with the same hull class.
# ---------------------------------------------------------------------------

func _test_replenish_same_route() -> void:
	var cluster = _make_cluster()
	var guild = TrafficGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2

	cluster.tick(period) # adoption
	_assert(guild.members.has(700), "(c) Mule adopted before the kill")
	var mule_rec = _find_rec(cluster, 700)
	_assert(mule_rec != null and mule_rec.is_live(), "(c) Mule's record is live (promoted)")
	if mule_rec == null or not mule_rec.is_live():
		return

	mule_rec.live_node.hulk()
	cluster.tick(period) # check-in observes is_dead -> OVERDUE
	_assert(guild.members[700]["state"] == TrafficGuild.MemberState.OVERDUE, "(c) hulked Mule goes OVERDUE")

	var resolved: bool = _advance_until_member_state(guild, 700, [TrafficGuild.MemberState.LOST], cluster, period, delay_ticks + 2)
	_assert(resolved, "(c) Mule resolves LOST after the delay")
	_assert(_find_rec(cluster, 700) == null, "(c) LOST Mule's record is erased from cluster.records")
	_assert(guild.losses == 1, "(c) losses incremented")

	var replacement_id := -1
	for i in range(30):
		for rid in guild.members.keys():
			if rid != 700 and guild.members[rid].get("flag", "") == Standing.FLAG_DRIFT \
					and guild.members[rid].get("route", []) == MULE_ROUTE \
					and guild.members[rid].get("state", -1) == TrafficGuild.MemberState.ACTIVE:
				var rec = _find_rec(cluster, rid)
				if rec != null and rec.is_live():
					replacement_id = rid
					break
		if replacement_id != -1:
			break
		cluster.tick(period)
	_assert(replacement_id != -1, "(c) a replacement hauler went ACTIVE (and live) on the Mule's exact route within the window")
	if replacement_id != -1:
		_assert(guild.members[replacement_id]["hull_script"] == CargoShuttle, "(c) replacement carries the same hull class as the lost hauler")
		var rec = _find_rec(cluster, replacement_id)
		_assert(rec != null and rec.is_live(), "(c) replacement's record is live")
		if rec != null and rec.is_live():
			var node = rec.live_node
			_assert(node.get_node_or_null("AITree") != null, "(c) replacement carries an AI tree")
			_assert(node.patrol_route == MULE_ROUTE, "(c) replacement's patrol_route matches the Mule's exact route")
	# Ore Barge (701) and Meridian Runner (702) were never touched.
	_assert(guild.members[701]["state"] == TrafficGuild.MemberState.ACTIVE, "(c) Ore Barge untouched (still ACTIVE)")
	_assert(guild.members[702]["state"] == TrafficGuild.MemberState.ACTIVE, "(c) Meridian Runner untouched (still ACTIVE)")

# ---------------------------------------------------------------------------
# (d) Freighter lifecycle: itinerary well-formedness (direct, deterministic --
# no RNG in the freighter job at all), a spawned freighter's civilian job
# tree, and clean departure/retirement via the same external-despawn
# discipline PirateGuild uses.
# ---------------------------------------------------------------------------

func _test_freighter_lifecycle() -> void:
	var cluster = _make_cluster()
	var guild = TrafficGuild.new(FAST_CONFIG)

	# --- Itinerary shape, driven directly (deterministic, no physics run). ---
	var job: Dictionary = guild._build_freighter_job(cluster, WORMHOLE_POS)
	var steps: Array = job.get("steps", [])
	var verbs: Array = []
	for st in steps:
		verbs.append(st.get("verb", ""))
	_assert(verbs == ["GO_TO", "DOCK_AT", "AWAIT", "GO_TO", "DOCK_AT", "AWAIT", "EXIT_AT"],
		"(d) freighter itinerary is the canonical GO_TO->DOCK_AT->AWAIT->GO_TO->DOCK_AT->AWAIT->EXIT_AT shape (got %s)" % str(verbs))
	if verbs.size() == 7:
		_assert(steps[0]["pos"] == IRONHOLD_POS, "(d) first leg targets the terminus nearest the wormhole (Ironhold)")
		_assert(steps[1]["station_pos"] == IRONHOLD_POS, "(d) first DOCK_AT is at Ironhold")
		_assert(steps[2]["condition"] == "undocked", "(d) first AWAIT is condition undocked")
		_assert(steps[3]["pos"] == DRIFT_MARKET_POS, "(d) second leg targets Drift Market")
		_assert(steps[4]["station_pos"] == DRIFT_MARKET_POS, "(d) second DOCK_AT is at Drift Market")
		_assert(steps[5]["condition"] == "undocked", "(d) second AWAIT is condition undocked")
		_assert(steps[6]["pos"] == WORMHOLE_POS, "(d) EXIT_AT targets the wormhole")

	# --- A real spawn: wire the guild in and let it schedule/spawn one. ---
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]
	var freighter_id: int = _wait_for_any_freighter(guild, cluster, period, 30)
	_assert(freighter_id != -1, "(d) a freighter went ACTIVE within the window")
	if freighter_id == -1:
		return

	var rec = _find_rec(cluster, freighter_id)
	_assert(rec != null and rec.is_live(), "(d) freighter's record is live")
	if rec == null or not rec.is_live():
		return
	var node = rec.live_node
	var tree = node.get_node_or_null("AITree")
	_assert(tree != null, "(d) freighter carries an AI tree")
	_assert(not node.assignment.is_empty(), "(d) freighter carries an assigned job")
	if tree != null:
		var root = tree.get_child(0) if tree.get_child_count() > 0 else null
		var child_names: Array = []
		if root != null:
			for c in root.get_children():
				child_names.append(c.name)
		_assert(child_names.has("ThreatResponse"), "(d) freighter's tree carries ThreatResponse (comply-or-run/SOS, same as any hauler) (children=%s)" % str(child_names))
		_assert(child_names.has("JobRunner"), "(d) freighter's tree carries JobRunner (children=%s)" % str(child_names))
		_assert(not child_names.has("CargoRun"), "(d) freighter's tree does NOT carry CargoRun (job-driven, not lane-driven)")

	# --- Departure: simulate the EXIT_AT external despawn, then retire. ---
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2
	_vanish_record(cluster, freighter_id)
	cluster.tick(period) # check-in: record gone -> OVERDUE
	_assert(guild.freighters[freighter_id]["state"] == TrafficGuild.FreighterState.OVERDUE, "(d) vanished freighter goes OVERDUE")

	var resolved: bool = _advance_until_freighter_state(guild, freighter_id, [TrafficGuild.FreighterState.DEPARTED], cluster, period, delay_ticks + 2)
	_assert(resolved, "(d) freighter resolves DEPARTED after the delay")
	_assert(_find_rec(cluster, freighter_id) == null, "(d) departed freighter's record stays retired")
	_assert(guild.freighters_departed == 1, "(d) freighters_departed counted")

# ---------------------------------------------------------------------------
# (e) Population cap: a low hard_cap with targets/freighter_target set well
# above it -- roster pressure must never exceed the cap across many ticks.
# ---------------------------------------------------------------------------

func _test_population_cap() -> void:
	var cluster = _make_cluster()
	var cfg: Dictionary = FAST_CONFIG.duplicate(true)
	cfg["population_targets"] = {Standing.FLAG_DRIFT: 5, Standing.FLAG_MERIDIAN: 5}
	cfg["freighter_target"] = 5
	cfg["hard_cap"] = 3
	var guild = TrafficGuild.new(cfg)
	cluster.directors.append(guild)
	var period: float = cfg["policy_period"]

	var max_seen := 0
	for i in range(200):
		cluster.tick(period)
		max_seen = maxi(max_seen, guild._total_roster_pressure())
		_assert(guild._total_roster_pressure() <= cfg["hard_cap"],
			"(e) roster pressure never exceeds hard_cap=%d (tick %d, got %d)" % [cfg["hard_cap"], i, guild._total_roster_pressure()])
	_assert(max_seen <= cfg["hard_cap"], "(e) max observed roster pressure over the run stayed at/under the cap (max=%d, cap=%d)" % [max_seen, cfg["hard_cap"]])

# ---------------------------------------------------------------------------
# (f) Determinism: two fresh guilds, same config, same seed, same scripted
# event sequence -> identical ledgers.
# ---------------------------------------------------------------------------

func _run_scripted_sequence(cluster, guild) -> void:
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2

	cluster.tick(period) # adoption
	_find_rec(cluster, 700).live_node.hulk()
	_advance_until_member_state(guild, 700, [TrafficGuild.MemberState.LOST], cluster, period, delay_ticks + 2)

	# Wait for the replacement hauler AND a freighter to both go ACTIVE.
	for i in range(30):
		var replaced := false
		for rid in guild.members.keys():
			if rid != 700 and guild.members[rid].get("route", []) == MULE_ROUTE and guild.members[rid].get("state", -1) == TrafficGuild.MemberState.ACTIVE:
				replaced = true
		var has_freighter := false
		for rid in guild.freighters.keys():
			if guild.freighters[rid].get("state", -1) == TrafficGuild.FreighterState.ACTIVE:
				has_freighter = true
		if replaced and has_freighter:
			break
		cluster.tick(period)

func _test_determinism() -> void:
	seed(42)
	var cluster1 = _make_cluster()
	var guild1 = TrafficGuild.new(FAST_CONFIG)
	cluster1.directors.append(guild1)
	_run_scripted_sequence(cluster1, guild1)

	seed(42)
	var cluster2 = _make_cluster()
	var guild2 = TrafficGuild.new(FAST_CONFIG)
	cluster2.directors.append(guild2)
	_run_scripted_sequence(cluster2, guild2)

	_assert(guild1.members == guild2.members, "(f) identical hauler ledgers across two seeded runs")
	_assert(guild1.freighters == guild2.freighters, "(f) identical freighter ledgers across two seeded runs")
	_assert(guild1.arrivals == guild2.arrivals, "(f) identical pending arrivals across two seeded runs")
	_assert(guild1.losses == guild2.losses and guild1.replenishments == guild2.replenishments,
		"(f) identical totals across two seeded runs")

# ---------------------------------------------------------------------------
# (g) Structural gap fix: cluster_manager.gd's generalized _attach_ai routes
# ANY non-pirate record whose behavior carries a "job" to the new civilian
# job tree, while the pirate branch (checked first, still returns early) is
# completely unaffected. Driven directly (no director involved) to isolate
# the _attach_ai change itself.
# ---------------------------------------------------------------------------

func _test_civilian_job_tree_and_pirate_untouched() -> void:
	var cluster := ClusterManager.new()
	main_node.add_child(cluster)
	spawned_clusters.append(cluster)

	var civilian := ClusterEntity.new()
	civilian.id = 9001
	civilian.name = "Civilian Job Runner"
	civilian.hull_script = CargoShuttle
	civilian.kind = ClusterEntity.Kind.TRAFFIC
	civilian.is_static = false
	civilian.pos = Vector2(1000, 1000)
	civilian.transponder_flag = Standing.FLAG_CIVILIAN
	civilian.behavior = {"job": {"steps": [{"verb": "GO_TO", "pos": Vector2(2000, 2000)}], "current": 0}}
	cluster.add_record(civilian)

	var pirate := ClusterEntity.new()
	pirate.id = 9002
	pirate.name = "Guild Pirate"
	pirate.hull_script = CargoShuttle
	pirate.kind = ClusterEntity.Kind.TRAFFIC
	pirate.is_static = false
	pirate.pos = Vector2(3000, 3000)
	pirate.transponder_flag = Standing.FLAG_CIVILIAN
	pirate.behavior = {"pirate": true, "job": {"steps": [{"verb": "GO_TO", "pos": Vector2(4000, 4000)}], "current": 0}}
	cluster.add_record(pirate)

	cluster.tick(0.0)

	var civ_rec = _find_rec(cluster, 9001)
	_assert(civ_rec != null and civ_rec.is_live(), "(g) civilian job record promoted")
	if civ_rec != null and civ_rec.is_live():
		var tree = civ_rec.live_node.get_node_or_null("AITree")
		_assert(tree != null, "(g) civilian job record carries an AI tree")
		_assert(not civ_rec.live_node.assignment.is_empty(), "(g) civilian job record carries the assigned job")
		if tree != null and tree.get_child_count() > 0:
			var names: Array = []
			for c in tree.get_child(0).get_children():
				names.append(c.name)
			_assert(names.has("ThreatResponse") and names.has("JobRunner"), "(g) civilian tree has ThreatResponse+JobRunner (got %s)" % str(names))

	var pirate_rec = _find_rec(cluster, 9002)
	_assert(pirate_rec != null and pirate_rec.is_live(), "(g) pirate-flagged record still promotes")
	if pirate_rec != null and pirate_rec.is_live():
		var ptree = pirate_rec.live_node.get_node_or_null("AITree")
		_assert(ptree != null, "(g) pirate branch still attaches an AI tree")
		_assert(not pirate_rec.live_node.assignment.is_empty(), "(g) pirate branch still assigns its job")
		if ptree != null and ptree.get_child_count() > 0:
			var pnames: Array = []
			for c in ptree.get_child(0).get_children():
				pnames.append(c.name)
			_assert(not pnames.has("ThreatResponse"), "(g) pirate branch is UNCHANGED -- still no ThreatResponse (build_pirate has none) (got %s)" % str(pnames))

# ---------------------------------------------------------------------------

func _finish() -> void:
	for c in spawned_clusters:
		if is_instance_valid(c):
			c.queue_free()
	spawned_clusters.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_traffic_guild <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_traffic_guild <<<")
		get_tree().quit(1)
