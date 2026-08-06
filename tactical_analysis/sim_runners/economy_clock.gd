extends Node

# WHAT LIMITS THE SIZE OF A CARGO LOAD?
#
# Built after answering this the slow way. "How much cargo is in transit" was
# chased through 240-game-minute campaign runs with 15 haulers, 6 pirates, 2
# patrols, live sensors and physics -- three wall-clock hours each -- to observe
# something that involves NO SHIPS AT ALL. `_score_pair` takes
# `min(LOT_SIZE, min(pickup_qty, dropoff_qty))`, and both quantities are pure
# functions of station bin state. No hull is required to read them.
#
# This ticks StationEconomy and nothing else -- no movers, no hulls, no physics
# -- so dt is free: eight game-HOURS in about a second.
#
# WHAT IT IS FOR. The seeded steady state in sim_harness is ASYMMETRIC:
#
#     if can_produce(rec, c):  stock = capacity * 0.92   # above surplus_line -> EXPORT open
#     elif has_demand(rec, c): stock = target            # == target -> SATISFIED -> IMPORT CLOSED
#
# so producers start able to sell and consumers start wanting nothing. If the
# binding term is the IMPORT deficit, every measured load is really
# `sink_rate x time_since_serviced` and says nothing about hold size, fleet
# size, or LOT_SIZE -- which is exactly what a fleet A/B suggested when 3x the
# haulers left the mean load unchanged (haulers cannot make a consumer drain
# faster).
#
# So print BOTH sides per game-minute and let the binding one name itself.
# SEED=harness reproduces today's world; SEED=both also opens the consumers.
#
# Deliberately NOT a test: there is no correct number here, only which side of
# the min() is holding the amount down.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-tactical-sim economy_clock
#   HOURS=8 SEED_MODE=harness|both|none

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const SimHarness = preload("res://tactical_analysis/sim_runners/sim_harness.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")

const STEP := 10.0   # game-seconds per pass; the default policy_period

# What a symmetric seed would use for the consumer side: far enough below
# target that an IMPORT posting is open at t=0, mirroring the producer line's
# 0.92 sitting above surplus_line. NOT a tuned number -- 0.60 of target is
# simply "has been drawing down a while", the consumer twin of "has been
# producing a while".
const SEED_CONSUMER_FRACTION_OF_TARGET := 0.60

var main_node: Node = null

func _envf(name: String, fallback: float) -> float:
	var v := OS.get_environment(name)
	return float(v) if v != "" else fallback

func _envs(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback

func setup(main) -> void:
	main_node = main
	var hours: float = _envf("HOURS", 8.0)
	var mode: String = _envs("SEED_MODE", "harness")
	print("=== economy_clock: which side of the min() limits a load? (%.1f game-hours, seed=%s) ===" % [hours, mode])

	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)
	var manager = ClusterManager.new()
	manager.name = "EconomyClockCluster"
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	manager.policy = pol
	manager.viewpoint = Vector2(1e9, 1e9)   # promote nothing: pure bookkeeping
	ClusterLoader.load_into(HomeCluster.build(), manager)
	main_node.add_child(manager)
	var econ = StationEconomy.new()

	if mode != "none":
		SimHarness.seed_steady_state(manager)
	if mode == "both":
		_open_the_consumers(manager)

	print("  postings at t=0: %s" % _posting_census(manager))
	print("
   min | EXPORTS  min_qty | IMPORTS  min_qty | best route amount | binding side")
	var minute: float = 0.0
	var passes: int = int(hours * 3600.0 / STEP)
	for i in range(passes):
		econ.tick(STEP, manager)
		minute += STEP / 60.0
		if fmod(minute, 15.0) > 0.001 and i < passes - 1:
			continue
		_report(manager, minute)
	get_tree().quit(0)

# The consumer twin of SEED_PRODUCER_FRACTION. sim_harness parks consumers AT
# target, which reads as SATISFIED and closes their IMPORT postings entirely --
# so a "running economy" ships with sellers holding goods and no buyers.
func _open_the_consumers(manager) -> void:
	for rec in manager.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		if rec.industry.is_empty():
			continue
		for c in Commodity.ALL:
			var bin: Dictionary = rec.stocks["self"][c]
			if float(bin.get("capacity", 0.0)) <= 0.0:
				continue
			if SimHarness.can_produce(rec, c):
				continue
			if SimHarness.has_demand(rec, c):
				bin["stock"] = float(bin.get("target", 0.0)) * SEED_CONSUMER_FRACTION_OF_TARGET

func _rec_by_id(manager, id: int):
	if id < 0:
		return null
	for rec in manager.records:
		if rec.id == id:
			return rec
	return null

func _posting_census(manager) -> String:
	var ex: int = 0
	var im: int = 0
	for rec in manager.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		for c in Commodity.ALL:
			var p: Dictionary = StationEconomy.get_posting(rec, "self", c)
			if p.is_empty():
				continue
			if p["direction"] == "EXPORT":
				ex += 1
			else:
				im += 1
	return "EXPORT open %d, IMPORT open %d" % [ex, im]

func _report(manager, minute: float) -> void:
	# The MINIMUM open quantity on each side is what matters, not the maximum:
	# min() picks the smaller, so the side with the smallest open posting is the
	# one holding loads down.
	var ex_min: float = INF
	var im_min: float = INF
	var ex_n: int = 0
	var im_n: int = 0
	for rec in manager.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		for c in Commodity.ALL:
			var p: Dictionary = StationEconomy.get_posting(rec, "self", c)
			if p.is_empty():
				continue
			if p["direction"] == "EXPORT":
				ex_n += 1
				ex_min = minf(ex_min, float(p["quantity"]))
			else:
				im_n += 1
				im_min = minf(im_min, float(p["quantity"]))

	# The number a hauler would actually load, through the REAL planner.
	var best: Dictionary = RoutePlanner.best_route(manager, Vector2.ZERO, "")
	var amount: float = float(best.get("amount", 0.0))
	# WHICH SIDE OF THE min() IS HOLDING THIS LOAD DOWN. Re-derived from the
	# CHOSEN route's own two postings rather than from the cluster-wide minima
	# above -- best_route picks the highest-scoring pair, not the thinnest one,
	# so the global minima cannot answer this. The route dict does not carry the
	# quantities, so they are looked up again here.
	var binding: String = "-"
	if not best.is_empty():
		var pu_rec = _rec_by_id(manager, int(best.get("pickup_id", -1)))
		var dr_rec = _rec_by_id(manager, int(best.get("dropoff_id", -1)))
		var com: String = str(best.get("commodity", ""))
		if pu_rec != null and dr_rec != null and com != "":
			var pu: float = float(StationEconomy.get_posting(pu_rec, "self", com).get("quantity", 0.0))
			var dr: float = float(StationEconomy.get_posting(dr_rec, "self", com).get("quantity", 0.0))
			if amount >= RoutePlanner.LOT_SIZE:
				binding = "LOT_SIZE (hold)"
			elif pu < dr:
				binding = "EXPORT (pickup) %.2f" % pu
			else:
				binding = "IMPORT (dropoff) %.2f" % dr
	print("  %5.0f | %7d  %7.2f | %7d  %7.2f | %17.2f | %s" % [
		minute, ex_n, (0.0 if ex_min == INF else ex_min),
		im_n, (0.0 if im_min == INF else im_min), amount, binding])
