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
	var avoid: Vector2 = _avoidance(actor, exclude_pos) * weight
	if avoid == Vector2.ZERO:
		return desired_dir
	var goal_weight: float = clampf(1.0 - last_urgency * weight, MIN_GOAL_WEIGHT, 1.0)
	var combined: Vector2 = desired_dir.normalized() * goal_weight + avoid
	if combined.length() < 0.01:
		return avoid
	return combined

# Companion output of the LAST _avoidance() call: the worst of the anti-overlap
# floor's overlap fraction and the single worst predictive threat's own urgency
# (0..1). steer() uses it to shrink the goal's pull as a threat gets more
# pressing, rather than an all-or-nothing switch.
#
# A static scratch field rather than a second return value BECAUSE THIS IS THE
# HOTTEST PATH IN THE GAME: steer() runs per AI mover per physics frame, so
# returning {"vec":..., "urgency":...} allocated and discarded a Dictionary
# every ship every frame. That landed in the same gate where test_perf_baseline
# moved 8.45 -> 12.42 ms avg -- a uniform per-frame cost, which is the right
# shape for an average shift (the M53c route planner, the other suspect, is
# throttled to one search per hull per 10s and cannot move a mean). It also
# forced station_keeping_leaf.gd to allocate the dict purely to read ["vec"]
# and throw the rest away.
#
# Safe as static state because physics is single-threaded and every caller
# reads it IMMEDIATELY after its own _avoidance() call, before any other ship
# can run. If avoidance ever moves off the physics thread this must become a
# real return value again.
static var last_urgency: float = 0.0

# Returns the avoidance vector; also sets `last_urgency` (read it immediately).
static func _avoidance(actor, exclude_pos) -> Vector2:
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

	# NEVER let avoidance push us INTO the body we have deliberately stopped
	# watching. `exclude_pos` (the dock/combat target) is skipped as an obstacle
	# above, which is correct -- a hull must be able to close on the thing it is
	# approaching -- but it left a blind spot: a dodge computed against OTHER
	# traffic can have a large component pointing straight at the excluded body,
	# and nothing was there to object.
	#
	# scripts/tests/test_dock_approach.gd measured exactly this. Solo approaches
	# are spotless (0 contacts, peak contact 0), but converging hulls dodging
	# EACH OTHER shove one into the station: 26 damaging station contacts across
	# three scenarios, all on arrival, none on departure. Worst case was the
	# HEAVY Nexus Freighter -- ponderous enough (max_omega 0.6-1.8) that it
	# cannot correct out of a shove, and massive enough that the one contact it
	# did take cost 2890 station HP where a shuttle's would have been a scratch.
	#
	# Approach-speed discipline alone cannot fix that, because the hull is being
	# DISPLACED, not travelling fast by choice. Projecting the inward component
	# out leaves peer-dodging fully intact (the tangential part survives) and
	# leaves goal-seeking alone (that is steer()'s own term), while making it
	# impossible for avoidance to ADD velocity toward the target. The honest
	# reading of "don't dodge my dock target": stop routing around it, do not go
	# blind to it.
	if exclude_pos != null and exclude_pos is Vector2 and exclude_pos.is_finite():
		var to_target: Vector2 = exclude_pos - pos
		if to_target.length() > 0.01:
			var t_dir: Vector2 = to_target.normalized()
			var into: float = floor_total.dot(t_dir)
			if into > 0.0:
				floor_total -= t_dir * into

	last_urgency = max(floor_urgency, maxf(worst_urgency, 0.0))
	return floor_total

