extends Node

# Autoload singleton: DebugSettings
# ----------------------------------
# Global debug knobs, deliberately the SIMPLEST possible thing. Game code reads these
# directly (e.g. DebugSettings.get_choice("missile_cleanup")) instead of routing a
# selection through the host/client packet -- so flipping a menu item on the local
# terminal changes host-side behavior immediately. This breaks the networking
# abstraction on purpose: it's a sandbox debug surface, not authoritative state. If a
# knob ever needs to be correct across a real multiplayer session, promote it out of
# here; until then, ease of adding new toggles wins.
#
# TO ADD A NEW DEBUG SELECTION: append one entry to OPTIONS. The top-bar "Debug" menu
# builds itself from this registry (see terminal_display._build_debug_menu), and any
# code anywhere can read it with get_choice("your_key"). No UI wiring needed.

signal changed(key: String, value: int)

# Stable indices for the "missile_cleanup" choices, so host code reads named values
# instead of magic ints. Order MUST match the "choices" array below.
enum MissileCleanup { OFF, ALL, VISIBLE, DISPROVAL }

# How a sensor bin holding more than one object collapses to a single blip.
# BLEND (current): max heat/EM, summed cross-section, largest object owns the id --
#   lets a hot enemy's signature bleed onto a co-bearing asteroid ("signature bleed").
# NEAREST: keep only the nearest object's clean signature+id; farther objects are
#   shadowed and their tracks dead-reckon, so neither identity is ever corrupted.
enum SignatureMerge { BLEND, NEAREST }

# Missile terminal evasion. OFF = fly straight at the intercept (current). ON = weave
# the steering aim by a random offset (re-rolled a few times a second) so the PD firing
# solution, built on the missile's tracked heading, keeps going stale. A survivability
# lever vs. overkill-buffed PD -- see warhead_laser_special_case.md.
enum MissileJink { OFF, ON }

# M28 -- kinetic collision damage on/off (playtesting knob + negative-control
# test lever). Default ON: the speed threshold is the real gate; this knob
# exists to let the effect be disabled outright, not to relax the threshold.
enum CollisionDamage { ON, OFF }

# Sensor-dot contact outlines (M26). Default OFF for now: the close-range dot
# sampler is a per-frame ray-vs-AABB over the target's components for every
# subtended bin, per sensor, per ship -- it does not yet scale, so we fall back
# to the authoritative cached silhouette for every contact. Flip ON to re-enable
# the measured-dot outline (bin-capped, but still the heavier path).
enum SensorDotOutlines { OFF, ON }

# M45 -- physics tick perf investigation bisection knobs. Each gates a whole
# subsystem OFF so the baseline harness (test_perf_baseline) can be re-run
# with one subsystem removed and diff the total physics-step cost against the
# PerfProbe tag total for that subsystem -- two independent attributions
# (probe table + bisection delta) instead of trusting the probe alone.
# Default ON (=0) everywhere: normal gameplay/tests are unaffected unless a
# harness explicitly flips one OFF for isolation.
enum PerfSubsystem { ON, OFF }

# M51 -- the pirate guild director's whole player-facing footprint (design
# doc: "an invisible hand"). Default OFF; ON prints one line per policy pass
# (counts by state, cap, streaks, pending etas) -- see scripts/directors/
# pirate_guild.gd's _log().
enum PirateGuildLog { OFF, ON }

# M51 follow-up -- job-runner step transitions (scripts/ai/jobs/
# job_runner_leaf.gd). ON prints one line per DONE/ABORT/complete for every
# ship running a job -- the console view of an otherwise-invisible pirate
# hunt (GO_DARK, victim selected, demand, take, exfil, relight...). Pairs
# with pirate_guild_log for the full career: guild events + job milestones.
enum JobLog { OFF, ON }

