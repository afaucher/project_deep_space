extends RefCounted

# M59 -- the routing counterfactual probe. OFF by default; a sim turns it on.
#
# WHY THIS EXISTS. A long economic run shows you where traffic went, and cannot
# tell you WHY it went there: a lane that goes quiet because it became dangerous
# and a lane that goes quiet because its destination stopped paying look
# identical in a traffic histogram. Since the whole claim under test is "cargo
# avoids dangerous lanes", inferring causation from that histogram would be
# exactly the mistake the ore-shortage diagnosis already made once (a starving
# consumer and a backed-up producer are the same curve seen from two ends).
#
# So instead of inferring, ask directly: at each replan, ALSO score the world
# with the reader's incidents removed, and record whether the winner changes.
# That turns a single expensive run into a per-decision A/B, and makes
# "risk changed N of M decisions" a measurement rather than a story.
#
# COST. One extra best_route() per replan. Replanning is throttled to
# REPLAN_CHECK_INTERVAL (10s) per hull, so at campaign scale this is a handful
# of extra searches per second across the whole fleet -- and it is skipped
# entirely by the `enabled` guard below, which is a single static bool read on
# the same throttled path. Same shape as PerfProbe: free when off.
#
# NOT a debug TOGGLE (DebugSettings) on purpose: this is sim-harness
# instrumentation, not something a player should be able to switch on mid-game,
# and it accumulates unbounded rows.

static var enabled: bool = false

# One row per planning decision. Plain data, appended in order.
#   {frame, hauler, chosen, blind, changed, risk, heard, score, blind_score}
# `chosen`/`blind` are "pickup_id>dropoff_id" or "" for no-viable-route.
static var decisions: Array = []

# Cheap running tallies, so a caller does not have to walk `decisions`.
static var total: int = 0
static var changed_by_risk: int = 0
static var risk_values: Array = []   # every non-zero risk seen, for a p95

static func reset() -> void:
	decisions.clear()
	risk_values.clear()
	total = 0
	changed_by_risk = 0

static func _lane(route: Dictionary) -> String:
	if route.is_empty():
		return ""
	return "%d>%d" % [route.get("pickup_id", -1), route.get("dropoff_id", -1)]

# `chosen` is the route the hull actually took with its own heard news;
# `blind` is the same search with incidents removed. Both may be empty (no
# viable route), and "chosen empty while blind is not" is itself a finding --
# risk pushed every option below MIN_VIABLE_SCORE and the hull idled.
static func record(actor_name: String, chosen: Dictionary, blind: Dictionary, heard: int) -> void:
	if not enabled:
		return
	var c := _lane(chosen)
	var b := _lane(blind)
	var risk: float = float(chosen.get("risk", 0.0))
	total += 1
	if c != b:
		changed_by_risk += 1
	if risk > 0.0:
		risk_values.append(risk)
	decisions.append({
		"frame": Engine.get_physics_frames(),
		"hauler": actor_name,
		"chosen": c,
		"blind": b,
		"changed": c != b,
		"risk": risk,
		"heard": heard,
		"score": float(chosen.get("score", 0.0)),
		"blind_score": float(blind.get("score", 0.0)),
	})

# THE CHECK THAT CAN INVALIDATE A WHOLE RUN, and the first thing to read.
# If risk never got large relative to the margin a competing route must beat
# (RoutePlanner.HYSTERESIS_MARGIN), then cargo never had a reason to divert and
# the cargo half of M59 is UNTESTED regardless of what the traffic did. A run
# that reads "0 decisions changed" means something completely different
# depending on this number.
static func risk_p95() -> float:
	if risk_values.is_empty():
		return 0.0
	var sorted: Array = risk_values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])

static func risk_max() -> float:
	var hi: float = 0.0
	for v in risk_values:
		hi = maxf(hi, float(v))
	return hi
