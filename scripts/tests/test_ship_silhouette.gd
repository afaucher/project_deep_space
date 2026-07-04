extends Node

# v1.1 outline revision -- unit battery for ShipSilhouette (the rectilinear
# union contour that replaced per-component boxes on the nav map). Pure math,
# no physics frames. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_ship_silhouette

const ShipSilhouette = preload("res://scripts/components/ship_silhouette.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main) -> void:
	print("Starting Ship Silhouette (outline v1.1) Tests")

	_test_touching_rects_weld()
	_test_plus_shape_single_concave_contour()
	_test_ring_hole_winding_tripwire()
	_test_hole_shrunk_by_interior_module()
	_test_fleet_smoke()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_ship_silhouette <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_ship_silhouette <<<")
		get_tree().quit(1)

func _hull(rect: Rect2) -> Dictionary:
	return {"id": "h%d" % randi(), "type": "hull", "rect": rect, "health": 100.0, "max_health": 100.0, "density": 20.0}

func _outers(loops: Array) -> Array:
	return loops.filter(func(l): return not l["is_hole"])

func _holes(loops: Array) -> Array:
	return loops.filter(func(l): return l["is_hole"])

func _loop_area(l: Dictionary) -> float:
	var pts: PackedVector2Array = l["points"]
	var area := 0.0
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area * 0.5)

# 1. Two rects sharing an edge weld into ONE boundary (the connectivity idiom
# every ship uses -- if this fails, everything fails).
func _test_touching_rects_weld() -> void:
	var loops: Array = ShipSilhouette.compute([
		_hull(Rect2(0, 0, 10, 10)),
		_hull(Rect2(10, 0, 10, 10)),
	])
	_assert(_outers(loops).size() == 1, "weld: two edge-touching rects should union to 1 outer, got %d" % _outers(loops).size())
	_assert(_holes(loops).is_empty(), "weld: no holes expected, got %d" % _holes(loops).size())
	if _outers(loops).size() == 1:
		var area: float = _loop_area(_outers(loops)[0])
		_assert(absf(area - 200.0) < 15.0, "weld: contour area should be ~200 (2x 10x10 + inflate fudge), got %.1f" % area)

# 2. Plus shape: one CONCAVE contour -- the Ironhold case. Area must match the
# rect sum (a convex hull would bridge the inner corners and read ~2x bigger;
# that over-area is exactly the leak/clutter v1.1 removes).
func _test_plus_shape_single_concave_contour() -> void:
	var comps: Array = [
		_hull(Rect2(-5, -5, 10, 10)),    # core
		_hull(Rect2(5, -5, 20, 10)),     # +X arm
		_hull(Rect2(-25, -5, 20, 10)),   # -X arm
		_hull(Rect2(-5, 5, 10, 20)),     # +Y arm
		_hull(Rect2(-5, -25, 10, 20)),   # -Y arm
	]
	var loops: Array = ShipSilhouette.compute(comps)
	_assert(_outers(loops).size() == 1, "plus: should union to 1 outer, got %d" % _outers(loops).size())
	_assert(_holes(loops).is_empty(), "plus: no holes expected, got %d" % _holes(loops).size())
	if _outers(loops).size() == 1:
		var pts: PackedVector2Array = _outers(loops)[0]["points"]
		_assert(pts.size() >= 8 and pts.size() <= 16, "plus: contour should have ~12 corners (concave plus), got %d" % pts.size())
		var area: float = _loop_area(_outers(loops)[0])
		# rect sum = 100 + 4*200 = 900; convex hull would be ~1700.
		_assert(absf(area - 900.0) < 60.0, "plus: contour area should track the rect sum (~900), got %.1f -- a convex-hull-like bridge reads ~1700" % area)

# 3. Ring (4 frame walls): 1 outer + 1 hole. THE winding tripwire -- if the
# engine's hole-winding convention ever flips, this fails loudly.
func _test_ring_hole_winding_tripwire() -> void:
	var loops: Array = ShipSilhouette.compute([
		_hull(Rect2(0, 0, 100, 10)),     # top
		_hull(Rect2(0, 90, 100, 10)),    # bottom
		_hull(Rect2(0, 10, 10, 80)),     # left
		_hull(Rect2(90, 10, 10, 80)),    # right
	])
	_assert(_outers(loops).size() == 1, "ring: 1 outer expected, got %d" % _outers(loops).size())
	_assert(_holes(loops).size() == 1, "ring: 1 hole expected (winding-convention tripwire), got %d" % _holes(loops).size())
	if _holes(loops).size() == 1:
		var hole_area: float = _loop_area(_holes(loops)[0])
		_assert(absf(hole_area - 6400.0) < 250.0, "ring: hole area should be ~6400 (80x80), got %.1f" % hole_area)

# 4. A module attached to the ring's inner wall shrinks the hole (fold-order
# hole-vs-interior-module correctness: the module quad is subtracted from the
# discovered hole).
func _test_hole_shrunk_by_interior_module() -> void:
	var loops: Array = ShipSilhouette.compute([
		_hull(Rect2(0, 0, 100, 10)),
		_hull(Rect2(0, 90, 100, 10)),
		_hull(Rect2(0, 10, 10, 80)),
		_hull(Rect2(90, 10, 10, 80)),
		_hull(Rect2(10, 10, 30, 30)),    # module in the corner, touching two walls
	])
	_assert(_outers(loops).size() == 1, "module-in-ring: 1 outer expected, got %d" % _outers(loops).size())
	_assert(_holes(loops).size() == 1, "module-in-ring: still 1 hole expected, got %d" % _holes(loops).size())
	if _holes(loops).size() == 1:
		var hole_area: float = _loop_area(_holes(loops)[0])
		# 80x80 minus 30x30 = 6400 - 900 = 5500.
		_assert(absf(hole_area - 5500.0) < 300.0, "module-in-ring: hole should shrink by the module's area (~5500), got %.1f" % hole_area)

# 5. Real fleet: every catalog ship + variant yields a sane silhouette --
# >= 1 outer, every loop a real polygon. Defence pod must keep its ring hole
# (the archetype); everything else in today's fleet is hole-free.
func _test_fleet_smoke() -> void:
	var entries: Array = []
	entries.append_array(ShipCatalog.SPAWNABLE)
	entries.append_array(ShipCatalog.VARIANTS)
	for entry in entries:
		var ship = entry["script"].new()
		var loops: Array = ShipSilhouette.compute(ship.ship_components)
		var label: String = entry["name"]
		_assert(_outers(loops).size() >= 1, "fleet(%s): at least one outer loop" % label)
		for l in loops:
			var pts: PackedVector2Array = l["points"]
			_assert(pts.size() >= 4, "fleet(%s): every loop needs >= 4 points, got %d" % [label, pts.size()])
		if label == "Defence Pod":
			_assert(_holes(loops).size() >= 1, "fleet(Defence Pod): the ring's hole IS the archetype -- expected >= 1 hole loop, got %d" % _holes(loops).size())
		# Cache path: loops_for on an instance caches per class and returns
		# the same content on a second call.
		var a: Array = ShipSilhouette.loops_for(ship)
		var b: Array = ShipSilhouette.loops_for(ship)
		_assert(a.size() == b.size(), "fleet(%s): loops_for should be stable across calls" % label)
		ship.free()
