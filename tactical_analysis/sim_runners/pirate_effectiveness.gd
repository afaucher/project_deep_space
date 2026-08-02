extends Node

# Does a pirate targeting strategy actually CATCH anything?
#
# test_pirate_targeting.gd is the cheap geometric screen -- it says a hunt
# point is well spread, survivable and plausible. It cannot say whether a
# pirate sitting there ever meets a hauler, and "pirates are not very
# successful" is a claim about outcomes, not geometry. This is the outcome
# instrument.
#
# It needs no new bookkeeping: PirateGuild already keeps the exact ledger --
# takes_total, losses, returned_empty, plus the streaks, cap and profitability
# backoff the guild steers itself on. All this runner does is put real
# planner-driven haulers and the authored patrols in front of it and read the
# counters.
#
# ONE STRATEGY PER RUN, chosen by the PIRATE_STRATEGY environment variable
# (STATION_CHORD | APPROACH_RING | CROSSROADS). Deliberately not a three-phase
# loop in one process: tearing a live cluster down and rebuilding it mid-run
# risks static state bleeding between phases (Standing/Hail registries,
# steering's frame caches), and a contaminated comparison is worse than none.
# Each run APPENDS a row, so three invocations build the table.
#
#   $env:PIRATE_STRATEGY="CROSSROADS"
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 \
#       --run-tactical-sim pirate_effectiveness
#
# Each arm writes its OWN CSV, so the three can run concurrently and be merged
# afterwards. Guild config is campaign-real (see GUILD_CONFIG), so at the
# default horizon these numbers describe the actual game, not a compressed
# proxy for it.

