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

# `desired_dir` bent to avoid obstacles. `exclude_pos` (Vector2 or null) is the
# body the caller is approaching (dock/combat target) -- never dodged. `weight`
# scales avoidance (combat passes < 1 to ease around rather than jerk).
static func steer(actor, desired_dir: Vector2, exclude_pos, weight: float = 1.0) -> Vector2:
	var avoid: Vector2 = _avoidance(actor, exclude_pos) * weight
	if avoid == Vector2.ZERO:
		return desired_dir
	var combined: Vector2 = desired_dir.normalized() + avoid
	if combined.length() < 0.01:
		return avoid
	return combined

static func _avoidance(actor, exclude_pos) -> Vector2:
	var pos: Vector2 = actor.position
	var vel: Vector2 = actor.linear_velocity
	var r_self: float = actor.get_bounding_radius()
	var total: Vector2 = Vector2.ZERO

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
				total += (-rel / dist) * ((safe - dist) / safe) * FLOOR_GAIN
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
		var away: Vector2 = perp * -side
		var urgency: float = (safe - miss) / safe
		var avoid_vec = away.normalized() * urgency * AVOID_GAIN
		if actor.name == "MobileHome" and Engine.get_process_frames() % 60 == 0:
			print("Steering ", actor.name, " obs: ", obs.name, " rel: ", rel, " relv: ", relv, " head: ", head, " perp: ", perp, " side: ", side, " away: ", away, " avoid: ", avoid_vec)
		total += avoid_vec
	return total

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
