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

# WHICH TIER THE STOP WAS (2026-08-03).
#
# The aggregate counters above conflate two different events, and the criterion-
# (4) review said so outright: interdiction fires at CAUTION tier as well as
# HOSTILE, and a CAUTION-tier subject is usually an innocent hull that failed to
# answer an ID challenge rather than anyone the patrol has a force-authorizing
# warrant against. The measured run that prompted this read `4 stops -> 2 guild
# losses -> ~2 hulks`, so AT MOST half of those four stops were pirates and the
# rest were civilians inspected and released. A single "stop rate" therefore
# cannot distinguish enforcement from harassment -- both count identically.
#
# So every counter above gets a per-tier twin, keyed by the tier string
# (Standing.CAUTION / Standing.HOSTILE). The aggregates stay -- callers and
# information_loop.gd's report read them, and the totals are still the right
# denominator for "did a patrol stop anything at all" -- these sit alongside.
#
# Note this splits OUTCOMES by tier, not motives. A HOSTILE-tier stop is a
# patrol acting on a determined-enemy standing or an enforceable warrant; it is
# not by itself proof the subject was a pirate, only that the patrol had grounds
# the CAUTION tier does not carry. The guild's own loss ledger remains the
# separate, independent number for "was it actually a pirate".
static var started_by_tier: Dictionary = {}
static var complied_by_tier: Dictionary = {}
static var refused_by_tier: Dictionary = {}
static var outpaced_by_tier: Dictionary = {}

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

# THE ROBBERY SIDE OF THE SAME QUESTION (2026-08-04).
#
# Everything above counts PATROL interdictions and deliberately excludes
# robberies -- `note_outcome` returns early unless the job carries
# `interdict_tier`, so a pirate's successful robbery can never be booked as a
# patrol's successful stop. Correct, and it left the pirate side entirely
# uncounted.
#
# That is now the last unmeasured stage on criterion (1). Lane choice (D44),
# victim selection, staying on the hunt past a witness (D46) and holding the
# track while closing (D47) are all solved and takes are still ~1 per run, so
# every remaining failure is in what happens AFTER the demand goes out. The
# patrol side has had exactly this breakdown since D28 and it is what located
# "pirates cannot comply" in one run; the robbery side has been inferred from
# takes, which cannot distinguish "they ran" from "they ignored me".
#
# Same three outcomes, same -1.0-means-none-attempted convention. Kept in this
# file rather than a new one because they share the hooks in step_demand_stop --
# two probes on one path would be two things to keep in sync.
static var robbery_started: int = 0
static var robbery_complied: int = 0
static var robbery_refused: int = 0
static var robbery_outpaced: int = 0

# D51 -- robberies the PIRATE walked away from. The funnel booked these as
# `returned_empty`, which is indistinguishable from "found nobody" -- so
# criterion (1) has been reading pirate CAUTION as pirate FAILURE. Measured
# cause: Flee outranks JobRunner in build_pirate, so a threatened pirate stops
# refreshing its own demand and the victim's compliance lapses.
static var robbery_abandoned_disengage: int = 0

static func note_robbery_abandoned_disengage() -> void:
	if enabled:
		robbery_abandoned_disengage += 1

static func reset() -> void:
	started = 0
	complied = 0
	refused = 0
	outpaced = 0
	open_ratios.clear()
	robbery_started = 0
	robbery_complied = 0
	robbery_refused = 0
	robbery_outpaced = 0
	robbery_abandoned_disengage = 0
	started_by_tier.clear()
	complied_by_tier.clear()
	refused_by_tier.clear()
	outpaced_by_tier.clear()

# Called once per interdiction, when the demand is first SENT (not when the job
# is assigned) -- that is the moment the outpaced test starts applying.
static func note_demand_geometry(job: Dictionary, separation: float, hail_range: float) -> void:
	if not enabled:
		return
	# A demand went out. Which KIND is what the tier tells us -- a patrol
	# interdiction carries `interdict_tier`, a robbery does not.
	if not job.has("interdict_tier"):
		robbery_started += 1
		return
	if hail_range <= 0.0:
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

# `tier` is the same value InterdictLeaf is about to stamp onto the job as
# `interdict_tier` -- passed explicitly because this hook fires at ASSIGNMENT,
# where the caller holds the tier in hand and the probe has no job dict to read
# it back out of. Without it there is a started/outcome asymmetry: the outcome
# hooks below could report per-tier results with no per-tier denominator to
# divide them by, which is the same "a rate with no attempts behind it" trap
# stop_rate()'s -1.0 convention exists to prevent.
static func note_started(tier: String) -> void:
	if not enabled:
		return
	started += 1
	started_by_tier[tier] = int(started_by_tier.get(tier, 0)) + 1

