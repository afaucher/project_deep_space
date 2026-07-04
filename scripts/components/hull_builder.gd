class_name HullBuilder

# M22 -- hull builders: the grammar ops. Pure static functions that generate
# component-dict arrays for the layout idioms every ship hand-expands today
# (frame walls, tapered profiles, station arms, armor boxes, destroyer
# zippers, mirrored port/stbd or fwd/aft pairs, radial stamps). See
# design_ideas/hull_shape_grammar.md §4 and
# implementation_plans/m22_hull_builders_design.md.
#
# Every function here is a PURE function: no Node access, no autoload reads,
# no shared mutable state, no RNG -- callable from a ship's _init() (before
# the scene tree exists) exactly as easily as from a test. Two identical
# calls always yield identical arrays (test item 8).
#
# Runtime is untouched: these return the exact same plain component-dict
# shape ships have always hand-authored. Ship._ready() normalization, the
# validator, and the renderer don't know or care whether a dict came from a
# hand-written literal or a builder call.
#
# No real ship file is converted this milestone -- the re-expression proof
# (LAC, small_station) lives in scripts/tests/test_hull_builders.gd only.

# Fixed wall/flank/cap thickness for the station arm idiom -- both arm pairs
# in small_station.gd (fwd/aft length 40, port/stbd length 100) use the same
# 10-unit wall thickness; only length/width vary. See arm() below.
const ARM_WALL_THICKNESS := 10.0

# Default density for hull-family segments produced by these builders. Matches
# fleet convention (every hand-authored hull component today is density 20.0).
const DEFAULT_DENSITY := 20.0

# ---------------------------------------------------------------------------
# Shared dict shape helper -- mirrors Parts._base_dict's field set (see
# parts_catalog.gd) so builder output is schema-identical to catalog output.
# ---------------------------------------------------------------------------

static func _hull_dict(comp_id: String, rect: Rect2, hp: float, density: float = DEFAULT_DENSITY) -> Dictionary:
	return {
		"id": comp_id,
		"type": "hull",
		"rect": rect,
		"health": hp,
		"max_health": hp,
		"density": density,
		"heat": 0.0,
		"em_emission": 0.0,
		"switchable": false,
	}

# ---------------------------------------------------------------------------
# frame(rect, thickness, hp) -- 4 wall segments around rect's perimeter.
# Top/bottom walls run the full width; left/right walls are inset by
# `thickness` top and bottom so no two walls overlap (they only touch at the
# four inner corners) -- overlap would fail the validator's overlap check.
# The walls' union AABB equals `rect` exactly; the interior cavity
# (rect shrunk by `thickness` on all sides) is covered by no wall.
#
# id_prefix (opts): ids are "<prefix>_top/_bottom/_left/_right" -- purely a
# function of the prefix + wall role, no counter, so two identical calls
# (same rect/thickness/hp/opts) always yield byte-identical ids (test item 8;
# a shared counter would be hidden mutable state and break this).
# ---------------------------------------------------------------------------

static func frame(rect: Rect2, thickness: float, hp: float, opts: Dictionary = {}) -> Array:
	var prefix: String = opts.get("id_prefix", "frame")
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y

	var top := Rect2(x, y, w, thickness)
	var bottom := Rect2(x, y + h - thickness, w, thickness)
	var left := Rect2(x, y + thickness, thickness, h - 2.0 * thickness)
	var right := Rect2(x + w - thickness, y + thickness, thickness, h - 2.0 * thickness)

	return [
		_hull_dict("%s_top" % prefix, top, hp),
		_hull_dict("%s_bottom" % prefix, bottom, hp),
		_hull_dict("%s_left" % prefix, left, hp),
		_hull_dict("%s_right" % prefix, right, hp),
	]

# ---------------------------------------------------------------------------
# taper(x0, x1, widths) -- stepped bow/stern profile. Splits [x0, x1] into
# widths.size() equal-length slices along x; slice i is a hull segment of
# that slice's x-extent, centered on y=0, with total (both-sides) height
# widths[i]. Adjacent slices share an edge (touching, not overlapping), so
# the whole run is connected end to end.
#
# id_prefix (opts): ids are "<prefix>_<index>" (index-derived, not a
# counter) so identical calls are byte-identical (test item 8).
# ---------------------------------------------------------------------------