# M52 dev convenience -- "pirate overdrive" (pirate_guild.gd). Playtesting
# M52's demand/robbery/interdiction loop end to end means waiting out the
# real cap-ramp (streak-gated, +/-1 per policy pass) and arrival pacing
# (2-5 MINUTES between spawns by default) -- ON bypasses both: cap jumps
# straight to a high fixed value and arrivals roll every 8-20s instead.
# Read directly by pirate_guild.gd (same "flip a menu item, host behavior
# changes immediately" convention this file's header describes), a sandbox
# debug surface, not authoritative state.
enum PirateOverdrive { OFF, ON }

# M53b -- the traffic guild director's whole player-facing footprint (mirrors
# pirate_guild_log below). Default ON; ON prints one line per policy pass
# (population-floor haulers by state, transient freighters by state, pending
# etas, losses/replenishments) -- see scripts/directors/traffic_guild.gd's
# _log().
enum TrafficGuildLog { OFF, ON }

# M53c Phase A -- the station economy director's log (mirrors TrafficGuildLog
# above). Default ON; ON prints one line per station per economy pass whose
# converters aren't all RUNNING (STARVED/BLOCKED is the interesting news --
# see scripts/directors/station_economy.gd's _log()).
enum StationEconomyLog { OFF, ON }

# M53c Phase C -- the ship-side route planner's search diagnostic (route_
# planner.gd's best_route()). Default OFF, unlike the two director logs
# above: this fires from EVERY ship's re-plan leaf, every REPLAN_CHECK_
# INTERVAL, so ON would spam any gate run with real traffic -- it exists for
# exactly one job, diagnosing "why did the planner find nothing," and gets
# flipped on for a short targeted sim/test run, never left on. Prints one
# line per best_route() call: how many EXPORT/IMPORT postings existed at all
# (open, before eligibility), how many of those this ship was ELIGIBLE for,
# how many pickup/dropoff pairs scored at all, and the winning candidate (or
# NONE) -- the four questions "is anything open," "am I locked out of it,"
# "did anything pair up," and "was the pair even worth it" collapsed into one
# line instead of four separate greps.
enum RoutePlannerLog { OFF, ON }

