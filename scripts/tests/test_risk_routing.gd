extends Node

# M59 acceptance -- cargo prices danger, and the loop that stops it being fatal
# (implementation_plans/m57_m61_information_economy_roadmap.md "M59").
#
# The M53c stub is now live: score = payout - travel_cost - risk, where risk is
# built from the READER'S OWN heard incidents. Four things must hold, and the
# last is the one that decides whether this milestone is a feature or a trap:
#
#   1. A hauler avoids a lane it has heard bad news about, choosing a rival lane
#      it would otherwise have passed over.
#   2. A hauler that heard NOTHING still flies the dangerous lane. Risk is
#      knowledge, not physics -- this is the fog behaving, and it is what makes
#      "flying into an ambush the player already knows about" possible.
#   3. Enough danger makes a lane not worth flying at all (MIN_VIABLE_SCORE).
#   4. **ROUTE ABANDONMENT IS NOT TERMINAL.** As a lane goes unserved its
#      destination's urgency climbs, its posting price climbs, and eventually
#      somebody takes the dangerous job because it finally pays enough. Without
#      this the risk term is a one-way ratchet that strangles the economy it
#      was added to make interesting. Section [4] is the real acceptance test.
#
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_risk_routing

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Incident = preload("res://scripts/mail/incident.gd")
const RiskMap = preload("res://scripts/mail/risk_map.gd")
const Mailbag = preload("res://scripts/mail/mailbag.gd")
const PatrolResponseLeaf = preload("res://scripts/ai/leaves/patrol_response_leaf.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")

var failures: Array = []
var finished: bool = false

# Two lanes out of one origin, deliberately near-equal in value so the risk term
# is the only thing that can decide between them.
const ORIGIN := Vector2(0, 0)
const SAFE_END := Vector2(0, 300000)
const DANGER_END := Vector2(300000, 0)

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _mk_station(id: int, pos: Vector2) -> ClusterEntity:
	var rec := ClusterEntity.new()
	rec.id = id
	rec.hull_script = SmallStation
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
	rec.pos = pos
	StationEconomy.ensure_holder(rec, "self")
	return rec

func _set_bin(rec, commodity: String, stock: float, capacity: float) -> void:
	var bin: Dictionary = rec.stocks["self"][commodity]
	bin["stock"] = stock
	bin["capacity"] = capacity
	bin["target"] = capacity * 0.5
	bin["surplus_line"] = capacity * 0.85

# Origin exports; both destinations import. `danger_stock` controls how starved
# the dangerous destination is -- which is the urgency dial section [4] turns.
func _build(danger_stock: float, safe_stock: float = 45.0) -> ClusterManager:
	var origin := _mk_station(980, ORIGIN)
	_set_bin(origin, Commodity.ORE, 100.0, 100.0)      # full -> max EXPORT urgency
	var safe := _mk_station(981, SAFE_END)
	_set_bin(safe, Commodity.ORE, safe_stock, 100.0)
	var danger := _mk_station(982, DANGER_END)
	_set_bin(danger, Commodity.ORE, danger_stock, 100.0)

	var cluster := ClusterManager.new()
	cluster.add_record(origin)
	cluster.add_record(safe)
	cluster.add_record(danger)
	return cluster

# An incident sitting on the middle of the dangerous lane.
func _danger_news(count: int, stamp: int = 0) -> Array:
	var out: Array = []
	for i in range(count):
		var e: Dictionary = Incident.make(Incident.KIND_ARMED_ROBBERY, "Raider", "PIRATE",
			DANGER_END * 0.5, "Victim")
		e["seq"] = i + 1
		e["stamp"] = stamp
		out.append(e)
	return out

func setup(_main) -> void:
	print("Starting Risk-Aware Routing (M59) Tests")
	_test_baseline_prefers_danger_lane()
	_test_news_flips_the_choice()
	_test_ignorance_flies_it_anyway()
	_test_enough_danger_kills_the_lane()
	_test_abandonment_is_not_terminal()
	_test_one_map_opposite_signs()
	_test_patrol_sweeps_toward_trouble(_main)
	_finalize()

