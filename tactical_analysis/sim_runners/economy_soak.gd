extends Node

# M53c -- long-run economy balance soak (implementation_plans/
# m53c_demand_routing.md "The soak sims"). NOT a test: it lives here, out of
# the normal gate, because it answers a BALANCE question ("does the cluster
# keep everyone served over time, or do stations run out of air?") rather than
# a correctness one, and because balance answers are read, not asserted.
#
# THE TIMESCALE POINT, which is why this runner exists at all:
# rates are lots/HOUR and bins carry roughly a day of buffer, so "30 minutes of
# game time" moves ~0.3 lots against a ~14-lot buffer and shows nothing. And
# 30 game-minutes of REAL physics is not cheap either -- at ~12ms/physics-step
# the sim runs ~83fps headless, so one game-hour costs ~43 real minutes.
#
# But the economy needs NO physics frames. It is pure bookkeeping:
# StationEconomy.tick(dt, cluster) accumulates dt and runs its pass per period,
# so tick(3600.0) advances an hour instantly (test_station_economy_reference
# already does 4 simulated hours in ~11s). That inverts the cost problem
# completely -- this runner covers WEEKS of game time in seconds.
#
# WHAT IT WILL REPORT TODAY (Phase A + B): total collapse. Coldreach fills its
# VOLATILES bin to capacity and goes BLOCKED while every other station drains
# to zero on air. That is CORRECT, not a bug: Phases A and B give the cluster
# production and consumption but NOTHING THAT REDISTRIBUTES -- hauling is Phase
# C. This run is therefore the deliberate "before" picture, and it is what turns
# "stations stop starving" into a measurable pass/fail once dispatch exists.
#
# ==> economy_soak going green is PHASE C's acceptance criterion, not Phase B's.
#
# A second runner (economy_traffic -- real hulls flying and docking) is
# deliberately NOT built yet: it is expensive and has nothing to prove until
# ships actually dispatch against postings.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim economy_soak

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")

# 30 game-DAYS, sampled hourly. Cheap because none of this touches physics.
const SIM_HOURS := 720
const SECONDS_PER_HOUR := 3600.0

# A bin at or under this fraction of its target counts as "starving" for the
# time-at-zero metric. Not zero exactly -- a station sitting at 2% of target is
# functionally out, and an exact-zero test would under-report.
const STARVING_FRACTION := 0.02

var log_file: FileAccess

func setup(_main) -> void:
	print("=== M53c economy soak: %d game-hours (%d days), no physics ===" % [SIM_HOURS, SIM_HOURS / 24])

	var def = HomeCluster.build()
	var m := ClusterManager.new()
	# Promote NOTHING. This manager is never added to the scene tree, so its
	# _ready() never runs and live_parent stays null -- under the DEFAULT
	# full-sim policy _reconcile() would try to promote every record and
	# _promote() would abort on `live_parent.add_child(node)` every pass (a
	# runtime error aborts the rest of that function for the frame per
	# CLAUDE.md; it does NOT halt the engine, so this would silently spew and
	# half-promote). Everything dormant is also exactly right here: the economy
	# director walks cluster.records regardless of liveness, which is the whole
	# reason the state lives on the record.
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)
	m.directors.append(StationEconomy.new())

	# StationEconomy's debug log prints one line per STALLED converter per pass.
	# That is right for playtesting (and ON is the house default for all three
	# director logs), but over 720 passes with a persistently starved refinery it
	# is ~168k lines, which is slow enough to dominate the run. Silence it here;
	# this runner's own report is the output that matters.
	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)

	# `stocks.has("self")` alone is NOT the right filter: the five M43 mobile
	# homes are STATION-kind records too and get zero-valued bins from
	# ensure_holder, which would pad the report with 5 all-zero rows (13
	# "stations" instead of 8). An economically real station has either authored
	# industry or at least one bin with actual capacity.
	var stations: Array = []
	for rec in m.records:
		if rec.kind != ClusterEntity.Kind.STATION or not rec.stocks.has("self"):
			continue
		if not rec.industry.is_empty():
			stations.append(rec)
			continue
		for c in Commodity.ALL:
			if rec.stocks["self"][c].get("capacity", 0.0) > 0.0:
				stations.append(rec)
				break
	stations.sort_custom(func(a, b): return a.name < b.name)
	print("Tracking %d stations with an authored economy." % stations.size())

	# Two outputs, matching the two conventions in CLAUDE.md:
	#   - the durable SUMMARY (one row per station-commodity) -> tactical_analysis/data/,
	#     tracked on purpose, and small enough to sit alongside the other sim
	#     results (the largest is ~17KB; an hourly trace of every bin would be
	#     1.6MB, 100x out of line, and would churn on every run).
	#   - the per-hour TRACE -> tmp/, gitignored, for when a summary row looks
	#     wrong and you need to see the shape of the drain.
	DirAccess.make_dir_recursive_absolute("res://tactical_analysis/data")
	DirAccess.make_dir_recursive_absolute("res://tmp")
	log_file = FileAccess.open("res://tmp/economy_soak_trace.csv", FileAccess.WRITE)
	if log_file == null:
		printerr("[SIM FAILED] could not open tmp/economy_soak_trace.csv for writing")
		get_tree().quit(1)
		return
	log_file.store_line("hour,station,flag,commodity,stock,target,capacity,urgency_dir,urgency")

	# name -> commodity -> {hours_starving, hours_full, min, max}
	var stats: Dictionary = {}
	for rec in stations:
		stats[rec.name] = {}
		for c in Commodity.ALL:
			stats[rec.name][c] = {
				"hours_starving": 0, "hours_full": 0,
				"min": INF, "max": -INF,
			}
	# station -> converter index -> hours in each state
	var conv_stats: Dictionary = {}
	for rec in stations:
		var convs: Array = rec.industry.get("converters", [])
		if not convs.is_empty():
			conv_stats[rec.name] = {"running": 0, "starved": 0, "blocked": 0}

	for hour in range(SIM_HOURS):
		m.tick(SECONDS_PER_HOUR)
		for rec in stations:
			var bins: Dictionary = rec.stocks["self"]
			for c in Commodity.ALL:
				var bin: Dictionary = bins[c]
				var stock: float = bin.get("stock", 0.0)
				var target: float = bin.get("target", 0.0)
				var capacity: float = bin.get("capacity", 0.0)
				var s: Dictionary = stats[rec.name][c]
				s["min"] = min(s["min"], stock)
				s["max"] = max(s["max"], stock)
				if target > 0.0 and stock <= target * STARVING_FRACTION:
					s["hours_starving"] += 1
				if capacity > 0.0 and stock >= capacity * 0.999:
					s["hours_full"] += 1
				var u: Dictionary = StationEconomy.urgency(rec, "self", c)
				log_file.store_line("%d,%s,%s,%s,%.3f,%.3f,%.3f,%s,%.3f" % [
					hour, rec.name, rec.transponder_flag, c,
					stock, target, capacity, u.get("direction", "?"), u.get("value", 0.0)])
			if conv_stats.has(rec.name):
				for conv in rec.industry.get("converters", []):
					match conv.get("state", -1):
						StationEconomy.ConverterState.RUNNING: conv_stats[rec.name]["running"] += 1
						StationEconomy.ConverterState.STARVED: conv_stats[rec.name]["starved"] += 1
						StationEconomy.ConverterState.BLOCKED: conv_stats[rec.name]["blocked"] += 1

	# FileAccess.store_line BUFFERS -- flush/close before anything reads it back
	# (CLAUDE.md: "a CSV being written may read back 0 lines until flushed").
	log_file.flush()
	log_file.close()

	_write_summary(stations, stats, conv_stats)
	_report(stations, stats, conv_stats)
	get_tree().quit(0)

