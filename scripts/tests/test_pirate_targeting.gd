extends Node

# Compares the three map-derived pirate hunt-targeting strategies against the
# REAL authored home cluster, on the three things a hunt point has to get
# right at once. Replaces the authored-lane premise that M53d deleted (see
# PirateGuild._pick_lane_point) -- haulers are planner-driven now, so there
# are no {"route": [...]} lanes left to sample and every hunt point had
# collapsed onto the wormhole fallback.
#
# The metrics, and why these three:
#
#   SPREAD      distinct coarse grid cells the points land in. A strategy that
#               concentrates is worse than the bug it replaces -- one spot,
#               forever, is exactly what the collapse looked like.
#   CLEARANCE   fraction clearing BOTH keep-aways (stations, charted beacons).
#               A point under a hub's guns or beside an EM-loud beacon is a
#               dead pirate; _away_from_hazards degrades to "least bad" rather
#               than failing, so this can silently be poor.
#   RELEVANCE   fraction sitting within CHORD_R of at least one trade-hub pair
#               chord. A proxy for "would cargo plausibly come past here",
#               computed from the map only. NOTE it is tautological for
#               STATION_CHORD and CROSSROADS, which sample points ON chords by
#               construction -- it is only a real measurement for
#               APPROACH_RING. Kept as a regression floor, not a scoreboard.
#
# NONE OF THESE MEASURE EFFECTIVENESS. They say a hunt point is well
# distributed, survivable and geometrically plausible; they say nothing about
# whether a pirate sitting there actually catches anything. Catch rate,
# time-to-contact and pirate losses need real haulers flying real routes --
# see tactical_analysis/sim_runners/. Treat this file as the cheap geometric
# screen and that sim as the verdict.
#
# There is no single winner by construction: APPROACH_RING should win
# relevance and lose clearance (hubs are where the defences are), CHORD should
# spread widest, CROSSROADS should trade some spread for concentration on
# chokepoints. The assertions are floors every strategy must clear; the
# printed table is the actual deliverable.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_pirate_targeting

const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")

const SAMPLES := 200
const GRID := 60000.0          # coarse cell for the spread metric
const CHORD_R := 30000.0       # "on a plausible trade line" for relevance

# Floors, deliberately loose -- this test exists to compare strategies and to
# catch a collapse, not to freeze tuning. MIN_CELLS is the one that would have
# caught the original bug (it produced exactly 1).
const MIN_CELLS := 5
const MIN_CLEARANCE_FRAC := 0.90
const MIN_RELEVANCE_FRAC := 0.50

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_cluster():
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	var pol = LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)   # promote nothing -- pure records, no physics
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)
	return m

func _wormhole_pos(cluster) -> Vector2:
	for rec in cluster.records:
		if rec.kind == ClusterEntity.Kind.WORMHOLE:
			return rec.pos
	return Vector2.ZERO

func _hub_positions(cluster) -> Array:
	var out: Array = []
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		if typeof(rec.industry) != TYPE_DICTIONARY or rec.industry.is_empty():
			continue
		out.append(rec.pos)
	return out

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _near_any_chord(p: Vector2, hubs: Array) -> bool:
	for i in range(hubs.size()):
		for j in range(i + 1, hubs.size()):
			if _dist_to_segment(p, hubs[i], hubs[j]) <= CHORD_R:
				return true
	return false

func setup(_main) -> void:
	print("Starting pirate hunt-targeting comparison")

	var cluster = _make_cluster()
	var guild = PirateGuild.new()
	var wh: Vector2 = _wormhole_pos(cluster)
	var hubs: Array = _hub_positions(cluster)
	var all_stations: Array = guild._station_positions(cluster)
	var beacons: Array = guild._beacon_positions(cluster)

	_assert(hubs.size() >= 6, "setup: the home cluster carries >= 6 TRADE hubs (got %d)" % hubs.size())
	_assert(all_stations.size() > hubs.size(),
		"setup: trade hubs are a strict SUBSET of station-kind records -- mobile homes excluded (%d stations, %d hubs)" % [all_stations.size(), hubs.size()])

	var strategies := {
		"STATION_CHORD": PirateGuild.HuntStrategy.STATION_CHORD,
		"APPROACH_RING": PirateGuild.HuntStrategy.APPROACH_RING,
		"CROSSROADS": PirateGuild.HuntStrategy.CROSSROADS,
	}

	print("\n  %-15s %8s %10s %10s" % ["strategy", "cells", "clear%", "relevant%"])
	print("  " + "-".repeat(46))

	var results: Dictionary = {}
	for label in strategies:
		PirateGuild.hunt_strategy = strategies[label]
		var cells: Dictionary = {}
		var cleared: int = 0
		var relevant: int = 0
		for _i in range(SAMPLES):
			var picked: Dictionary = guild._pick_hunt_point(cluster, wh, all_stations, beacons)
			var p: Vector2 = picked.get("pos", Vector2.ZERO)
			cells[Vector2i(int(floor(p.x / GRID)), int(floor(p.y / GRID)))] = true
			if guild._hazard_clearance(p, all_stations, beacons) >= 0.0:
				cleared += 1
			if _near_any_chord(p, hubs):
				relevant += 1
		var clear_frac: float = float(cleared) / float(SAMPLES)
		var rel_frac: float = float(relevant) / float(SAMPLES)
		results[label] = {"cells": cells.size(), "clear": clear_frac, "relevant": rel_frac}
		print("  %-15s %8d %9.0f%% %9.0f%%" % [label, cells.size(), clear_frac * 100.0, rel_frac * 100.0])

	print("")
	for label in results:
		var r: Dictionary = results[label]
		_assert(r["cells"] >= MIN_CELLS,
			"%s: spreads over >= %d distinct cells (got %d) -- no collapse onto one spot" % [label, MIN_CELLS, r["cells"]])
		_assert(r["clear"] >= MIN_CLEARANCE_FRAC,
			"%s: >= %.0f%% of points clear both keep-aways (got %.0f%%)" % [label, MIN_CLEARANCE_FRAC * 100.0, r["clear"] * 100.0])
		_assert(r["relevant"] >= MIN_RELEVANCE_FRAC,
			"%s: >= %.0f%% of points sit on a plausible trade line (got %.0f%%)" % [label, MIN_RELEVANCE_FRAC * 100.0, r["relevant"] * 100.0])

	# The regression that started this: whatever strategy ships, it must not
	# degrade to the wormhole fallback. That fallback only fires when the
	# cluster has < 2 trade hubs, which the real cluster never does -- but the
	# authored-lane path had an equivalent empty-set collapse that shipped
	# unnoticed, so pin it.
	PirateGuild.hunt_strategy = PirateGuild.HuntStrategy.CROSSROADS
	var at_wormhole: int = 0
	for _i in range(SAMPLES):
		var p: Vector2 = guild._pick_hunt_point(cluster, wh, all_stations, beacons).get("pos", Vector2.ZERO)
		if p.distance_to(wh) < 1.0:
			at_wormhole += 1
	_assert(at_wormhole == 0,
		"the shipping default never degrades to the wormhole fallback (got %d/%d)" % [at_wormhole, SAMPLES])

	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_pirate_targeting <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_pirate_targeting <<<")
		get_tree().quit(1)
