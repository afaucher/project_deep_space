extends Node

# M51 -- the pirate guild director (implementation_plans/m51_pirate_guild_design.md
# "Tests"). Manual cluster.tick() drive (no physics frames needed -- the guild
# is pure ledger + policy tick, deterministic under the FAST test config), a
# synthetic two-record cluster (a wormhole + one cargo lane -- everything the
# guild is honestly allowed to read: its own members' nodes, and the records
# array's public geometry). Covers the five spec'd scenarios:
#   (a) bootstrap floor            (b) replacement-on-kill, no resurrection
#   (c) cash-out                   (d) streaks move the cap both ways, bounded
#   (e) determinism under a seed
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_pirate_guild

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const PirateOreShuttle = preload("res://scripts/ships/pirate_ore_shuttle.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")

# Fast config per CLAUDE.md/the design doc -- config is data, so tuning it for
# test speed is legitimate, not a test backdoor.
const FAST_CONFIG := {
	"policy_period": 0.5,
	"presumed_lost_delay": 2.0,
	"arrival_window": [4.0, 8.0],
	"base_cap": 1,
	"max_cap": 3,
	"takes_per_cap_raise": 2,
	"losses_per_cap_cut": 2,
	"cashin_radius": 8000.0,
	"hull_mix": [PirateOreShuttle, ArmedPinnace],
	"name_pool": ["Alpha Trader", "Bravo Light", "Charlie Return", "Delta Odds", "Echo Wind", "Foxtrot Change"],
}

const WORMHOLE_POS := Vector2.ZERO
const LANE_ROUTE := [Vector2(10000, 0), Vector2(50000, 20000)]

var main_node: Node = null
var failures: Array = []
var spawned_clusters: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# ---------------------------------------------------------------------------
# Cluster fixture -- a wormhole + one cargo lane (the only public geometry
# the honesty rule lets the guild read). No player/viewpoint; default policy
# (full_sim, ClusterManager._init()) keeps everything the guild spawns
# immediately promotable so tests can touch the live node right away.
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

	var lane := ClusterEntity.new()
	lane.id = 700
	lane.name = "Test Lane"
	lane.hull_script = CargoShuttle
	lane.kind = ClusterEntity.Kind.TRAFFIC
	lane.is_static = false
	lane.pos = LANE_ROUTE[0]
	lane.behavior = {"route": LANE_ROUTE, "cargo": true, "loop": true}
	cluster.add_record(lane)

	spawned_clusters.append(cluster)
	return cluster

func _find_rec(cluster, record_id: int):
	for r in cluster.records:
		if r.id == record_id:
			return r
	return null

# Simulates a member vanishing from the cluster's own tracking (an EXIT_AT
# despawn, or drift out of range) WITHOUT marking it dead -- removes its
# ClusterEntity from cluster.records (so a later reconcile can never
# resurrect it) and frees whatever live node it had. This is the "vanished"
# half of the check-in rule; `.hulk()` (below) is the "observed dead" half.
func _vanish_record(cluster, record_id: int) -> void:
	for i in range(cluster.records.size()):
		if cluster.records[i].id == record_id:
			var rec = cluster.records[i]
			cluster.records.remove_at(i)
			if rec.live_node != null and is_instance_valid(rec.live_node):
				rec.live_node.queue_free()
			return

# Duck-typed "is this a guild-spawned pirate" check (avoids an `is` reference
# to a project class_name -- CLAUDE.md's headless class-cache caveat): every
# guild-spawned record carries a unique "PIRATE_GUILD_<id>" iff tag.
func _is_guild_pirate_node(node) -> bool:
	if node == null or not (node is RigidBody2D) or not node.has_method("get_ship_mass"):
		return false
	for tag in node.iff_tags:
		if String(tag).begins_with("PIRATE_GUILD_"):
			return true
	return false

func _count_alive_pirate_nodes(cluster) -> int:
	var n := 0
	for child in cluster.get_children():
		if _is_guild_pirate_node(child) and not child.is_dead:
			n += 1
	return n

# Ticks (each call = exactly one policy pass, since FAST_CONFIG.policy_period
# is passed as dt) until some member is ACTIVE and its record is live, or
# max_ticks is exhausted. Returns the record id, or -1.
func _wait_for_any_active(cluster, guild, max_ticks: int, period: float) -> int:
	for i in range(max_ticks):
		for rid in guild.members.keys():
			var m: Dictionary = guild.members[rid]
			if m.get("state", -1) == PirateGuild.MemberState.ACTIVE:
				var rec = _find_rec(cluster, rid)
				if rec != null and rec.is_live():
					return rid
		cluster.tick(period)
	return -1

