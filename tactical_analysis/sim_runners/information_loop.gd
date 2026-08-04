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
const EngagementProbe = preload("res://scripts/instrumentation/engagement_probe.gd")
const LaneProbe = preload("res://scripts/instrumentation/lane_probe.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")
const RiskMap = preload("res://scripts/mail/risk_map.gd")

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
	# SEEDED, like pirate_scenarios. Without this every run draws different
	# pirate arrivals, lurk points and lanes -- and with only 1-2 robberies per
	# game-hour, every funnel stage downstream is measured at n<=2. Comparing
	# two unseeded runs then reports DICE as signal, which is exactly what
	# happened when a patrol-threshold change was "measured" against a run whose
	# patrols never received any news at all.
	#
	# SEED is overridable so a sweep can vary it deliberately: same seed = a
	# true A/B of one variable; different seeds = a sample of the distribution.
	# Both are useful; mixing them silently is not.
	seed(int(_envf("SEED", 20260802.0)))
	sim_minutes = _envf("SIM_MINUTES", 60.0)
	NUM_HAULERS = int(_envf("NUM_HAULERS", 8.0))
	print("=== information_loop: does the chain actually close? (%.0f game-min, %d haulers) ===" % [
		sim_minutes, NUM_HAULERS])
	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)
		# JOB_LOG=1 turns on the pirate job narration. Off by default because a
		# long run drowns in it, but it carries the ONE thing the funnel cannot
		# derive from counters: WHY stage 1 is empty. step_select_victim aborts
		# with two distinct reasons -- "hunt time budget (Ns) spent" (never found
		# prey: an ENCOUNTER problem, fixed by geometry//lurk placement) versus
		# "hunt budget spent (N attempts, nothing taken)" (found prey and could
		# not land it: an EXECUTION problem, fixed by speed/patience/tactics).
		# Those need opposite fixes, and "takes 0" alone cannot tell them apart.
		if _envf("JOB_LOG", 0.0) > 0.0:
			DebugSettings.set_choice("job_log", DebugSettings.JobLog.ON)
	ThreatResponseLeaf.sos_chance = 0.6

	# LANE_RUN=0 disables the lane-transit posture without touching the posture
	# roll, so an A/B changes exactly one thing: whether a false-flag pirate
	# MOVES along its lane or parks on it.
	PirateGuild.lane_run_enabled = _envf("LANE_RUN", 1.0) > 0.0  # D39: ON, matches the shipped default -- the posture exists to raise encounter volume
	var cfg: Dictionary = _guild_config()
	print("    LANE_RUN=%s" % ("on" if PirateGuild.lane_run_enabled else "OFF"))
	print("    pirates: base_cap=%d max_cap=%d arrival=%s hunt=%.0fs | victim_sos=%.2f" % [
		cfg["base_cap"], cfg["max_cap"], str(cfg["arrival_window"]), cfg["hunt_seconds"],
		ThreatResponseLeaf.sos_chance])
	guild = PirateGuild.new(cfg)
	# The TRADE DIRECTOR was missing from every run before now -- only
	# StationEconomy and PirateGuild were installed, so a three-system validation
	# was running with two of the three. Its job here is HAULER REPLACEMENT:
	# without it, pirates thin the fleet over a long run and traffic silently
	# decays, which would quietly suppress the encounter rate the capstone is
	# meant to measure.
	#
	# Its OVERDUE incident publishing stays OFF (TrafficGuild.overdue_incidents_
	# enabled, see M62): that detection polls live nodes with no channel, so it
	# would be an instant cluster-wide news source bypassing the mail network.
	var traffic := TrafficGuild.new()
	manager = SimHarness.build_live_home_cluster(main, [guild, traffic])
	SimHarness.spawn_planner_haulers(manager, NUM_HAULERS)
	clock = SimHarness.Clock.new(SETTLE_MINUTES, sim_minutes)

	# One extra best_route per replan (throttled to 10s per hull) so every
	# routing decision carries its own counterfactual. Sim-only.
	DecisionProbe.enabled = true
	DecisionProbe.reset()
	EngagementProbe.enabled = true
	EngagementProbe.reset()
	LaneProbe.enabled = true
	LaneProbe.reset()

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
		# UNCONDITIONAL heartbeat, once per game-minute. The lane trace is NOT a
		# progress indicator -- it only writes rows when some hauler holds a
		# planner job, so a frozen file is ambiguous between "hung" and "nobody
		# is hauling". This line always prints, so a stalled run is obvious
		# instead of being mistaken for a slow one (2026-08-02: a sim sat one
		# minute from its finish line for 4.5 hours, burning CPU inside a single
		# frame, and nothing said so).
		if clock.frames % 3600 == 0:
			print("[heartbeat] game-minute %d / %d" % [
				clock.frames / 3600, clock.total_frames / 3600])
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
				# Distance to the nearest station AT THE ROBBERY. Without it a
				# latency figure is uninterpretable: a 0.1s "station learned"
				# reads as absurd until you know the victim was inside a
				# station's 30,000u comms envelope, in which case one 15Hz relay
				# tick explains it exactly. Measured, not inferred from
				# constants -- the guild's _R_STATION_AVOID is 25,000, i.e.
				# SMALLER than the radio range it is meant to keep clear of.
				_chain[key] = {"t_robbery": int(e.get("stamp", frame)),
					"t_station": -1, "t_patrol": -1, "t_sweep": -1,
					"src": rec.id, "seq": int(e.get("seq", 0)),
					"station_dist": _nearest_station_dist(e.get("pos", Vector2.ZERO))}
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

