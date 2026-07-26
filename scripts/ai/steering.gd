extends RefCounted
class_name Steering

# Shared collision-avoidance steering layer (see design_ideas/collision_avoidance.md).
# Every AI mover routes its desired direction through steer(): a velocity-lookahead
# avoidance vector is blended in, and because that vector grows with imminence it
# naturally OVERRIDES the goal when a hit is about to happen (a few frames) while
# only nudging (BLEND) when a threat is distant. Callers suppress it under external
# control (docking) by simply not calling it, and pass `exclude_pos` for the body
# they are deliberately approaching so a hull can still reach its target.

const SCAN_RANGE := 8000.0     # only consider obstacles within this
const LOOKAHEAD_TIME := 6.0    # seconds ahead to predict a collision (long enough that a heavy hull has room to swing clear)
const MARGIN := 400.0          # extra clearance beyond the two radii
const AVOID_GAIN := 4.0        # strength of a predictive dodge
const FLOOR_GAIN := 3.0        # strength of the anti-overlap short-range push
# The goal never drops to literally zero pull, even at maximum urgency -- see
# steer()'s goal_weight. A hard 0% cut (tried first, see test_nav_gauntlet.gd's
# commit history) let a chain of consecutive dodges fling the ship off in a
# pure escape heading for many seconds before goal-seeking resumed, tracing a
# huge loop through the rest of the field instead of a local dodge. Keeping a
# small residual pull toward the goal at all times means the ship is always
# net-progressing even while it dodges hard, so a local dodge stays local.
const MIN_GOAL_WEIGHT := 0.15

# `desired_dir` bent to avoid obstacles. `exclude_pos` (Vector2 or null) is the
# body the caller is approaching (dock/combat target) -- never dodged. `weight`
# scales avoidance (combat passes < 1 to ease around rather than jerk).
#
# The goal's own contribution shrinks continuously as urgency rises (down to
# MIN_GOAL_WEIGHT, never to zero) instead of being blended in at a fixed full
# weight regardless of how close the threat is. That fixed-full-weight blend
# was the actual bug behind test_nav_gauntlet.gd's Deepcut repro: goal-seeking
# (weight 1) roughly balanced the anti-overlap floor's modest push right at
# the margin boundary, so the ship ground along an obstacle's edge for ~10
# seconds instead of committing to a clean escape.
#
# `weight` scales BOTH halves -- the dodge AND the goal suppression -- so it
# coherently means "how much avoidance authority this caller grants". Scaling
# only the dodge (the first version of this change) regressed
# test_e2e_drone_vs_bouy: steer_to_target_leaf.gd passes weight 0.4 asking to
# EASE around threats, but got a gentled dodge with FULL goal suppression, so a
# drone could never press an attack and its target survived. At weight 0 the
# limit is now sensible too -- no dodge and no suppression, i.e. pure
# goal-seeking -- rather than "don't dodge, but still refuse to go there".
static func steer(actor, desired_dir: Vector2, exclude_pos, weight: float = 1.0) -> Vector2:
	var result: Dictionary = _avoidance(actor, exclude_pos)
	var avoid: Vector2 = result["vec"] * weight
	if avoid == Vector2.ZERO:
		return desired_dir
	var goal_weight: float = clampf(1.0 - result["urgency"] * weight, MIN_GOAL_WEIGHT, 1.0)
	var combined: Vector2 = desired_dir.normalized() * goal_weight + avoid
	if combined.length() < 0.01:
		return avoid
	return combined