# --- 1. Establish the control. ----------------------------------------------
func _test_baseline_prefers_danger_lane() -> void:
	print("[1] with no news, the hungrier destination wins (the control)")
	var cluster := _build(10.0) # starved -> strong IMPORT pull, beats the safe lane
	var route: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "")
	_assert(not route.is_empty(), "a route exists")
	if not route.is_empty():
		_assert(route["dropoff_id"] == 982,
			"the starved (dangerous) destination is chosen when nothing is known (picked %d)" % route["dropoff_id"])

# --- 2. Heard news changes the decision. ------------------------------------
func _test_news_flips_the_choice() -> void:
	print("[2] heard news reroutes the hauler")
	var cluster := _build(30.0)
	var route: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "", _danger_news(3))
	_assert(not route.is_empty(), "a route still exists -- the hauler diverts rather than idling")
	if not route.is_empty():
		_assert(route["dropoff_id"] == 981,
			"it now takes the SAFE lane it previously passed over (picked %d)" % route["dropoff_id"])

# --- 3. The fog: risk is knowledge, not physics. ----------------------------
func _test_ignorance_flies_it_anyway() -> void:
	print("[3] a hauler that heard nothing flies into it")
	var cluster := _build(30.0)
	var informed: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "", _danger_news(3))
	var ignorant: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "", [])
	_assert(not informed.is_empty() and not ignorant.is_empty(), "both hulls plan a route")
	if not informed.is_empty() and not ignorant.is_empty():
		_assert(informed["dropoff_id"] != ignorant["dropoff_id"],
			"two hulls, IDENTICAL world state, different destinations -- they were told different things")
		_assert(ignorant["dropoff_id"] == 982,
			"the uninformed one flies the lane the informed one is avoiding")

# --- 4. Enough danger closes a lane outright. -------------------------------
func _test_enough_danger_kills_the_lane() -> void:
	print("[4] enough danger makes a lane not worth flying")
	# Only the dangerous destination has any pull at all, so there is no rival
	# lane to divert to -- the choice is fly it or idle.
	var origin := _mk_station(990, ORIGIN)
	_set_bin(origin, Commodity.ORE, 100.0, 100.0)
	var danger := _mk_station(991, DANGER_END)
	_set_bin(danger, Commodity.ORE, 40.0, 100.0) # mild pull -> thin margin
	var cluster := ClusterManager.new()
	cluster.add_record(origin)
	cluster.add_record(danger)

	var quiet: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "")
	_assert(not quiet.is_empty(), "the lane is viable when nothing is known")
	var loud: Dictionary = RoutePlanner.best_route(cluster, ORIGIN, "", _danger_news(6))
	_assert(loud.is_empty(), "six fresh robberies on it and the hauler idles instead -- no route worth flying")

# --- 5. THE ACCEPTANCE TEST: abandonment must not be terminal. --------------
func _test_abandonment_is_not_terminal() -> void:
	print("[5] a starving destination wins the abandoned lane back")
	var news := _danger_news(3)

	# IDENTICAL danger, IDENTICAL news. The only thing that changes is how
	# starved the dangerous destination has become -- which is exactly what
	# happens to it BECAUSE haulers stopped going. If risk were absolute rather
	# than priced, the lane could never recover and the economy behind it would
	# strangle.
	var abandoned: Dictionary = RoutePlanner.best_route(_build(30.0), ORIGIN, "", news)
	var starving: Dictionary = RoutePlanner.best_route(_build(0.0), ORIGIN, "", news)

	_assert(not abandoned.is_empty() and abandoned["dropoff_id"] == 981,
		"at moderate hunger the dangerous lane stays abandoned (picked %s)" % str(abandoned.get("dropoff_id", -1)))
	_assert(not starving.is_empty() and starving["dropoff_id"] == 982,
		"once it is starving, somebody takes the job again (picked %s)" % str(starving.get("dropoff_id", -1)))
	_assert(not starving.is_empty() and starving["score"] > 0.0,
		"and the dangerous run is genuinely profitable at that price, not merely least-bad")