static func taper(x0: float, x1: float, widths: Array, opts: Dictionary = {}) -> Array:
	var prefix: String = opts.get("id_prefix", "taper")
	var out: Array = []
	var n: int = widths.size()
	if n == 0:
		return out
	var slice_w: float = (x1 - x0) / float(n)
	for i in range(n):
		var seg_x0: float = x0 + slice_w * float(i)
		var half: float = float(widths[i]) / 2.0
		var rect := Rect2(seg_x0, -half, slice_w, half * 2.0)
		# Health scales with segment area at fleet hull density so a wider
		# step is also a tougher one (same idea as Parts' hull health_per_area).
		var area: float = slice_w * (half * 2.0)
		var hp: float = max(1.0, area * 1.28) # LIGHT/STANDARD health_per_area, a reasonable default
		out.append(_hull_dict("%s_%d" % [prefix, i], rect, hp))
	return out

# ---------------------------------------------------------------------------
# arm(dir, offset, length, width, hp) -- station arm idiom: a cap (end wall,
# matching the core tube's cross-section) plus two side flanks (running
# alongside the arm, outboard of the core's cross-section, from `offset` to
# `offset + length` along `dir`). This is "author one arm's shell" from
# hull_shape_grammar.md §4 / small_station.gd's idiom -- the core tube itself
# (reactor/sensors/living_quarters/cargo) is NOT part of the shell; callers
# add that separately.
#
# dir: unit vector along the arm's axis (e.g. Vector2(1,0) for a fwd arm,
#      Vector2(0,-1) for a port arm). Must be one of the 4 axis-aligned unit
#      vectors -- this idiom is Rect2-only geometry (see grammar doc §2).
# offset: distance from the ship origin to where the flanks begin (matches
#      the ship-relative distance to the core's far edge along dir).
# length: flank length along dir.
# width: the core tube's cross-section width (the cap matches this width;
#      the flanks sit just outboard of it, thickness ARM_WALL_THICKNESS).
# hp: health/max_health applied to cap + both flanks.
#
# id_prefix (opts): optional id prefix; produces "<prefix>_cap",
# "<prefix>_flank_pos", "<prefix>_flank_neg" ("pos"/"neg" along +perp/-perp,
# where perp = dir rotated +90degrees -- deliberately direction-agnostic
# naming since "port/stbd" vs "fwd/aft" depends on which axis dir is on;
# mirror_y/mirror_x's id-suffix convention is for THEIR output, not arm()'s).
# ---------------------------------------------------------------------------

static func arm(dir: Vector2, offset: float, length: float, width: float, hp: float, opts: Dictionary = {}) -> Array:
	var prefix: String = opts.get("id_prefix", "arm")
	var perp := Vector2(-dir.y, dir.x)
	var half_w: float = width / 2.0
	var thickness: float = ARM_WALL_THICKNESS

	# Build each rect from a PAIR of opposite corners (both expressed via
	# signed vector math along dir/perp) and take the component-wise min/size
	# from that pair -- robust regardless of dir's sign (e.g. dir = (0,-1)
	# for a "port" arm, where naive "start" corners are NOT the min corner).
	var dir_a: Vector2 = dir * offset
	var dir_b: Vector2 = dir * (offset + length)

	var flank_pos_rect := _rect_from_corners(dir_a + perp * half_w, dir_b + perp * (half_w + thickness))
	var flank_neg_rect := _rect_from_corners(dir_a + perp * (-half_w), dir_b + perp * (-half_w - thickness))

	var cap_dir_a: Vector2 = dir * (offset + length)
	var cap_dir_b: Vector2 = dir * (offset + length + thickness)
	var cap_rect := _rect_from_corners(cap_dir_a + perp * (-half_w), cap_dir_b + perp * half_w)

	return [
		_hull_dict("%s_cap" % prefix, cap_rect, hp),
		_hull_dict("%s_flank_pos" % prefix, flank_pos_rect, hp),
		_hull_dict("%s_flank_neg" % prefix, flank_neg_rect, hp),
	]