func _advance_until_state(cluster, guild, record_id: int, target_states: Array, max_ticks: int, period: float) -> bool:
	for i in range(max_ticks):
		if guild.members.has(record_id) and target_states.has(guild.members[record_id].get("state", -1)):
			return true
		cluster.tick(period)
	return guild.members.has(record_id) and target_states.has(guild.members[record_id].get("state", -1))

func _roster_count(guild) -> int:
	var n: int = guild.arrivals.size()
	for rid in guild.members.keys():
		var st = guild.members[rid].get("state", -1)
		if st == PirateGuild.MemberState.ACTIVE or st == PirateGuild.MemberState.OVERDUE:
			n += 1
	return n

# ---------------------------------------------------------------------------

func setup(main) -> void:
	# Narrate guild milestones in this test's log (also covers the _event
	# logging paths -- arrival scheduled/spawned, OVERDUE, LOST, CASHED_OUT,
	# cap moves -- so a logging crash would fail the suite, not a playtest).
	DebugSettings.set_choice("pirate_guild_log", DebugSettings.PirateGuildLog.ON)
	main_node = main
	print("Starting Pirate Guild (M51) Tests")

	print("\n--- (a) Bootstrap floor ---")
	_test_bootstrap_floor()

	print("\n--- (b) Replacement on kill (no resurrection) ---")
	_test_replacement_on_kill()

	print("\n--- (c) Cash-out ---")
	await _test_cash_out()

	print("\n--- (d) Streaks move the cap both ways, bounded ---")
	_test_streaks_bounded()

	print("\n--- (e) Determinism ---")
	_test_determinism()

	_finish()

# ---------------------------------------------------------------------------
# (a) Bootstrap floor: fresh guild, empty roster -> one arrival scheduled ->
# after its eta, exactly one ACTIVE pirate record exists at the wormhole,
# carrying build_pirate + an assigned hunt job.
# ---------------------------------------------------------------------------

func _test_bootstrap_floor() -> void:
	var cluster = _make_cluster()
	var guild = PirateGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]

	cluster.tick(period) # first policy pass: empty roster -> floor schedules one arrival
	_assert(guild.arrivals.size() == 1, "(a) one arrival scheduled from an empty roster")
	_assert(guild.members.is_empty(), "(a) no member ACTIVE yet (still pending eta)")

	var rid: int = _wait_for_any_active(cluster, guild, 60, period)
	_assert(rid != -1, "(a) the scheduled arrival eventually went ACTIVE")
	_assert(guild.arrivals.is_empty(), "(a) the arrivals queue drained once it spawned")

	var rec = _find_rec(cluster, rid)
	_assert(rec != null and rec.is_live(), "(a) the arrived pirate's record is live")
	if rec != null and rec.is_live():
		var node = rec.live_node
		_assert(node.get_node_or_null("AITree") != null, "(a) promoted pirate carries an AI tree")
		_assert(not node.assignment.is_empty(), "(a) promoted pirate carries an assigned job")
		var steps: Array = node.assignment.get("steps", [])
		var verbs: Array = []
		for st in steps:
			verbs.append(st.get("verb", ""))
		_assert(verbs.has("SELECT_VICTIM"), "(a) the assigned job is a hunt (has SELECT_VICTIM)")
		_assert(node.position.distance_to(WORMHOLE_POS) < 2000.0, "(a) pirate spawned near the wormhole")
	_assert(_count_alive_pirate_nodes(cluster) == 1, "(a) exactly one live pirate hull exists")

# ---------------------------------------------------------------------------
# (b) Replacement on kill: hulk the active pirate -> OVERDUE -> LOST after
# the delay -> its record is GONE (no-resurrection: keep ticking, alive
# pirate-hull count must stay 0 until the replacement) -> a replacement
# arrival lands under a DIFFERENT cover name; losses == 1.
# ---------------------------------------------------------------------------

func _test_replacement_on_kill() -> void:
	var cluster = _make_cluster()
	var guild = PirateGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2

	var first_id: int = _wait_for_any_active(cluster, guild, 60, period)
	_assert(first_id != -1, "(b) an initial pirate went ACTIVE")
	if first_id == -1:
		return
	var first_cover: String = guild.members[first_id]["cover_name"]

	_find_rec(cluster, first_id).live_node.hulk()

	cluster.tick(period) # check-in observes is_dead -> OVERDUE
	_assert(guild.members[first_id]["state"] == PirateGuild.MemberState.OVERDUE, "(b) hulked pirate goes OVERDUE")

	var resolved := false
	for i in range(delay_ticks):
		cluster.tick(period)
		_assert(_count_alive_pirate_nodes(cluster) == 0, "(b) no alive pirate hull mid-resolution (no resurrection, tick %d)" % i)
		if guild.members[first_id]["state"] == PirateGuild.MemberState.LOST:
			resolved = true
			break
	_assert(resolved, "(b) hulked pirate resolves LOST after the delay")
	_assert(_find_rec(cluster, first_id) == null, "(b) LOST pirate's record is erased from cluster.records")
	_assert(guild.losses == 1, "(b) losses incremented")
	_assert(guild.loss_streak == 1, "(b) loss_streak incremented")

	var replacement_id := -1
	for i in range(60):
		cluster.tick(period)
		_assert(_count_alive_pirate_nodes(cluster) <= 1, "(b) still no resurrection of the lost pirate while waiting for the replacement")
		for rid in guild.members.keys():
			if rid != first_id and guild.members[rid].get("state", -1) == PirateGuild.MemberState.ACTIVE:
				replacement_id = rid
				break
		if replacement_id != -1:
			break
	_assert(replacement_id != -1, "(b) a replacement arrival became ACTIVE within the window")
	if replacement_id != -1:
		_assert(guild.members[replacement_id]["cover_name"] != first_cover, "(b) replacement uses a different cover name")

