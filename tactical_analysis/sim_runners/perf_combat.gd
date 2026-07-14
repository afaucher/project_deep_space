extends Node

# M45 follow-up -- combat performance investigation ("just adding 3 frigates
# slows the game down incredibly; 10 extra ships (missiles) in less than a
# second, and it adds up fast").
#
# test_perf_baseline.gd (scripts/tests/, part of the regular gate) measures a
# STEADY-STATE scene (traffic/cargo, ~24 ships, roughly constant membership)
# and reports one averaged table. Combat is the opposite shape: "ships" group
# membership SPIKES the moment missile volleys launch (Missile extends Ship --
# see scripts/ships/missile.gd -- so every in-flight missile is a full "ships"
# group member paying sensor sweep, contact decay/correlate, datalink relay,
# heat/EM, weapons/PD, eng-log every physics frame, same as a frigate). An
# averaged window would smear that spike away, so this is a separate,
# investigative sim (not a regression guard -- no budget assert; lives here
# with the other tactical_analysis tooling, not scripts/tests/, so it doesn't
# add ~25s to every future build.ps1 gate). It:
#   1. Spawns 3 frigates per side (matching the report), full AI
#      (AITreeFactory.build_default()), positioned at broadside range so they
#      engage immediately -- the same setup test_ai_duel.gd uses to force a
#      decisive, volley-heavy exchange, just at 3x scale and instrumented
#      instead of scored.
#   2. Samples Performance.TIME_PHYSICS_PROCESS AND the live "ships" group
#      census (split into real ships vs Missile instances) every physics
#      frame for a fixed real-time window (no Engine.time_scale -- measures
#      wall-clock-realistic per-frame cost at the same pacing a player
#      experiences it, not a sped-up trial resolution).
#   3. Buckets those samples per second and prints/writes a timeline CSV, so
#      the missile-count spike and the phys-time spike are visible side by
#      side, frame-accurate -- unlike test_perf_baseline's single average.
#   4. Reports the SAME PerfProbe attribution table shape as test_perf_baseline
#      (which tag is spending the time) for this combat window, directly
#      comparable per-tag against the traffic baseline's numbers.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim perf_combat

const Frigate = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")

const SHIPS_PER_SIDE := 3
const START_RANGE := 8000.0   # test_ai_duel's optimal broadside range -- forces immediate engagement
const MEASURE_SECONDS := 25.0
const MEASURE_FRAMES := int(MEASURE_SECONDS * 60.0)

var main_node: Node = null
var frame: int = 0
var finished: bool = false

var phys_samples_us: Array = []     # one entry per physics frame
var ships_samples: Array = []       # live "ships" group census per physics frame
var missile_samples: Array = []     # live Missile-instance count per physics frame
# Engine-side load monitors, sampled alongside the script-side probes so the
# UNattributed share of the tick (total minus PerfProbe tags) can be split
# between "our script" and "Godot's own physics" -- collision-pair count is
# the direct driver of broadphase/narrowphase/solver cost.
var active_obj_samples: Array = []  # Performance.PHYSICS_2D_ACTIVE_OBJECTS
var pair_samples: Array = []        # Performance.PHYSICS_2D_COLLISION_PAIRS
var island_samples: Array = []      # Performance.PHYSICS_2D_ISLAND_COUNT
# Wall-clock time between consecutive physics frames, measured directly with
# Time.get_ticks_usec. TIME_PHYSICS_PROCESS is known to HOLD a stale reading
# across many frames (see test_perf_baseline's WARMUP_FRAMES note), which can
# inflate averages/percentiles after a stall -- under --fixed-fps the loop
# never sleeps, so wall delta per frame is the honest total cost (physics +
# process + engine overhead) to cross-check the monitor against.
var wall_samples_us: Array = []
var _last_frame_us: int = -1
# Hulks still in the scene: dead ships (fuel-out missiles hulk() but are never
# freed; killed frigates persist as wreckage) keep paying the full per-ship
# tick -- this census shows how much of the "ships" group is dead weight.
var dead_samples: Array = []