# key -> { label, choices (display strings, index == stored value), default }
const OPTIONS := {
	"missile_cleanup": {
		"label": "Missile contact cleanup",
		"choices": [
			"Off (20s dead-reckon timeout)",   # OFF      -- current shipped behavior
			"Purge all immediately",           # ALL      -- Option 1
			"Purge only if visible",           # VISIBLE  -- Option 2
			"Trace disproval (WIP)",           # DISPROVAL-- Option 3 (placeholder, see decay loop)
		],
		"default": MissileCleanup.ALL,
	},
	"signature_merge": {
		"label": "Co-bearing bin merge",
		"choices": [
			"Blend (max heat/EM, sum CS)",     # BLEND   -- old behavior; bleeds signatures
			"Nearest-wins (no bleed)",         # NEAREST -- shadow farther objects
		],
		"default": SignatureMerge.NEAREST,
	},
	"missile_jink": {
		"label": "Missile evasive jink",
		"choices": [
			"Off (fly straight)",              # OFF -- current behavior
			"On (weave to spoil PD)",          # ON  -- terminal evasion
		],
		"default": MissileJink.OFF,
	},
	"collision_damage": {
		"label": "Kinetic collision damage",
		"choices": [
			"On (speed-gated kinetic damage)", # ON  -- current behavior
			"Off (no contact damage)",         # OFF -- playtesting / negative control
		],
		"default": CollisionDamage.ON,
	},
	"sensor_dot_outlines": {
		"label": "Sensor-dot contact outlines",
		"choices": [
			"Off (authoritative silhouette for all)", # OFF -- current fallback
			"On (measured dots for unidentified)",     # ON  -- the M26 dot sampler
		],
		"default": SensorDotOutlines.OFF,
	},
	"perf_sensors": {
		"label": "M45 bisect: sensor sweeps",
		"choices": [
			"On (default)",
			"Off (skip sensor timer/sweep -- perf isolation only)",
		],
		"default": PerfSubsystem.ON,
	},
	"perf_ai": {
		"label": "M45 bisect: AI tree tick",
		"choices": [
			"On (default)",
			"Off (skip Beehave tree tick -- perf isolation only)",
		],
		"default": PerfSubsystem.ON,
	},
	"perf_eng_log": {
		"label": "M45 bisect: eng-log crossings",
		"choices": [
			"On (default)",
			"Off (skip _check_eng_log_crossings -- perf isolation only)",
		],
		"default": PerfSubsystem.ON,
	},
	# M45c -- PD kill-wave spike bisection. Isolates hypothesis 1 (execute_fire's
	# per-shot intersect_shape physics query) from hypothesis 2 (the pd_assign
	# outer-while loop's own iteration shape) so each can be measured
	# independently via perf_combat.gd. Perf isolation only -- OFF states are
	# not fairness-safe (see ship.gd call sites) and must never ship as the
	# default.
	"perf_pd_hit_query": {
		"label": "M45c bisect: PD execute_fire intersect_shape query",
		"choices": [
			"On (default)",
			"Off (skip the query, resolve hit against tracked contact directly -- perf isolation only)",
		],
		"default": PerfSubsystem.ON,
	},
	"perf_pd_multi_pass": {
		"label": "M45c bisect: PD assignment multi-pass concentration",
		"choices": [
			"On (default)",
			"Off (cap the outer while loop to a single pass -- perf isolation only, breaks concentration fairness)",
		],
		"default": PerfSubsystem.ON,
	},
	# Both pirate logs default ON (M52a): the console is omniscient by
	# declaration -- developer visibility, not guild knowledge -- and the
	# zero-takes campaign loop was invisible until these were flipped on.
	"pirate_guild_log": {
		"label": "Pirate guild director log",
		"choices": [
			"Off",
			"On (default -- one line per policy pass)",
		],
		"default": PirateGuildLog.ON,
	},
	"job_log": {
		"label": "AI job step log",
		"choices": [
			"Off",
			"On (default -- one line per job step transition)",
		],
		"default": JobLog.ON,
	},
	"pirate_overdrive": {
		"label": "Pirate overdrive (dev)",
		"choices": [
			"Off (normal cap ramp + 2-5min arrivals)",
			"On (cap maxed, arrivals every 8-20s)",
		],
		"default": PirateOverdrive.OFF,
	},
	"traffic_guild_log": {
		"label": "Traffic guild director log",
		"choices": [
			"Off",
			"On (default -- one line per policy pass)",
		],
		"default": TrafficGuildLog.ON,
	},
	"station_economy_log": {
		"label": "Station economy director log",
		"choices": [
			"Off",
			"On (default -- one line per STARVED/BLOCKED converter)",
		],
		"default": StationEconomyLog.ON,
	},
	"route_planner_log": {
		"label": "Route planner search diagnostic",
		"choices": [
			"Off (default -- fires from every ship, spams a real run)",
			"On (one line per best_route() call: postings/eligibility/best candidate)",
		],
		"default": RoutePlannerLog.OFF,
	},
}

var _values := {}

func _ready() -> void:
	for key in OPTIONS:
		_values[key] = OPTIONS[key]["default"]

func get_choice(key: String) -> int:
	# The one-liner this replaces was `_values.get(key, OPTIONS.get(key, {}).get("default", 0))`,
	# which reads as a cheap lookup with a fallback but is not: GDScript evaluates
	# the default argument EAGERLY, so every call paid three dictionary lookups
	# AND allocated a throwaway `{}` -- even on the hit path where the fallback is
	# discarded. This is read per-ship-per-frame from hot gates (ship.gd's sensor
	# block, the signature-merge mode inside every sweep), so the allocation was
	# happening tens of times a frame to produce nothing.
	if _values.has(key):
		return _values[key]
	var opt: Dictionary = OPTIONS.get(key, {})
	return opt.get("default", 0)

func set_choice(key: String, value: int) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key, value)