func _nearest_station_dist(p: Vector2) -> float:
	var best: float = INF
	for rec in manager.records:
		if _is_station(rec):
			best = minf(best, p.distance_to(rec.pos))
	return best

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
	var lane_risk: Dictionary = {}
	var all_incidents: Array = []
	for rec_i in manager.records:
		for e_i in rec_i.incident_log:
			all_incidents.append(e_i)
	for rec in manager.records:
		var n = rec.live_node
		if n == null or not is_instance_valid(n):
			continue
		var job = n.get("default_job")
		if job == null or not (job is Dictionary) or not job.has("pickup_accept"):
			continue
		var lane := "%s>%s" % [str(job.get("pickup_id", "?")), str(job.get("dropoff_id", "?"))]
		lanes[lane] = int(lanes.get(lane, 0)) + 1
		# TRUE danger on this lane, from every incident that exists -- not from
		# any one hull's heard news. Divergence between this and where the
		# traffic actually goes IS the fog, and is the thing the oscillation
		# claim needs: a lane can be genuinely dangerous while nobody has heard.
		if not lane_risk.has(lane):
			lane_risk[lane] = RiskMap.lane_risk(
				job.get("pickup_pos", Vector2.ZERO), job.get("dropoff_pos", Vector2.ZERO),
				all_incidents, Engine.get_physics_frames())
	for lane in lanes:
		_trace.store_line("%.1f,%s,%d,%.2f" % [minute, lane, lanes[lane], lane_risk.get(lane, 0.0)])
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
	var stations_with_warrant := 0
	var patrol_like := 0
	var patrols_holding_news := 0
	var haulers_holding_news := 0
	var hauler_like := 0

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
				var had: int = notarized
				for wkey in node.warrants:
					var w: Dictionary = node.warrants[wkey]
					if w.get("origin_flag", "") != "" and w.get("offense", "") == Standing.OFF_ARMED_ROBBERY:
						notarized += 1
				if notarized > had:
					stations_with_warrant += 1
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
			elif rec.kind != ClusterEntity.Kind.TRAFFIC:
				# ROCKS AND BEACONS ARE NOT CARGO (2026-08-03, second pass).
				# The first fix this morning corrected the DENOMINATOR MISMATCH
				# ("33 of 14") but kept counting every non-station non-authority
				# RECORD as a civilian hull -- and Kind also covers ASTEROID,
				# BEACON and WORMHOLE. The home cluster has an asteroid field and
				# a beacon road at ~25k spacing, so the "125 civilian hulls" that
				# replaced it was mostly scenery. Real prey is ~14 authored
				# haulers plus TrafficGuild's freighter_target of 2.
				#
				# This matters beyond tidiness: prey DENSITY is the lever for the
				# encounter problem that is currently the whole of criterion (1),
				# and a hull count inflated ~8x hides how thin the target
				# population really is.
				pass
				# (2026-08-03). This read `%d of %d` against NUM_HAULERS and
				# printed "33 of 14" -- because the numerator counts every
				# non-station non-authority RECORD (pirates, guild-spawned
				# traffic, anything the cluster made) while the denominator was
				# the authored hauler count. A ratio whose two halves count
				# different populations is not a ratio, and this one exceeded
				# 100% without anybody noticing for ten runs.
			else:
				hauler_like += 1
				if foreign > 0:
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
	# CALIBRATION NOTE (2026-08-02): HYSTERESIS_MARGIN is the bar a competing
	# route must clear to REPLAN AN EXISTING JOB -- it is NOT the bar for
	# changing which route WINS a fresh search. Two near-equal lanes flip on a
	# few points. A run measured p95 4.6 against margin 60 while the
	# counterfactual showed 250 of 5199 decisions changed, so comparing to the
	# margin gave exactly the wrong verdict. THE COUNTERFACTUAL IS THE DIRECT
	# MEASUREMENT; this line only distinguishes 'risk was literally always zero'
	# (nothing to measure) from 'risk existed' (read the counterfactual).
	if DecisionProbe.total == 0:
		print("  >>> NO DECISIONS OBSERVED -- haulers never replanned; nothing below is measurable")
	elif DecisionProbe.risk_max() <= 0.0:
		print("  >>> RISK WAS ALWAYS ZERO -- the cargo half of M59 is UNTESTED by this run,")
		print("      whatever the traffic did. No robberies fed it. Raise pressure or run longer.")
	else:
		print("  >>> risk was non-zero -- the counterfactual below is the real answer")

	print("\n=== COUNTERFACTUAL: did risk change any decision? ===")
	print("  decisions changed by risk    : %d of %d" % [DecisionProbe.changed_by_risk, DecisionProbe.total])
	print("  flew a KNOWN-risky lane anyway: %d%s" % [DecisionProbe.risked_anyway,
		"" if DecisionProbe.risked_anyway == 0 else "  (mean score %.0f -- the payout that justified it)" % (DecisionProbe.risked_score_sum / DecisionProbe.risked_anyway)])
	# A risk term that only ever makes haulers FLEE is a veto, not a price.
	# Criterion (3) needs both numbers to be non-zero.

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
	print("  reached a station            : %d  (median %s s%s)" % [
		lat_station.size(), _median(lat_station), " -- N=1, NOT a distribution" if lat_station.size() == 1 else ""])
	print("  reached a patrol             : %d  (median %s s%s)" % [
		lat_patrol.size(), _median(lat_patrol), " -- N=1, NOT a distribution" if lat_patrol.size() == 1 else ""])
	# The number that makes a latency figure interpretable at all.
	for key in _chain:
		var cc: Dictionary = _chain[key]
		print("    robbery %s: %.0fu from nearest station (station comms reach 30,000u)" % [
			key, cc.get("station_dist", -1.0)])

	print("\n=== ENGAGEMENTS (did a patrol STOP anything?) ===")
	print("  interdictions started        : %d" % EngagementProbe.started)
	print("  subject COMPLIED (stopped)   : %d" % EngagementProbe.complied)
	print("  refused (patience expired)   : %d" % EngagementProbe.refused)
	print("  outpaced the patrol          : %d" % EngagementProbe.outpaced)
	var sr: float = EngagementProbe.stop_rate()
	print("  stop rate                    : %s" % ("n/a -- none attempted" if sr < 0.0 else "%.0f%%" % (sr * 100.0)))
	# BY TIER, because the aggregate above cannot tell enforcement from
	# harassment (2026-08-03). Interdiction fires at CAUTION as well as HOSTILE,
	# and a CAUTION subject is usually an innocent hull that failed to answer an
	# ID challenge. The run that forced this split read 4 stops against ~2 hulks
	# and 2 guild losses -- so at most half of it was pirates, and the single
	# number said nothing about which half. Criterion (4) asks about stopping
	# PIRATES, which is a claim about the HOSTILE line below, not the blend.
	for tier in EngagementProbe.tiers_seen():
		var t_start: int = int(EngagementProbe.started_by_tier.get(tier, 0))
		var t_comp: int = int(EngagementProbe.complied_by_tier.get(tier, 0))
		var t_ref: int = int(EngagementProbe.refused_by_tier.get(tier, 0))
		var t_out: int = int(EngagementProbe.outpaced_by_tier.get(tier, 0))
		var t_sr: float = EngagementProbe.stop_rate_for(tier)
		print("    tier %-8s : started %d, complied %d, refused %d, outpaced %d -- stop rate %s" % [
			tier, t_start, t_comp, t_ref, t_out,
			("n/a" if t_sr < 0.0 else "%.0f%%" % (t_sr * 100.0))])
	# A tier line whose starts and outcomes disagree is not a bug in the counters:
	# the outcome hooks fire for any job carrying `interdict_tier`, including jobs
	# assembled outside InterdictLeaf, and an interdiction still in flight when
	# the run ends is a start with no outcome at all.
	# WHERE the demand opened, relative to the range it must be held inside.
	# A 1v1 trace (pursuit_trace.gd) showed the patrol out-accelerating the
	# pirate 115.6 vs 79.8 u/s^2 and closing a 2500u gap to ~600u repeatedly --
	# so "outpaced" is not a propulsion deficit, and this is the number that
	# can say what it actually is.
	var og: Dictionary = EngagementProbe.opening_summary()
	if not og.is_empty():
		print("  demand OPENED at sep/hail    : median %.2f, max %.2f (n=%d)" % [
			og["median"], og["max"], og["n"]])
		print("    already past the 1.2x line : %d of %d -- doomed before the chase began" % [
			og["born_outpaced"], og["n"]])

	print("\n=== SWEEP OUTCOMES (motion vs effect) ===")
	print("  sweeps started               : %d" % sweeps_started)
	print("  sweeps that saw a HOSTILE    : %d" % sweeps_with_contact)

	print("\n=== THE FUNNEL (where does it go to zero?) ===")
	print("  1. robberies completed            : %d  (live hulls %d, ledger %d)" % [
		robbery_incidents, takes, ledger_takes])
	print("  2. incidents recorded (all logs)  : %d" % incidents_recorded)
	print("  3. stations holding foreign news  : %d of %d" % [stations_holding_news, stations])
	# SUMMED ACROSS STATIONS, and the label has to say so (2026-08-03). Each
	# authority issues its OWN warrant on the same subject, so 2 robberies
	# legitimately reads 10 -- one verdict held at five ports, not ten
	# prosecutions. That is correct behaviour and a misleading number; the first
	# D29 run would otherwise have read as a 5x over-count of its own robberies.
	# `stations_with_warrant` is the honest denominator-free version.
	print("  4. notarized ARMED_ROBBERY warrants: %d (summed over %d of %d stations holding one)" % [
		notarized, stations_with_warrant, stations])
	print("  5. patrols holding foreign news   : %d of %d" % [patrols_holding_news, patrol_like])
	print("  6. patrol lane sweeps STARTED     : %d (peak concurrent %d)" % [sweeps_started, peak_sweeps_seen])
	print("     haulers holding foreign news   : %d of %d civilian hulls (%d authored)" % [haulers_holding_news, hauler_like, NUM_HAULERS])
	print("  (guild LEDGER: takes %d, losses %d, returned_empty %d)" % [
		ledger_takes, guild.losses, guild.returned_empty])
	if ledger_takes != takes:
		print("  !! ledger disagrees with ground truth (%d vs %d) -- the cash-out mis-booking" % [
			ledger_takes, takes])

	# TWO BRANCHES, NOT ONE CHAIN (corrected 2026-08-02). An earlier version
	# walked stages 1-6 linearly and reported the first zero, which called a
	# healthy run broken: notarization read 0 while patrols were informed 2/2
	# and 23 sweeps had fired. Notarization is NOT on the path to a sweep.
	#
	# This is D1's verdict/evidence split surfacing in the instrument:
	#   EVIDENCE  incident -> stations -> patrols -> sweeps   (mailbags)
	#   VERDICT   incident -> notarized warrant               (warrant store)
	# They share a root and then diverge. A zero on one says nothing about the
	# other, and collapsing them into one ladder misattributes the failure.
	var ev := ""
	if robbery_incidents == 0 and takes == 0:
		ev = "no robbery ever completed -- nothing downstream is measurable"
	elif incidents_recorded == 0:
		ev = "robberies happen but no incident is recorded"
	elif stations_holding_news == 0:
		ev = "incidents exist but never reach a station"
	elif patrols_holding_news == 0:
		ev = "stations know but patrols never receive the map"
	elif sweeps_started == 0:
		ev = "patrols hold the map but never act on it"

	var vd := ""
	if incidents_recorded == 0:
		vd = "no incident to notarize"
	elif notarized == 0:
		vd = "stations have the news but issue no warrant (EXPECTED when the pirate ran dark -- an authority cannot charge an unidentified hull)"

	print("
=== WHERE EACH BRANCH STANDS ===")
	_report_economy()
	_report_lanes()
	print("  EVIDENCE (incident -> stations -> patrols -> sweeps): %s" % (
		"CLOSED end to end" if ev == "" else "breaks -- " + ev))
	print("  VERDICT  (incident -> notarized warrant)            : %s" % (
		"CLOSED end to end" if vd == "" else "breaks -- " + vd))
	# Kept for instruments that grep it, but now reports the EVIDENCE branch
	# only, which is the one a sweep depends on.
	if ev != "":
		print("
  >>> CHAIN BREAKS AT STAGE %d -- %s" % [
			1 if (robbery_incidents == 0 and takes == 0) else
			(2 if incidents_recorded == 0 else
			(3 if stations_holding_news == 0 else
			(5 if patrols_holding_news == 0 else 6))), ev])
	else:
		print("
  >>> the evidence chain closed end to end")

	var path := "res://tactical_analysis/data/information_loop.csv"
	SimHarness.append_row(path,
		"sim_minutes,takes,incidents,stations_with_news,stations,notarized,patrols_with_news,patrols,sweeps_started,haulers_with_news",
		"%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			sim_minutes, takes, incidents_recorded, stations_holding_news, stations,
			notarized, patrols_holding_news, patrol_like, sweeps_started, haulers_holding_news])
	print("  wrote ", path)
	get_tree().quit(0)

