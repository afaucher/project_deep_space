extends "res://addons/beehave/nodes/leaves/action.gd"

# M59 -- the lane response. A patrol reads the SAME incident map cargo reads
# (scripts/mail/risk_map.gd) and moves toward what cargo is moving away from.
#
# WHY THIS EXISTS, measured rather than assumed. A patrol orbits its home
# station at 24,000u (home_cluster.gd's `12000.0 * SCALE`) while lane piracy
# happens ~300,000u out. Station and LAC comms are both 30,000u, so a patrol on
# station IS inside the relay link and DOES receive notarized warrants -- that
# part works. What it never does is ENCOUNTER the subject. Without this leaf a
# patrol can hold a valid warrant for a pirate for an entire campaign and never
# once be in the same region of space as it. The warrant was never the missing
# piece; a reason to leave the orbit was.
#
# Sits AHEAD of JobRunner in build_patrol (ai_tree_factory.gd), same shape as
# RoutePlannerLeaf: a planning leaf that always returns FAILURE, so it never
# claims the tick -- it only decides what the job runner will find. Motion is
# JobRunner's, as it is for every other job in the game.
#
# USES THE `assignment` SLOT, NOT `default_job`. JobRunnerLeaf's two-slot model
# already means "an overriding mission pre-empts the standing duty, and the
# standing duty resumes when it ends". A sweep is exactly that, so the authored
# diamond route survives untouched and comes back on its own -- overwriting
# default_job would destroy the patrol's route permanently, which is the sort of
# thing that looks fine in a test and ruins a campaign an hour in.
#
# Deliberately NOT here: chasing a specific hull. This leaf sends a patrol to a
# PLACE, and what happens when it gets there is the existing Interdict/Engage
# machinery reacting to whatever it finds -- including nothing. A patrol that
# sweeps an empty lane because the news was stale is correct behaviour, not a
# bug: the whole model is that information is old.
const RiskMap = preload("res://scripts/mail/risk_map.gd")
const Mailbag = preload("res://scripts/mail/mailbag.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

# How far from its current position a patrol will go to answer a report. Keeps
# a patrol responding to its own neighbourhood rather than abandoning a station
# to cross the cluster -- the "who is nearest" question no director is around
# to answer.
const RESPONSE_RANGE := 220000.0

# Re-decide at most this often. A sweep is a commitment, not a per-frame
# opinion; without this the patrol would re-target every tick as recency
# weights drift and never actually arrive anywhere.
const DECIDE_INTERVAL_FRAMES := 1800   # 30s

# A hotspot must outweigh this to be worth leaving station for.
#
# 2026-08-02 -- was a bare 20.0, which is ~80% of ONE fresh incident
# (RiskMap.WEIGHT_PER_INCIDENT = 25). Combined with a half-life shorter than
# delivery latency that made it unreachable: a report arriving 22 game-minutes
# old weighed 1.1. Measured result was patrols holding the news 2/2 and sweeping
# ZERO times.
#
# Expressed as a FRACTION of WEIGHT_PER_INCIDENT rather than an absolute, so it
# cannot silently drift when that constant moves -- the same mis-scaling that
# bit HYSTERESIS_MARGIN when LOT_SIZE changed.
#
# Policy this encodes: **a single credible report is worth investigating.** A
# robbery is rare (measured ~2 per game-hour), so requiring a CLUSTER before a
# patrol will move means it never moves. What the threshold still rejects is a
# report so old it has decayed past a third of its original weight -- roughly an
# hour and a half at the current half-life.
const MIN_HOTSPOT_WEIGHT := RiskMap.WEIGHT_PER_INCIDENT * 0.3

# How long to loiter on arrival before the sweep completes and the patrol falls
# back to its route. Long enough for the sensor sweep to actually find someone.
const LOITER_SECONDS := 45.0

# ROUTINE PATROL (2026-08-02). Absent any news, a patrol used to loop a
# 24,000u diamond around one station FOREVER -- on a map whose lanes are
# 300,000u long. It only ever left on an incident, which measured 2 runs in 5.
#
# Two payoffs, and the second is the bigger one:
#   * coverage -- a hull that visits neighbours can stumble onto a pirate that
#     nobody has reported;
#   * COURIER -- arriving within a station's 30,000u comms range triggers the
#     tier-1 mailbag relay (patrols share HOME_IFF with home stations), so a
#     circulating patrol carries news BETWEEN stations. Today the only couriers
#     are haulers, and haulers go where cargo is, which is precisely where
#     trouble is not. No docking needed: radio range is enough.
#
# THERE AND BACK, explicitly. The sweep path relies on the diamond resuming to
# get home, which is a side effect rather than a decision; a routine patrol
# states its return leg so the hull visibly cycles out and back.
const ROUTINE_INTERVAL_FRAMES := 21600   # 6 game-minutes between circuits
const ROUTINE_LOITER_SECONDS := 20.0     # long enough for a relay tick to land
const ROUTINE_MAX_RANGE := 260000.0      # a neighbour, not the far side of the cluster

var _last_decide_frame: int = -DECIDE_INTERVAL_FRAMES
var _last_routine_frame: int = -ROUTINE_INTERVAL_FRAMES
var _home: Vector2 = Vector2.INF          # cached on first tick -- nearest station
var _last_dest: Vector2 = Vector2.INF     # avoid picking the same neighbour twice running

# ONE WEIGHTED DRAW over a mixed candidate list (2026-08-02):
#
#   [{hotspot, weight = severity x proximity x recency}, {station, weight = 1}, ...]
#
# A sweep and a routine circuit are the SAME ACT -- go somewhere, look, come
# home -- differing only in why. Expressing that as one draw removes a pile of
# machinery that existed to arbitrate between two branches: no MIN_HOTSPOT
# threshold as a policy gate, no separate routine interval, no "sweep or
# circulate" decision.
#
# It also fixes the stickiness measured earlier. Deterministic argmax kept a
# patrol parked on one report for its whole ~52-minute actionable life (52
# sweeps off 2 incidents). Now a fresh incident at weight 25 competes against
# ~12 stations at weight 1, so it wins about 2/3 of draws -- dominant, not
# absolute -- and as it decays its share falls, so attention drifts to newer
# trouble or back to ordinary circulation without any "this is stale" rule.
#
# STATION_WEIGHT is the dial for how much a patrol wanders when nothing is
# happening. Raising it makes patrols circulate more and chase less.
const STATION_WEIGHT := 1.0

# A floor, NOT a policy gate: it exists so near-zero hotspots do not bloat the
# candidate list, not to decide what is worth answering. The draw decides that.
const HOTSPOT_NOISE_FLOOR := 0.5

func _candidates(actor: Node, cluster, heard: Array, frame: int) -> Array:
	var out: Array = []
	for e in heard:
		var p: Vector2 = e.get("pos", Vector2.ZERO)
		if actor.position.distance_to(p) > RESPONSE_RANGE:
			continue
		var w: float = RiskMap.weight_at(heard, p, frame)
		if w <= HOTSPOT_NOISE_FLOOR:
			continue
		out.append({"pos": p, "weight": w, "why": "SWEEP %s" % e.get("kind", "?")})
	for rec in cluster.records:
		if rec.kind != ClusterEntity.Kind.STATION:
			continue
		if rec.pos == _home:
			continue # "go home and come home" is a no-op
		if _home != Vector2.INF and _home.distance_to(rec.pos) > ROUTINE_MAX_RANGE:
			continue
		out.append({"pos": rec.pos, "weight": STATION_WEIGHT, "why": "ROUTINE"})
	return out

func tick(actor: Node, _blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE
	if not actor.assignment.is_empty():
		return FAILURE # already on a mission -- never interrupt

	var frame := Engine.get_physics_frames()
	if frame - _last_decide_frame < DECIDE_INTERVAL_FRAMES:
		return FAILURE
	_last_decide_frame = frame

	var cluster = actor.get("cluster_manager_ref")
	if cluster == null or not is_instance_valid(cluster):
		return FAILURE
	if not actor.has_method("get_mailbag"):
		return FAILURE

	# Home is wherever this hull started its beat -- cached once, so a patrol
	# dragged far out by a sweep still knows where "back" is.
	if _home == Vector2.INF:
		var best: float = INF
		for rec in cluster.records:
			if rec.kind != ClusterEntity.Kind.STATION:
				continue
			var d: float = actor.position.distance_to(rec.pos)
			if d < best:
				best = d
				_home = rec.pos
		if _home == Vector2.INF:
			# No station known (bare fixture, or a cluster whose stations are
			# all dormant). Fall back to where this hull was standing when it
			# first decided -- a patrol always has a place it started, and the
			# there-and-back shape must not depend on finding a station.
			_home = actor.position

	# Heard news only, clamped to this hull's delivered version. A patrol out of
	# touch draws against a stale picture, which is the point.
	var heard: Array = Mailbag.read_incidents(cluster, actor.get_mailbag())
	var cands: Array = _candidates(actor, cluster, heard, frame)
	if cands.is_empty():
		return FAILURE

	var total: float = 0.0
	for c in cands:
		total += c["weight"]
	var roll: float = randf() * total
	var pick: Dictionary = cands[cands.size() - 1]
	for c in cands:
		roll -= c["weight"]
		if roll <= 0.0:
			pick = c
			break

	actor.assign_job({
		"sweep": true, # marker: an instrument must tell this from an Interdict demand
		"steps": [
			{"verb": "GO_TO", "pos": pick["pos"]},
			# Loiter: long enough to sweep sensors, and -- at a station -- long
			# enough inside its 30,000u comms envelope for the tier-1 mailbag
			# relay to tick. That is what makes a circulating patrol a COURIER,
			# carrying news between stations without any docking mechanics.
			{"verb": "AWAIT", "condition": "clear", "clear_range": 0.0,
				"timeout": LOITER_SECONDS, "on_abort": ""},
			# The return leg is STATED, not inherited from the diamond route
			# resuming -- so the hull visibly cycles out and back.
			{"verb": "GO_TO", "pos": _home},
		],
		"current": 0,
	})
	if DebugSettings and DebugSettings.get_choice("patrol_log") == DebugSettings.PatrolLog.ON:
		print("[Patrol] %s: %s to %s (w %.1f of %.1f over %d candidates) -- %d incidents heard" % [
			actor.debug_label(), pick["why"], str(pick["pos"]), pick["weight"], total, cands.size(), heard.size()])
	return FAILURE
