extends Node

# M25 acceptance -- geometry unification + static outline v1
# (implementation_plans/m25_outline_v1_geometry_design.md). Covers plan items
# 1-9: Ship.get_local_aabb()/get_bounding_radius() (AABB oracle, radius oracle,
# cache correctness, empty-components fallback) and the navigation_panel.gd
# outline-v1 seams (outline_alpha pure function, _outline_draw_list transform
# correctness, stale-contact safety, _bounds_radius_for, station gating).
#
# Item 10 (avoidance-margin regression) is NOT implemented here per the plan --
# the main session runs test_avoidance/test_docking_multi directly and records
# the clearance lines. This test is synchronous (no physics needed -- pure
# geometry/math + live-instance introspection), so setup() does everything and
# quits immediately, same pattern as test_ship_designs.gd/test_parts_catalog.gd.
# Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_ship_geometry
# Pass marker: >>> [TEST PASSED] test_ship_geometry <<<

const Ship = preload("res://scripts/ships/ship.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")
const Destroyer = preload("res://scripts/ships/destroyer.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const NavigationPanel = preload("res://scripts/ui/navigation_panel.gd")
const ShipSilhouette = preload("res://scripts/components/ship_silhouette.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main: Node) -> void:
	print("Starting Ship Geometry (M25) Tests")

	_test_aabb_oracle()
	_test_radius_oracle()
	_test_cache_correctness()
	_test_empty_components_fallback()
	_test_outline_alpha_battery()
	_test_draw_list_correctness()
	_test_stale_contact_safety()
	_test_bounds_ring()
	_test_station_gating()
	_test_simple_body_outline()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_ship_geometry <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_ship_geometry <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# v1.1 asteroid path: a simple body (no ship_components) refines to its TRUE
# BOUNDING CIRCLE, not dots (nothing for the sampler to touch) and not rect
# loops (no rects). Asteroids are the original "don't hit what you can't see"
# case -- they must not be left as unrefinable blips.
# ---------------------------------------------------------------------------

func _test_simple_body_outline() -> void:
	var Asteroid = preload("res://scripts/asteroid.gd")
	var rock = Asteroid.new()
	rock.name = "GeomTestRock"
	add_child(rock)

	var rock_contact := {"instance_id": rock.get_instance_id(), "pos": Vector2.ZERO}
	_assert(NavigationPanel._is_simple_body(rock_contact), "Simple-body: an asteroid contact should classify as a simple body")
	_assert(is_equal_approx(NavigationPanel._bounds_radius_for(rock_contact), 300.0), "Simple-body: asteroid bounds radius should be its 300u collision circle, got %s" % NavigationPanel._bounds_radius_for(rock_contact))
	_assert(NavigationPanel._outline_draw_list(rock_contact) == [], "Simple-body: an asteroid must produce NO silhouette loops (no rects to leak), got %s" % str(NavigationPanel._outline_draw_list(rock_contact)))

	var frigate = Frigate.new()
	frigate.name = "GeomTestNotSimple"
	add_child(frigate)
	var ship_contact := {"instance_id": frigate.get_instance_id(), "pos": Vector2.ZERO}
	_assert(not NavigationPanel._is_simple_body(ship_contact), "Simple-body: a ship (has ship_components) must NOT take the circle path")

	rock.queue_free()
	frigate.queue_free()

# ---------------------------------------------------------------------------
# Helper: independently recompute the union AABB of a ship's component rects,
# WITHOUT touching get_local_aabb()/_cached_aabb at all -- this must be a
# clean-room oracle, not a comparison of the method to itself.
# ---------------------------------------------------------------------------

func _recompute_aabb(ship) -> Rect2:
	var comps: Array = ship.ship_components
	if comps.is_empty():
		return Rect2(-10, -10, 20, 20)
	var min_x = INF; var max_x = -INF
	var min_y = INF; var max_y = -INF
	for c in comps:
		var r: Rect2 = c.get("rect", Rect2(-10, -10, 20, 20))
		min_x = min(min_x, r.position.x)
		max_x = max(max_x, r.position.x + r.size.x)
		min_y = min(min_y, r.position.y)
		max_y = max(max_y, r.position.y + r.size.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _recompute_radius(aabb: Rect2) -> float:
	var corners = [
		aabb.position,
		aabb.position + Vector2(aabb.size.x, 0),
		aabb.position + Vector2(0, aabb.size.y),
		aabb.position + aabb.size,
	]
	var max_dist = 0.0
	for pt in corners:
		max_dist = max(max_dist, pt.length())
	return max_dist

func _all_catalog_entries() -> Array:
	return ShipCatalog.SPAWNABLE + ShipCatalog.VARIANTS

# ---------------------------------------------------------------------------
# Item 1: AABB oracle -- every catalog ship (SPAWNABLE + VARIANTS), the union
# of component rects recomputed independently in-test must equal
# get_local_aabb() exactly.
# ---------------------------------------------------------------------------

func _test_aabb_oracle() -> void:
	for entry in _all_catalog_entries():
		var ship_name: String = entry["name"]
		var ship = entry["script"].new()
		var expected: Rect2 = _recompute_aabb(ship)
		var actual: Rect2 = ship.get_local_aabb()
		_assert(actual == expected, "Item 1: %s get_local_aabb() %s should equal independently-recomputed union %s" % [ship_name, actual, expected])

# ---------------------------------------------------------------------------
# Item 2: Radius oracle -- get_bounding_radius() == max corner distance of the
# independently-recomputed AABB. Plus the two anchor facts: destroyer radius
# > 50 (the flat-ring lie, now fixed), LAC radius < 25.
# ---------------------------------------------------------------------------

func _test_radius_oracle() -> void:
	for entry in _all_catalog_entries():
		var ship_name: String = entry["name"]
		var ship = entry["script"].new()
		var expected_aabb: Rect2 = _recompute_aabb(ship)
		var expected_radius: float = _recompute_radius(expected_aabb)
		var actual_radius: float = ship.get_bounding_radius()
		_assert(is_equal_approx(actual_radius, expected_radius), "Item 2: %s get_bounding_radius() %s should equal independently-recomputed radius %s" % [ship_name, actual_radius, expected_radius])

	var destroyer = Destroyer.new()
	_assert(destroyer.get_bounding_radius() > 50.0, "Item 2: Destroyer bounding radius %s should be > 50 (the flat-ring lie this milestone fixes)" % destroyer.get_bounding_radius())

	var lac = LightAttackCraft.new()
	_assert(lac.get_bounding_radius() < 25.0, "Item 2: LightAttackCraft bounding radius %s should be < 25" % lac.get_bounding_radius())

# ---------------------------------------------------------------------------
# Item 3: Cache correctness -- two calls return identical values; mutating a
# component's health (non-geometric) doesn't invalidate the cache; the cached
# AABB matches what the damage raymarch actually used (get_local_aabb() is the
# raymarch's own single source of truth, so this asserts identity across two
# calls bracketing a raymarch-triggering take_damage()).
# ---------------------------------------------------------------------------

func _test_cache_correctness() -> void:
	var ship = Frigate.new()

	var aabb_1: Rect2 = ship.get_local_aabb()
	var aabb_2: Rect2 = ship.get_local_aabb()
	_assert(aabb_1 == aabb_2, "Item 3: two get_local_aabb() calls should return identical values")

	var radius_1: float = ship.get_bounding_radius()
	var radius_2: float = ship.get_bounding_radius()
	_assert(is_equal_approx(radius_1, radius_2), "Item 3: two get_bounding_radius() calls should return identical values")

	# Mutate a component's health (non-geometric) -- must not invalidate the cache.
	for c in ship.ship_components:
		if c["type"] == "hull":
			c["health"] = c["health"] * 0.5
			break
	var aabb_after_damage: Rect2 = ship.get_local_aabb()
	_assert(aabb_after_damage == aabb_1, "Item 3: mutating component health should not invalidate the cached AABB")

	# The raymarch (take_damage) reads get_local_aabb() directly as its bounding
	# box for the ray-vs-box clip -- calling it again afterward must still agree
	# with the pre-damage cached value (one source of truth, not two divergent
	# caches).
	ship.take_damage(10.0, Vector2(100, 0), Vector2(-1, 0), "kinetic")
	var aabb_after_raymarch: Rect2 = ship.get_local_aabb()
	_assert(aabb_after_raymarch == aabb_1, "Item 3: get_local_aabb() after a take_damage() raymarch should still match the original cached AABB")

# ---------------------------------------------------------------------------
# Item 4: Fallback -- a Ship with empty ship_components returns radius 50.0,
# no crash.
# ---------------------------------------------------------------------------

func _test_empty_components_fallback() -> void:
	var ship = Ship.new()
	ship.ship_components = []
	var radius: float = ship.get_bounding_radius()
	_assert(is_equal_approx(radius, 50.0), "Item 4: Ship with empty ship_components should return bounding radius 50.0, got %s" % radius)

# ---------------------------------------------------------------------------
# Item 5: outline_alpha() pure-function battery.
# ---------------------------------------------------------------------------

func _test_outline_alpha_battery() -> void:
	var full := 1500.0
	var start := 3000.0

	_assert(is_equal_approx(NavigationPanel.outline_alpha(1500.0, full, start), 1.0), "Item 5: outline_alpha(1500) should be 1.0")
	_assert(is_equal_approx(NavigationPanel.outline_alpha(3000.0, full, start), 0.0), "Item 5: outline_alpha(3000) should be 0.0")
	_assert(is_equal_approx(NavigationPanel.outline_alpha(2250.0, full, start), 0.5), "Item 5: outline_alpha(2250) should be 0.5")

	# Clamped both sides.
	_assert(is_equal_approx(NavigationPanel.outline_alpha(0.0, full, start), 1.0), "Item 5: outline_alpha(0) should clamp to 1.0")
	_assert(is_equal_approx(NavigationPanel.outline_alpha(10000.0, full, start), 0.0), "Item 5: outline_alpha(10000) should clamp to 0.0")

	# Strictly monotonic (non-increasing overall, strictly decreasing across
	# the fade window itself) as distance increases.
	var samples: Array = [1500.0, 1800.0, 2100.0, 2400.0, 2700.0, 3000.0]
	var prev_alpha: float = NavigationPanel.outline_alpha(samples[0], full, start)
	for i in range(1, samples.size()):
		var a: float = NavigationPanel.outline_alpha(samples[i], full, start)
		_assert(a < prev_alpha, "Item 5: outline_alpha should strictly decrease across the fade window (dist %s -> %s should be < %s -> %s)" % [samples[i-1], prev_alpha, samples[i], a])
		prev_alpha = a

# ---------------------------------------------------------------------------
# Item 6 (v1.1): Draw-list correctness. Fake contact backed by a live frigate
# at rotation PI/4: _outline_draw_list returns SILHOUETTE loops (union
# contour, cached per class -- ship_outline_rendering.md "first-playtest
# revision"), NOT per-component rects. Oracle: ShipSilhouette.compute() run
# directly on the components. The frigate is a solid hull -> exactly one
# outer loop, no holes; its loop bbox must match the M25 AABB (grown by the
# weld inflate) and its area must track the component-area sum -- a
# convex-hull-style bridge or per-component regression both fail those.
# ---------------------------------------------------------------------------

func _test_draw_list_correctness() -> void:
	var ship = Frigate.new()
	ship.name = "GeomTestFrigate"
	ship.position = Vector2(1000, 0)
	ship.rotation = PI / 4.0
	add_child(ship)

	var contact := {
		"instance_id": ship.get_instance_id(),
		"pos": ship.position,
	}

	var entries: Array = NavigationPanel._outline_draw_list(contact)
	var oracle: Array = ShipSilhouette.compute(ship.ship_components)
	_assert(entries.size() == oracle.size(), "Item 6: _outline_draw_list should return one entry per silhouette loop, got %d expected %d" % [entries.size(), oracle.size()])
	_assert(entries.size() == 1, "Item 6: the frigate (solid hull) should silhouette to exactly ONE loop, got %d" % entries.size())

	if entries.size() == 1:
		var entry: Dictionary = entries[0]
		_assert(entry["is_hole"] == false, "Item 6: the frigate's single loop must be an outer boundary, not a hole")
		_assert(is_equal_approx(entry["rotation"], PI / 4.0), "Item 6: entry rotation should be the ship's heading PI/4, got %s" % entry["rotation"])

		var pts: PackedVector2Array = entry["points"]
		_assert(pts.size() >= 4, "Item 6: silhouette loop needs >= 4 points, got %d" % pts.size())

		# Loop bbox == M25 AABB grown by the weld inflate (ties the silhouette
		# to the same canonical geometry the bounds ring / avoidance use).
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		var area := 0.0
		for i in range(pts.size()):
			min_p = min_p.min(pts[i])
			max_p = max_p.max(pts[i])
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			area += a.x * b.y - b.x * a.y
		area = absf(area * 0.5)
		var expected_bbox: Rect2 = ship.get_local_aabb().grow(0.1)
		var loop_bbox := Rect2(min_p, max_p - min_p)
		_assert(loop_bbox.position.is_equal_approx(expected_bbox.position) and loop_bbox.size.is_equal_approx(expected_bbox.size), "Item 6: silhouette bbox %s should equal the ship AABB grown by the weld inflate %s" % [loop_bbox, expected_bbox])

		var rect_area_sum := 0.0
		for c in ship.ship_components:
			var r: Rect2 = c["rect"]
			rect_area_sum += r.size.x * r.size.y
		_assert(absf(area - rect_area_sum) < rect_area_sum * 0.15, "Item 6: silhouette area %.0f should track the component-area sum %.0f (a convex-hull-like bridge reads far larger)" % [area, rect_area_sum])

		# Caller-transform convention check: local points rotate by the SHIP's
		# heading, no stray 90-degree engineering-panel offset. Verified via a
		# manual rotation-matrix computation on the first point.
		var p0: Vector2 = pts[0]
		var cos45 := cos(PI / 4.0)
		var sin45 := sin(PI / 4.0)
		var manual := Vector2(
			ship.position.x + (p0.x * cos45 - p0.y * sin45),
			ship.position.y + (p0.x * sin45 + p0.y * cos45)
		)
		var via_api: Vector2 = ship.position + p0.rotated(entry["rotation"])
		_assert(via_api.is_equal_approx(manual), "Item 6: caller transform (c_pos + p.rotated(rot)) must equal the manual rotation matrix, got %s vs %s" % [via_api, manual])

	ship.queue_free()

# ---------------------------------------------------------------------------
# Item 7: Stale contact safety. Contact whose instance was freed -> empty
# list, no error. This is a dead-reckoned contact after a kill -- a hot path,
# and exactly the missing-key/freed-instance frame-abort CLAUDE.md warns about.
# ---------------------------------------------------------------------------

func _test_stale_contact_safety() -> void:
	var ship = Frigate.new()
	ship.name = "StaleTestFrigate"
	add_child(ship)
	var freed_id: int = ship.get_instance_id()
	ship.free()

	var stale_contact := {
		"instance_id": freed_id,
		"pos": Vector2(500, 500),
	}
	var entries: Array = NavigationPanel._outline_draw_list(stale_contact)
	_assert(entries == [], "Item 7: _outline_draw_list on a freed instance should return [], got %s" % str(entries))

	var radius: float = NavigationPanel._bounds_radius_for(stale_contact)
	_assert(radius > 0.0, "Item 7: _bounds_radius_for on a freed instance should still return a positive fallback, got %s" % radius)

	# Also: a contact with no instance_id at all (-1 default, or missing key).
	var no_instance_contact := {"pos": Vector2(0, 0)}
	var entries_2: Array = NavigationPanel._outline_draw_list(no_instance_contact)
	_assert(entries_2 == [], "Item 7: _outline_draw_list on a contact with no instance_id should return [], got %s" % str(entries_2))

# ---------------------------------------------------------------------------
# Item 8: Bounds ring. _bounds_radius_for: live destroyer contact -> its true
# radius; invalid instance -> signature-scaled fallback; never returns 0.
# ---------------------------------------------------------------------------

func _test_bounds_ring() -> void:
	var destroyer = Destroyer.new()
	destroyer.name = "BoundsTestDestroyer"
	add_child(destroyer)

	var live_contact := {
		"instance_id": destroyer.get_instance_id(),
		"pos": destroyer.position,
	}
	var radius: float = NavigationPanel._bounds_radius_for(live_contact)
	_assert(is_equal_approx(radius, destroyer.get_bounding_radius()), "Item 8: _bounds_radius_for on a live destroyer contact should equal its true get_bounding_radius() (%s), got %s" % [destroyer.get_bounding_radius(), radius])
	_assert(radius > 50.0, "Item 8: live destroyer's bounds radius should be > 50 (same anchor as Item 2)")

	# Invalid instance -> signature-scaled fallback, never 0.
	var invalid_contact := {
		"instance_id": -1,
		"pos": Vector2.ZERO,
		"signature": {"cross_section": 80.0},
	}
	var fallback_radius: float = NavigationPanel._bounds_radius_for(invalid_contact)
	_assert(fallback_radius > 0.0, "Item 8: invalid-instance contact should get a positive fallback radius, got %s" % fallback_radius)

	# Never-zero even with a totally empty contact dict.
	var empty_contact := {}
	var empty_radius: float = NavigationPanel._bounds_radius_for(empty_contact)
	_assert(empty_radius > 0.0, "Item 8: an empty contact dict should still get a positive fallback radius, got %s" % empty_radius)

	destroyer.queue_free()

# ---------------------------------------------------------------------------
# Item 9 (v1.1): Size-proportional fade window. The old two-case ship/station
# threshold switch is gone -- the window derives from bounding radius
# (start = OUTLINE_START_RADII * r, full = OUTLINE_FULL_RADII * r), so a
# station resolves from much further out than a frigate PURELY because it is
# bigger, and a contact at 8000u resolves for the station but not the frigate.
# ---------------------------------------------------------------------------

func _test_station_gating() -> void:
	var dist := 8000.0

	var station = ShipCatalog.SPAWNABLE.filter(func(e): return e["name"] == "Medium Station")[0]["script"].new()
	station.name = "GatingTestStation"
	add_child(station)
	var frigate = Frigate.new()
	frigate.name = "GatingTestFrigate"
	add_child(frigate)

	var frig_r: float = frigate.get_bounding_radius()
	var stn_r: float = station.get_bounding_radius()
	_assert(stn_r > frig_r * 3.0, "Item 9: sanity -- the station should be much bigger than the frigate (%.0f vs %.0f)" % [stn_r, frig_r])

	var frig_alpha: float = NavigationPanel.outline_alpha(dist, NavigationPanel.OUTLINE_FULL_RADII * frig_r, NavigationPanel.OUTLINE_START_RADII * frig_r)
	_assert(is_equal_approx(frig_alpha, 0.0), "Item 9: a frigate-sized contact at 8000u should read alpha 0 (start=%.0f), got %s" % [NavigationPanel.OUTLINE_START_RADII * frig_r, frig_alpha])

	var stn_alpha: float = NavigationPanel.outline_alpha(dist, NavigationPanel.OUTLINE_FULL_RADII * stn_r, NavigationPanel.OUTLINE_START_RADII * stn_r)
	_assert(stn_alpha > 0.0, "Item 9: a station-sized contact at 8000u should read alpha > 0 (start=%.0f), got %s" % [NavigationPanel.OUTLINE_START_RADII * stn_r, stn_alpha])

	# Anchor the constants roughly to the old hand-tuned feel: a frigate
	# resolves fully somewhere inside 1000-2000u, starts resolving inside
	# 2000-4000u.
	_assert(NavigationPanel.OUTLINE_FULL_RADII * frig_r > 1000.0 and NavigationPanel.OUTLINE_FULL_RADII * frig_r < 2000.0, "Item 9: frigate full-resolve distance should land in 1000-2000u, got %.0f" % (NavigationPanel.OUTLINE_FULL_RADII * frig_r))
	_assert(NavigationPanel.OUTLINE_START_RADII * frig_r > 2000.0 and NavigationPanel.OUTLINE_START_RADII * frig_r < 4000.0, "Item 9: frigate fade-start distance should land in 2000-4000u, got %.0f" % (NavigationPanel.OUTLINE_START_RADII * frig_r))

	station.queue_free()
	frigate.queue_free()
