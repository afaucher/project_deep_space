extends Node

# M50 -- the generality proof (implementation_plans/m50_pirate_tree_design.md
# "Tests"): a plain ship runs GO_TO -> DOCK_AT -> AWAIT{undocked} -> EXIT_AT
# through the job runner against a REAL station (SmallStation, open/
# uncontrolled -- same station class test_docking.gd exercises). This is the
# trader/commuter skeleton, shipped a milestone early on purpose (design_
# ideas/jobs_and_itineraries.md: "a trader IS GO_TO -> DOCK_AT -> AWAIT ->
# GO_TO -> DOCK_AT -> ... -> EXIT_AT as data").
#
# `await get_tree().physics_frame` live-ship style, generous settle loops,
# never exact frames (Godot 2D physics/timing isn't bit-deterministic
# run-to-run, CLAUDE.md).

const SmallStation = preload("res://scripts/ships/small_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DockingBay = preload("res://scripts/docking/docking_bay.gd")
const JobRunnerLeaf = preload("res://scripts/ai/jobs/job_runner_leaf.gd")
const BlackboardScript = preload("res://addons/beehave/blackboard.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func setup(main) -> void:
	main_node = main
	print("Starting Visitor Itinerary (M50) Tests")

	var station = SmallStation.new()
	station.name = "VisitorStation"
	station.owner_id = 1
	station.iff_tags = ["TEAM_STATION"]
	station.position = Vector2.ZERO
	main_node.add_child(station) # _ready() grows the DockingBay
	spawned.append(station)

	var bay: Node = null
	for c in station.get_children():
		if c is DockingBay:
			bay = c
	if bay == null:
		_assert(false, "setup: station should have grown a DockingBay")
		_finish()
		return

	# CargoShuttle -- an ordinary dockable civilian hull, no cargo-specific
	# AI attached (the point is proving the GENERIC runner drives it, not
	# CargoRunLeaf). Starts well off the berth, same offset idiom as
	# test_docking.gd.
	# CargoShuttle is deliberately low-accel (design: "mass ~40, accel ~25") --
	# a few thousand units off-route is plenty to prove GO_TO recovers from
	# arbitrary displacement without paying an excessive real-time travel
	# budget in this test (see the generous settle loops below regardless).
	var visitor = CargoShuttle.new()
	visitor.name = "Visitor"
	visitor.owner_id = 50
	visitor.iff_tags = ["TEAM_VISITOR"]
	visitor.position = Vector2(4500, 3500)
	main_node.add_child(visitor)
	spawned.append(visitor)

	var exit_pos: Vector2 = Vector2(9000, 9000)

	var job := {
		"steps": [
			{"verb": "GO_TO", "pos": station.position}, # default arrive_radius/cruise (1500.0/700.0)
			{"verb": "DOCK_AT", "station_pos": station.position},
			{"verb": "AWAIT", "condition": "undocked"},
			{"verb": "EXIT_AT", "pos": exit_pos}, # default radius/cruise (1500.0/700.0)
		],
		"current": 0,
	}
	visitor.assign_job(job)

	var runner = JobRunnerLeaf.new()
	var bb = BlackboardScript.new()

	# --- Phase 1: GO_TO -> DOCK_AT -> actually captured/DOCKED. ---
	var docked := false
	for i in range(3600): # up to 60s -- CargoShuttle is deliberately low-accel
		await main_node.get_tree().physics_frame
		if not is_instance_valid(visitor):
			break
		runner.tick(visitor, bb)
		if bay.state == DockingBay.State.DOCKED:
			docked = true
			break
	_assert(docked, "GO_TO -> DOCK_AT drove the visitor to a real capture (bay state=%d, job current=%d)" % [bay.state, job.get("current", -1)])
	_assert(job.get("current", -1) == 2, "job advanced past DOCK_AT to the AWAIT{undocked} step once captured (current=%d)" % job.get("current", -1))

	# --- Phase 2: AWAIT{undocked} rides out the station's own release cycle
	# (manual_undock defaults false -> DockingBay auto-releases after
	# dock_duration, same M19 timer cargo shuttles ride). ---
	var released := false
	for i in range(600): # up to 10s -- comfortably past SmallStation's dock_duration
		await main_node.get_tree().physics_frame
		if not is_instance_valid(visitor):
			break
		runner.tick(visitor, bb)
		if bay.state == DockingBay.State.EMPTY and visitor.get("docking_bay") == null:
			released = true
			break
	_assert(released, "the station released the visitor and AWAIT{undocked} observed it (bay state=%d)" % bay.state)
	_assert(job.get("current", -1) == 3, "job advanced past AWAIT{undocked} to EXIT_AT once released (current=%d)" % job.get("current", -1))

	# --- Phase 3: EXIT_AT flies to the exit point and despawns. ---
	var despawned := false
	var last_dist := INF
	for i in range(3600): # up to 60s -- CargoShuttle is deliberately low-accel
		await main_node.get_tree().physics_frame
		if not is_instance_valid(visitor):
			despawned = true
			break
		last_dist = visitor.position.distance_to(exit_pos)
		runner.tick(visitor, bb)
	_assert(despawned, "EXIT_AT despawned the visitor on arrival (last known distance to exit=%.0f)" % last_dist)
	spawned.erase(visitor) # already freed -- don't touch it again in cleanup

	_finish()

func _finish() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	if failures.is_empty():
		print(">>> [TEST PASSED] test_visitor_itinerary <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_visitor_itinerary <<<")
		get_tree().quit(1)
