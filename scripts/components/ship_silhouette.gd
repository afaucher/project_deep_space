class_name ShipSilhouette

# v1.1 outline revision (design_ideas/ship_outline_rendering.md, "first-
# playtest revision") -- the nav map's close-range outline is the ship's
# SILHOUETTE: the rectilinear union contour of its component rects, not the
# per-component boxes (those leaked module layout and read as clutter on the
# Ironhold approach). Pure static geometry + a per-class cache; no Node deps.
#
# Output space: ship-local (same frame the rects are authored in). Callers
# rotate/translate per contact, same as every other outline path.
#
# Holes: a fully-enclosed empty region (the defence pod's ring center) comes
# back as its own loop with `is_hole = true`. They're rare by construction --
# the validator's connectivity rule plus dense layouts mean most hulls union
# into a single boundary ring.
#
# Winding convention: Godot's Geometry2D polygon ops mark holes by winding
# (see _is_hole). If a future engine version flips the convention,
# test_ship_silhouette's ring fixture fails loudly -- trust the test, not the
# docs comment.

# Rects are inflated by this before merging so edge-TOUCHING rects (the
# validator's connectivity idiom -- shared edges, zero overlap) reliably union
# instead of depending on exact-coincident-edge handling in the clipper. The
# resulting contour is fatter by this amount -- invisible at map scale.
const EDGE_WELD_INFLATE := 0.1

# Holes smaller than this area are merge noise, not architecture -- drop them.
const MIN_HOLE_AREA := 100.0

# script resource path -> Array of {"points": PackedVector2Array, "is_hole": bool}
static var _cache: Dictionary = {}

# Silhouette loops for a ship instance, cached per CLASS (geometry is a pure
# function of the authored design; every instance of a class shares it).
static func loops_for(ship) -> Array:
	var script = ship.get_script()
	var key: String = script.resource_path if script != null else ""
	if key != "" and _cache.has(key):
		return _cache[key]
	var comps = ship.get("ship_components")
	if comps == null:
		return []
	var loops: Array = compute(comps)
	if key != "":
		_cache[key] = loops
	return loops

# Compute the union silhouette of a component array. Exposed separately from
# the cache so tests can drive it with fixtures.
static func compute(components: Array) -> Array:
	# 1. Every component rect -> an inflated CCW quad.
	var pending: Array = []
	for comp in components:
		var rect: Rect2 = comp.get("rect", Rect2())
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		pending.append(_rect_poly(rect.grow(EDGE_WELD_INFLATE)))
	if pending.is_empty():
		return []

	# 2. Fold every quad into a growing set of disjoint outer boundaries,
	# collecting hole rings as merges produce them. The validator guarantees
	# edge-connectivity, so a connected ship converges to ONE outer; the loop
	# still handles disjoint leftovers defensively (draws them separately
	# rather than dropping them).
	var outers: Array = [pending.pop_back()]
	var holes: Array = []
	var stuck := false
	while not pending.is_empty() and not stuck:
		stuck = true
		for p_idx in range(pending.size() - 1, -1, -1):
			var merged_into := -1
			for o_idx in range(outers.size()):
				var result: Array = Geometry2D.merge_polygons(outers[o_idx], pending[p_idx])
				var new_outers: Array = []
				for ring in result:
					if _is_hole(ring):
						holes.append(ring)
					else:
						new_outers.append(ring)
				if new_outers.size() == 1:
					# Union succeeded -- the quad dissolved into this boundary.
					outers[o_idx] = new_outers[0]
					merged_into = o_idx
					break
				# new_outers.size() == 2 -> disjoint from this outer; try the next.
			if merged_into != -1:
				pending.remove_at(p_idx)
				stuck = false
		if stuck and not pending.is_empty():
			# No pending quad touches any current outer (disconnected design --
			# the validator flags those, but don't infinite-loop on one).
			outers.append(pending.pop_back())
			stuck = false

	# 2b. Outers can become mergeable with each other only after a bridging
	# quad joined them; one final pairwise pass settles it.
	var settled := false
	while not settled:
		settled = true
		for i in range(outers.size()):
			if not settled:
				break
			for j in range(outers.size() - 1, i, -1):
				var result: Array = Geometry2D.merge_polygons(outers[i], outers[j])
				var new_outers: Array = []
				for ring in result:
					if _is_hole(ring):
						holes.append(ring)
					else:
						new_outers.append(ring)
				if new_outers.size() == 1:
					outers[i] = new_outers[0]
					outers.remove_at(j)
					settled = false
					break

	# 3. A hole ring discovered mid-fold may have been (partly) filled by
	# quads merged later (interior modules land inside the not-yet-closed
	# ring). Subtract every quad from every hole; keep what survives.
	var final_holes: Array = []
	for hole in holes:
		var fragments: Array = [hole]
		for comp in components:
			var rect: Rect2 = comp.get("rect", Rect2())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			var quad := _rect_poly(rect.grow(EDGE_WELD_INFLATE))
			var next_fragments: Array = []
			for frag in fragments:
				# clip = frag minus quad; returns 0..n fragments.
				var clipped: Array = Geometry2D.clip_polygons(frag, quad)
				for piece in clipped:
					if not _is_hole(piece):
						next_fragments.append(piece)
					# (clip can emit its own winding artifacts; only keep
					# solid fragments of the hole region.)
			fragments = next_fragments
			if fragments.is_empty():
				break
		for frag in fragments:
			if absf(_ring_area(frag)) >= MIN_HOLE_AREA:
				final_holes.append(frag)

	var out: Array = []
	for ring in outers:
		out.append({"points": ring, "is_hole": false})
	for ring in final_holes:
		out.append({"points": ring, "is_hole": true})
	return out

static func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])

# Hole detection by winding. Geometry2D's boolean ops emit hole rings wound
# opposite to boundary rings; is_polygon_clockwise() is the discriminator the
# engine docs point at. Verified empirically by test_ship_silhouette's ring
# fixture -- if this ever reads inverted on an engine upgrade, that test is
# the tripwire.
static func _is_hole(ring: PackedVector2Array) -> bool:
	return Geometry2D.is_polygon_clockwise(ring)

# Signed shoelace area (used only for the min-hole-area cut).
static func _ring_area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