# ---------------------------------------------------------------------------
# Approach discipline (design_ideas/port_zones_and_channels.md "Two speed
# rules, not one"). Returns the speed this actor should actually be doing,
# given `cruise` as what it WANTS to be doing.
#
# RULE 1 -- self-imposed, universal. Shed speed near anything dockable, at
# every station, zone or no zone, authority or none. This is competence, not
# compliance: you slow down because you don't want to hit the thing, and
# physics does not care about jurisdiction. Five of the home cluster's eight
# stations are SmallStations that publish no zone at all, so a rule that only
# applied inside an authored zone would leave most of the cluster's traffic
# ungoverned.
#
# RULE 2 -- externally imposed, only where an authority exists to impose it.
# A port zone's `speed_advisory` (medium_station.gd), obeyed inside the zone
# whether or not this hull is docking, since a ship merely transiting is still
# traffic. NPCs treat it as mandatory; the player gets an amber gauge and is
# free to be a menace (helm_panel.gd).
#
# WHY THIS EXISTS AT ALL: scripts/tests/test_dock_approach.gd measured 26
# damaging station contacts over three scenarios -- ALL on arrival, none on
# departure -- costing a MediumStation 36.9% of its hull in 9 dock cycles.
# The mechanism is that Steering.steer() takes `exclude_pos` and deliberately
# never dodges the body being approached, so converging hulls dodge EACH OTHER
# straight into the station they have stopped watching. A station is
# stationary, so ship<->station closing speed IS the ship's own speed: holding
# it under Ship.COLLISION_DAMAGE_MIN_SPEED (150 u/s) on approach makes that
# whole class of damage structurally impossible rather than merely rarer.
const DOCK_APPROACH_SPEED := 120.0    # under COLLISION_DAMAGE_MIN_SPEED (150) with headroom for closing geometry
# The allowed speed follows a BRAKING CURVE, v = sqrt(v_dock^2 + 2*a*d), not a
# linear ramp over a fixed margin. Two earlier shapes were both wrong:
#   - margin 6000, linear: demanded ~40 u/s^2 of braking no loaded hull has, so
#     the clamp commanded a speed the ship could not reach and
#     test_dock_approach still measured 385 u/s contacts against a 120 limit.
#   - margin 18000, linear: fixed the damage (0.00% station HP) but made hulls
#     crawl the whole way in -- MediumStation throughput fell from 16 dock
#     cycles to 6, because a linear ramp is slowest exactly where there is
#     still plenty of room.
# The curve asks for a CONSTANT, achievable deceleration instead: full cruise
# until braking is genuinely required, then a proper deceleration profile. It
# also self-scales to the hull -- a Freighter (accel ~8-12, max_speed ~400)
# needs far less room than a 700 u/s shuttle and is allowed to use it.
# Braking authority is derived PER HULL from its own thrust and mass, not
# assumed. A global constant here would silently require every ship in the
# game to brake at least that hard: author a HEAVY hull at the top of its
# max_speed band with weak engines and it would be physically unable to shed
# speed on approach, ram the station, and nothing would explain why --
# ComponentSpec.HANDLING_BANDS constrains max_speed and max_omega but says
# NOTHING about acceleration. Deriving it also lets a nimble shuttle keep its
# speed far longer than a loaded freighter, which is both faster and correct.
#
# BRAKE_FRACTION is below 1.0 because full rated thrust is not available for
# braking: the hull must first rotate to point retrograde (max_omega is low on
# exactly the heavy hulls that need the most braking room) and keeps spending
# some authority on steering while it does.
# 0.35, not the 0.65 first tried. Measured, not reasoned: at 0.65 a shuttle's
# thrust-to-mass permitted far more speed than the earlier flat 8.0 u/s^2
# constant did, and test_dock_approach's SmallStation traffic case regressed
# from 0.00% station HP / peak contact 101 to 3.99% / peak 464 while throughput
# doubled -- hulls arriving hot, exactly as if the clamp had been relaxed,
# because it had been. Rotation time is only part of what a hull spends
# braking authority on; it is also fighting the peer-avoidance shove that put
# it off-axis in the first place.
const APPROACH_BRAKE_FRACTION := 0.35
const APPROACH_DECEL_FLOOR := 4.0     # u/s^2 -- a badly damaged/underpowered hull still gets a usable curve
const APPROACH_MAX_RANGE := 45000.0   # beyond this, don't even consider the body (cheap early-out)

