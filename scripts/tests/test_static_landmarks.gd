extends Node

# M16 acceptance -- static landmarks. Proves the wormhole exists and promotes as
# a non-physics landmark, asteroid fields expand deterministically inside their
# radius, the beacon road validates as continuously lit (and is longer), and the
# validator trips on out-of-bounds fields / dark road gaps / outposts off fields.
# Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_static_landmarks
# Pass marker per CLAUDE.md. All checks synchronous (promote/demote are immediate).

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterValidator = preload("res://scripts/cluster/cluster_validator.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")

const FIELD_ID_BASE := 1000000
const FIELD_ID_STRIDE := 10000

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Static Landmarks (M16) Tests")

	_test_home_clean_and_lit()
	_test_broken_landmarks()
	_test_fields_expand()
	_test_wormhole_promotes()
	_test_road_is_longer()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_static_landmarks <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_static_landmarks <<<")
		get_tree().quit(1)

# The home cluster validates clean AND specifically lights its road / seats its
# outposts (no advisory warnings on those).
func _test_home_clean_and_lit() -> void:
	var def = HomeCluster.build()
	var r = ClusterValidator.validate(def)
	if not r["violations"].is_empty():
		print("Home cluster violations:")
		for v in r["violations"]:
			print("  id=", v["entity_id"], " field=", v["field"], " sev=", v["severity"], " -- ", v["reason"])
	var errors: Array = r["violations"].filter(func(v): return v["severity"] == "error")
	_assert(r["ok"] and errors.is_empty(), "home: zero error-severity violations")
	_assert(not _has_field(r["violations"], "road_lit"), "home: road should be fully lit (no road_lit warning)")
	_assert(not _has_field(r["violations"], "outpost_field"), "home: every outpost should sit on a field")
	_assert(not _has_field(r["violations"], "beacon_graph"), "home: beacon graph should be connected")

# Each new M16 rule trips on a deliberately-broken fixture.
func _test_broken_landmarks() -> void:
	# Field disk spills outside bounds -> error.
	var d1 = ClusterDef.new()
	d1.bounds = Rect2(-10000, -10000, 20000, 20000)
	d1.add_field({"center": Vector2(0, 0), "radius": 50000.0, "count": 5, "seed": 1})
	_assert(_has_sev(ClusterValidator.validate(d1)["violations"], "field", "error"),
		"broken: a field extending outside bounds should error")

	# Beacon gap wider than comms range -> road_lit warning.
	var d2 = ClusterDef.new()
	d2.bounds = Rect2(-500000, -500000, 1000000, 1000000)
	d2.add_entity(_bc(200, Vector2(0, 0)))
	d2.add_entity(_bc(201, Vector2(120000, 0)))   # 120k apart, > 50k range
	d2.beacon_edges = [[200, 201]]
	_assert(_has_sev(ClusterValidator.validate(d2)["violations"], "road_lit", "warning"),
		"broken: an over-long beacon gap should warn road_lit")

	# Outpost sitting on no field -> outpost_field warning.
	var d3 = ClusterDef.new()
	d3.bounds = Rect2(-500000, -500000, 1000000, 1000000)
	d3.add_entity(_outpost(300, Vector2(0, 0)))
	d3.add_field({"center": Vector2(200000, 0), "radius": 5000.0, "count": 3, "seed": 1})
	_assert(_has_sev(ClusterValidator.validate(d3)["violations"], "outpost_field", "warning"),
		"broken: an outpost off every field should warn outpost_field")

# Fields expand deterministically: right count, every rock inside its radius+bounds.
func _test_fields_expand() -> void:
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	main_node.add_child(m)
	ClusterLoader.load_into(def, m)

	var exp: int = 0
	for f in def.asteroid_fields:
		exp += int(f["count"])
	_assert(_count_kind(m, ClusterEntity.Kind.ASTEROID) == exp,
		"fields: asteroid records should equal sum of field counts")

	var bad: int = 0
	for rec in m.records:
		if rec.kind == ClusterEntity.Kind.ASTEROID:
			var fi: int = (rec.id - FIELD_ID_BASE) / FIELD_ID_STRIDE
			var f = def.asteroid_fields[fi]
			if rec.pos.distance_to(f["center"]) > float(f["radius"]) + 1.0:
				bad += 1
			if not def.bounds.has_point(rec.pos):
				bad += 1
	_assert(bad == 0, "fields: every asteroid must lie within its field radius and bounds (bad=%d)" % bad)
	m.queue_free()

# The wormhole is a Node2D landmark: it promotes and demotes through the manager
# without touching velocity (the is-RigidBody2D guards), and reads as WORMHOLE.
func _test_wormhole_promotes() -> void:
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	var pol = LivenessPolicy.new()
	pol.configure_bubble(45000.0, 60000.0)
	m.policy = pol
	main_node.add_child(m)
	ClusterLoader.load_into(def, m)

	var wh = _rec(m, 500)
	_assert(wh != null and wh.kind == ClusterEntity.Kind.WORMHOLE, "wormhole: record present with WORMHOLE kind")
	if wh != null:
		m.viewpoint = wh.pos
		m.tick(0.0)
		_assert(wh.is_live(), "wormhole: should promote at its position")
		_assert(wh.is_live() and wh.live_node is Wormhole, "wormhole: live node should be a Wormhole")
		m.viewpoint = Vector2(1e9, 0)
		m.tick(0.0)   # demote -- must not error on a Node2D (no linear_velocity)
		_assert(not wh.is_live(), "wormhole: should demote cleanly")
	m.queue_free()

# The "make the road longer" requirement, pinned so it can't silently shrink.
func _test_road_is_longer() -> void:
	var def = HomeCluster.build()
	var beacons: int = 0
	for e in def.entities:
		if e.get("kind") == ClusterEntity.Kind.BEACON:
			beacons += 1
	_assert(beacons > 4, "road: home road should have more than 4 beacons (got %d)" % beacons)

# --- helpers ---
func _bc(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "name": "B", "hull": Buoy, "kind": ClusterEntity.Kind.BEACON,
		"pos": pos, "comms_range": 50000.0, "iff_tags": [], "is_static": true}

func _outpost(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "name": "O", "hull": SmallStation, "kind": ClusterEntity.Kind.STATION,
		"pos": pos, "role": "outpost", "iff_tags": [], "is_static": true}

func _has_field(viol: Array, field: String) -> bool:
	for v in viol:
		if v["field"] == field:
			return true
	return false

func _has_sev(viol: Array, field: String, severity: String) -> bool:
	for v in viol:
		if v["field"] == field and v["severity"] == severity:
			return true
	return false

func _count_kind(m, kind: int) -> int:
	var n: int = 0
	for r in m.records:
		if r.kind == kind:
			n += 1
	return n

func _rec(m, id: int):
	for r in m.records:
		if r.id == id:
			return r
	return null
