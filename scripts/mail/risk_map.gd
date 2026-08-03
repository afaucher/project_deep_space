extends RefCounted

# M59 -- one map, read with opposite signs.
#
# This module exists so that "cargo avoids dangerous lanes and patrols prefer
# them" is literally the same weighting function consulted twice, not two
# subsystems that happen to agree. If they drift apart, a patrol sweeps
# somewhere cargo was never afraid of, and the loop the design is built on
# (cargo flees -> pirates follow -> patrols follow -> pirates leave -> cargo
# returns) quietly stops closing.
#
#   RoutePlanner._risk_estimate -> lane_risk()   subtract it: avoid, or charge more
#   PatrolResponseLeaf          -> hotspot()     seek it: go where the work is
#
# THE INPUT IS ALWAYS HEARD NEWS, NEVER TRUTH. Callers pass their own
# Mailbag.read_incidents() result, clamped to their delivered version, so two
# readers with different travel histories legitimately disagree. Nothing in
# here reaches for world state.
#
# The three weights and why they are what they are:
#
#   PROXIMITY, measured to a SEGMENT for a lane and to a point for a sweep.
#   RISK_CORRIDOR_RADIUS is the pirate detection radius from the viability
#   work -- beyond it an incident tells you nothing about this lane.
#
#   RECENCY, halved every RISK_HALF_LIFE_FRAMES. This is the damping term for
#   the predator-prey oscillation, and its half-life is the main dial for how
#   fast that cycle runs -- which is why it is named rather than an inline 0.5.
#
#   WEIGHT PER INCIDENT, per lot on the cargo side (see RoutePlanner's own
#   warning that anything in absolute score units must scale with LOT_SIZE).
#
# Deliberately NOT weighted by incident kind: an OVERDUE (hull stopped
# reporting, culprit unknown) counts the same as a witnessed ARMED_ROBBERY.
# Separating them is a policy judgement, and the point of the verdict/evidence
# split is that policy lives in the consumer, visibly, rather than in the record.

const RISK_CORRIDOR_RADIUS := 20000.0
# 2026-08-02 -- 18,000 (5 game-min) -> 108,000 (30 game-min), set against
# MEASURED delivery latency rather than in isolation.
#
# The old value was chosen as "the damping term for the predator-prey
# oscillation" before any latency existed to compare it against. Then the
# courier network was measured: a robbery 54-77km from any station takes ~22
# GAME-MINUTES to reach a port. At a 5-minute half-life that is 4.5 half-lives,
# so a fresh incident worth 25 arrives weighing 1.1 -- **news was stale before
# it landed**, and PatrolResponseLeaf could never clear its threshold no matter
# how much trouble there was.
#
# THE RULE THIS ENCODES (D22): in a world where information is CARRIED, a decay
# constant must be set relative to measured delivery time. A half-life shorter
# than the latency means nobody can ever act on anything.
#
# 30 game-min leaves a delivered report at ~0.6 of its original weight, and an
# hour-old one at ~0.25 -- still decaying, still a damping term, but no longer
# self-defeating.
const RISK_HALF_LIFE_FRAMES := 108000.0  # 30 game-minutes at 60Hz

# How much a single fresh incident sitting exactly on the lane weighs, before
# the caller scales it. Cargo multiplies by lots; the patrol side uses the raw
# weight only to RANK candidate hotspots, so its absolute value never matters
# there -- only its ordering.
const WEIGHT_PER_INCIDENT := 25.0

static func _recency(e: Dictionary, now: int) -> float:
	var age: float = float(maxi(0, now - int(e.get("stamp", 0))))
	return pow(0.5, age / RISK_HALF_LIFE_FRAMES)

# Point-to-SEGMENT distance, never point-to-line: a lane is bounded by its two
# stations, so an incident 200,000u past the dropoff must not read as "on the
# lane" merely because it sits near the infinite extension of it.
static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Total danger weight along the a->b corridor, per unit of load.
static func lane_risk(a: Vector2, b: Vector2, incidents: Array, now: int) -> float:
	if incidents.is_empty():
		return 0.0
	var total: float = 0.0
	for e in incidents:
		var d: float = dist_to_segment(e.get("pos", Vector2.ZERO), a, b)
		if d >= RISK_CORRIDOR_RADIUS:
			continue
		total += WEIGHT_PER_INCIDENT * (1.0 - d / RISK_CORRIDOR_RADIUS) * _recency(e, now)
	return total