# arm() helper: builds a Rect2 from two opposite corners, regardless of which
# one is numerically smaller on either axis (handles dir vectors with
# negative components, e.g. a "port" or "aft" arm pointing along -X/-Y).
static func _rect_from_corners(c1: Vector2, c2: Vector2) -> Rect2:
	var pos := Vector2(min(c1.x, c2.x), min(c1.y, c2.y))
	var size := Vector2(abs(c2.x - c1.x), abs(c2.y - c1.y))
	return Rect2(pos, size)

# ---------------------------------------------------------------------------
# armor_box(inner, thickness, hp) -- wrap a reactor (or any inner rect) in a
# 4-sided armor shell, same construction as frame() but expressed in terms of
# the OUTER envelope implied by growing `inner` outward by `thickness` on all
# sides (frame()'s rect = inner grown by thickness).
# ---------------------------------------------------------------------------

static func armor_box(inner: Rect2, thickness: float, hp: float, opts: Dictionary = {}) -> Array:
	var frame_opts: Dictionary = opts.duplicate(true)
	if not frame_opts.has("id_prefix"):
		frame_opts["id_prefix"] = "armor_box"
	var outer := Rect2(
		inner.position.x - thickness,
		inner.position.y - thickness,
		inner.size.x + 2.0 * thickness,
		inner.size.y + 2.0 * thickness
	)
	return frame(outer, thickness, hp, frame_opts)

# ---------------------------------------------------------------------------
# zipper(x0, x1, cell_w, cells) -- alternating hull/weapon flank (destroyer
# idiom). `cells` is an array of length n = (x1-x0)/cell_w; each entry is
# either:
#   - a Dictionary with "kind": "hull" (a hull cell is generated, health
#     scaled to the cell area), or
#   - a pre-built weapon component Dictionary (already has "type": "weapons"
#     etc, e.g. from Parts.make) -- zipper() places it (overwrites its "rect"
#     to the cell's slot, preserving its other fields) rather than building
#     a new dict, so the caller's weapon stats survive verbatim.
# Cells are placed left to right, each cell_w wide, all sharing the same
# y-extent (2*half_h centered on 0, half_h taken from cell_h/2 -- see below),
# so consecutive cells touch edge to edge (connected end to end).
# ---------------------------------------------------------------------------

static func zipper(x0: float, x1: float, cell_w: float, cell_h: float, cells: Array, hp: float = 100.0, opts: Dictionary = {}) -> Array:
	var prefix: String = opts.get("id_prefix", "zipper")
	var out: Array = []
	var half_h: float = cell_h / 2.0
	for i in range(cells.size()):
		var cell_x0: float = x0 + cell_w * float(i)
		var rect := Rect2(cell_x0, -half_h, cell_w, cell_h)
		var entry = cells[i]
		if entry is Dictionary and entry.get("kind", "") == "hull":
			var area: float = cell_w * cell_h
			var cell_hp: float = max(1.0, area * 1.28)
			out.append(_hull_dict("%s_hull_%d" % [prefix, i], rect, cell_hp if not entry.has("hp") else entry["hp"]))
		elif entry is Dictionary:
			# Pre-built weapon (or other) component dict -- place it at this
			# cell's slot, keep all its other authored fields untouched. Its
			# own "id" (already deterministic, authored by the caller/Parts)
			# is preserved as-is; only a missing id gets an index-derived one.
			var placed: Dictionary = entry.duplicate(true)
			placed["rect"] = rect
			if not placed.has("id"):
				placed["id"] = "%s_weapon_%d" % [prefix, i]
			out.append(placed)
		else:
			# Fallback: an unrecognized cell entry becomes a plain hull cell so
			# zipper() never silently drops a slot.
			var area2: float = cell_w * cell_h
			var cell_hp2: float = max(1.0, area2 * 1.28)
			out.append(_hull_dict("%s_hull_%d" % [prefix, i], rect, cell_hp2))
	return out

# ---------------------------------------------------------------------------
# mirror_y(comps) -- port <-> stbd: rect (x, -y-h, w, h); heading -> wrapped
# (-heading); id suffix "_port" <-> "_stbd" (also swaps the bare substrings
# "port"/"stbd" anywhere in the id, matching small_station.gd's naming, e.g.
# "hull_port_fwd_flank" -> "hull_stbd_fwd_flank").
# ---------------------------------------------------------------------------

