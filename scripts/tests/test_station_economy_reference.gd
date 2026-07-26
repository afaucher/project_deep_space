extends Node

# M53c Phase A acceptance -- the design doc's "Worked reference case" table
# (design_ideas/station_economy.md) as an ORACLE, not an input: it is the
# EXPECTED STEADY STATE that falls out of home_cluster.gd's authored
# converters/sinks/sources, not a set of authored constants in its own right
# (implementation_plans/m53c_demand_routing.md "Phase A" test list, first
# bullet). Builds the REAL home cluster (HomeCluster.build() + ClusterLoader,
# same path _bootstrap_campaign uses) and runs StationEconomy over it for a
# few simulated hours, then checks each station's OBSERVED net rate per
# commodity against the table, with a tolerance -- not exact floats, since
# this is a full authored fixture, not a hand-picked unit case. Also checks
# the cluster-wide net (sum across all 8 stations) settles to ~0 per
# commodity, the table's own "net" row. Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_station_economy_reference

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

var main_node: Node = null
var failures: Array = []

# Loose relative to the rates involved (smallest authored rate is 0.10 lots/hr
# -- Corvus Yards' GOODS sink) but tight enough to catch a wiring mistake.
# Bins are auto-sized with ~24h of buffer either side of a mid-capacity
# starting stock, so over SIM_HOURS none of these should starve/block at all;
# a tolerance failure means the model, not the buffer, is wrong.
const TOLERANCE := 0.02
# 1.0h, down from 4.0. Commodity.BUFFER_HOURS shrank bins from ~24h of
# throughput to 3-6h, deliberately (see that table -- the economy was on a clock
# 30-60x slower than transport). That invalidates this test's original premise,
# which was "a 4h run cannot hit a clamp given ~24h buffers". The tightest bin
# now is Coldreach's VOLATILES: 3.2/hr into a 9.6-lot capacity starting at 4.8,
# so it BLOCKS after 1.5h and its observed rate would read 1.2/hr instead of the
# authored 3.2.
#
# 1.0 leaves 1.5x margin on that constraint and every rate reads exact. NOTE: an
# 0.5 window was tried first and produced net 0.000 for EVERY station-commodity,
# with converters never leaving state=-1 (never processed at all). The bins were
# verified correct at that point via economy_soak, ClusterManager.tick forwards
# dt unclamped, and StationEconomy's own period is 10s -- so 1800s should be 180
# passes and it is NOT understood why it wasn't. Recorded rather than explained.
# It fails LOUDLY (all zeros, not a plausible-but-wrong number), so it is not a
# silent trap, but anyone shortening this window further should expect to hit it
# and should chase the cause rather than assume a smaller number is safe.
#
# If a rate ever needs a longer window than this to measure, shrink the window --
# do not grow the buffers back.
const SIM_HOURS := 1.0

# station name -> {commodity -> expected net lots/hour}, transcribed from the
# design doc's reference table. Note the "-- " ORE cell for Drift Market is
# expressed as 0.0 (no mechanism at all, not a tiny authored rate); same for
# every RARE cell outside Meridian's two claims and Ironhold's export gate.
#
# M53d rebalance (implementation_plans/m53d_meridian_sovereignty.md):
#  - Ironhold exports REFINED (1.60) instead of raw ORE, so its ORE sink
#    collapses 5.6 -> 0.8 and its REFINED sink becomes 2.10 (0.50 population
#    upkeep + 1.60 export, merged because the model allows one sink per
#    commodity per station).
#  - Refinery Prime scales to the ore that frees up: 3.3 -> 6.6 in, 2.2 -> 4.4
#    out, same 2:3 ratio.
#  - Margins added to the two "faucet" commodities (Coldreach VOLATILES
#    2.60 -> 3.20, Ironhold GOODS import 1.50 -> 1.85).
#  - RARE: a pure export, sourced only at the two Meridian claims.
const EXPECTED := {
	"Ironhold": {Commodity.ORE: -0.8, Commodity.VOLATILES: -0.60, Commodity.REFINED: -2.10, Commodity.GOODS: 1.85, Commodity.RARE: -0.65},
	"Drift Market": {Commodity.ORE: 0.0, Commodity.VOLATILES: -0.50, Commodity.REFINED: -0.50, Commodity.GOODS: -0.30, Commodity.RARE: 0.0},
	"Refinery Prime": {Commodity.ORE: -6.6, Commodity.VOLATILES: -0.45, Commodity.REFINED: 4.40, Commodity.GOODS: -0.40, Commodity.RARE: 0.0},
	"Coldreach": {Commodity.ORE: 0.6, Commodity.VOLATILES: 3.20, Commodity.REFINED: -0.25, Commodity.GOODS: -0.20, Commodity.RARE: 0.0},
	"Slag Bay": {Commodity.ORE: 3.2, Commodity.VOLATILES: -0.40, Commodity.REFINED: -0.25, Commodity.GOODS: -0.20, Commodity.RARE: 0.0},
	"Halvorsen Claim": {Commodity.ORE: 1.8, Commodity.VOLATILES: -0.22, Commodity.REFINED: -0.25, Commodity.GOODS: -0.15, Commodity.RARE: 0.40},
	"Corvus Yards": {Commodity.ORE: 1.8, Commodity.VOLATILES: -0.21, Commodity.REFINED: -0.20, Commodity.GOODS: -0.10, Commodity.RARE: 0.40},
	"Deepcut": {Commodity.ORE: 1.5, Commodity.VOLATILES: -0.22, Commodity.REFINED: -0.25, Commodity.GOODS: -0.15, Commodity.RARE: 0.0},
}