# The tracked artifact: one row per station-commodity, plus the converter
# uptime columns where a station has industry. Small, diffable, and directly
# comparable run-to-run -- which is what makes it Phase C's acceptance evidence.
func _write_summary(stations: Array, stats: Dictionary, conv_stats: Dictionary) -> void:
	var f := FileAccess.open("res://tactical_analysis/data/economy_soak.csv", FileAccess.WRITE)
	if f == null:
		printerr("[SIM] could not write economy_soak.csv summary")
		return
	f.store_line("sim_hours,station,flag,commodity,hours_starving,hours_full,min_stock,max_stock,conv_running,conv_starved,conv_blocked")
	for rec in stations:
		var cs: Dictionary = conv_stats.get(rec.name, {})
		for c in Commodity.ALL:
			var s: Dictionary = stats[rec.name][c]
			f.store_line("%d,%s,%s,%s,%d,%d,%.2f,%.2f,%d,%d,%d" % [
				SIM_HOURS, rec.name, rec.transponder_flag, c,
				s["hours_starving"], s["hours_full"], s["min"], s["max"],
				cs.get("running", 0), cs.get("starved", 0), cs.get("blocked", 0)])
	f.flush()
	f.close()

func _report(stations: Array, stats: Dictionary, conv_stats: Dictionary) -> void:
	print("\n=== Starvation (hours at <= %d%% of target, out of %d) ===" % [int(STARVING_FRACTION * 100), SIM_HOURS])
	print("station              flag         commodity    starving  full   min      max")
	var total_starving: int = 0
	for rec in stations:
		for c in Commodity.ALL:
			var s: Dictionary = stats[rec.name][c]
			if s["hours_starving"] == 0 and s["hours_full"] == 0:
				continue   # healthy the whole run -- only print the interesting rows
			total_starving += s["hours_starving"]
			print("%-20s %-12s %-12s %-9d %-6d %-8.2f %-8.2f" % [
				rec.name, rec.transponder_flag, c,
				s["hours_starving"], s["hours_full"], s["min"], s["max"]])

	print("\n=== Converter uptime (hours) ===")
	for name in conv_stats.keys():
		var cs: Dictionary = conv_stats[name]
		print("%-20s running=%-6d starved=%-6d blocked=%-6d" % [name, cs["running"], cs["starved"], cs["blocked"]])

	print("\n=== Verdict ===")
	if total_starving == 0:
		print("SERVED: no station spent any hour starving across %d game-days." % (SIM_HOURS / 24))
	else:
		print("COLLAPSE: %d station-commodity-hours spent starving across %d game-days." % [total_starving, SIM_HOURS / 24])
		print("At Phase A/B this is EXPECTED and correct -- production and consumption")
		print("exist but NOTHING REDISTRIBUTES. Hauling is Phase C; this is the 'before'")
		print("baseline that makes Phase C's success measurable.")
	print("\nSummary: tactical_analysis/data/economy_soak.csv   Per-hour trace: tmp/economy_soak_trace.csv")
