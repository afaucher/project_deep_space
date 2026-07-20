extends Node

# M15 acceptance -- the world-data layer. Proves the home cluster is well-formed,
# the validator trips on each broken rule, the loader populates records, and the
# campaign bootstrap logic (load -> place viewpoint -> promote the neighbourhood)
# works without the menu. Run headless:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_cluster_loader
# Pass marker per CLAUDE.md. All checks are synchronous (no physics frames).

const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const ClusterValidator = preload("res://scripts/cluster/cluster_validator.gd")
const ClusterDef = preload("res://scripts/cluster/cluster_def.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const Standing = preload("res://scripts/combat/standing.gd")

var main_node: Node = null
var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Cluster Loader Tests")

	_test_home_validates_clean()
	_test_broken_fixture_trips_rules()
	_test_loader_populates()
	_test_bootstrap_promotes_neighbour()
	_test_warrant_authority_defaults()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_cluster_loader <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_cluster_loader <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# The authored home cluster must validate with zero errors (warnings printed).
# ---------------------------------------------------------------------------
func _test_home_validates_clean() -> void:
	var def = HomeCluster.build()
	_assert(def.bounds.has_point(def.player_start), "home: player_start must be inside bounds")
	var r = ClusterValidator.validate(def)
	if not r["violations"].is_empty():
		print("Home cluster violations:")
		for v in r["violations"]:
			print("  id=", v["entity_id"], " field=", v["field"], " sev=", v["severity"], " -- ", v["reason"])
	var errors: Array = r["violations"].filter(func(v): return v["severity"] == "error")
	_assert(r["ok"] == true, "home: ClusterValidator should return ok=true")
	_assert(errors.is_empty(), "home: cluster should have zero error-severity violations, got " + str(errors.size()))

# ---------------------------------------------------------------------------
# A deliberately-broken fixture must trip each error rule.
# ---------------------------------------------------------------------------
func _test_broken_fixture_trips_rules() -> void:
	var def = ClusterDef.new()
	def.name = "Broken"
	def.bounds = Rect2(-10000, -10000, 20000, 20000)
	def.player_start = Vector2.ZERO
	# id 1 duplicated; id 2 overlaps id 1 (500u < 3000); id 3 out of bounds.
	def.add_entity(_st(1, Vector2(0, 0)))
	def.add_entity(_st(1, Vector2(5000, 0)))       # duplicate id
	def.add_entity(_st(2, Vector2(0, 500)))         # overlaps id 1
	def.add_entity(_st(3, Vector2(100000, 0)))      # out of bounds
	def.add_entity(_bc(50, Vector2(1000, 0)))
	def.beacon_edges = [[50, 99]]                   # 99 is not a beacon -> dangling

	var r = ClusterValidator.validate(def)
	var viol: Array = r["violations"]
	_assert(r["ok"] == false, "broken: fixture should validate ok=false")
	_assert(_has(viol, "id", "error"), "broken: expected a duplicate-id error")
	_assert(_has(viol, "overlap", "error"), "broken: expected a station-overlap error")
	_assert(_has(viol, "pos", "error"), "broken: expected an out-of-bounds error")
	_assert(_has(viol, "beacon_edge", "error"), "broken: expected a dangling-beacon-edge error")

# ---------------------------------------------------------------------------
# The loader turns every authored entity into a record with the right kind.
# ---------------------------------------------------------------------------
func _test_loader_populates() -> void:
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	main_node.add_child(m)
	ClusterLoader.load_into(def, m)

	# Expected counts derived from the def (robust to layout changes): loaded
	# records = authored entities + the asteroids each field expands into.
	var exp_stations: int = _count_def_kind(def, ClusterEntity.Kind.STATION)
	var exp_beacons: int = _count_def_kind(def, ClusterEntity.Kind.BEACON)
	var exp_field_asteroids: int = 0
	for f in def.asteroid_fields:
		exp_field_asteroids += int(f["count"])
	var exp_total: int = def.entities.size() + exp_field_asteroids

	_assert(m.records.size() == exp_total,
		"loader: records should be entities + field asteroids (%d vs %d)" % [m.records.size(), exp_total])
	_assert(_count_kind(m, ClusterEntity.Kind.STATION) == exp_stations, "loader: station count mismatch")
	_assert(_count_kind(m, ClusterEntity.Kind.BEACON) == exp_beacons, "loader: beacon count mismatch")
	_assert(_count_kind(m, ClusterEntity.Kind.ASTEROID) == exp_field_asteroids, "loader: asteroid count should equal sum of field counts")
	m.queue_free()

func _count_def_kind(def, kind: int) -> int:
	var n: int = 0
	for e in def.entities:
		if e.get("kind") == kind:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Bootstrap logic: place the viewpoint at player_start, tick, and the adjacent
# hub goes live while a distant hub stays dormant. This is _bootstrap_campaign
# minus the menu button -- the load->place->promote path, proven headlessly.
# ---------------------------------------------------------------------------
func _test_bootstrap_promotes_neighbour() -> void:
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	m.policy.configure_bubble(45000.0, 60000.0)
	main_node.add_child(m)
	ClusterLoader.load_into(def, m)

	m.viewpoint = def.player_start
	m.tick(0.0)

	var ironhold = _rec(m, 1)       # (0,0), ~3000 from player_start -> live
	var drift_market = _rec(m, 2)   # (120000,40000) -> dormant
	_assert(ironhold != null and ironhold.is_live(), "bootstrap: the adjacent hub should promote")
	_assert(drift_market != null and not drift_market.is_live(), "bootstrap: a distant hub should stay dormant")

	m.viewpoint = Vector2(1e9, 0)   # demote everything before teardown
	m.tick(0.0)
	m.queue_free()

# ---------------------------------------------------------------------------
# M52b -- warrant_authority defaults thread through the same authored-data
# pipeline authority_flags already uses (design doc: "Stations and patrol/
# military ships default warrant_authority to their own flag; everyone
# else... stays empty").
# ---------------------------------------------------------------------------
func _test_warrant_authority_defaults() -> void:
	var def = HomeCluster.build()
	var m = ClusterManager.new()
	main_node.add_child(m)
	ClusterLoader.load_into(def, m)

	var ironhold = _rec(m, 1)        # medium station hub
	var patrol_alpha = _rec(m, 600)  # light-attack-craft patrol
	var hermits_rest = _rec(m, 200)  # mobile home (civilian, not an authority)
	var mule = _rec(m, 700)          # cargo shuttle (civilian, not an authority)

	_assert(ironhold != null and ironhold.warrant_authority == [Standing.FLAG_DRIFT],
		"warrant_authority: a hub station should default to its own flag, got " + str(ironhold.warrant_authority if ironhold != null else "<missing>"))
	_assert(patrol_alpha != null and patrol_alpha.warrant_authority == [Standing.FLAG_DRIFT],
		"warrant_authority: a patrol should default to its own flag, got " + str(patrol_alpha.warrant_authority if patrol_alpha != null else "<missing>"))
	_assert(hermits_rest != null and hermits_rest.warrant_authority.is_empty(),
		"warrant_authority: a mobile home (civilian) must stay empty, got " + str(hermits_rest.warrant_authority if hermits_rest != null else "<missing>"))
	_assert(mule != null and mule.warrant_authority.is_empty(),
		"warrant_authority: a cargo shuttle (civilian) must stay empty, got " + str(mule.warrant_authority if mule != null else "<missing>"))

	m.queue_free()

# --- helpers ---
func _st(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "name": "S", "hull": MediumStation,
		"kind": ClusterEntity.Kind.STATION, "pos": pos, "iff_tags": [], "is_static": true}

func _bc(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "name": "B", "hull": Buoy,
		"kind": ClusterEntity.Kind.BEACON, "pos": pos, "iff_tags": [], "is_static": true}

func _has(viol: Array, field: String, severity: String) -> bool:
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
