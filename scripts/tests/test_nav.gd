extends Node

# M17 acceptance -- the nav computer's routing. Named destinations; an on-road
# route traverses the beacon chain; a severed edge (sabotaged beacon) and a short
# hop both collapse to a direct route; an off-graph (dark) destination routes via
# beacons then a direct final leg. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_nav
# Synchronous. Pass marker per CLAUDE.md.

const NavComputer = preload("res://scripts/nav/nav_computer.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Wormhole = preload("res://scripts/wormhole.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main) -> void:
	print("Starting Nav Computer (M17) Tests")
	var def = _build()

	# Named destinations: 4 beacons + 2 stations + 1 wormhole.
	var dests = NavComputer.destinations(def)
	_assert(dests.size() == 7, "destinations should list 4 beacons + 2 stations + wormhole (got %d)" % dests.size())
	_assert(_has_name(dests, "Ironhold"), "destinations should include Ironhold")
	_assert(_has_name(dests, "Nexus Wormhole"), "destinations should include the wormhole")

	# On-road: start by beacon 0, far dest by beacon 3 -> traverse all beacons + dest.
	var r = NavComputer.route(def, Vector2(-2000, 0), Vector2(32000, 0))
	_assert(r.size() == 5, "on-road route should be 4 beacons + dest (got %d)" % r.size())
	_assert(r[0] == Vector2(0, 0), "route should start at the nearest beacon")
	_assert(r[r.size() - 1] == Vector2(32000, 0), "route should end at the destination")

	# Severed edge -> direct (the sabotage mechanic).
	def.beacon_edges = [[10, 11], [12, 13]]           # drop 11-12
	var r2 = NavComputer.route(def, Vector2(-2000, 0), Vector2(32000, 0))
	_assert(r2.size() == 1 and r2[0] == Vector2(32000, 0), "a severed beacon graph should force a direct route")
	def.beacon_edges = [[10, 11], [11, 12], [12, 13]] # restore

	# Short hop -> direct, not via the road.
	var r3 = NavComputer.route(def, Vector2(-2000, 0), Vector2(-1500, 0))
	_assert(r3.size() == 1 and r3[0] == Vector2(-1500, 0), "a short hop should route direct")

	# Dark: off-graph destination -> beacon path then a direct final leg.
	var r4 = NavComputer.route(def, Vector2(-2000, 0), Vector2(15000, 50000))
	_assert(r4.size() >= 2, "an off-graph destination should route via beacons then direct")
	_assert(r4[r4.size() - 1] == Vector2(15000, 50000), "the final leg should end at the dark destination")
	_assert(not _is_beacon(def, r4[r4.size() - 1]), "the last waypoint should be the destination, not a beacon")

	if failures.is_empty():
		print(">>> [TEST PASSED] test_nav <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_nav <<<")
		get_tree().quit(1)

func _build():
	var def = ClusterDef.new()
	def.bounds = Rect2(-100000, -100000, 200000, 200000)
	for i in range(4):
		def.add_entity({"id": 10 + i, "name": "Beacon " + str(i), "hull": Buoy,
			"kind": ClusterEntity.Kind.BEACON, "pos": Vector2(i * 10000, 0)})
	def.beacon_edges = [[10, 11], [11, 12], [12, 13]]
	def.add_entity({"id": 1, "name": "Ironhold", "hull": SmallStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(0, -8000)})
	def.add_entity({"id": 2, "name": "Drift Market", "hull": SmallStation,
		"kind": ClusterEntity.Kind.STATION, "pos": Vector2(30000, -8000)})
	def.add_entity({"id": 500, "name": "Nexus Wormhole", "hull": Wormhole,
		"kind": ClusterEntity.Kind.WORMHOLE, "pos": Vector2(15000, 50000)})
	return def

func _has_name(dests: Array, dname: String) -> bool:
	for d in dests:
		if d["name"] == dname:
			return true
	return false

func _is_beacon(def, pos: Vector2) -> bool:
	for e in def.entities:
		if e.get("kind") == ClusterEntity.Kind.BEACON and e["pos"].distance_to(pos) < 1.0:
			return true
	return false