# THE THIRD SYSTEM, WHICH THIS RUNNER HAS NEVER REPORTED ON (2026-08-03).
#
# The goal is "a long economy sim showing all THREE playing together", and this
# funnel measured two of them. A long run could have shown piracy working and
# patrols working while the economy quietly starved behind it, and the report
# would have read as success -- the same failure shape as every instrument bug
# found today, just with a whole subsystem missing rather than a wrong number.
#
# DELIBERATELY LESS THAN economy_traffic's VERDICT, and labelled so. That
# runner's SERVED/UNSERVED/UNDERSUPPLIED/OVER_EXPORTED/REPAIR_DRAIN attribution
# needs per-minute flow accounting this runner does not keep, and porting it
# would be the duplication that has already bitten once today (two copies of the
# force-authorization rule disagreeing). What IS computable from end state is
# the one verdict economy_traffic checks FIRST and calls the case where "net
# flow reads HEALTHY while the station is dead":
#
#   STARVED -- the station wants a commodity, cannot make it itself, and its bin
#              is at the floor. Consumption has already stopped.
#
# So this answers "did the economy survive" and explicitly not "was it served
# well". A clean line here does NOT mean economy_traffic would pass.
func _report_economy() -> void:
	var starved: Array = []
	var watched: int = 0
	for rec in manager.records:
		if not _is_station(rec):
			continue
		var self_bins: Dictionary = rec.stocks.get("self", {})
		for c in self_bins:
			if not _wants(rec, c) or _makes(rec, c):
				continue
			watched += 1
			var bin: Dictionary = self_bins[c]
			var target: float = float(bin.get("target", 0.0))
			if target <= 0.0:
				continue
			var stock: float = float(bin.get("stock", 0.0))
			# Same 2% floor economy_traffic uses for `starved`.
			if stock <= target * 0.02:
				starved.append("%s/%s" % [rec.name, c])
	print("")
	print("=== ECONOMY (did the third system survive?) ===")
	print("  imported bins watched        : %d (station wants it, cannot make it)" % watched)
	if watched == 0:
		print("  >>> NOTHING WATCHED -- no station imports anything, so this says nothing")
		return
	if starved.is_empty():
		print("  starved bins                 : 0")
		print("  >>> no imported bin hit the floor. NOT a SERVED verdict -- this")
		print("      runner does not track flow rates; run economy_traffic for that.")
	else:
		print("  starved bins                 : %d of %d" % [starved.size(), watched])
		for k in starved:
			print("      STARVED %s" % k)
		print("  >>> a starved bin means consumption has ALREADY stopped there.")