static func mirror_y(comps: Array) -> Array:
	var out: Array = []
	for c in comps:
		var m: Dictionary = c.duplicate(true)
		if m.has("rect"):
			var r: Rect2 = m["rect"]
			m["rect"] = Rect2(r.position.x, -r.position.y - r.size.y, r.size.x, r.size.y)
		if m.has("heading"):
			m["heading"] = wrapf(-float(m["heading"]), -PI, PI)
		if m.has("id"):
			m["id"] = _swap_tokens(m["id"], "port", "stbd")
		out.append(m)
	return out

# ---------------------------------------------------------------------------
# mirror_x(comps) -- fwd <-> aft: rect (-x-w, y, w, h); heading -> wrapped
# (PI - heading); id suffix "_fwd" <-> "_aft" (substring swap, same rule).
# ---------------------------------------------------------------------------

static func mirror_x(comps: Array) -> Array:
	var out: Array = []
	for c in comps:
		var m: Dictionary = c.duplicate(true)
		if m.has("rect"):
			var r: Rect2 = m["rect"]
			m["rect"] = Rect2(-r.position.x - r.size.x, r.position.y, r.size.x, r.size.y)
		if m.has("heading"):
			m["heading"] = wrapf(PI - float(m["heading"]), -PI, PI)
		if m.has("id"):
			m["id"] = _swap_tokens(m["id"], "fwd", "aft")
		out.append(m)
	return out

# Swaps every occurrence of token `a` with `b` and vice versa in `id`, in a
# single pass (so "a" -> "b" and "b" -> "a" don't cascade into each other).
# Uses a placeholder that cannot collide with real ids.
static func _swap_tokens(id: String, a: String, b: String) -> String:
	var placeholder := "__swap__"
	var result: String = id.replace(a, placeholder)
	result = result.replace(b, a)
	result = result.replace(placeholder, b)
	return result

# ---------------------------------------------------------------------------
# rotate_90(comps, n) -- radial stamp; rotates each component's rect corners
# by n*90 degrees about the origin, and advances heading by n*PI/2 (wrapped).
# For future radially-symmetric designs (mine plus-shape, defence pod ring);
# the existing stations are mirror-symmetric, not rotation-symmetric (see
# design note in hull_shape_grammar.md / m22 plan), so this gets synthetic
# unit tests only, not a re-expression proof against a real ship.
#
# n=0 is identity; n=4 (or any multiple of 4) is also identity (TAU wrap).
# Rect2 has no rotation, so a rotated rect is reconstructed from its 4
# rotated corners' new AABB -- for n*90-degree rotations this is exact (no
# corner-cutting/approximation) since axis-aligned rects rotated by a
# multiple of 90 degrees are still axis-aligned rects.
# ---------------------------------------------------------------------------

static func rotate_90(comps: Array, n: int) -> Array:
	var out: Array = []
	var steps: int = ((n % 4) + 4) % 4
	for c in comps:
		var m: Dictionary = c.duplicate(true)
		if m.has("rect"):
			var r: Rect2 = m["rect"]
			var corners := [
				r.position,
				r.position + Vector2(r.size.x, 0.0),
				r.position + Vector2(0.0, r.size.y),
				r.position + r.size,
			]
			var rotated: Array = []
			for pt in corners:
				rotated.append(_rotate_point_90(pt, steps))
			var min_x: float = INF
			var min_y: float = INF
			var max_x: float = -INF
			var max_y: float = -INF
			for pt in rotated:
				min_x = min(min_x, pt.x)
				min_y = min(min_y, pt.y)
				max_x = max(max_x, pt.x)
				max_y = max(max_y, pt.y)
			m["rect"] = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		if m.has("heading"):
			m["heading"] = wrapf(float(m["heading"]) + steps * (PI / 2.0), -PI, PI)
		out.append(m)
	return out

# Rotates a point by steps*90 degrees about the origin (steps in [0,3]).
# Exact integer-axis-swap rotation -- no trig, no floating rounding drift.
static func _rotate_point_90(pt: Vector2, steps: int) -> Vector2:
	var p := pt
	for _i in range(steps):
		p = Vector2(-p.y, p.x)
	return p
