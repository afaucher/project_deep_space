extends Node

# THE FUNNEL. Does information actually flow the whole way, in a real campaign?
#
# M57-M59 shipped as a chain of mechanisms, each unit-tested in isolation:
#
#   a robbery happens -> the victim records a positioned incident -> the news
#   reaches a station -> an authority notarizes it -> a patrol hears it ->
#   the patrol sweeps the lane
#
# Every link had a passing test and the chain was still broken end to end: the
# mailbag only merged on DOCK, and the authored patrol route is four waypoints
# with `loop: true` and no DOCK verb, so a patrol's mailbag stayed empty for an
# entire campaign. The unit tests passed because they hand-set the mailbag --
# they constructed a precondition the world never supplies.
#
# So this runner measures the chain as a FUNNEL rather than asserting any single
# link. The interesting output is not a pass/fail, it is WHERE THE COUNT GOES TO
# ZERO -- that is the broken link, and it names itself.
#
# Deliberately NOT a test: there is no correct number here yet. A funnel that
# reads 6 robberies -> 6 incidents -> 2 delivered -> 1 notarized -> 0 sweeps is
# a finding about pacing, not a failure. Turning any stage into an assertion
# before we know the natural rate would be inventing a budget.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-tactical-sim information_loop
#   SIM_MINUTES=90 ... (default 60)

const SimHarness = preload("res://tactical_analysis/sim_runners/sim_harness.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const TrafficGuild = preload("res://scripts/directors/traffic_guild.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const Mailbag = preload("res://scripts/mail/mailbag.gd")
const Incident = preload("res://scripts/mail/incident.gd")
const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")
const DecisionProbe = preload("res://scripts/instrumentation/decision_probe.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")

var NUM_HAULERS: int = 8
const SETTLE_MINUTES := 2.0
const DT := 1.0 / 60.0

# Piracy has to actually happen or the funnel measures nothing, so this uses the
# settings the A/B showed produce takes at campaign scale (hunt=900s), not the
# authored defaults that produced zero.
# Pirate PRESSURE is env-tunable because this runner serves two different
# questions and they need opposite settings:
#
#   CHAIN test   -- deliberately unrealistic pressure, so every stage of the
#                   funnel fires enough times to give latency medians and sweep
#                   outcomes a real sample. Answers "does the chain close?"
#   PACING test  -- authored pressure, long run. Answers "how often does this
#                   happen in a real campaign?" -- a different question that
#                   only means anything once the chain is proven.
#
# Conflating them wastes the expensive run: you cannot establish latency from
# n=6, and you cannot calibrate pacing on a config you deliberately distorted.
#
# The binding constraint on piracy volume is `base_cap`, which is 1 by default
# -- ONE pirate may exist at a time, rising to 3 only after takes. With a
# 900s hunt that single slot is occupied for 15 game-minutes, which is why a
# 30-minute run produced exactly one pirate.
func _guild_config() -> Dictionary:
	return {
		"hunt_seconds": _envf("HUNT_SECONDS", 900.0),
		"colors_chance": _envf("PIRATE_COLORS_CHANCE", 0.5),
		"sos_reprisal_chance": _envf("PIRATE_SOS_REPRISAL", 0.15),
		"base_cap": int(_envf("PIRATE_BASE_CAP", 1.0)),
		"max_cap": int(_envf("PIRATE_MAX_CAP", 3.0)),
		"arrival_window": [_envf("PIRATE_ARRIVAL_MIN", 120.0), _envf("PIRATE_ARRIVAL_MAX", 300.0)],
	}

var manager = null
var guild = null
var clock = null
var sim_minutes: float = 60.0

# Peak values, not final: a sweep assignment CLEARS when it completes, and a
# funnel that sampled only at the end would read zero sweeps for a patrol that
# swept five times and came home. Same for warrants, which can expire.
var peak_sweeps_seen: int = 0
var sweeps_started: int = 0
var _patrols_sweeping_last: Dictionary = {}

# --- latency chain: per robbery, when did each tier first learn of it? -------
# Keyed "source_id:seq". {t_robbery, t_station, t_patrol, t_sweep} in frames,
# -1 until observed. This is the direct measurement of "information has a
# position and a velocity" -- the headline claim, and the one thing an
# end-state count can never show.
var _chain: Dictionary = {}

# --- lane occupancy over time -----------------------------------------------
# Oscillation is TEMPORAL. An end-state histogram cannot show a lane being
# abandoned and then won back, which is exactly the self-correcting loop M59
# claims. Sampled per minute: lane -> haulers currently planning it.
var _trace = null
var _sample_accum: float = 0.0

# --- sweep outcomes, not sweep counts ---------------------------------------
var sweeps_reached: int = 0
var sweeps_with_contact: int = 0
var _sweep_saw_hostile: Dictionary = {}

func _envf(name: String, fallback: float) -> float:
	var v := OS.get_environment(name)
	return float(v) if v != "" else fallback

func setup(main) -> void:
	sim_minutes = _envf("SIM_MINUTES", 60.0)
	NUM_HAULERS = int(_envf("NUM_HAULERS", 8.0))
	print("=== information_loop: does the chain actually close? (%.0f game-min, %d haulers) ===" % [
		sim_minutes, NUM_HAULERS])
	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)
	ThreatResponseLeaf.sos_chance = 0.6

	var cfg: Dictionary = _guild_config()
	print("    pirates: base_cap=%d max_cap=%d arrival=%s hunt=%.0fs | victim_sos=%.2f" % [
		cfg["base_cap"], cfg["max_cap"], str(cfg["arrival_window"]), cfg["hunt_seconds"],
		ThreatResponseLeaf.sos_chance])
	guild = PirateGuild.new(cfg)
	manager = SimHarness.build_live_home_cluster(main, [guild])
	SimHarness.spawn_planner_haulers(manager, NUM_HAULERS)
	clock = SimHarness.Clock.new(SETTLE_MINUTES, sim_minutes)

	# One extra best_route per replan (throttled to 10s per hull) so every
	# routing decision carries its own counterfactual. Sim-only.
	DecisionProbe.enabled = true
	DecisionProbe.reset()

	# Per-minute trace to tmp/ (gitignored), summary to tactical_analysis/data/
	# -- the same split economy_traffic uses.
	DirAccess.make_dir_recursive_absolute("res://tmp")
	_trace = FileAccess.open("res://tmp/information_loop_trace.csv", FileAccess.WRITE)
	if _trace != null:
		_trace.store_line("minute,lane,haulers_planning,mean_risk_on_lane")

	await _run()
	_report()