# ---------------------------------------------------------------------------
# (c) Cash-out: walk an ACTIVE member's node to the wormhole, set
# loot_takes = 1, let a check-in capture it (a check-in must land between the
# move and the disappearance, or last_seen_pos goes stale), then despawn it
# THE WAY PRODUCTION DOES -- queue_free on the live node (EXIT_AT's own
# mechanism), record left in place. ClusterManager._reconcile()'s external-
# despawn retirement must then remove the record itself (without it, the
# very next pass would resurrect a fresh pirate from the stale record and
# the member would never resolve) -> OVERDUE -> CASHED_OUT after the delay,
# takes_total == 1, take_streak bumped, NOT counted as a loss. Scenarios
# (d)/(e) keep the _vanish_record splice (streak/determinism mechanics don't
# need the physics frame the deferred free requires).
# ---------------------------------------------------------------------------

func _test_cash_out() -> void:
	var cluster = _make_cluster()
	var guild = PirateGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2

	var rid: int = _wait_for_any_active(cluster, guild, 60, period)
	_assert(rid != -1, "(c) an initial pirate went ACTIVE")
	if rid == -1:
		return
	var rec = _find_rec(cluster, rid)
	var node = rec.live_node
	node.loot_takes = 1
	node.position = WORMHOLE_POS + Vector2(1000, 0) # well inside cashin_radius (8000)

	cluster.tick(period) # a check-in lands here, snapshotting last_seen_pos/loot_takes while still live
	_assert(guild.members[rid]["last_loot_takes"] == 1, "(c) check-in captured loot_takes")
	_assert(guild.members[rid]["last_seen_pos"].distance_to(WORMHOLE_POS) <= FAST_CONFIG["cashin_radius"], "(c) check-in captured last_seen_pos near the wormhole")
	_assert(guild.members[rid]["state"] == PirateGuild.MemberState.ACTIVE, "(c) still ACTIVE right after the check-in")

	# The REAL despawn path: queue_free (what EXIT_AT does), record untouched.
	# The free is deferred, so one engine frame must elapse before the node
	# reads as invalid and _reconcile()'s retirement can see it.
	node.queue_free()
	await main_node.get_tree().physics_frame
	await main_node.get_tree().physics_frame
	cluster.tick(period) # reconcile retires the record; check-in: record gone -> OVERDUE
	_assert(_find_rec(cluster, rid) == null, "(c) reconcile retired the externally-despawned record (no resurrection source left)")
	_assert(guild.members[rid]["state"] == PirateGuild.MemberState.OVERDUE, "(c) vanished pirate goes OVERDUE")

	var resolved := false
	for i in range(delay_ticks):
		cluster.tick(period)
		if guild.members[rid]["state"] == PirateGuild.MemberState.CASHED_OUT:
			resolved = true
			break
	_assert(resolved, "(c) resolves CASHED_OUT (vanished near the wormhole)")
	_assert(guild.takes_total == 1, "(c) takes_total credited")
	_assert(guild.take_streak == 1, "(c) take_streak bumped")
	_assert(guild.losses == 0, "(c) NOT counted as a loss")

# ---------------------------------------------------------------------------
# (d) Streaks move the cap both ways, bounded: scripted cash-outs climb the
# cap to max_cap and never past; scripted losses fall it to base_cap and
# never below. The floor keeps scheduling toward cap throughout (roster
# pressure never exceeds max_cap).
# ---------------------------------------------------------------------------

