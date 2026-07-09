extends RefCounted

# Minimal test double for RadarCrossSection.cross_section_at_angle / M38 tests
# (scripts/tests/test_radar_cross_section.gd). Needs only what that call path
# touches: `.rotation`, `.ship_components` (via get()), `.get_script()`
# (RefCounted has this natively), and `get_local_aabb()` for the empty-geometry
# fallback. Not a real Ship -- no Node/scene deps, matches the pure-fixture
# style used elsewhere in this repo's static-helper tests.

var rotation: float = 0.0
var ship_components: Array = []

func get_local_aabb() -> Rect2:
	if ship_components.is_empty():
		return Rect2()
	var result := Rect2()
	var first := true
	for comp in ship_components:
		var rect: Rect2 = comp.get("rect", Rect2())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if first:
			result = rect
			first = false
		else:
			result = result.merge(rect)
	return result