func _run() -> void:
	# Clock.advance() ticks the manager ITSELF and returns a phase string --
	# do not also call manager.tick() here or every director runs twice per
	# frame. (CLAUDE.md's warning still applies to the underlying hazard: a
	# ClusterManager with a bare Vector2 viewpoint self-ticks nothing, which is
	# why the tick has to come from the harness at all.)
	while true:
		await get_tree().physics_frame
		var phase: String = clock.advance(manager)
		if phase == "measure_start":
			# Promotion churn is not a finding -- zero the transient counters.
			sweeps_started = 0
			peak_sweeps_seen = 0
			_patrols_sweeping_last.clear()
		if phase == "done":
			break
		_sample_sweeps()
		_sample_chain()
		_sample_trace()

# Sweeps are transient, so poll for the rising edge rather than reading a final
# state. A patrol that swept and returned is a SUCCESS of this mechanism and
# would be invisible to an end-of-run snapshot.
func _sample_sweeps() -> void:
	var sweeping := 0
	for rec in manager.records:
		var node = rec.live_node
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("get_mailbag"):
			continue
		var asg: Dictionary = node.get("assignment") if node.get("assignment") != null else {}
		if asg.get("sweep", false):
			sweeping += 1
			if not _patrols_sweeping_last.get(rec.id, false):
				sweeps_started += 1
				_sweep_saw_hostile[rec.id] = false
			_patrols_sweeping_last[rec.id] = true
			# A sweep that finds nobody is not a failure of the mechanism, but a
			# mechanism that NEVER finds anybody is. Counted separately.
			if not _sweep_saw_hostile.get(rec.id, false):
				for cid in node.active_contacts:
					if node.active_contacts[cid].get("standing", "") == Standing.HOSTILE:
						_sweep_saw_hostile[rec.id] = true
						sweeps_with_contact += 1
						break
		else:
			_patrols_sweeping_last[rec.id] = false
	peak_sweeps_seen = maxi(peak_sweeps_seen, sweeping)

# Who knows about each robbery, and WHEN. Polls mailbag versions per source and
# records first-crossings; nothing in game code has to carry a timestamp.
func _sample_chain() -> void:
	var frame := Engine.get_physics_frames()
	for rec in manager.records:
		for e in rec.incident_log:
			if e.get("kind", "") != Incident.KIND_ARMED_ROBBERY:
				continue
			var key := "%d:%d" % [rec.id, int(e.get("seq", 0))]
			if not _chain.has(key):
				_chain[key] = {"t_robbery": int(e.get("stamp", frame)),
					"t_station": -1, "t_patrol": -1, "t_sweep": -1,
					"src": rec.id, "seq": int(e.get("seq", 0))}
	for key in _chain:
		var c: Dictionary = _chain[key]
		if c["t_station"] >= 0 and c["t_patrol"] >= 0:
			continue
		for rec2 in manager.records:
			if Mailbag.version_of(rec2.mailbag, c["src"]) < c["seq"]:
				continue
			if _is_station(rec2):
				if c["t_station"] < 0:
					c["t_station"] = frame
			elif _is_patrol_rec(rec2):
				if c["t_patrol"] < 0:
					c["t_patrol"] = frame