# This hull's usable braking deceleration, u/s^2.
static func _brake_accel(actor) -> float:
	if not actor.has_method("get_ship_max_thrust"):
		return APPROACH_DECEL_FLOOR
	var thrust: float = actor.get_ship_max_thrust()
	var m: float = maxf(0.001, actor.mass)
	return maxf(APPROACH_DECEL_FLOOR, (thrust / m) * APPROACH_BRAKE_FRACTION)
const APPROACH_CLOSE_RADII := 1.5     # fully slowed by this multiple of the target's bounding radius

# Frame-scoped shared cache of dockable bodies, same idiom as ship.gd's
# _port_authority_cache (and for the same reason -- see that comment, which
# describes this exact trap). The first version of approach_speed_limit()
# rescanned the ENTIRE "ships" group per ship per frame, calling get("dockable")
# and get_port_zone() on each: O(ships^2) per tick, in the hottest path in the
# game. It cost 5.3ms of average frame time (test_perf_baseline 12.42 -> 17.71
# ms avg, and it FAILED the gate) -- and the giveaway was the distribution:
# avg 17.71 / p95 18.44 / max 18.73, near-perfectly uniform, which is a fixed
# per-frame cost rather than a spike.
#
# Rebuilt once per physics frame by whichever ship asks first, no invalidation
# hooks to miss. A station promoted mid-frame lands next frame at worst
# (1/60s), and dockability is set at construction/promote time anyway.
static var _dockable_cache: Array = []
static var _dockable_cache_frame: int = -1

static func _dockables(actor) -> Array:
	var frame: int = Engine.get_physics_frames()
	if _dockable_cache_frame != frame:
		_dockable_cache = []
		for s in actor.get_tree().get_nodes_in_group("ships"):
			if is_instance_valid(s) and s.get("dockable") == true:
				_dockable_cache.append(s)
		_dockable_cache_frame = frame
	return _dockable_cache

# The same braking curve approach_speed_limit applies to a station hull, but
# aimed at an ARBITRARY point: the fastest this hull may travel `distance` from
# a spot it needs to be doing `terminal` at, given its own derived braking
# authority. v = sqrt(v_term^2 + 2*a*d).
#
# approach_speed_limit cannot serve this: it measures room to the nearest
# DOCKABLE BODY's hull (APPROACH_CLOSE_RADII of the bounding radius), which for
# a SmallStation is fully slowed only within ~300 units. A docking hull needs to
# be slow much earlier than that -- not to avoid hitting the station, but
# because at cruise it physically cannot turn onto the berth axis in the
# ~1200 units of run the geometry provides. See job_steps.step_dock_at.
static func speed_for_arrival(actor, distance: float, terminal: float) -> float:
	var decel: float = _brake_accel(actor)
	return sqrt(terminal * terminal + 2.0 * decel * maxf(0.0, distance))

static func approach_speed_limit(actor, cruise: float) -> float:
	var limit: float = cruise
	var pos: Vector2 = actor.position
	var decel: float = _brake_accel(actor)
	for b in _dockables(actor):
		if b == actor or not is_instance_valid(b):
			continue
		var dist: float = pos.distance_to(b.position)
		if dist >= APPROACH_MAX_RANGE:
			continue
		var r: float = b.get_bounding_radius() if b.has_method("get_bounding_radius") else 300.0
		# Rule 1: the braking curve. Fully slowed by APPROACH_CLOSE_RADII of the
		# target's hull, and allowed whatever speed a constant APPROACH_DECEL
		# could still shed over the distance remaining beyond that.
		var near: float = r * APPROACH_CLOSE_RADII
		var room: float = maxf(0.0, dist - near)
		var allowed: float = sqrt(DOCK_APPROACH_SPEED * DOCK_APPROACH_SPEED + 2.0 * decel * room)
		# Rule 2: a published limit, where there is an authority to publish one.
		var zone: Dictionary = b.get_port_zone() if b.has_method("get_port_zone") else {}
		if not zone.is_empty() and dist <= float(zone.get("radius", 0.0)):
			var advisory: float = float(zone.get("rules", {}).get("speed_advisory", 0.0))
			if advisory > 0.0:
				allowed = minf(allowed, advisory)
		limit = minf(limit, allowed)
	return limit

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