# `job` is passed so the hook can prove this was a PATROL interdiction rather
# than a pirate's robbery demand. Cheap: two dictionary lookups on a path that
# runs once per demand outcome, not per frame.
static func note_outcome(job: Dictionary, outcome: String) -> void:
	if not enabled:
		return
	if not job.has("interdict_tier"):
		# A robbery demand resolving. Same three outcomes, counted separately --
		# never folded into the patrol totals, which is the discriminator this
		# probe was built around.
		match outcome:
			"complied": robbery_complied += 1
			"refused": robbery_refused += 1
			"outpaced": robbery_outpaced += 1
		return
	var tier: String = _tier_key(job)
	match outcome:
		"complied":
			complied += 1
			complied_by_tier[tier] = int(complied_by_tier.get(tier, 0)) + 1
		"refused":
			refused += 1
			refused_by_tier[tier] = int(refused_by_tier.get(tier, 0)) + 1
		"outpaced":
			outpaced += 1
			outpaced_by_tier[tier] = int(outpaced_by_tier.get(tier, 0)) + 1

# `str()` rather than a typed read, because `interdict_tier` is only a Standing
# string on the paths the GAME builds: InterdictLeaf._tier_of returns
# Standing.CAUTION or Standing.HOSTILE, but hand-built job fixtures treat the
# field purely as a "this is a patrol job, not a robbery" marker and one of them
# (scripts/tests/test_outlaw_response.gd) sets the literal `1`. That one is
# latent rather than live -- it never turns the probe on, so the guard above
# returns first -- but the shape is what matters: assigning a non-String to a
# typed String raises a runtime error, and per CLAUDE.md's dictionary trap that
# aborts the rest of the calling function for the frame, which here would be the
# aggregate increment beside it and whatever step_demand_stop does next.
# Bucketing an odd value under its own string key instead keeps the aggregates
# exact and leaves the strange key visible in the report rather than dropped.
static func _tier_key(job: Dictionary) -> String:
	return str(job.get("interdict_tier", ""))

# Every tier that appeared in ANY counter, sorted, so a report can iterate
# without assuming which tiers a given run happened to produce.
#
# Union rather than just started_by_tier's keys, because the two sides do not
# have to agree. `note_started` fires only from InterdictLeaf, while the outcome
# hooks fire from step_demand_stop for ANY job carrying `interdict_tier` --
# including jobs assembled by hand (test fixtures, pursuit_trace.gd) that never
# went through the leaf. Keying off starts alone would hide those outcomes
# entirely; a tier with outcomes and no starts is an asymmetry a reader needs to
# see, not one the report should silently drop.
static func tiers_seen() -> Array:
	var keys: Dictionary = {}
	for d in [started_by_tier, complied_by_tier, refused_by_tier, outpaced_by_tier]:
		for k in d:
			keys[k] = true
	var out: Array = keys.keys()
	out.sort()
	return out

# The number the goal actually asks for: of the interdictions a patrol started,
# how many ended with the subject stopped. Returns -1 when nothing was attempted,
# so "no attempts" cannot be misread as "0% success".
static func stop_rate() -> float:
	var resolved: int = complied + refused + outpaced
	return (float(complied) / resolved) if resolved > 0 else -1.0

# The same number restricted to one tier, which is the form the criterion
# actually needs: "stopping some pirates" is a claim about the HOSTILE-tier rate,
# and the CAUTION-tier rate is a claim about how often patrols successfully pull
# over hulls that merely failed to identify themselves. Reporting only the blend
# lets a run of administrative stops stand in for enforcement.
#
# Same -1.0 convention as stop_rate(), and it matters MORE here: splitting one
# small sample across two tiers routinely leaves a tier with zero attempts, and
# a 0% there would read as "patrols tried and always failed" when nothing was
# ever tried.
static func stop_rate_for(tier: String) -> float:
	var did_comply: int = int(complied_by_tier.get(tier, 0))
	var resolved: int = did_comply \
		+ int(refused_by_tier.get(tier, 0)) \
		+ int(outpaced_by_tier.get(tier, 0))
	return (float(did_comply) / resolved) if resolved > 0 else -1.0

# Of the robbery demands a pirate issued, how many ended with the victim
# stopped. Same -1.0 convention as stop_rate(): "none attempted" must not read
# as "0% success", which matters more here than anywhere because robberies are
# the sparsest event in the simulation.
static func robbery_stop_rate() -> float:
	var resolved: int = robbery_complied + robbery_refused + robbery_outpaced
	return (float(robbery_complied) / resolved) if resolved > 0 else -1.0
