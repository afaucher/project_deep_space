extends Node

# M29 acceptance -- convex-hull collision
# (implementation_plans/m28_m30_collision_roadmap.md, M29 section). Every
# Ship's bounding-CIRCLE collision shape becomes a single ConvexPolygonShape2D
# built from ShipSilhouette's outer-loop points (holes ignored -- M30 handles
# notches). Asteroids keep their circle; missiles keep their tiny 2.0 circle
# (Missile._init/_ready strips every OTHER CollisionShape2D child, see
# missile.gd). This test is a mix of pure-geometry checks (points +
# Geometry2D, no physics needed) and a couple of physics-frame probes
# (tightness via space-state point query, tunneling via a moving body).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_collision_shapes
# Pass marker per CLAUDE.md.

const ShipScript = preload("res://scripts/ships/ship.gd")
const ShipSilhouette = preload("res://scripts/components/ship_silhouette.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const Missile = preload("res://scripts/ships/missile.gd")

# Full catalog ship roster (glob of scripts/ships/*.gd, minus ship.gd itself,
# minus missile.gd/asteroid.gd which are handled as their own exceptions).
const Buoy = preload("res://scripts/ships/buoy.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const DefencePod = preload("res://scripts/ships/defence_pod.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const AsteroidStation = preload("res://scripts/ships/asteroid_station.gd")
const Mine = preload("res://scripts/ships/mine.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const Pinnace = preload("res://scripts/ships/pinnace.gd")
const Freighter = preload("res://scripts/ships/freighter.gd")
const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")
const Destroyer = preload("res://scripts/ships/destroyer.gd")
const PirateLAC = preload("res://scripts/ships/pirate_lac.gd")
const SensorDrone = preload("res://scripts/ships/sensor_drone.gd")

# (class_name, script) pairs for every catalog ship. Excludes Missile (its own
# exception, checked separately) and Buoy/SensorDrone are STRUCTURE-less
# simple hulls but still go through the normal ship convex-hull path.
const CATALOG: Array = [
	["Buoy", Buoy],
	["CargoShuttle", CargoShuttle],
	["DefencePod", DefencePod],
	["LightAttackCraft", LightAttackCraft],
	["AsteroidStation", AsteroidStation],
	["Mine", Mine],
	["Frigate", Frigate],
	["SmallStation", SmallStation],
	["MediumStation", MediumStation],
	["Pinnace", Pinnace],
	["Freighter", Freighter],
	["OreShuttle", OreShuttle],
	["Destroyer", Destroyer],
	["PirateLAC", PirateLAC],
	["SensorDrone", SensorDrone],
]

var main_node: Node = null
var failures: Array = []
var finished: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _free_if_valid(n) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

# Find the (first, and per M29 policy ONLY) CollisionShape2D child of a body.
func _collision_shapes(body: Node) -> Array:
	var out: Array = []
	for c in body.get_children():
		if c is CollisionShape2D:
			out.append(c)
	return out

func setup(main) -> void:
	main_node = main
	print("Starting Collision Shapes (M29) Tests")
	_test_shape_policy()
	_test_hull_correctness()
	_test_destroyer_tightness_pure_geometry()
	_start_physics_phase_1()

# ---------------------------------------------------------------------------
# 1. Shape policy: every catalog ship carries exactly one ConvexPolygonShape2D
# with >= 3 points; asteroid carries CircleShape2D; missile carries its own
# 2.0-radius CircleShape2D (the documented exception).
# ---------------------------------------------------------------------------
func _test_shape_policy() -> void:
	print("--- Item 1: shape policy across the catalog ---")
	for pair in CATALOG:
		var cls_name: String = pair[0]
		var script = pair[1]
		var ship = script.new()
		ship.owner_id = 9000
		main_node.add_child(ship)
		var shapes: Array = _collision_shapes(ship)
		_assert(shapes.size() == 1, "%s: should carry exactly one CollisionShape2D (got %d)" % [cls_name, shapes.size()])
		if shapes.size() == 1:
			var shp = shapes[0].shape
			_assert(shp is ConvexPolygonShape2D, "%s: shape should be ConvexPolygonShape2D (got %s)" % [cls_name, shp.get_class()])
			if shp is ConvexPolygonShape2D:
				_assert(shp.points.size() >= 3, "%s: hull should have >= 3 points (got %d)" % [cls_name, shp.points.size()])
		_free_if_valid(ship)

	# Asteroid: circle, unchanged.
	var rock = Asteroid.new()
	main_node.add_child(rock)
	var rock_shapes: Array = _collision_shapes(rock)
	_assert(rock_shapes.size() == 1, "asteroid: should carry exactly one CollisionShape2D (got %d)" % rock_shapes.size())
	if rock_shapes.size() == 1:
		_assert(rock_shapes[0].shape is CircleShape2D, "asteroid: shape should stay CircleShape2D (got %s)" % rock_shapes[0].shape.get_class())
	_free_if_valid(rock)

	# Missile: the documented exception -- its own tiny 2.0 circle survives
	# Ship._ready()'s convex-hull add because Missile._ready() strips every
	# CollisionShape2D that isn't its own (see missile.gd _ready()).
	var missile = Missile.new()
	missile.setup(9001, Vector2.ZERO, Vector2.ZERO, 0.0)
	main_node.add_child(missile)
	var missile_shapes: Array = _collision_shapes(missile)
	_assert(missile_shapes.size() == 1, "missile: should carry exactly one CollisionShape2D (got %d)" % missile_shapes.size())
	if missile_shapes.size() == 1:
		var mshape = missile_shapes[0].shape
		_assert(mshape is CircleShape2D, "missile: shape should be CircleShape2D, the documented exception (got %s)" % mshape.get_class())
		if mshape is CircleShape2D:
			_assert(is_equal_approx(mshape.radius, Missile.MISSILE_COLLISION_RADIUS), "missile: circle radius should be MISSILE_COLLISION_RADIUS=%.1f (got %.2f)" % [Missile.MISSILE_COLLISION_RADIUS, mshape.radius])
	_free_if_valid(missile)

# ---------------------------------------------------------------------------
# 2. Hull correctness: the shape's points equal Geometry2D.convex_hull() of
# the ship's silhouette outer-loop points (point-set equality within epsilon).
# Checked for a sample spanning simple (frigate), elongated (destroyer), and
# hole-bearing (defence pod) hulls.
# ---------------------------------------------------------------------------
const HULL_SAMPLE: Array = [
	["Frigate", Frigate],
	["Destroyer", Destroyer],
	["DefencePod", DefencePod],
	["Freighter", Freighter],
	["MediumStation", MediumStation],
]

func _point_in_set(pt: Vector2, set: PackedVector2Array, eps: float) -> bool:
	for p in set:
		if pt.distance_to(p) <= eps:
			return true
	return false

const HULL_CORRECTNESS_EPS := 0.5

func _test_hull_correctness() -> void:
	print("--- Item 2: hull correctness vs Geometry2D.convex_hull of silhouette ---")
	for pair in HULL_SAMPLE:
		var cls_name: String = pair[0]
		var script = pair[1]
		var ship = script.new()
		ship.owner_id = 9002
		main_node.add_child(ship)

		var loops: Array = ShipSilhouette.loops_for(ship)
		var outer_points: PackedVector2Array = PackedVector2Array()
		for loop in loops:
			if not loop.get("is_hole", false):
				outer_points.append_array(loop.get("points", PackedVector2Array()))
		var expected_hull: PackedVector2Array = Geometry2D.convex_hull(outer_points)

		var shapes: Array = _collision_shapes(ship)
		if shapes.size() == 1 and shapes[0].shape is ConvexPolygonShape2D:
			var actual: PackedVector2Array = shapes[0].shape.points
			_assert(actual.size() == expected_hull.size(), "%s: hull point count should match Geometry2D.convex_hull (got %d vs %d)" % [cls_name, actual.size(), expected_hull.size()])
			var all_match := true
			for p in actual:
				if not _point_in_set(p, expected_hull, HULL_CORRECTNESS_EPS):
					all_match = false
					break
			_assert(all_match, "%s: every collision-shape point should exist in Geometry2D.convex_hull's point set (within %.1fu)" % [cls_name, HULL_CORRECTNESS_EPS])
		else:
			_assert(false, "%s: expected a single ConvexPolygonShape2D to compare against the hull oracle" % cls_name)
		_free_if_valid(ship)

# ---------------------------------------------------------------------------
# 3. Tightness, pure geometry: destroyer's own hull points (ship-local) via
# Geometry2D.is_point_in_polygon. Destroyer AABB spans roughly x:-60..60,
# y:-25..25 -> old bounding radius = sqrt(60^2+25^2) ~= 65. A broadside point
# 50u off the centerline (well inside the old circle, well outside the hull's
# +/-25 half-width) must be OUTSIDE the hull; a nose point at the same
# distance along +X (inside the hull's +/-60 long axis) must be INSIDE.
# ---------------------------------------------------------------------------
func _test_destroyer_tightness_pure_geometry() -> void:
	print("--- Item 3: destroyer tightness (pure geometry, ship-local) ---")
	var destroyer = Destroyer.new()
	destroyer.owner_id = 9003
	main_node.add_child(destroyer)

	var old_circle_radius: float = destroyer.get_bounding_radius()
	print("[destroyer] old bounding-circle radius = %.2f" % old_circle_radius)
	_assert(old_circle_radius > 60.0, "destroyer: sanity -- old circumscribing radius should be well over the hull's half-width (got %.2f)" % old_circle_radius)

	var shapes: Array = _collision_shapes(destroyer)
	_assert(shapes.size() == 1 and shapes[0].shape is ConvexPolygonShape2D, "destroyer: expected a single ConvexPolygonShape2D")
	if shapes.size() == 1 and shapes[0].shape is ConvexPolygonShape2D:
		var hull_pts: PackedVector2Array = shapes[0].shape.points

		var broadside_pt := Vector2(0.0, 50.0) # off centerline, inside old ~65u circle
		var nose_pt := Vector2(50.0, 0.0)       # same distance, along the long axis

		var broadside_in_old_circle: bool = broadside_pt.length() <= old_circle_radius
		var nose_in_old_circle: bool = nose_pt.length() <= old_circle_radius
		_assert(broadside_in_old_circle, "destroyer: broadside probe point should lie inside the OLD circle (proves it's a meaningful before/after case)")
		_assert(nose_in_old_circle, "destroyer: nose probe point should lie inside the OLD circle too")

		var broadside_in_hull: bool = Geometry2D.is_point_in_polygon(broadside_pt, hull_pts)
		var nose_in_hull: bool = Geometry2D.is_point_in_polygon(nose_pt, hull_pts)
		print("[destroyer] broadside(0,50) in_old_circle=%s in_hull=%s | nose(50,0) in_old_circle=%s in_hull=%s" % [
			str(broadside_in_old_circle), str(broadside_in_hull), str(nose_in_old_circle), str(nose_in_hull)])
		_assert(not broadside_in_hull, "destroyer: broadside point (0,50) should be OUTSIDE the convex hull (was inside the old circle) -- the milestone's tightness proof")
		_assert(nose_in_hull, "destroyer: nose point (50,0) should be INSIDE the convex hull (same long axis as the hull's extent)")
	_free_if_valid(destroyer)

# ---------------------------------------------------------------------------
# 4/5. Physics-frame phases: (a) tightness confirmed via a live space-state
# point query (not just pure geometry), (b) M28 ram-accuracy regression is
# covered by re-running test_collision_damage separately (see report), and
# (c) the tunneling probe -- a LAC at max_speed on a path crossing a station
# arm's thin cross-section.
# ---------------------------------------------------------------------------
var phase: String = ""
var t: float = 0.0

func _start_physics_phase_1() -> void:
	phase = "tightness_query"
	t = 0.0
	pq_settle_frames = 0
	print("--- Item 3b: destroyer tightness via live space-state point query ---")
	pq_destroyer = Destroyer.new()
	pq_destroyer.owner_id = 9004
	pq_destroyer.position = Vector2(5000, 5000) # clear of everything else
	pq_destroyer.rotation = 0.0
	main_node.add_child(pq_destroyer)

var pq_destroyer = null
var pq_settle_frames: int = 0
const PQ_SETTLE_FRAMES_NEEDED := 5 # let the physics server commit the new shape/transform before querying

func _phase_tightness_query_process(_delta: float) -> void:
	pq_settle_frames += 1
	if pq_settle_frames < PQ_SETTLE_FRAMES_NEEDED:
		return
	var space_state = pq_destroyer.get_world_2d().direct_space_state
	var old_radius: float = pq_destroyer.get_bounding_radius()

	var broadside_world: Vector2 = pq_destroyer.position + Vector2(0.0, 50.0)
	var nose_world: Vector2 = pq_destroyer.position + Vector2(50.0, 0.0)

	var q_broadside := PhysicsPointQueryParameters2D.new()
	q_broadside.position = broadside_world
	q_broadside.collide_with_bodies = true
	q_broadside.collide_with_areas = false
	var res_broadside: Array = space_state.intersect_point(q_broadside, 32)
	var hit_broadside := false
	for r in res_broadside:
		if r.get("collider") == pq_destroyer:
			hit_broadside = true

	var q_nose := PhysicsPointQueryParameters2D.new()
	q_nose.position = nose_world
	q_nose.collide_with_bodies = true
	q_nose.collide_with_areas = false
	var res_nose: Array = space_state.intersect_point(q_nose, 32)
	var hit_nose := false
	for r in res_nose:
		if r.get("collider") == pq_destroyer:
			hit_nose = true

	print("[space-state] old_circle_radius=%.2f broadside_hit=%s nose_hit=%s" % [old_radius, str(hit_broadside), str(hit_nose)])
	_assert(not hit_broadside, "destroyer (live query): broadside point (+50u off centerline) should NOT register a hit against the convex hull")
	_assert(hit_nose, "destroyer (live query): nose point (+50u along long axis) SHOULD register a hit against the convex hull")

	_free_if_valid(pq_destroyer)
	_start_tunneling_phase()

# ---------------------------------------------------------------------------
# Tunneling probe: a LightAttackCraft at max_speed (2200 u/s -> ~36.7u/frame at
# 60Hz) on a straight path crossing a station arm's thin cross-section (small
# station's forward arm: Y span -20..20, i.e. 40u thick, at X ~20..90). The
# LAC starts well clear on one side, aimed straight through the arm, and must
# be observed to CONTACT the station (body_entered) rather than silently pass
# through. If it tunnels, the contingency is CCD_MODE_CAST_RAY on the LAC
# (applied only if this probe demonstrates tunneling -- see report).
# ---------------------------------------------------------------------------
var tp_station = null
var tp_lac = null
var tp_contact_detected := false
const TUNNEL_TIMEOUT := 5.0

func _start_tunneling_phase() -> void:
	phase = "tunneling"
	t = 0.0
	tp_contact_detected = false
	print("--- Item 5: tunneling probe -- LAC at max_speed through a station arm ---")

	tp_station = SmallStation.new()
	tp_station.name = "TunnelStation"
	tp_station.owner_id = 1
	tp_station.iff_tags = ["TEAM_PLAYER"]
	tp_station.position = Vector2(20000, 20000)
	main_node.add_child(tp_station)

	# Small station's forward arm: rect roughly X 20..90, Y -20..20 (see
	# small_station.gd pd_fwd/hull_fwd_cap/reactor_1) -- 40u thick along Y.
	# Fire the LAC along +Y straight through the arm's midpoint (X=55 local),
	# starting well clear on the -Y side, so its path crosses the full 40u
	# thickness in a single frame if it's going to tunnel at all.
	var arm_local_x := 55.0
	var start_world: Vector2 = tp_station.position + Vector2(arm_local_x, -400.0)

	tp_lac = LightAttackCraft.new()
	tp_lac.name = "TunnelLAC"
	tp_lac.owner_id = 9005
	tp_lac.iff_tags = ["TEAM_HOSTILE"]
	tp_lac.position = start_world
	tp_lac.rotation = PI / 2.0 # nose +Y
	main_node.add_child(tp_lac)
	tp_lac.linear_velocity = Vector2(0.0, tp_lac.max_speed)
	tp_lac.body_entered.connect(_on_tunnel_contact)

func _on_tunnel_contact(body: Node) -> void:
	if phase == "tunneling" and body == tp_station:
		tp_contact_detected = true

func _phase_tunneling_process(delta: float) -> void:
	t += delta
	# Stop once the LAC has clearly passed beyond the arm (well past +Y of it)
	# or timed out.
	var past_arm: bool = tp_lac != null and is_instance_valid(tp_lac) and tp_lac.position.y > tp_station.position.y + 400.0
	if tp_contact_detected or past_arm or t > TUNNEL_TIMEOUT:
		print("[tunnel] contact_detected=%s  final LAC pos=%s  t=%.3f  max_speed=%.1f (~%.1fu/frame @60Hz)" % [
			str(tp_contact_detected), str(tp_lac.position) if is_instance_valid(tp_lac) else "freed", t, tp_lac.max_speed if is_instance_valid(tp_lac) else -1.0, (tp_lac.max_speed / 60.0) if is_instance_valid(tp_lac) else -1.0])
		# No silent pass-through: assert contact was observed. If this ever
		# fails, the documented contingency is continuous_cd =
		# RigidBody2D.CCD_MODE_CAST_RAY on LIGHT-tier fast hulls (see
		# light_attack_craft.gd / ship.gd _ready()) -- apply it and re-run.
		_assert(tp_contact_detected, "tunneling probe: LAC at max_speed should CONTACT the station arm, not pass through it silently")
		_free_if_valid(tp_lac)
		_free_if_valid(tp_station)
		_finish()

func _physics_process(delta: float) -> void:
	if finished:
		return
	match phase:
		"tightness_query": _phase_tightness_query_process(delta)
		"tunneling": _phase_tunneling_process(delta)

func _finish() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_collision_shapes <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_collision_shapes <<<")
		get_tree().quit(1)
