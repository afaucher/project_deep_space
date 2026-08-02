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

# How far from its current position a patrol will go to answer a report. Keeps
# a patrol responding to its own neighbourhood rather than abandoning a station
# to cross the cluster -- the "who is nearest" question no director is around
# to answer.
const RESPONSE_RANGE := 220000.0

# Re-decide at most this often. A sweep is a commitment, not a per-frame
# opinion; without this the patrol would re-target every tick as recency
# weights drift and never actually arrive anywhere.
const DECIDE_INTERVAL_FRAMES := 1800   # 30s

# A hotspot must outweigh this to be worth leaving station for. One stale
# report should not pull a patrol off its post.
const MIN_HOTSPOT_WEIGHT := 20.0

# How long to loiter on arrival before the sweep completes and the patrol falls
# back to its route. Long enough for the sensor sweep to actually find someone.
const LOITER_SECONDS := 45.0

var _last_decide_frame: int = -DECIDE_INTERVAL_FRAMES

func tick(actor: Node, _blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE
	if not actor.assignment.is_empty():
		return FAILURE # already on a mission (a sweep, or an Interdict demand) -- never interrupt

	var frame := Engine.get_physics_frames()
	if frame - _last_decide_frame < DECIDE_INTERVAL_FRAMES:
		return FAILURE
	_last_decide_frame = frame

	var cluster = actor.get("cluster_manager_ref")
	if cluster == null or not is_instance_valid(cluster):
		return FAILURE # bare fixture, never promoted -- nothing to read
	if not actor.has_method("get_mailbag"):
		return FAILURE

	# Heard news only, clamped to this hull's delivered version. A patrol that
	# has been out of touch sweeps against a stale picture, which is the point.
	var heard: Array = Mailbag.read_incidents(cluster, actor.get_mailbag())
	if heard.is_empty():
		return FAILURE

	var hot: Dictionary = RiskMap.hotspot(heard, frame, actor.position, RESPONSE_RANGE)
	if hot.is_empty() or hot.get("weight", 0.0) < MIN_HOTSPOT_WEIGHT:
		return FAILURE

	actor.assign_job({
		# Marker so an instrument can tell a lane sweep apart from an Interdict
		# demand -- both land in the same assignment slot, and a funnel that
		# counted "patrol has an assignment" would silently conflate them.
		"sweep": true,
		"steps": [
			{"verb": "GO_TO", "pos": hot["pos"]},
			# clear_range 0 makes this a pure timer: loiter, sweep, then done.
			{"verb": "AWAIT", "condition": "clear", "clear_range": 0.0,
				"timeout": LOITER_SECONDS, "on_abort": ""},
		],
		"current": 0,
	})
	if DebugSettings and DebugSettings.get_choice("patrol_log") == DebugSettings.PatrolLog.ON:
		print("[Patrol] %s: SWEEP to %s (weight %.1f, %s%s) -- %d incidents heard" % [
			actor.debug_label(), str(hot["pos"]), hot.get("weight", 0.0),
			hot.get("kind", "?"),
			" on %s" % hot["subject_name"] if hot.get("subject_name", "") != "" else "",
			heard.size()])
	return FAILURE