# The heaviest concentration of trouble a patrol can reach, or an empty dict.
#
# Scored by summing every OTHER incident's weight around each candidate, so a
# cluster of three beats a lone outlier -- a patrol should sweep where trouble
# repeats, not chase the single most recent report. Returns the incident's own
# position rather than a centroid: a real place something happened reads better
# in a log than an averaged point in empty space, and centroids of two distant
# clusters land between them, where nothing ever happened.
#
# `max_range` keeps a patrol from abandoning its station for the far side of the
# cluster; `from_pos` is the patrol's own position, so this is "the worst thing
# near me", not "the worst thing anywhere".
static func hotspot(incidents: Array, now: int, from_pos: Vector2, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_weight: float = 0.0
	for e in incidents:
		var p: Vector2 = e.get("pos", Vector2.ZERO)
		if from_pos.distance_to(p) > max_range:
			continue
		var weight: float = 0.0
		for other in incidents:
			var d: float = p.distance_to(other.get("pos", Vector2.ZERO))
			if d >= RISK_CORRIDOR_RADIUS:
				continue
			weight += WEIGHT_PER_INCIDENT * (1.0 - d / RISK_CORRIDOR_RADIUS) * _recency(other, now)
		if weight > best_weight:
			best_weight = weight
			best = {"pos": p, "weight": weight, "kind": e.get("kind", ""), "subject_name": e.get("subject_name", "")}
	return best


# Pick a hotspot at random, WEIGHTED by severity, instead of always taking the
# heaviest (2026-08-02).
#
# Why: deterministic argmax makes a patrol lock on. Measured -- one report kept
# the same point as the winner for its whole ~52-minute actionable life, so the
# patrol re-swept a place it was already standing every ~45-75s and never went
# home (52 sweeps off 2 incidents in one seed). The stickiness was the argmax,
# not the threshold.
#
# Weighted sampling keeps the intent -- heavier trouble is visited more often --
# while letting attention move. It ALSO makes two patrols diverge naturally
# instead of both converging on the same coordinates.
#
# Honest limit: with exactly ONE known incident this still returns that
# incident, so it does not by itself stop a lone report holding a patrol. What
# it fixes is the multi-incident case, and it composes with routine circulation
# (PatrolResponseLeaf) which gives a patrol something else to do. A real
# "this hotspot has been answered" notion is still open.
#
# Uses the global RNG, which sims seed -- so a run stays reproducible.
static func pick_weighted(incidents: Array, now: int, from_pos: Vector2, max_range: float) -> Dictionary:
	var cands: Array = []
	var total: float = 0.0
	for e in incidents:
		var p: Vector2 = e.get("pos", Vector2.ZERO)
		if from_pos.distance_to(p) > max_range:
			continue
		var weight: float = 0.0
		for other in incidents:
			var d: float = p.distance_to(other.get("pos", Vector2.ZERO))
			if d >= RISK_CORRIDOR_RADIUS:
				continue
			weight += WEIGHT_PER_INCIDENT * (1.0 - d / RISK_CORRIDOR_RADIUS) * _recency(other, now)
		if weight <= 0.0:
			continue
		cands.append({"pos": p, "weight": weight, "kind": e.get("kind", ""), "subject_name": e.get("subject_name", "")})
		total += weight
	if cands.is_empty():
		return {}
	var roll: float = randf() * total
	for c in cands:
		roll -= c["weight"]
		if roll <= 0.0:
			return c
	return cands[cands.size() - 1]


# Weight AT a position: every nearby incident's severity x proximity x recency.
# Factored out so the patrol's candidate list and hotspot()/pick_weighted() all
# score a place the same way -- three copies of this sum would drift.
static func weight_at(incidents: Array, p: Vector2, now: int) -> float:
	var w: float = 0.0
	for other in incidents:
		var d: float = p.distance_to(other.get("pos", Vector2.ZERO))
		if d >= RISK_CORRIDOR_RADIUS:
			continue
		w += WEIGHT_PER_INCIDENT * (1.0 - d / RISK_CORRIDOR_RADIUS) * _recency(other, now)
	return w