func _is_patrol_rec(rec) -> bool:
	var n = rec.live_node
	var auth = n.get("warrant_authority") if n != null and is_instance_valid(n) else null
	return auth != null and auth is Array and not auth.is_empty()

# Lane occupancy + the risk haulers currently see on each lane, once a minute.
func _sample_trace() -> void:
	_sample_accum += DT
	if _sample_accum < 60.0 or _trace == null:
		return
	_sample_accum = 0.0
	var minute: float = clock.frames / 3600.0
	var lanes: Dictionary = {}
	for rec in manager.records:
		var n = rec.live_node
		if n == null or not is_instance_valid(n):
			continue
		var job = n.get("default_job")
		if job == null or not (job is Dictionary) or not job.has("pickup_accept"):
			continue
		var lane := "%s>%s" % [str(job.get("pickup_id", "?")), str(job.get("dropoff_id", "?"))]
		lanes[lane] = int(lanes.get(lane, 0)) + 1
	for lane in lanes:
		_trace.store_line("%.1f,%s,%d,%.2f" % [minute, lane, lanes[lane], 0.0])
	_trace.flush() # store_line BUFFERS -- a crash three hours in must not lose the run

func _is_station(rec) -> bool:
	return rec.kind == ClusterEntity.Kind.STATION

func _median(a: Array) -> String:
	if a.is_empty():
		return "n/a"
	var b: Array = a.duplicate()
	b.sort()
	return "%.1f" % float(b[b.size() / 2])