# Cluster-wide net per commodity, and the single most important line in this
# file. It used to assert net == 0: supply exactly equalling demand, which read
# as elegant closure and was in fact the bug. A producer running at exactly
# 100% of demand NEVER accumulates surplus, never clears surplus_line, and
# therefore never opens an EXPORT posting -- the cluster could not trade its
# principal commodities at any fleet size, with any router. Cargo in flight is
# also a permanent deficit a zero-margin system can never refill.
#
# So the cluster now runs a DELIBERATE surplus, and this table is that
# intention written down. The surplus is what the Nexus hauler carries out; if
# one of these drifts to zero, trade in that commodity silently dies.
const EXPECTED_MARGIN := {
	Commodity.ORE: 1.50,
	Commodity.VOLATILES: 0.60,
	Commodity.REFINED: 0.60,
	Commodity.GOODS: 0.35,
	Commodity.RARE: 0.15,
}

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Station Economy Reference-Table (M53c Phase A oracle) Tests")

	var def = HomeCluster.build()
	var m := ClusterManager.new()
	# Promote NOTHING. This manager is never added to the scene tree, so its
	# _ready() never runs and live_parent stays null -- under the DEFAULT
	# full-sim policy _reconcile() would then try to promote every record and
	# _promote() would abort on `live_parent.add_child(node)` every single pass
	# (a runtime error aborts the rest of that function for the frame, per
	# CLAUDE.md -- it does NOT halt the engine, so the test still "passed" while
	# emitting ~20KB of SCRIPT ERROR spam and silently half-promoting records).
	# A tiny bubble plus a viewpoint at the far edge of the world keeps every
	# record dormant, which is also the STRONGER assertion: the reference steady
	# state must hold with nothing live at all, since the economy director walks
	# cluster.records directly regardless of liveness.
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)
	m.directors.append(StationEconomy.new({"policy_period": 3600.0}))   # 1 pass = 1 hour

	var stations: Dictionary = {}   # name -> record, for the 8 named in EXPECTED
	for rec in m.records:
		if rec.kind == ClusterEntity.Kind.STATION and EXPECTED.has(rec.name):
			stations[rec.name] = rec

	for name in EXPECTED.keys():
		_assert(stations.has(name), "reference station '%s' exists in the authored home cluster" % name)

	var initial: Dictionary = {}   # name -> {commodity -> stock}
	for name in stations.keys():
		var rec = stations[name]
		initial[name] = {}
		for c in Commodity.ALL:
			initial[name][c] = rec.stocks["self"][c]["stock"]

	# Everything stays dormant (see the policy above) -- which is precisely the
	# point: the director walks cluster.records directly regardless of liveness
	# (same mechanism test_station_economy's sub-test F pins in isolation).
	# SIM_HOURS worth of ticks in one call.
	m.tick(SIM_HOURS * 3600.0)

	var net_by_commodity: Dictionary = {}
	for c in Commodity.ALL:
		net_by_commodity[c] = 0.0

	for name in EXPECTED.keys():
		if not stations.has(name):
			continue
		var rec = stations[name]
		for c in Commodity.ALL:
			var delta: float = rec.stocks["self"][c]["stock"] - initial[name][c]
			var observed_rate: float = delta / SIM_HOURS
			var expected_rate: float = EXPECTED[name][c]
			net_by_commodity[c] += observed_rate
			_assert(abs(observed_rate - expected_rate) < TOLERANCE,
				"%s %s: observed net %.3f lots/hr vs expected %.3f (delta %.3f over %.1fh)" %
					[name, c, observed_rate, expected_rate, delta, SIM_HOURS])

	for c in Commodity.ALL:
		var want: float = EXPECTED_MARGIN[c]
		_assert(abs(net_by_commodity[c] - want) < TOLERANCE * EXPECTED.size(),
			"cluster-wide net %s should be the authored SURPLUS %.2f, not 0 (got %.4f lots/hr) -- see EXPECTED_MARGIN" % [c, want, net_by_commodity[c]])

	# Sanity: nothing should have STARVED/BLOCKED across a 4h run given the
	# auto-sized ~24h buffer -- if this fires, the buffer assumption (not the
	# rate model) is the thing to revisit.
	for name in stations.keys():
		var rec = stations[name]
		var converters: Array = rec.industry.get("converters", [])
		for conv in converters:
			_assert(conv.get("state", -1) == StationEconomy.ConverterState.RUNNING,
				"%s's converter stayed RUNNING across %.0fh (state=%s)" % [name, SIM_HOURS, str(conv.get("state", -1))])

	_finalize()

func _finalize() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_station_economy_reference <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_station_economy_reference <<<")
		get_tree().quit(1)
