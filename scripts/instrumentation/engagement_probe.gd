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

static func reset() -> void:
	started = 0
	complied = 0
	refused = 0
	outpaced = 0

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
