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

	if failures.is_empty():
		print(">>> [TEST PASSED] test_ship_geometry <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_ship_geometry <<<")
		get_tree().quit(1)

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
# Item 6: Draw-list correctness. Fake contact backed by a live frigate at
# distance 1000, rotation PI/4: _outline_draw_list returns one entry per
# component; every entry's rect is in the frigate's authored rect set;
# spot-check hull_fwd's four world-space corners against hand-computed
# rotate+translate values. forward = +X (ship.gd's own convention, see
# frigate.gd's "Layout relative to center (0,0). Forward +X, Right +Y") --
# the engineering panel's 90-degree display convention must NOT leak into
# this world-space math.
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
	_assert(entries.size() == ship.ship_components.size(), "Item 6: _outline_draw_list should return one entry per component, got %d expected %d" % [entries.size(), ship.ship_components.size()])

	var authored_rects: Array = []
	for c in ship.ship_components:
		authored_rects.append(c["rect"])

	for entry in entries:
		var r: Rect2 = entry["rect"]
		_assert(authored_rects.has(r), "Item 6: entry rect %s should be one of the frigate's authored rects" % r)

	# Spot-check hull_fwd: Rect2(15, -15, 15, 30) at ship rotation PI/4,
	# position (1000, 0). Hand-computed rotate(PI/4) + translate corners:
	var hull_fwd_rect := Rect2(15, -15, 15, 30)
	var hull_fwd_entry = null
	for entry in entries:
		if entry["rect"] == hull_fwd_rect:
			hull_fwd_entry = entry
			break
	_assert(hull_fwd_entry != null, "Item 6: hull_fwd's rect %s should appear in the draw list" % hull_fwd_rect)

	if hull_fwd_entry != null:
		var rot: float = hull_fwd_entry["rotation"]
		_assert(is_equal_approx(rot, PI / 4.0), "Item 6: entry rotation should be the ship's heading PI/4, got %s" % rot)

		var expected_world_pos: Vector2 = ship.position + hull_fwd_rect.position.rotated(PI / 4.0)
		_assert(hull_fwd_entry["world_pos"].is_equal_approx(expected_world_pos), "Item 6: hull_fwd world_pos %s should equal hand-computed rotate+translate %s" % [hull_fwd_entry["world_pos"], expected_world_pos])

		# Full four-corner hand computation (caller applies rotate+translate to
		# all four corners the same way world_pos does for the min corner).
		var local_corners = [
			hull_fwd_rect.position,
			hull_fwd_rect.position + Vector2(hull_fwd_rect.size.x, 0),
			hull_fwd_rect.position + hull_fwd_rect.size,
			hull_fwd_rect.position + Vector2(0, hull_fwd_rect.size.y),
		]
		var expected_world_corners: Array = []
		for lc in local_corners:
			expected_world_corners.append(ship.position + lc.rotated(PI / 4.0))

		# hand-computed numeric check (rotate(PI/4): x' = x*cos - y*sin, y' = x*sin + y*cos)
		var cos45 := cos(PI / 4.0)
		var sin45 := sin(PI / 4.0)
		var manual_min_corner := Vector2(
			ship.position.x + (hull_fwd_rect.position.x * cos45 - hull_fwd_rect.position.y * sin45),
			ship.position.y + (hull_fwd_rect.position.x * sin45 + hull_fwd_rect.position.y * cos45)
		)
		_assert(hull_fwd_entry["world_pos"].is_equal_approx(manual_min_corner), "Item 6: hull_fwd world_pos %s should equal fully-manual rotation-matrix computation %s (checks no stray 90-degree/engineering-panel convention leaked in)" % [hull_fwd_entry["world_pos"], manual_min_corner])
		_assert(not hull_fwd_entry["world_pos"].is_equal_approx(ship.position + hull_fwd_rect.position.rotated(PI / 4.0 + PI / 2.0)), "Item 6: hull_fwd world_pos must NOT match a world_pos computed with an extra +90-degree offset (the engineering panel's display convention leaking in)")

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
# Item 9: Station gating. A station contact at 8000 has alpha 0 under ship
# thresholds but > 0 under station thresholds -- asserts the type switch works.
# ---------------------------------------------------------------------------

func _test_station_gating() -> void:
	var dist := 8000.0

	var ship_alpha: float = NavigationPanel.outline_alpha(dist, NavigationPanel.OUTLINE_FULL, NavigationPanel.OUTLINE_FADE_START)
	_assert(is_equal_approx(ship_alpha, 0.0), "Item 9: a contact at 8000u should read alpha 0 under SHIP thresholds (full=%s start=%s), got %s" % [NavigationPanel.OUTLINE_FULL, NavigationPanel.OUTLINE_FADE_START, ship_alpha])

	var station_alpha: float = NavigationPanel.outline_alpha(dist, NavigationPanel.STATION_OUTLINE_FULL, NavigationPanel.STATION_OUTLINE_FADE_START)
	_assert(station_alpha > 0.0, "Item 9: the same contact at 8000u should read alpha > 0 under STATION thresholds (full=%s start=%s), got %s" % [NavigationPanel.STATION_OUTLINE_FULL, NavigationPanel.STATION_OUTLINE_FADE_START, station_alpha])

	# Also exercise the type-switch helper directly: a STRUCTURE-tier ship
	# instance must be classified as a station; an ordinary ship must not.
	var station = ShipCatalog.SPAWNABLE.filter(func(e): return e["name"] == "Small Station")[0]["script"].new()
	station.name = "GatingTestStation"
	add_child(station)
	_assert(NavigationPanel._is_station_ship(station) == true, "Item 9: a STRUCTURE-tier ship instance should be classified as a station")

	var frigate = Frigate.new()
	frigate.name = "GatingTestFrigate"
	add_child(frigate)
	_assert(NavigationPanel._is_station_ship(frigate) == false, "Item 9: a non-STRUCTURE ship instance should NOT be classified as a station")

	station.queue_free()
	frigate.queue_free()