func _wants(rec, commodity: String) -> bool:
	if rec.industry.get("sinks", {}).get(commodity, 0.0) > 0.0:
		return true
	for conv in rec.industry.get("converters", []):
		if conv.get("in", {}).get(commodity, 0.0) > 0.0:
			return true
	return false

func _makes(rec, commodity: String) -> bool:
	if rec.industry.get("sources", {}).get(commodity, 0.0) > 0.0:
		return true
	for conv in rec.industry.get("converters", []):
		if conv.get("out", {}).get(commodity, 0.0) > 0.0:
			return true
	return false

# DO PIRATES SIT WHERE CARGO ACTUALLY FLIES? (2026-08-03)
#
# The encounter model predicted ~79% of hunts should see prey (1e12 u^2 bounds,
# 45,000u passive array, 14 haulers at ~700u/s, 900s hunt). Measured: 163 empty
# hunts against 3 contested, under 2%. A 40x miss is a wrong ASSUMPTION, not a
# tuning gap, and the suspect one is uniformity -- cargo flies the lanes that
# pay, while `_random_hub_pair` samples station pairs evenly.
#
# This table tests that instead of asserting it, and it needs no long run:
# robberies are rare but lane CHOICE is sampled every hauler replan and every
# pirate arrival, so the two distributions converge in game-minutes.
#
# Read `efficiency` first. `overlap` alone is uninterpretable -- a cluster where
# cargo itself is spread thin has a low ceiling no targeting rule could beat --
# which is the same defect the "RISK WAS ALWAYS ZERO" banner had.
func _report_lanes() -> void:
	print("")
	print("=== LANES (do pirates sit where cargo flies?) ===")
	var og: Dictionary = LaneProbe.overlap_summary()
	if og.is_empty():
		print("  >>> NO SAMPLES on one side -- cargo %d lanes, pirate %d lanes." % [
			LaneProbe.cargo_picks.size(), LaneProbe.pirate_picks.size()])
		print("      Says nothing about targeting; it says the probe saw nothing.")
		return
	print("  cargo used %d lanes, pirates chose %d" % [og["cargo_lanes"], og["pirate_lanes"]])
	print("  overlap    : %.4f  (P a random pirate-second and cargo-second share a lane)" % og["overlap"])
	print("  ceiling    : %.4f  (same, if pirates distributed EXACTLY like cargo)" % og["best"])
	print("  efficiency : %.2f  (1.00 = already optimal, 0.10 = watching empty roads)" % og["efficiency"])
	if LaneProbe.pirate_unresolved > 0:
		# Not folded into the table on purpose: APPROACH_RING and the
		# wormhole-anchored fallbacks produce segments whose ends are not two
		# stations, and bucketing those would invent lanes that do not exist.
		print("  (%d pirate picks had no two-station lane -- ring/wormhole postures)" % LaneProbe.pirate_unresolved)
	# DID CARGO SIMPLY LEAVE? Cargo presence on the pirate's chosen lane in the 3
	# game-minutes BEFORE it committed, against the 3 after. A ratio well under
	# 1.0 means traffic drained away from under the pirate -- which would make
	# "pirates find no prey" partly the RISK SYSTEM WORKING rather than a
	# targeting failure, and would matter because a hunt job commits to one lane,
	# so a pirate cannot follow the traffic it just scared off.
	#
	# READ THE PRECONDITION WITH IT: cargo can only avoid what it has HEARD, and
	# that needs a completed robbery plus a courier. Most hunts take nothing, so
	# most lanes here have nothing to avoid and a ratio near 1.0 is the EXPECTED
	# null, not evidence of bravery.
	var av: Dictionary = LaneProbe.avoidance_summary()
	if av.is_empty():
		print("  avoidance    : no hunt landed on a lane cargo ever used -- nothing to compare")
	else:
		print("  avoidance    : cargo-samples before %d / during %d -> ratio %.2f (%d of %d hunts scored)" % [
			av["before"], av["during"], av["ratio"], av["hunts_scored"], av["hunts_total"]])
		print("                 (<1.0 = traffic drained off the lane the pirate picked)")
	print("")
	print("  lane                                     cargo%   pirate%   (n cargo / n pirate)")
	for row in LaneProbe.table():
		print("  %-38s %6.1f    %6.1f    (%d / %d)" % [
			row["lane"], row["cargo"] * 100.0, row["pirate"] * 100.0,
			row["cargo_n"], row["pirate_n"]])