# --- 6. THE THESIS: one map, read with opposite signs. ----------------------
func _test_one_map_opposite_signs() -> void:
	print("[6] cargo and patrol read the SAME map")
	var news := _danger_news(3)
	var mid: Vector2 = DANGER_END * 0.5

	var risk: float = RiskMap.lane_risk(ORIGIN, DANGER_END, news, 0)
	var hot: Dictionary = RiskMap.hotspot(news, 0, ORIGIN, 1000000.0)
	_assert(risk > 0.0, "the dangerous lane carries risk for cargo (%.1f)" % risk)
	_assert(not hot.is_empty() and hot["pos"] == mid,
		"and the patrol's hotspot is the SAME place cargo is avoiding")
	_assert(RiskMap.lane_risk(ORIGIN, SAFE_END, news, 0) == 0.0,
		"while the safe lane carries none -- the two sides cannot disagree, it is one function")

	# A cluster of three outweighs a lone outlier: sweep where trouble REPEATS,
	# not wherever the single most recent report happened to be.
	var mixed: Array = _danger_news(3)
	var lone: Dictionary = Incident.make(Incident.KIND_OVERDUE, "", "", Vector2(0, 250000), "G")
	lone["seq"] = 99
	lone["stamp"] = 0
	mixed.append(lone)
	var hot2: Dictionary = RiskMap.hotspot(mixed, 0, ORIGIN, 1000000.0)
	_assert(not hot2.is_empty() and hot2["pos"] == mid,
		"a cluster of three beats a lone outlier (picked %s)" % str(hot2.get("pos", "none")))

	# Range gates it: a patrol answers its own neighbourhood.
	_assert(RiskMap.hotspot(news, 0, Vector2(5000000, 0), 220000.0).is_empty(),
		"trouble on the far side of the cluster is not this patrol's to answer")

	# And recency decays it, which is the oscillation's damping term.
	var stale: Dictionary = RiskMap.hotspot(news, int(RiskMap.RISK_HALF_LIFE_FRAMES * 4.0), ORIGIN, 1000000.0)
	_assert(stale.is_empty() or stale["weight"] < hot["weight"],
		"old news weighs less than fresh news")

# --- 7. The patrol actually leaves its post. --------------------------------
func _test_patrol_sweeps_toward_trouble(main) -> void:
	print("[7] a patrol assigns a sweep from heard news")
	var patrol = Frigate.new()
	patrol.name = "Sweeper"
	patrol.owner_id = 95
	patrol.position = ORIGIN
	main.add_child(patrol)

	# A source record holding the incidents, and a cluster to find it in.
	var src := ClusterEntity.new()
	src.id = 777
	for e in _danger_news(3):
		src.incident_seq += 1
		e["seq"] = src.incident_seq
		src.incident_log.append(e)
	var cluster := ClusterManager.new()
	cluster.add_record(src)
	patrol.cluster_manager_ref = cluster

	var leaf = PatrolResponseLeaf.new()

	# Knows nothing yet -> stays on its route. The fog gates the patrol too.
	leaf.tick(patrol, null)
	_assert(patrol.assignment.is_empty(),
		"a patrol that has heard nothing does NOT leave station, though the log exists on the record")

	# Deliver the news, then let it decide again.
	Mailbag.sync_direct(patrol.get_mailbag(), src.id, src.incident_seq, 0)
	leaf._last_decide_frame = -100000
	leaf.tick(patrol, null)
	_assert(not patrol.assignment.is_empty(), "once told, it takes a sweep assignment")
	if not patrol.assignment.is_empty():
		var steps: Array = patrol.assignment.get("steps", [])
		_assert(steps.size() >= 1 and steps[0].get("verb", "") == "GO_TO",
			"the sweep is a GO_TO the reported place")
		if steps.size() >= 1:
			_assert(steps[0].get("pos", Vector2.ZERO) == DANGER_END * 0.5,
				"aimed at the hotspot, which is where cargo stopped flying")

	# It must not thrash: an existing assignment is never interrupted.
	var before: Dictionary = patrol.assignment
	leaf._last_decide_frame = -100000
	leaf.tick(patrol, null)
	_assert(patrol.assignment == before,
		"a sweep already under way is not re-decided every tick")

	patrol.queue_free()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_risk_routing <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_risk_routing <<<")
		get_tree().quit(1)
