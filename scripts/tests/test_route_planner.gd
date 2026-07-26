extends Node

# M53c Phase C acceptance (implementation_plans/m53c_demand_routing.md "Phase
# C -- The ship-side planner"; design_ideas/station_economy.md "Routing:
# EVERY ship plans for itself" / "The independent's plan"). Covers:
#   A. hysteresis -- a competing route only replaces the standing plan once it
#      clears the remaining value by a margin (pure function, RoutePlanner.
#      should_replan).
#   B. the deadhead leg is a REAL cost -- the SAME posting pair scores
#      differently (here: a sign flip) depending on where the ship already
#      is. Synthetic fixture, NOT the design doc's own worked numbers: that
#      table used a deliberately linear illustrative price curve while
#      StationEconomy.price() is mildly convex (see that file's own comment,
#      and route_planner.gd's TRAVEL_COST_PER_UNIT comment) -- not
#      bit-reproducible, so this reproduces the same QUALITATIVE ordering
#      (profitable from nearby, unprofitable from far away) with numbers this
#      test controls end to end.
#   C. two ships with different flags make different choices from IDENTICAL
#      world state -- the real Coldreach VOLATILES eligibility restriction
#      (home_cluster.gd) is the concrete, in-scope mechanism for this today
#      (fog/heard-sets are Mail phase 2-3, out of scope for Phase C).
#   D. anti-collapse (every eligible station served at least once over N
#      passes) and settling into a circuit (the back half of a long run
#      repeats a small number of routes) -- one simulation, both assertions,
#      against the REAL home cluster.
#   E. JobSteps.step_dock_at's new `delivery` param stages Ship.pending_
#      delivery on first entry to the step (pure function).
#   F. pending_delivery actually settles -- moves the right stock -- the
#      moment DockingBay's real DOCKED transition fires (Part 1's delivery
#      seam), driven by real physics like test_repair_services.gd.
# Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_route_planner

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const LivenessPolicy = preload("res://scripts/cluster/liveness_policy.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const Commodity = preload("res://scripts/economy/commodity.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const RoutePlanner = preload("res://scripts/ai/route_planner.gd")
const JobSteps = preload("res://scripts/ai/jobs/job_steps.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

const EPS := 0.01

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _approx(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < EPS, "%s (expected %.4f, got %.4f)" % [msg, b, a])

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func _mk_station(id: int, pos: Vector2 = Vector2.ZERO) -> ClusterEntity:
	var rec := ClusterEntity.new()
	rec.id = id
	rec.hull_script = SmallStation
	rec.kind = ClusterEntity.Kind.STATION
	rec.is_static = true
	rec.pos = pos
	StationEconomy.ensure_holder(rec, "self")
	return rec

func _set_bin(rec, holder: String, commodity: String, stock: float, capacity: float, target: float = -1.0, surplus_line: float = -1.0) -> void:
	var bin: Dictionary = rec.stocks[holder][commodity]
	bin["stock"] = stock
	bin["capacity"] = capacity
	bin["target"] = target if target >= 0.0 else capacity * 0.5
	bin["surplus_line"] = surplus_line if surplus_line >= 0.0 else capacity * 0.85

func _rec_by_id(cluster, id: int):
	for rec in cluster.records:
		if rec.id == id:
			return rec
	return null

func _med_bay(st) -> Node:
	for c in st.get_children():
		if c is DockingBay:
			return c
	return null

func setup(main) -> void:
	main_node = main
	print("Starting Route Planner (M53c Phase C) Tests")

	_test_hysteresis()
	_test_deadhead_leg_costed()
	_test_flag_changes_choice()
	_test_anti_collapse()
	_test_settles_into_circuit()
	_test_dock_at_stages_pending_delivery()

	_run_delivery_on_dock()

# ---------------------------------------------------------------------------
# A. Hysteresis -- a competing route must beat the current plan's remaining
# value by a margin, or a hauler thrashes between near-equal routes.
# ---------------------------------------------------------------------------
func _test_hysteresis() -> void:
	print("--- A: hysteresis prevents thrash under small posting updates ---")
	_assert(not RoutePlanner.should_replan(100.0, 100.0),
		"A: an EQUAL candidate never replaces the standing plan")
	_assert(not RoutePlanner.should_replan(100.0, 100.0 + RoutePlanner.HYSTERESIS_MARGIN * 0.5),
		"A: a small improvement (half the margin) does not clear the hysteresis band")
	_assert(not RoutePlanner.should_replan(100.0, 100.0 + RoutePlanner.HYSTERESIS_MARGIN),
		"A: an improvement of EXACTLY the margin does not clear it (strict >)")
	_assert(RoutePlanner.should_replan(100.0, 100.0 + RoutePlanner.HYSTERESIS_MARGIN + 1.0),
		"A: an improvement past the margin DOES replace the standing plan")
	_assert(RoutePlanner.should_replan(-INF, 1.0),
		"A: any viable candidate beats no plan at all (remaining_value's -INF sentinel)")

# ---------------------------------------------------------------------------
# B. The deadhead leg is a REAL cost -- the SAME posting pair, scored from two
# different ship positions, gives opposite-sign answers (design doc: "being
# already where the cargo is dominates").
# ---------------------------------------------------------------------------
func _test_deadhead_leg_costed() -> void:
	print("--- B: a deadhead leg is costed (position flips a route's score) ---")
	var pickup := _mk_station(970, Vector2(0, 0))
	_set_bin(pickup, "self", Commodity.ORE, 100.0, 100.0, 10.0, 50.0)   # stock == capacity -> max EXPORT urgency
	var dropoff := _mk_station(971, Vector2(50000, 0))
	_set_bin(dropoff, "self", Commodity.ORE, 0.0, 100.0, 50.0, 90.0)    # empty -> max IMPORT urgency

	var cluster := ClusterManager.new()
	cluster.add_record(pickup)
	cluster.add_record(dropoff)

	# NEAR: right on top of the pickup -- deadhead ~0.
	var route_near: Dictionary = RoutePlanner.best_route(cluster, Vector2(0, 0), "")
	_assert(not route_near.is_empty(), "B: a route exists from beside the pickup")
	if not route_near.is_empty():
		_assert(route_near["score"] > 0.0, "B: scored from NEXT TO the pickup, the route is profitable (score %.1f)" % route_near["score"])

	# FAR: a long way from the pickup -- the SAME pair, only the ship's
	# position changed.
	var far_pos := Vector2(2000000, 0)
	var route_far: Dictionary = RoutePlanner.best_route(cluster, far_pos, "")
	# This used to assert a route STILL came back from 2,000,000 units out, with a
	# negative score -- which encoded best_route()'s old argmax-even-when-losing
	# behaviour. RoutePlanner.MIN_VIABLE_SCORE now rejects it, and that rejection
	# is a STRONGER demonstration of the same point: the deadhead alone flipped an
	# identical posting pair from worth flying to not worth flying. Nothing about
	# the two stations changed -- only where the ship was standing.
	_assert(route_far.is_empty(),
		"B: the IDENTICAL posting pair is REJECTED from far away -- deadhead alone makes it unprofitable")

	# And a mid-range position still returns a route, but a worse-scoring one, so
	# the cost is graded rather than a cliff at the viability floor.
	var mid_pos := Vector2(120000, 0)
	var route_mid: Dictionary = RoutePlanner.best_route(cluster, mid_pos, "")
	_assert(not route_mid.is_empty(), "B: a mid-range route is still viable")
	if not route_mid.is_empty():
		_assert(route_near["score"] > route_mid["score"],
			"B: being already where the cargo is dominates (near %.1f > mid %.1f)" % [route_near["score"], route_mid["score"]])

# ---------------------------------------------------------------------------
# C. Two ships with different flags make different choices from IDENTICAL
# world state -- Coldreach's VOLATILES posting is eligible only for
# Standing.FLAG_MERIDIAN (home_cluster.gd's real authored restriction).
# ---------------------------------------------------------------------------
func _test_flag_changes_choice() -> void:
	print("--- C: two ships with different flags choose differently from the same world state ---")
	var def = HomeCluster.build()
	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)

	var coldreach = null
	var ironhold = null
	for rec in m.records:
		if rec.name == "Coldreach":
			coldreach = rec
		elif rec.name == "Ironhold":
			ironhold = rec
	_assert(coldreach != null and ironhold != null, "C: Coldreach and Ironhold exist in the authored home cluster")
	if coldreach == null or ironhold == null:
		return

	# Every OTHER bin in the freshly-loaded cluster starts exactly at target
	# (ClusterLoader's _bin() authors stock == target) -- SATISFIED, no
	# posting. Open exactly one EXPORT (Coldreach VOLATILES, Meridian-only)
	# and one IMPORT (Ironhold VOLATILES) so there is exactly one candidate
	# route in the whole cluster, and it is the restricted one.
	_set_bin(coldreach, "self", Commodity.VOLATILES,
		coldreach.stocks["self"][Commodity.VOLATILES]["capacity"], coldreach.stocks["self"][Commodity.VOLATILES]["capacity"],
		coldreach.stocks["self"][Commodity.VOLATILES]["target"], coldreach.stocks["self"][Commodity.VOLATILES]["surplus_line"])
	_set_bin(ironhold, "self", Commodity.VOLATILES, 0.0,
		ironhold.stocks["self"][Commodity.VOLATILES]["capacity"], ironhold.stocks["self"][Commodity.VOLATILES]["target"],
		ironhold.stocks["self"][Commodity.VOLATILES]["surplus_line"])

	var route_drift: Dictionary = RoutePlanner.best_route(m, coldreach.pos, Standing.FLAG_DRIFT)
	var route_meridian: Dictionary = RoutePlanner.best_route(m, coldreach.pos, Standing.FLAG_MERIDIAN)

	_assert(route_drift.is_empty(),
		"C: a Drift-flagged ship sitting AT Coldreach finds NOTHING (the only open posting is Meridian-restricted)")
	_assert(not route_meridian.is_empty(), "C: a Meridian-flagged ship in the identical world state finds the Coldreach->Ironhold lane")
	if not route_meridian.is_empty():
		_assert(route_meridian["commodity"] == Commodity.VOLATILES, "C: the Meridian ship's route is the VOLATILES lane")
		_assert(route_meridian["pickup_name"] == "Coldreach" and route_meridian["dropoff_name"] == "Ironhold",
			"C: the Meridian ship's route is Coldreach -> Ironhold")

# ---------------------------------------------------------------------------
# D. Anti-collapse -- every eligible station served at least once over N
# passes (the test that would have caught the rejected dock-count demand
# model), against the REAL home cluster.
#
# A SINGLE perpetual ship is the wrong fixture for this: the design doc
# itself says the periphery (Corvus Yards) is structurally underserved
# ("nobody comes" until its export urgency clears ~0.94) BECAUSE of where a
# ship already tends to be -- exactly principle 8's "being already where the
# cargo is dominates." A lone greedy ship can settle into a stable circuit
# among the well-connected hubs that never revisits a vantage point from
# which Corvus wins, which is a fixture artifact, not a routing bug (verified
# empirically: it reproduces even after 300+ passes of a single ship). The
# real system never has only one hauler (TrafficGuild's population floor), so
# this fixture starts one ship AT EACH station -- the same diversity of
# vantage points a real multi-hull fleet provides -- and unions what gets
# served across all of them.
# ---------------------------------------------------------------------------
func _test_anti_collapse() -> void:
	print("--- D: anti-collapse (every station served, real home cluster) ---")
	var def = HomeCluster.build()
	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	m.directors.append(econ)

	# Let real urgency develop from the authored converters/sinks/sources
	# before any hauling starts -- a freshly-loaded cluster starts every bin
	# exactly at target (SATISFIED, no postings at all).
	m.tick(24.0 * 3600.0)

	var stations: Array = []
	for rec in m.records:
		if rec.kind == ClusterEntity.Kind.STATION and rec.stocks.has("self") and not rec.industry.is_empty():
			stations.append(rec)
	_assert(stations.size() == 8, "D: fixture sanity -- 8 economically-active stations in the home cluster (got %d)" % stations.size())

	var ship_flag: String = Standing.FLAG_DRIFT
	var ship_positions: Array = []
	for rec in stations:
		ship_positions.append(rec.pos) # one ship starting AT each station
	var served: Dictionary = {}

	const PASSES_PER_SHIP := 15
	for p in range(PASSES_PER_SHIP):
		for s in range(ship_positions.size()):
			var route: Dictionary = RoutePlanner.best_route(m, ship_positions[s], ship_flag)
			if route.is_empty():
				continue
			served[route["pickup_name"]] = true
			served[route["dropoff_name"]] = true
			var pickup_rec = _rec_by_id(m, route["pickup_id"])
			var dropoff_rec = _rec_by_id(m, route["dropoff_id"])
			StationEconomy.fulfill(pickup_rec, route["pickup_accept"], route["amount"])
			StationEconomy.fulfill(dropoff_rec, route["dropoff_accept"], route["amount"])
			ship_positions[s] = route["dropoff_pos"]
		m.tick(1200.0) # ~20 simulated minutes per round of completed trips

	for rec in stations:
		_assert(served.has(rec.name), "D anti-collapse: %s was served (pickup or dropoff) at least once over %d ships x %d passes" %
			[rec.name, ship_positions.size(), PASSES_PER_SHIP])

# ---------------------------------------------------------------------------
# D2. A ship settles into a circuit over N passes rather than oscillating.
# Single, UNCONTESTED ship (a crowded multi-ship board is noisy pass to pass
# purely from seven competitors' own actions, which is a fixture artifact of
# testing many agents at once, not a property of any one ship's own
# planning). Explicitly applies the SAME hysteresis this leaf/RoutePlanner
# ships (RoutePlanner.should_replan against the just-completed route's own
# score) at each re-plan-on-completion decision -- the design doc's "re-plan
# on itinerary completion... WITH HYSTERESIS" applies the margin at
# completion too, not only mid-route, or a hauler would hop to whatever's
# nominally best every single lap purely from ordinary urgency jitter.
# ---------------------------------------------------------------------------
func _test_settles_into_circuit() -> void:
	print("--- D2: a ship settles into a circuit rather than oscillating ---")
	var def = HomeCluster.build()
	var m := ClusterManager.new()
	var pol := LivenessPolicy.new()
	pol.configure_bubble(1.0, 2.0)
	m.policy = pol
	m.viewpoint = Vector2(1e9, 1e9)
	ClusterLoader.load_into(def, m)
	var econ := StationEconomy.new({"policy_period": 3600.0})
	m.directors.append(econ)
	m.tick(24.0 * 3600.0)

	var ship_flag: String = Standing.FLAG_DRIFT
	var ship_pos: Vector2 = Vector2.ZERO # Ironhold
	var current: Dictionary = {} # the standing plan
	var route_log: Array = []

	const PASSES := 40
	for i in range(PASSES):
		var candidate: Dictionary = RoutePlanner.best_route(m, ship_pos, ship_flag)
		if candidate.is_empty():
			m.tick(3600.0)
			continue
		var chosen: Dictionary = candidate
		if not current.is_empty() and not RoutePlanner.should_replan(current["score"], candidate["score"]):
			chosen = current # candidate didn't clear the margin -- keep flying the standing plan
		current = chosen
		route_log.append("%s:%s->%s" % [chosen["commodity"], chosen["pickup_name"], chosen["dropoff_name"]])
		var pickup_rec = _rec_by_id(m, chosen["pickup_id"])
		var dropoff_rec = _rec_by_id(m, chosen["dropoff_id"])
		StationEconomy.fulfill(pickup_rec, chosen["pickup_accept"], chosen["amount"])
		StationEconomy.fulfill(dropoff_rec, chosen["dropoff_accept"], chosen["amount"])
		ship_pos = chosen["dropoff_pos"]
		m.tick(1200.0)

	var tail: Array = route_log.slice(int(route_log.size() / 2.0), route_log.size())
	var distinct: Dictionary = {}
	for r in tail:
		distinct[r] = distinct.get(r, 0) + 1
	_assert(tail.size() > 0, "D2: enough routes completed to judge (%d)" % route_log.size())
	if tail.size() > 0:
		_assert(distinct.size() <= max(2, int(tail.size() / 4.0)),
			"D2: the back half of the run settles onto a small number of repeating routes, hysteresis-gated (%d distinct out of %d passes: %s)" %
				[distinct.size(), tail.size(), str(distinct.keys())])

# ---------------------------------------------------------------------------
# E. JobSteps.step_dock_at's `delivery` param stages Ship.pending_delivery on
# first entry -- pure function, no docking/physics needed.
# ---------------------------------------------------------------------------
func _test_dock_at_stages_pending_delivery() -> void:
	print("--- E: DOCK_AT's `delivery` param stages Ship.pending_delivery ---")
	var shuttle = CargoShuttle.new()
	shuttle.name = "StageTest"
	shuttle.position = Vector2(500000, 500000) # nowhere near any station -- never actually docks
	main_node.add_child(shuttle)

	var step: Dictionary = {
		"verb": "DOCK_AT", "station_pos": Vector2(500000, 500000),
		"delivery": {"acceptance": {"holder": "self", "commodity": Commodity.ORE, "direction": "IMPORT", "price": 42.0, "asker_flag": Standing.FLAG_DRIFT}, "amount": 1.0},
		"scratch": {},
	}
	JobSteps.step_dock_at(shuttle, step, {})
	_assert(not shuttle.pending_delivery.is_empty(), "E: a 'delivery' param stages Ship.pending_delivery on the first tick of the step")
	_approx(shuttle.pending_delivery.get("amount", -1.0), 1.0, "E: the staged delivery carries the itinerary's amount")
	_assert(shuttle.pending_delivery.get("acceptance", {}).get("commodity", "") == Commodity.ORE,
		"E: the staged delivery carries the itinerary's acceptance")

	_free_if_valid(shuttle)

# ---------------------------------------------------------------------------
# F. pending_delivery settles on the REAL DOCKED transition (Part 1's
# delivery seam) -- physics-driven, same phase-machine idiom test_repair_
# services.gd uses to wait for a real capture to settle.
# ---------------------------------------------------------------------------
var g_station = null
var g_bay = null
var g_shuttle = null
var g_rec: ClusterEntity = null
var g_t: float = 0.0
const G_DOCK_TIMEOUT := 15.0

func _run_delivery_on_dock() -> void:
	print("--- F: pending_delivery settles the moment DockingBay reaches DOCKED ---")
	g_station = MediumStation.new()
	g_station.name = "DeliveryHost"
	g_station.owner_id = 1
	g_station.iff_tags = ["TEAM_PLAYER"]
	g_station.position = Vector2.ZERO
	g_station.port_zone = {"radius": 8000.0, "authority": "DeliveryHost Control", "rules": {}}
	main_node.add_child(g_station)
	g_bay = _med_bay(g_station)
	_assert(g_bay != null, "F: station grows a DockingBay")
	if g_bay == null:
		_finalize()
		return

	g_rec = ClusterEntity.new()
	g_rec.id = 980
	g_rec.kind = ClusterEntity.Kind.STATION
	g_rec.is_static = true
	StationEconomy.ensure_holder(g_rec, "self")
	_set_bin(g_rec, "self", Commodity.GOODS, 0.0, 100.0, 50.0) # empty -> IMPORT urgency 1.0
	g_station.cluster_record_ref = weakref(g_rec)

	var accept: Dictionary = StationEconomy.accept_posting(g_rec, "self", Commodity.GOODS, "")
	_assert(not accept.is_empty(), "F: a real posting exists to accept against")

	var fwd: Vector2 = Vector2.RIGHT.rotated(g_bay.global_rotation)
	g_shuttle = CargoShuttle.new()
	g_shuttle.name = "DeliveryShuttle"
	g_shuttle.owner_id = 60
	g_shuttle.iff_tags = ["TEAM_PLAYER"]
	g_shuttle.dockable = true
	g_shuttle.position = g_bay.global_position + fwd * 200.0
	g_shuttle.pending_delivery = {"acceptance": accept, "amount": 5.0}
	main_node.add_child(g_shuttle)

	var result: Dictionary = g_station.request_docking_via_control(g_shuttle)
	_assert(result.get("outcome", "") == "granted", "F: docking request granted")
	g_shuttle.wants_dock = true
	g_t = 0.0

func _step_delivery_on_dock(delta: float) -> void:
	g_t += delta
	if g_bay.state == DockingBay.State.DOCKED:
		_assert(g_shuttle.pending_delivery.is_empty(), "F: pending_delivery is cleared the moment DOCKED settles")
		_approx(g_rec.stocks["self"][Commodity.GOODS]["stock"], 5.0, "F: 5 lots of GOODS actually landed in the station's own stock")
		_finish_delivery_on_dock()
	elif g_t > G_DOCK_TIMEOUT:
		_assert(false, "F: shuttle never reached DOCKED (state=%d)" % g_bay.state)
		_finish_delivery_on_dock()

func _finish_delivery_on_dock() -> void:
	_free_if_valid(g_shuttle)
	_free_if_valid(g_station)
	_finalize()

func _physics_process(delta: float) -> void:
	if finished:
		return
	if g_station != null and g_shuttle != null and is_instance_valid(g_shuttle):
		_step_delivery_on_dock(delta)

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_route_planner <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_route_planner <<<")
		get_tree().quit(1)