func _test_streaks_bounded() -> void:
	var cluster = _make_cluster()
	var guild = PirateGuild.new(FAST_CONFIG)
	cluster.directors.append(guild)
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2
	var base_cap: int = FAST_CONFIG["base_cap"]
	var max_cap: int = FAST_CONFIG["max_cap"]

	# --- Climb: repeated cash-outs raise the cap, clamped at max_cap. ---
	for s in range(6):
		var rid: int = _wait_for_any_active(cluster, guild, 60, period)
		_assert(rid != -1, "(d) an ACTIVE member exists to cash out (#%d)" % s)
		if rid == -1:
			break
		var node = _find_rec(cluster, rid).live_node
		node.loot_takes = 1
		node.position = WORMHOLE_POS
		cluster.tick(period)
		_vanish_record(cluster, rid)
		var resolved: bool = _advance_until_state(cluster, guild, rid, [PirateGuild.MemberState.CASHED_OUT], delay_ticks + 2, period)
		_assert(resolved, "(d) success #%d resolved CASHED_OUT" % s)
		_assert(guild.cap >= base_cap and guild.cap <= max_cap, "(d) cap in bounds after success #%d (cap=%d)" % [s, guild.cap])
		_assert(_roster_count(guild) <= max_cap, "(d) roster pressure never exceeds max_cap after success #%d (got %d)" % [s, _roster_count(guild)])
	_assert(guild.cap == max_cap, "(d) enough successes climb cap to max_cap (got %d)" % guild.cap)

	# --- Fall: repeated losses lower the cap, clamped at base_cap. ---
	for s in range(8):
		var rid: int = _wait_for_any_active(cluster, guild, 60, period)
		_assert(rid != -1, "(d) an ACTIVE member exists to lose (#%d)" % s)
		if rid == -1:
			break
		_find_rec(cluster, rid).live_node.hulk()
		var resolved: bool = _advance_until_state(cluster, guild, rid, [PirateGuild.MemberState.LOST], delay_ticks + 2, period)
		_assert(resolved, "(d) loss #%d resolved LOST" % s)
		_assert(guild.cap >= base_cap and guild.cap <= max_cap, "(d) cap in bounds after loss #%d (cap=%d)" % [s, guild.cap])
		_assert(_roster_count(guild) <= max_cap, "(d) roster pressure never exceeds max_cap after loss #%d (got %d)" % [s, _roster_count(guild)])
	_assert(guild.cap == base_cap, "(d) enough losses fall cap back to base_cap (got %d)" % guild.cap)

# ---------------------------------------------------------------------------
# (e) Determinism: two fresh guilds, same config, same seed, same scripted
# event sequence -> identical arrival etas and cover names (compare the
# whole ledger -- members + any still-pending arrivals -- for deep equality).
# ---------------------------------------------------------------------------

func _run_scripted_sequence(cluster, guild) -> void:
	var period: float = FAST_CONFIG["policy_period"]
	var delay_ticks: int = ceili(FAST_CONFIG["presumed_lost_delay"] / period) + 2

	var id1: int = _wait_for_any_active(cluster, guild, 60, period)
	var node1 = _find_rec(cluster, id1).live_node
	node1.loot_takes = 1
	node1.position = WORMHOLE_POS
	cluster.tick(period)
	_vanish_record(cluster, id1)
	_advance_until_state(cluster, guild, id1, [PirateGuild.MemberState.CASHED_OUT], delay_ticks + 2, period)

	var id2: int = _wait_for_any_active(cluster, guild, 60, period)
	_find_rec(cluster, id2).live_node.hulk()
	_advance_until_state(cluster, guild, id2, [PirateGuild.MemberState.LOST], delay_ticks + 2, period)

	var id3: int = _wait_for_any_active(cluster, guild, 60, period)
	var node3 = _find_rec(cluster, id3).live_node
	node3.loot_takes = 2
	node3.position = WORMHOLE_POS
	cluster.tick(period)
	_vanish_record(cluster, id3)
	_advance_until_state(cluster, guild, id3, [PirateGuild.MemberState.CASHED_OUT], delay_ticks + 2, period)

func _test_determinism() -> void:
	seed(42)
	var cluster1 = _make_cluster()
	var guild1 = PirateGuild.new(FAST_CONFIG)
	cluster1.directors.append(guild1)
	_run_scripted_sequence(cluster1, guild1)

	seed(42)
	var cluster2 = _make_cluster()
	var guild2 = PirateGuild.new(FAST_CONFIG)
	cluster2.directors.append(guild2)
	_run_scripted_sequence(cluster2, guild2)

	_assert(guild1.members == guild2.members, "(e) identical ledgers (etas/names/history) across two seeded runs")
	_assert(guild1.arrivals == guild2.arrivals, "(e) identical pending arrivals across two seeded runs")
	_assert(guild1.cap == guild2.cap and guild1.takes_total == guild2.takes_total and guild1.losses == guild2.losses,
		"(e) identical totals/cap across two seeded runs")

# ---------------------------------------------------------------------------

func _finish() -> void:
	for c in spawned_clusters:
		if is_instance_valid(c):
			c.queue_free()
	spawned_clusters.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_pirate_guild <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_pirate_guild <<<")
		get_tree().quit(1)