const SimHarness = preload("res://tactical_analysis/sim_runners/sim_harness.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const ThreatResponseLeaf = preload("res://scripts/ai/leaves/threat_response_leaf.gd")

# Hours, not minutes. A single interception is a multi-minute affair -- transit
# to the hunting ground, lurk for a victim, intercept, demand, hold alongside,
# exfil -- and the guild's own arrival window is 2-5 minutes on top. A
# 25-minute window sees a handful of cycles, which is noise, not a rate. Same
# lesson the economy sim learned at 30 vs 180 minutes.
#
# Override for a smoke test: $env:SIM_MINUTES="1"
const DEFAULT_SIM_MINUTES := 180.0
const SETTLE_MINUTES := 3.0
const NUM_HAULERS := 8

# CAMPAIGN-REAL, deliberately. An earlier version compressed the arrival window
# to 25-55s and raised the cap to 3-6 so a 25-minute run produced a usable
# sample -- legitimate for a relative comparison, but it meant absolute takes
# said nothing about the actual game. At a 3-hour horizon the real 120-300s
# window yields dozens of arrivals on its own, so the compression buys nothing
# and costs realism. Empty = PirateGuild.DEFAULT_CONFIG untouched.
const GUILD_CONFIG := {}

# Hunt budget sweep (2026-08-01). The default 150s was measured to be shorter
# than the cluster's own timescale -- a hauler round trip is ~900s and the
# pirate can see 13% of a lane -- so this exists to test that diagnosis
# directly rather than argue about it. $env:PIRATE_HUNT_SECONDS="900"
# Generic env float, for the tradecraft sweep below.
static func _envf(key: String, dflt: float) -> float:
	var raw: String = OS.get_environment(key).strip_edges()
	return float(raw) if raw.is_valid_float() else dflt

static func _hunt_seconds() -> float:
	var raw: String = OS.get_environment("PIRATE_HUNT_SECONDS").strip_edges()
	if raw.is_valid_float() and float(raw) > 0.0:
		return float(raw)
	return 150.0

# Per-strategy path so the three arms can run CONCURRENTLY without racing each
# other's appends -- three processes appending to one file interleave rows and
# can lose a header. Merge afterwards.
const CSV_DIR := "res://tactical_analysis/data/"
const CSV_HEADER := "strategy,sim_minutes,haulers,members,takes,losses,returned_empty,resolved,takes_per_hour,take_rate,loss_rate,final_cap,backoff"

var manager
var guild
var clock
var strategy_label: String = "CROSSROADS"
var sim_minutes: float = DEFAULT_SIM_MINUTES

func _sim_minutes_from_env() -> float:
	var raw: String = OS.get_environment("SIM_MINUTES").strip_edges()
	if raw.is_valid_float() and raw.to_float() > 0.0:
		return raw.to_float()
	return DEFAULT_SIM_MINUTES

func _strategy_from_env() -> int:
	match OS.get_environment("PIRATE_STRATEGY").strip_edges().to_upper():
		"STATION_CHORD":
			strategy_label = "STATION_CHORD"
			return PirateGuild.HuntStrategy.STATION_CHORD
		"APPROACH_RING":
			strategy_label = "APPROACH_RING"
			return PirateGuild.HuntStrategy.APPROACH_RING
		_:
			strategy_label = "CROSSROADS"
			return PirateGuild.HuntStrategy.CROSSROADS

func setup(main) -> void:
	PirateGuild.hunt_strategy = _strategy_from_env()
	sim_minutes = _sim_minutes_from_env()
	print("=== pirate_effectiveness: strategy=%s, %.0f game-min, %d haulers ===" % [
		strategy_label, sim_minutes, NUM_HAULERS])

	if DebugSettings:
		DebugSettings.set_choice("station_economy_log", DebugSettings.StationEconomyLog.OFF)

	var cfg: Dictionary = GUILD_CONFIG.duplicate(true)
	cfg["hunt_seconds"] = _hunt_seconds()
	cfg["colors_chance"] = _envf("PIRATE_COLORS_CHANCE", 1.0)
	cfg["sos_reprisal_chance"] = _envf("PIRATE_SOS_REPRISAL", 0.0)
	ThreatResponseLeaf.sos_chance = _envf("VICTIM_SOS_CHANCE", 1.0)
	print("    hunt=%.0fs colors_chance=%.2f sos_reprisal=%.2f victim_sos_chance=%.2f" % [
		cfg["hunt_seconds"], cfg["colors_chance"], cfg["sos_reprisal_chance"],
		ThreatResponseLeaf.sos_chance])
	guild = PirateGuild.new(cfg)
	manager = SimHarness.build_live_home_cluster(main, [guild])
	SimHarness.spawn_planner_haulers(manager, NUM_HAULERS)
	clock = SimHarness.Clock.new(SETTLE_MINUTES, sim_minutes)

const TRACE_PERIOD_FRAMES := 1800   # 30 game-seconds

# Where is a stalled member actually stuck? Two strategies produced one member
# that stayed ACTIVE for three game-hours, and the first explanation on offer
# ("never reached its staging point") does not survive arithmetic: transit runs
# lit at 700 u/s and the widest hub-to-hub chord is ~12 minutes. So dump the
# thing that settles it -- job step index, distance to target, and whether the
# hull is actually MOVING. A pirate at v=0 in step 0 is a stuck job; a pirate
# at v=700 in step 0 for an hour is a target it can never reach; a pirate
# oscillating is steering.
func _trace_members() -> void:
	for rid in guild.members:
		var m: Dictionary = guild.members[rid]
		if m.get("state", -1) != PirateGuild.MemberState.ACTIVE:
			continue
		var rec = null
		for r in manager.records:
			if r.id == rid:
				rec = r
				break
		if rec == null:
			print("[TRACE] member %d ACTIVE but no record" % rid)
			continue
		var node = rec.live_node if rec.get("live_node") != null else null
		if node == null or not is_instance_valid(node):
			print("[TRACE] member %d ACTIVE, record present, NOT PROMOTED (no live node)" % rid)
			continue
		var job: Dictionary = node.assignment if node.get("assignment") != null else {}
		var step_idx: int = job.get("current", -1)
		var steps: Array = job.get("steps", [])
		var verb: String = steps[step_idx].get("verb", "?") if step_idx >= 0 and step_idx < steps.size() else "?"
		var target = steps[step_idx].get("pos", null) if verb == "GO_TO" and step_idx < steps.size() else null
		var dist: float = node.position.distance_to(target) if target is Vector2 else -1.0
		print("[TRACE] member %d step %d/%d %s  pos=%s  speed=%.0f  dist_to_target=%.0f" % [
			rid, step_idx, steps.size(), verb, str(node.position.round()),
			node.linear_velocity.length(), dist])

func _physics_process(_delta: float) -> void:
	if clock.frames % TRACE_PERIOD_FRAMES == 0:
		_trace_members()
	match clock.advance(manager):
		"measure_start":
			# Zero at the stopwatch start: promotion produces a burst of
			# collision damage and early churn unrelated to hunting.
			guild.takes_total = 0
			guild.losses = 0
			guild.returned_empty = 0
			print("--- settle closed; measuring %.0f game-min ---" % sim_minutes)
		"done":
			_finish()

func _finish() -> void:
	var takes: int = guild.takes_total
	var losses: int = guild.losses
	var empty: int = guild.returned_empty
	var resolved: int = takes + losses + empty
	var hours: float = sim_minutes / 60.0

	# What must be non-zero for any of the numbers below to mean anything.
	# `members` is the one that matters most: it separates "no pirate
	# succeeded" from "no pirate existed", and the first version of this file
	# could not tell those apart -- it reported a clean, confident zero while
	# the cluster clock was never being driven at all.
	var live: Dictionary = SimHarness.liveness({
		"pirates spawned": guild.members.size(),
		"cycles resolved": resolved,
	})

	print("\n=== %s over %.0f game-min ===" % [strategy_label, sim_minutes])
	SimHarness.print_liveness(live)
	print("  members         %d spawned, %d arrivals pending" % [guild.members.size(), guild.arrivals.size()])
	print("  member states   %s" % str(_state_histogram()))
	print("  takes           %d" % takes)
	print("  losses          %d" % losses)
	print("  returned empty  %d" % empty)
	print("  resolved        %d" % resolved)
	if resolved > 0:
		print("  take rate       %.0f%%" % (100.0 * float(takes) / float(resolved)))
		print("  loss rate       %.0f%%" % (100.0 * float(losses) / float(resolved)))
	print("  final cap       %d (backoff x%.1f)" % [guild.cap, guild.backoff_factor])

	var csv_path: String = "%spirate_effectiveness_%s.csv" % [CSV_DIR, strategy_label.to_lower()]
	SimHarness.append_row(csv_path, CSV_HEADER, "%s,%.0f,%d,%d,%d,%d,%d,%d,%.2f,%.3f,%.3f,%d,%.2f" % [
		strategy_label, sim_minutes, NUM_HAULERS, guild.members.size(),
		takes, losses, empty, resolved,
		float(takes) / hours,
		(float(takes) / float(resolved)) if resolved > 0 else 0.0,
		(float(losses) / float(resolved)) if resolved > 0 else 0.0,
		guild.cap, guild.backoff_factor])
	print("\nAppended to %s" % csv_path)
	get_tree().quit(0)

func _state_histogram() -> Dictionary:
	var names := {
		PirateGuild.MemberState.SCHEDULED: "SCHEDULED",
		PirateGuild.MemberState.ACTIVE: "ACTIVE",
		PirateGuild.MemberState.OVERDUE: "OVERDUE",
		PirateGuild.MemberState.LOST: "LOST",
		PirateGuild.MemberState.CASHED_OUT: "CASHED_OUT",
		PirateGuild.MemberState.RETURNED_EMPTY: "RETURNED_EMPTY",
	}
	var hist: Dictionary = {}
	for rid in guild.members:
		var key: String = names.get(guild.members[rid].get("state", -1), "UNKNOWN")
		hist[key] = hist.get(key, 0) + 1
	return hist