func _report() -> void:
	var incidents_recorded := 0
	var robbery_incidents := 0
	var stations := 0
	var stations_holding_news := 0
	var notarized := 0
	var patrol_like := 0
	var patrols_holding_news := 0
	var haulers_holding_news := 0

	for rec in manager.records:
		incidents_recorded += rec.incident_seq
		# Durable robbery count: a LOST pirate's record is ERASED, so summing
		# live hulls' loot_takes undercounts. The victim's incident survives on
		# the victim's record, which makes it the only count that cannot be
		# deleted by the outcome it is measuring.
		for e in rec.incident_log:
			if e.get("kind", "") == Incident.KIND_ARMED_ROBBERY:
				robbery_incidents += 1
		var bag: Dictionary = rec.mailbag
		# "Holds news" = knows about some OTHER source's log, not just its own.
		var foreign := 0
		for sid in bag:
			if sid != rec.id and Mailbag.version_of(bag, sid) > 0:
				foreign += 1
		if _is_station(rec):
			stations += 1
			if foreign > 0:
				stations_holding_news += 1
			var node = rec.live_node
			if node != null and is_instance_valid(node):
				for wkey in node.warrants:
					var w: Dictionary = node.warrants[wkey]
					if w.get("origin_flag", "") != "" and w.get("offense", "") == Standing.OFF_ARMED_ROBBERY:
						notarized += 1
		else:
			var node2 = rec.live_node
			# `.get()` on a node without the property yields Nil, and `and` does
			# NOT protect a method call on that result -- this crashed a
			# completed 30-minute run at the reporting step. Bind first, then
			# test. (CLAUDE.md's Dictionary-miss rule, same shape: a missing
			# field aborts the rest of the function.)
			var auth = node2.get("warrant_authority") if node2 != null and is_instance_valid(node2) else null
			var is_patrol: bool = auth != null and auth is Array and not auth.is_empty()
			if is_patrol:
				patrol_like += 1
				if foreign > 0:
					patrols_holding_news += 1
			elif foreign > 0:
				haulers_holding_news += 1

	# GROUND TRUTH, not the ledger. PirateGuild books a completed robbery as
	# `presumed LOST` when the cash-out check-in misses (an 8000u ring the
	# pirate crosses in ~11s against a 10s poll), so takes_total can read 0 for
	# a run where piracy worked -- which is precisely the reading this funnel
	# exists to avoid manufacturing. Sum the hulls, as pirate_scenarios does.
	# Stage 2 (incidents) is an independent ground-truth cross-check on this.
	var takes: int = 0
	for rec2 in manager.records:
		var n = rec2.live_node
		if n != null and is_instance_valid(n):
			var lt = n.get("loot_takes")
			if lt != null:
				takes += int(lt)
	var ledger_takes: int = guild.takes_total

	# READ THIS FIRST -- it can invalidate everything below. If risk never got
	# large relative to the margin a competing route must beat, cargo never had a
	# REASON to divert, and '0 decisions changed' then means UNTESTED rather than
	# INEFFECTIVE. Opposite conclusions from an identical number, so it prints
	# ABOVE the funnel rather than in a footnote.
	var p95: float = DecisionProbe.risk_p95()
	var margin: float = RoutePlanner.HYSTERESIS_MARGIN
	print("\n=== PRECONDITION: did risk ever matter? ===")
	print("  routing decisions observed   : %d" % DecisionProbe.total)
	print("  risk p95 / max               : %.1f / %.1f  (margin to beat: %.1f)" % [p95, DecisionProbe.risk_max(), margin])
	if DecisionProbe.total == 0:
		print("  >>> NO DECISIONS OBSERVED -- haulers never replanned; nothing below is measurable")
	elif p95 < margin:
		print("  >>> RISK NEVER GOT BIG ENOUGH -- the cargo half of M59 is UNTESTED by this run,")
		print("      whatever the traffic did. Raise pirate pressure or run longer.")
	else:
		print("  >>> risk cleared the margin -- diversion was possible, so the counts below mean something")

	print("\n=== COUNTERFACTUAL: did risk change any decision? ===")
	print("  decisions changed by risk    : %d of %d" % [DecisionProbe.changed_by_risk, DecisionProbe.total])

	var lat_station: Array = []
	var lat_patrol: Array = []
	for key in _chain:
		var c: Dictionary = _chain[key]
		if c["t_station"] >= 0:
			lat_station.append((c["t_station"] - c["t_robbery"]) / 60.0)
		if c["t_patrol"] >= 0:
			lat_patrol.append((c["t_patrol"] - c["t_robbery"]) / 60.0)
	print("\n=== LATENCY (game-seconds from robbery to knowing) ===")
	print("  robberies tracked            : %d" % _chain.size())
	print("  reached a station            : %d  (median %s s)" % [lat_station.size(), _median(lat_station)])
	print("  reached a patrol             : %d  (median %s s)" % [lat_patrol.size(), _median(lat_patrol)])

	print("\n=== SWEEP OUTCOMES (motion vs effect) ===")
	print("  sweeps started               : %d" % sweeps_started)
	print("  sweeps that saw a HOSTILE    : %d" % sweeps_with_contact)

	print("\n=== THE FUNNEL (where does it go to zero?) ===")
	print("  1. robberies completed            : %d  (live hulls %d, ledger %d)" % [
		robbery_incidents, takes, ledger_takes])
	print("  2. incidents recorded (all logs)  : %d" % incidents_recorded)
	print("  3. stations holding foreign news  : %d of %d" % [stations_holding_news, stations])
	print("  4. notarized ARMED_ROBBERY warrants: %d" % notarized)
	print("  5. patrols holding foreign news   : %d of %d" % [patrols_holding_news, patrol_like])
	print("  6. patrol lane sweeps STARTED     : %d (peak concurrent %d)" % [sweeps_started, peak_sweeps_seen])
	print("     haulers holding foreign news   : %d of %d" % [haulers_holding_news, NUM_HAULERS])
	print("  (guild LEDGER: takes %d, losses %d, returned_empty %d)" % [
		ledger_takes, guild.losses, guild.returned_empty])
	if ledger_takes != takes:
		print("  !! ledger disagrees with ground truth (%d vs %d) -- the cash-out mis-booking" % [
			ledger_takes, takes])

	# Name the first empty stage rather than leaving a reader to scan the table.
	var stage := ""
	if robbery_incidents == 0 and takes == 0: stage = "1 -- no robbery ever completed, so nothing downstream can be measured"
	elif incidents_recorded == 0: stage = "2 -- robberies happen but no incident is recorded"
	elif stations_holding_news == 0: stage = "3 -- incidents exist but never reach a station"
	elif notarized == 0: stage = "4 -- stations have the news but issue no warrant"
	elif patrols_holding_news == 0: stage = "5 -- patrols never receive the map"
	elif sweeps_started == 0: stage = "6 -- patrols have the map but never act on it"
	if stage != "":
		print("\n  >>> CHAIN BREAKS AT STAGE %s" % stage)
	else:
		print("\n  >>> the chain closed end to end")

	var path := "res://tactical_analysis/data/information_loop.csv"
	SimHarness.append_row(path,
		"sim_minutes,takes,incidents,stations_with_news,stations,notarized,patrols_with_news,patrols,sweeps_started,haulers_with_news",
		"%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			sim_minutes, takes, incidents_recorded, stations_holding_news, stations,
			notarized, patrols_holding_news, patrol_like, sweeps_started, haulers_holding_news])
	print("  wrote ", path)
	get_tree().quit(0)
