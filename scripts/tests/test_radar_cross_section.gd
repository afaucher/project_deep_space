extends Node

# M38 -- unit battery for RadarCrossSection (angle-accurate cross-section for
# active sensors). Pure math, no physics frames. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_radar_cross_section

const RadarCrossSection = preload("res://scripts/components/radar_cross_section.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main) -> void:
	print("Starting Radar Cross-Section (M38) Tests")

	_test_rect_bow_on_gives_beam()
	_test_rect_broadside_gives_length()
	_test_cache_is_stable_across_calls()
	_test_empty_ship_no_crash()
	_test_cross_section_at_angle_wrapper()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_radar_cross_section <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_radar_cross_section <<<")
		get_tree().quit(1)

func _hull(rect: Rect2) -> Dictionary:
	return {"id": "h%d" % randi(), "type": "hull", "rect": rect, "health": 100.0, "max_health": 100.0, "density": 20.0}

# A 200 (x, "length") by 40 (y, "beam") single-hull rectangle, centered on
# origin -- Rect2(Vector2(-100,-20), Vector2(200,40)).
func _rect_ship_components() -> Array:
	return [_hull(Rect2(Vector2(-100, -20), Vector2(200, 40)))]

# 1. Bow-on (looking down the ship's local +/-X axis, i.e. bucket_center ~ 0)
# should project the BEAM (~40), not the length.
func _test_rect_bow_on_gives_beam() -> void:
	var comps: Array = _rect_ship_components()
	var extent: float = RadarCrossSection.compute(comps, 0.0)
	_assert(absf(extent - 40.0) < 2.0, "bow-on: expected extent ~40 (beam), got %.2f" % extent)

# 2. Broadside (bucket_center ~ PI/2) should project the LENGTH (~200).
func _test_rect_broadside_gives_length() -> void:
	var comps: Array = _rect_ship_components()
	var extent: float = RadarCrossSection.compute(comps, PI / 2.0)
	_assert(absf(extent - 200.0) < 2.0, "broadside: expected extent ~200 (length), got %.2f" % extent)

# 3. Caching: two calls with the same ship class + angle bucket return the
# identical cached value (exact reproducibility).
func _test_cache_is_stable_across_calls() -> void:
	var ship = _make_test_ship(_TestShipScript, _rect_ship_components(), 0.0)
	var a: float = RadarCrossSection.cross_section_at_angle(ship, 0.0)
	var b: float = RadarCrossSection.cross_section_at_angle(ship, 0.0)
	_assert(a == b, "cache: repeated lookups for the same class+bucket should be identical, got %.4f vs %.4f" % [a, b])
	_assert(absf(a - 40.0) < 2.0, "cache: bow-on cached value should be ~40 (beam), got %.2f" % a)
	# RefCounted test doubles are GC'd automatically -- no .free() (that's for
	# manually-managed Objects like Node; calling it on a RefCounted errors).

# 4. A ship with genuinely no geometry (empty ship_components, no usable
# AABB) doesn't crash and returns 0.0. Uses its OWN fixture script identity
# (test_rcs_ship_empty.gd) so RadarCrossSection's per-class cache (keyed by
# script.resource_path) can't collide with the rect fixture's bucket-0 entry
# from the other test cases above.
func _test_empty_ship_no_crash() -> void:
	var ship = _make_test_ship(_TestShipScriptEmpty, [], 0.0)
	var extent: float = RadarCrossSection.cross_section_at_angle(ship, 0.0)
	_assert(extent == 0.0, "empty ship: expected 0.0 extent, got %.2f" % extent)

	# Defensive guard: ship_components == null must not crash, even called
	# directly (e.g. a bad test fixture) -- returns 0.0.
	var bad_ship := RefCounted.new()
	var extent2: float = RadarCrossSection.cross_section_at_angle(bad_ship, 0.0)
	_assert(extent2 == 0.0, "null ship_components: expected 0.0 extent guard, got %.2f" % extent2)

# 5. The public cached wrapper (world-frame angle_from_target, ship.rotation
# applied) gives the same bow/broadside behavior as the pure compute() path,
# including when the ship itself is rotated 90 degrees (local bow-on is then
# a world-frame PI/2 bearing). Own fixture script identity for the same
# cache-isolation reason as above.
func _test_cross_section_at_angle_wrapper() -> void:
	var ship = _make_test_ship(_TestShipScriptRotated, _rect_ship_components(), PI / 2.0) # ship rotated 90deg
	# World bearing PI/2 - ship.rotation (PI/2) = local 0 -> bow-on -> beam.
	var bow: float = RadarCrossSection.cross_section_at_angle(ship, PI / 2.0)
	_assert(absf(bow - 40.0) < 2.0, "rotated ship, bow-on world bearing: expected ~40, got %.2f" % bow)
	# World bearing 0 - ship.rotation (PI/2) = local -PI/2 -> broadside -> length.
	var broadside: float = RadarCrossSection.cross_section_at_angle(ship, 0.0)
	_assert(absf(broadside - 200.0) < 2.0, "rotated ship, broadside world bearing: expected ~200, got %.2f" % broadside)

# Minimal script-backed test double: ShipSilhouette.loops_for/get_script and
# RadarCrossSection only need `ship_components` and `rotation` to be readable
# via get()/get_script(), plus get_local_aabb() for the empty-geometry
# fallback -- a RefCounted-based fixture script covers all of it with no
# Node/scene deps. Three distinct script identities (empty/rotated variants
# just `extend` the base fixture) so each test case gets its own per-class
# cache bucket space and can't bleed into another case's cached value.
const _TestShipScript = preload("res://scripts/tests/fixtures/test_rcs_ship.gd")
const _TestShipScriptEmpty = preload("res://scripts/tests/fixtures/test_rcs_ship_empty.gd")
const _TestShipScriptRotated = preload("res://scripts/tests/fixtures/test_rcs_ship_rotated.gd")

func _make_test_ship(script: Script, components: Array, rot: float):
	var ship = script.new()
	ship.ship_components = components
	ship.rotation = rot
	return ship
