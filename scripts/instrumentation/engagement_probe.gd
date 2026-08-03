extends RefCounted

# Did a patrol actually STOP anything? OFF by default; a sim turns it on.
#
# WHY THIS EXISTS. The funnel counts "sweeps that saw a HOSTILE" -- 20 in one
# seed -- which says a patrol got within sensor range of something it considered
# hostile. It says NOTHING about whether a demand was issued, whether the
# subject complied, fled, or outran the patrol. Those are different outcomes and
# the goal's fourth criterion ("stopping some pirates") is a claim about
# outcomes, so it has been genuinely unmeasured rather than merely low.
#
# Counts only PATROL interdictions. `step_demand_stop` is shared -- pirates use
# it to rob people -- so the hooks gate on `job.has("interdict_tier")`, which
# only InterdictLeaf sets. Without that discriminator these counters would
# happily report a pirate's successful robbery as a patrol's successful stop.
#
# Same shape as PerfProbe/DecisionProbe: a single static bool read on paths that
# already run, free when off.

static var enabled: bool = false

static var started: int = 0        # interdiction assigned (INTERCEPT + DEMAND_STOP)
static var complied: int = 0       # subject held station -- an actual STOP
static var refused: int = 0        # patience expired, never complied
static var outpaced: int = 0       # subject outran the patrol beyond hail range

# THE GEOMETRY A DEMAND OPENS AT (2026-08-03).
#
# Added because two confident wrong causes in a row were both "the patrol is too
# slow". A 1v1 trace (tactical_analysis/sim_runners/pursuit_trace.gd) killed
# that outright: the patrol out-accelerates the pirate 115.6 to 79.8 u/s^2, has
# the higher top speed, and closes a 2500u opening gap to ~600u repeatedly
# without ever approaching its abort threshold.
#
# What DOES vary is where the demand starts relative to the range it must be
# held inside. Contacts are held at SENSOR range; the demand must stay inside
# 1.2x HAIL range, and the funnel's own aborts show that number swinging 3x
# between pairings (9000 in one, 27000 in another). A patrol can therefore open
# an interdiction already most of the way to its own abort line -- which is a
# geometry problem, not a propulsion one.
#
# So record the opening separation and the hail range, and let the ratio say it.
static var open_ratios: Array = []   # separation / hail_range at demand issue

static func reset() -> void:
	started = 0
	complied = 0
	refused = 0
	outpaced = 0
	open_ratios.clear()

# Called once per interdiction, when the demand is first SENT (not when the job
# is assigned) -- that is the moment the outpaced test starts applying.
static func note_demand_geometry(job: Dictionary, separation: float, hail_range: float) -> void:
	if not enabled or not job.has("interdict_tier") or hail_range <= 0.0:
		return
	open_ratios.append(separation / hail_range)

# Fraction of interdictions that opened ALREADY past the 1.2x abort line, and
# the median opening ratio. If the first number is materially above zero, the
# problem is where patrols start demanding, and no amount of chase tuning
# touches it.
static func opening_summary() -> Dictionary:
	if open_ratios.is_empty():
		return {}
	var sorted: Array = open_ratios.duplicate()
	sorted.sort()
	var doomed: int = 0
	for r in open_ratios:
		if r > 1.2:
			doomed += 1
	return {
		"n": open_ratios.size(),
		"median": float(sorted[sorted.size() / 2]),
		"max": float(sorted[sorted.size() - 1]),
		"born_outpaced": doomed,
	}

static func note_started() -> void:
	if enabled:
		started += 1

# `job` is passed so the hook can prove this was a PATROL interdiction rather
# than a pirate's robbery demand. Cheap: one dictionary lookup on a path that
# runs once per demand outcome, not per frame.
static func note_outcome(job: Dictionary, outcome: String) -> void:
	if not enabled or not job.has("interdict_tier"):
		return
	match outcome:
		"complied": complied += 1
		"refused": refused += 1
		"outpaced": outpaced += 1

# The number the goal actually asks for: of the interdictions a patrol started,
# how many ended with the subject stopped. Returns -1 when nothing was attempted,
# so "no attempts" cannot be misread as "0% success".
static func stop_rate() -> float:
	var resolved: int = complied + refused + outpaced
	return (float(complied) / resolved) if resolved > 0 else -1.0