func setup(main) -> void:
	main_node = main
	print("=== M45 follow-up: combat perf (%d v %d frigates, %.0fs measured window) ===" % [SHIPS_PER_SIDE, SHIPS_PER_SIDE, MEASURE_SECONDS])

	for i in range(SHIPS_PER_SIDE):
		var a = Frigate.new()
		a.name = "TeamA_%d" % i
		a.owner_id = 100 + i
		a.iff_tags = ["TEAM_A"]
		a.position = Vector2(0, i * 300.0)
		a.rotation = 0.0
		main_node.add_child(a)
		a.add_child(AITreeFactory.build_default())

		var b = Frigate.new()
		b.name = "TeamB_%d" % i
		b.owner_id = 200 + i
		b.iff_tags = ["TEAM_B"]
		b.position = Vector2(START_RANGE, i * 300.0)
		b.rotation = PI
		main_node.add_child(b)
		b.add_child(AITreeFactory.build_default())

	var ship_count := get_tree().get_nodes_in_group("ships").size()
	print("  scene census: %d members of the 'ships' group at start (%d frigates)" % [ship_count, SHIPS_PER_SIDE * 2])

	# M45_PROBE_OFF=1: leave PerfProbe disabled and measure the raw tick only.
	# The attribution table costs real time to collect (~57 ships x ~11
	# begin/end pairs each = >1000 ticks_usec+dict ops per frame, each landing
	# OUTSIDE its own tag) -- comparing avg TIME_PHYSICS_PROCESS between a
	# probed and an unprobed run is how that observer overhead is quantified.
	if OS.get_environment("M45_PROBE_OFF") == "1":
		print("  [probe-off] PerfProbe stays disabled -- raw tick measurement only")
	else:
		PerfProbe.enabled = true

