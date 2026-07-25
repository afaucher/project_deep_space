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
const SIM_HOURS := 4.0

# station name -> {commodity -> expected net lots/hour}, transcribed from the
# design doc's reference table. Note the "-- " ORE cell for Drift Market is
# expressed as 0.0 (no mechanism at all, not a tiny authored rate).
const EXPECTED := {
	"Ironhold": {Commodity.ORE: -5.6, Commodity.VOLATILES: -0.60, Commodity.REFINED: -0.50, Commodity.GOODS: 1.50},
	"Drift Market": {Commodity.ORE: 0.0, Commodity.VOLATILES: -0.50, Commodity.REFINED: -0.50, Commodity.GOODS: -0.30},
	"Refinery Prime": {Commodity.ORE: -3.3, Commodity.VOLATILES: -0.45, Commodity.REFINED: 2.20, Commodity.GOODS: -0.40},
	"Coldreach": {Commodity.ORE: 0.6, Commodity.VOLATILES: 2.60, Commodity.REFINED: -0.25, Commodity.GOODS: -0.20},
	"Slag Bay": {Commodity.ORE: 3.2, Commodity.VOLATILES: -0.40, Commodity.REFINED: -0.25, Commodity.GOODS: -0.20},
	"Halvorsen Claim": {Commodity.ORE: 1.8, Commodity.VOLATILES: -0.22, Commodity.REFINED: -0.25, Commodity.GOODS: -0.15},
	"Corvus Yards": {Commodity.ORE: 1.8, Commodity.VOLATILES: -0.21, Commodity.REFINED: -0.20, Commodity.GOODS: -0.10},
	"Deepcut": {Commodity.ORE: 1.5, Commodity.VOLATILES: -0.22, Commodity.REFINED: -0.25, Commodity.GOODS: -0.15},
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
		_assert(abs(net_by_commodity[c]) < TOLERANCE * EXPECTED.size(),
			"cluster-wide net %s settles to ~0 (got %.4f lots/hr, the table's own 'net' row)" % [c, net_by_commodity[c]])

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
