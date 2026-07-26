extends "res://addons/beehave/nodes/leaves/action.gd"

# M53c Phase C -- the re-plan leaf (design_ideas/station_economy.md "The
# independent's plan"; implementation_plans/m53c_demand_routing.md "Phase C").
# Sits AHEAD of JobRunner in ai_tree_factory.build_civilian_job() so it can
# (re)plant a fresh route into actor.default_job before the runner ticks it
# THIS SAME frame -- the identical "assign then let the runner pick it up
# same-tick" idiom Interdict/JobRunner already use (see that pairing's own
# header comment in ai_tree_factory.gd). Always returns FAILURE -- a
# side-effect leaf, exactly like Interdict/Challenge: it never claims the
# tick itself, JobRunner (next in the selector) does the actual flying.
#
# Only manages the STANDING-DUTY slot (default_job) -- an overriding
# `assignment` (a guild hunt, an M52 demand response) is left completely
# alone, the same "assignment wins" rule JobRunnerLeaf itself follows. This is
# also what keeps the transient wormhole freighters (TrafficGuild, which use
# assign_job()/`assignment` for their fixed GO_TO/DOCK_AT/EXIT_AT itinerary)
# untouched even though they run this same tree -- their route lives in the
# slot this leaf never looks at.
#
# Re-plans when:
#   - default_job is empty or already complete (design doc: "re-plan on
#     itinerary completion") -- always takes best_route(), whatever it is.
#   - default_job is a route-shaped job (carries "pickup_accept" --
#     RoutePlanner.route_itinerary()'s own marker) AND enough real time has
#     passed since the last check (REPLAN_CHECK_INTERVAL) to be worth the
#     cost. Standing in for "a material information change" (design doc) now
#     that the board is globally readable and drifts continuously -- there is
#     no fog/latency substrate yet (Mail phase 2-3, out of scope) to gate on
#     an actual event. RoutePlanner.should_replan()'s hysteresis margin is
#     what actually keeps this from thrashing between near-equal routes.
# A default_job that ISN'T route-shaped (an authored non-planner standing
# duty, if one ever runs this tree) is left alone by the periodic check --
# only replaced once it empties, same as any other job.

const RoutePlanner = preload("res://scripts/ai/route_planner.gd")

# Real-seconds between re-evaluations of an ALREADY-running route plan. Cheap
# to check (RoutePlanner.best_route is at most a few hundred dict reads), but
# there is no reason to re-search every physics tick -- the board only moves
# on the station economy's own policy_period (StationEconomy, default 10s),
# so checking faster than that buys nothing.
const REPLAN_CHECK_INTERVAL := 10.0

# Per-instance (not per-ship-class) throttle for the EMPTY-job search below --
# ai_tree_factory.build_civilian_job() builds a fresh tree (and therefore a
# fresh leaf instance) per promoted ship, so this is safe as plain instance
# state, not a Ship field. Bug found empirically (M53c Phase C review,
# 2026-07-25): with no job at all, the old code called RoutePlanner.
# best_route() -- the SAME O(stations^2 x commodities) search -- EVERY
# PHYSICS TICK, unboundedly, for as long as nothing viable existed (e.g. a
# freshly-loaded cluster before any EXPORT posting has opened -- see
# route_planner.gd's TRAVEL_COST_PER_UNIT-adjacent economics: a source/
# converter-fed bin needs ~8-29 REAL HOURS to clear its surplus_line and open
# its first EXPORT). A single idle hauler burned tens of thousands of
# redundant searches a minute; a fleet of them is a real perf problem, not
# just log spam. Throttled to the same REPLAN_CHECK_INTERVAL cadence as the
# has-a-job path.
var _last_empty_search_frame: int = -1

func tick(actor: Node, _blackboard) -> int:
	if actor == null or actor.is_dead:
		return FAILURE
	if not actor.assignment.is_empty():
		return FAILURE # an overriding mission owns this tick -- never touch it

	var cluster = actor.get("cluster_manager_ref")
	if cluster == null or not is_instance_valid(cluster):
		return FAILURE # never promoted through a ClusterManager (sandbox/bare fixture) -- nothing to plan against

	var job: Dictionary = actor.default_job
	var steps: Array = job.get("steps", [])
	var complete: bool = job.is_empty() or job.get("current", 0) >= steps.size()

	if not complete:
		if not job.has("pickup_accept"):
			return FAILURE # a non-planner standing duty -- not ours to touch
		if not _due_for_check(job):
			return FAILURE
		job["_replan_check_frame"] = Engine.get_physics_frames()
		var candidate: Dictionary = RoutePlanner.best_route(cluster, actor.position, _own_flag(actor))
		if candidate.is_empty():
			return FAILURE
		var remaining: float = RoutePlanner.remaining_value(actor.position, job)
		if not RoutePlanner.should_replan(remaining, candidate["score"]):
			return FAILURE
		actor.set_default_job(RoutePlanner.route_itinerary(candidate))
		_job_log(actor, "RE-PLAN %s %s->%s (score %.1f beat remaining %.1f by margin)" %
			[candidate["commodity"], candidate["pickup_name"], candidate["dropoff_name"], candidate["score"], remaining])
		return FAILURE

	if not _due_for_empty_search():
		return FAILURE
	_last_empty_search_frame = Engine.get_physics_frames()
	var route: Dictionary = RoutePlanner.best_route(cluster, actor.position, _own_flag(actor))
	if route.is_empty():
		return FAILURE # nothing viable anywhere right now -- Idle (below JobRunner) picks this up
	actor.set_default_job(RoutePlanner.route_itinerary(route))
	actor.default_job["_replan_check_frame"] = Engine.get_physics_frames()
	_job_log(actor, "PLAN %s %s->%s (score %.1f)" %
		[route["commodity"], route["pickup_name"], route["dropoff_name"], route["score"]])
	return FAILURE

func _due_for_empty_search() -> bool:
	if _last_empty_search_frame < 0:
		return true
	var elapsed: float = (Engine.get_physics_frames() - _last_empty_search_frame) / 60.0
	return elapsed >= REPLAN_CHECK_INTERVAL

# The ship's own currently-broadcast flag -- what a station's price()/
# is_eligible() sees this ship as (StationEconomy's asker_flag). "" (no
# active transponder, or none at all) reads as an anonymous asker: eligible
# only for unrestricted postings, foreign_multiplier pricing everywhere.
func _own_flag(actor: Node) -> String:
	if actor.has_method("get_active_transponder_data"):
		return actor.get_active_transponder_data().get("flag", "")
	return ""

func _due_for_check(job: Dictionary) -> bool:
	var last: int = job.get("_replan_check_frame", -1)
	if last < 0:
		return true
	var elapsed: float = (Engine.get_physics_frames() - last) / 60.0
	return elapsed >= REPLAN_CHECK_INTERVAL

func _job_log(actor: Node, msg: String) -> void:
	if DebugSettings and DebugSettings.get_choice("job_log") == DebugSettings.JobLog.ON:
		print("[RoutePlanner] %s: %s" % [actor.debug_label(), msg])