# Returns {"vec": Vector2, "urgency": float (0..1)}. `urgency` is the worst of
# the anti-overlap floor's overlap fraction and the single worst predictive
# threat's own urgency -- steer() uses it to shrink the goal's pull as a
# threat gets more pressing, rather than an all-or-nothing switch.
static func _avoidance(actor, exclude_pos) -> Dictionary:
	var pos: Vector2 = actor.position
	var vel: Vector2 = actor.linear_velocity
	var r_self: float = actor.get_bounding_radius()

	# Anti-overlap floor (already-touching bodies) is still SUMMED: those never
	# oppose each other the way two flanking predictive threats do -- a ship
	# squeezed between two things it's already overlapping needs to be pushed
	# away from BOTH at once, and there's no "pick one" reading of that. It's
	# also short-range/rare (only fires once avoidance has already failed to
	# keep clearance), so summing it doesn't reintroduce the cancellation bug.
	var floor_total: Vector2 = Vector2.ZERO
	var floor_urgency: float = 0.0

	# Predictive avoidance takes the SINGLE most urgent threat, not a sum. A
	# dense field routinely has obstacles on opposite sides at once; summing
	# their (near-opposite) dodge vectors collapses toward zero and the ship
	# sails straight down the middle into whichever third rock sits there
	# (design_ideas/collision_avoidance.md's "wrong combinator" problem,
	# confirmed by scripts/tests/test_nav_gauntlet.gd). Reacting to only the
	# worst (highest-urgency) threat this tick means the ship commits to one
	# clean dodge instead of averaging conflicting ones; as that threat clears
	# (or its TTCA runs out), the next-worst threat becomes "worst" and takes
	# over -- a threat-by-threat sequence rather than a blended compromise.
	var worst_urgency: float = -1.0
	var worst_avoid: Vector2 = Vector2.ZERO

	for obs in _nearby(actor):
		var opos: Vector2 = obs.position
		var orad: float = _radius_of(obs)
		if exclude_pos != null and opos.distance_to(exclude_pos) < orad + 1.0:
			continue   # the body we're approaching -- don't dodge it
		var rel: Vector2 = opos - pos
		var dist: float = rel.length()
		var safe: float = r_self + orad + MARGIN

		# Anti-overlap floor: already too close -> direct push, ignoring velocity.
		if dist < safe:
			if dist > 0.01:
				var frac: float = (safe - dist) / safe
				floor_total += (-rel / dist) * frac * FLOOR_GAIN
				floor_urgency = max(floor_urgency, frac)
			else:
				floor_urgency = 1.0
			continue

		# Predictive: closest approach along the relative velocity.
		var relv: Vector2 = obs.linear_velocity - vel
		var speed2: float = relv.length_squared()
		if speed2 < 1.0:
			continue   # ~no closing motion -> only the floor matters
		var ttca: float = -rel.dot(relv) / speed2
		if ttca <= 0.0 or ttca > LOOKAHEAD_TIME:
			continue   # moving apart, or too far ahead to matter yet
		var miss: float = (rel + relv * ttca).length()
		if miss >= safe:
			continue   # will clear it anyway

		# Steer perpendicular to the relative velocity, away from the obstacle's side.
		var head: Vector2 = relv.normalized() if relv.length() > 0.01 else rel.normalized()
		var perp: Vector2 = Vector2(-head.y, head.x)
		var side: float = signf(perp.dot(rel))
		if absf(side) < 0.001:
			side = 1.0   # dead ahead -> pick a side deterministically
		# Pure perpendicular dodge has a degenerate case: a single obstacle
		# sitting almost exactly on the route (test_nav_gauntlet.gd's Deepcut
		# repro has one 12 units off dead-center, ~1600 units from the goal)
		# turns a tangential-only escape into a stable ORBIT -- the ship keeps
		# just enough sideways motion to maintain clearance without ever
		# gaining distance, since nothing pushes the miss distance to actually
		# GROW over time. Mixing in a modest radial (directly away from the
		# obstacle) component breaks that symmetry: distance now trends
		# upward tick over tick, so the predictive threat eventually clears on
		# its own instead of looping forever.
		var away: Vector2 = (perp * -side * 0.7 + (-rel).normalized() * 0.3).normalized()
		# Urgency blends miss-distance closeness with imminence (TTCA) -- a
		# near-miss that's still seconds away shouldn't outrank a wider miss
		# that's about to happen RIGHT now. Without the TTCA term, "worst" was
		# picked on miss-distance alone, which could latch onto a distant
		# threat over an imminent one and reproduce the same stuck-oscillation
		# failure this fix targets.
		var closeness: float = (safe - miss) / safe
		var imminence: float = 1.0 - clampf(ttca / LOOKAHEAD_TIME, 0.0, 1.0)
		var urgency: float = closeness * (0.5 + 0.5 * imminence)
		if urgency > worst_urgency:
			worst_urgency = urgency
			worst_avoid = away * closeness * AVOID_GAIN

	if worst_urgency >= 0.0:
		floor_total += worst_avoid
	var urgency: float = max(floor_urgency, maxf(worst_urgency, 0.0))
	return {"vec": floor_total, "urgency": urgency}

static func _nearby(actor) -> Array:
	var out: Array = []
	var pos: Vector2 = actor.position
	for g in ["ships", "obstacles"]:
		for b in actor.get_tree().get_nodes_in_group(g):
			if b == actor:
				continue
			if pos.distance_to(b.position) < SCAN_RANGE:
				out.append(b)
	return out

static func _radius_of(obs) -> float:
	if obs.has_method("get_bounding_radius"):
		return obs.get_bounding_radius()
	return 300.0