func _physics_process(_delta: float) -> void:
	if finished:
		return
	frame += 1

	var phys_us: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0
	var all_ships: Array = get_tree().get_nodes_in_group("ships")
	var missile_count := 0
	var dead_count := 0
	for s in all_ships:
		if s is Missile:
			missile_count += 1
		if s.is_dead:
			dead_count += 1
	dead_samples.append(dead_count)

	phys_samples_us.append(phys_us)
	ships_samples.append(all_ships.size())
	missile_samples.append(missile_count)
	active_obj_samples.append(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
	pair_samples.append(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	island_samples.append(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))
	var now_us := Time.get_ticks_usec()
	if _last_frame_us >= 0:
		wall_samples_us.append(now_us - _last_frame_us)
	_last_frame_us = now_us

	if frame >= MEASURE_FRAMES:
		_finish()

func _finish() -> void:
	finished = true

	var n := phys_samples_us.size()

	# --- Per-second timeline: bucket the per-frame samples, 60 to a bucket ---
	var timeline: Array = []
	var i := 0
	while i < n:
		var end_i: int = min(i + 60, n)
		var bucket_phys: Array = phys_samples_us.slice(i, end_i)
		var bucket_ships: Array = ships_samples.slice(i, end_i)
		var bucket_missiles: Array = missile_samples.slice(i, end_i)
		var sum_phys := 0.0
		var max_phys := 0.0
		for v in bucket_phys:
			sum_phys += v
			max_phys = max(max_phys, v)
		var max_ships := 0
		for v in bucket_ships:
			max_ships = max(max_ships, v)
		var max_missiles := 0
		for v in bucket_missiles:
			max_missiles = max(max_missiles, v)
		timeline.append({
			"t": i / 60,
			"avg_phys_ms": (sum_phys / bucket_phys.size()) / 1000.0,
			"max_phys_ms": max_phys / 1000.0,
			"max_ships": max_ships,
			"max_missiles": max_missiles,
		})
		i = end_i

	print("\n=== Combat timeline (per second) ===")
	print("%-6s %14s %14s %10s %10s" % ["t(s)", "avg phys ms", "max phys ms", "ships", "missiles"])
	for row in timeline:
		print("%-6d %14.3f %14.3f %10d %10d" % [row["t"], row["avg_phys_ms"], row["max_phys_ms"], row["max_ships"], row["max_missiles"]])

	var timeline_path := "res://tactical_analysis/data/perf_combat_timeline.csv"
	var tf := FileAccess.open(timeline_path, FileAccess.WRITE)
	if tf != null:
		tf.store_line("t_s,avg_phys_ms,max_phys_ms,max_ships,max_missiles")
		for row in timeline:
			tf.store_line("%d,%.4f,%.4f,%d,%d" % [row["t"], row["avg_phys_ms"], row["max_phys_ms"], row["max_ships"], row["max_missiles"]])
		tf.flush()
		tf.close()
		print("\n  wrote ", timeline_path)

	# --- Whole-window summary (same shape as test_perf_baseline, for direct comparison) ---
	var total := 0.0
	for v in phys_samples_us:
		total += v
	var avg_us: float = total / n if n > 0 else 0.0
	var sorted_samples: Array = phys_samples_us.duplicate()
	sorted_samples.sort()
	var p95_idx: int = clampi(int(ceil(n * 0.95)) - 1, 0, n - 1)
	var p95_us: float = sorted_samples[p95_idx] if n > 0 else 0.0
	var max_us: float = sorted_samples[n - 1] if n > 0 else 0.0
	var peak_missiles := 0
	for v in missile_samples:
		peak_missiles = max(peak_missiles, v)
	var peak_ships := 0
	for v in ships_samples:
		peak_ships = max(peak_ships, v)

	print("\n=== Performance.TIME_PHYSICS_PROCESS over %d frames (whole window, includes ramp-up) ===" % n)
	print("  avg=%.3fms  p95=%.3fms  max=%.3fms  peak_ships=%d  peak_missiles=%d" % [
		avg_us / 1000.0, p95_us / 1000.0, max_us / 1000.0, peak_ships, peak_missiles])

	# --- Engine-side physics load (see the sample-time comment above) ---
	var sums := [0.0, 0.0, 0.0]
	var peaks := [0.0, 0.0, 0.0]
	var mon_arrays: Array = [active_obj_samples, pair_samples, island_samples]
	for m in range(3):
		for v in mon_arrays[m]:
			sums[m] += v
			peaks[m] = max(peaks[m], v)
	print("  engine load: active_objects avg=%.1f peak=%d  |  collision_pairs avg=%.1f peak=%d  |  islands avg=%.1f peak=%d" % [
		sums[0] / n, int(peaks[0]), sums[1] / n, int(peaks[1]), sums[2] / n, int(peaks[2])])

	# --- Wall-clock cross-check (see wall_samples_us comment above) ---
	var wn := wall_samples_us.size()
	if wn > 0:
		var wtotal := 0.0
		for v in wall_samples_us:
			wtotal += v
		var wsorted: Array = wall_samples_us.duplicate()
		wsorted.sort()
		var wp95: float = wsorted[clampi(int(ceil(wn * 0.95)) - 1, 0, wn - 1)]
		print("  wall-clock/frame: avg=%.3fms  p95=%.3fms  max=%.3fms  (%d frames)" % [
			(wtotal / wn) / 1000.0, wp95 / 1000.0, float(wsorted[wn - 1]) / 1000.0, wn])

	var dead_sum := 0.0
	var dead_peak := 0
	for v in dead_samples:
		dead_sum += v
		dead_peak = max(dead_peak, v)
	print("  dead-ship census: avg=%.1f peak=%d (of avg %.1f group members)" % [
		dead_sum / n, dead_peak, _avg(ships_samples)])

	# --- PerfProbe attribution table (same format as test_perf_baseline) ---
	var rep: Dictionary = PerfProbe.report(n)
	var tags: Array = rep.keys()
	tags.sort_custom(func(a, b): return rep[a]["avg_us_per_frame"] > rep[b]["avg_us_per_frame"])

	const TICK_BUDGET_US := 16666.67
	print("\n=== PerfProbe attribution (ranked by avg us/frame, whole window) ===")
	print("%-24s %10s %14s %14s %10s" % ["tag", "calls", "avg us/frame", "max frame us", "%% of tick"])
	for tag in tags:
		var d = rep[tag]
		print("%-24s %10d %14.2f %14d %9.2f%%" % [
			tag, d["calls"], d["avg_us_per_frame"], d["max_frame_us"],
			(d["avg_us_per_frame"] / TICK_BUDGET_US) * 100.0])

	var csv_path := "res://tactical_analysis/data/perf_combat.csv"
	PerfProbe.report_csv(csv_path, n)
	print("\n  wrote ", csv_path)

	PerfProbe.enabled = false

	if peak_missiles == 0:
		printerr("  WARNING: no missiles were ever in flight -- scenario did not exercise combat")

	print("\nCombat perf sim complete.")
	get_tree().quit(0)

func _avg(arr: Array) -> float:
	var t := 0.0
	for v in arr:
		t += v
	return t / max(1, arr.size())
