extends Node

# M22 acceptance -- hull builder grammar ops. Proves HullBuilder's pure
# functions (frame/taper/arm/armor_box/zipper/mirror_y/mirror_x/rotate_90)
# produce correct, validator-legal geometry, and -- the milestone's real gate
# -- that the grammar can re-express a REAL ship's hull (LightAttackCraft) and
# a REAL station's arm shells (SmallStation, via mirror composition) exactly.
# See implementation_plans/m22_hull_builders_design.md's numbered test plan
# (items 1-8, mapped 1:1 to the _test_* functions below). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_hull_builders
#
# Validation here is synchronous/pure (no physics needed), so setup() does
# everything and quits immediately -- same pattern as test_ship_designs.gd.

const HullBuilder = preload("res://scripts/components/hull_builder.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const SmallStation = preload("res://scripts/ships/small_station.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

# Wrapped-angle equality -- the plan's called-out failure mode (-PI vs PI,
# -0.0 vs 0.0). Wraps BOTH sides into [-PI, PI) before comparing, then
# allows a small epsilon (also wrap-aware: -PI and PI-eps are close on the
# circle even though their wrapped scalars differ by ~2*PI).
func _angles_equal(a: float, b: float, eps: float = 1e-4) -> bool:
	var wa: float = wrapf(a, -PI, PI)
	var wb: float = wrapf(b, -PI, PI)
	var diff: float = abs(wrapf(wa - wb, -PI, PI))
	return diff <= eps

func setup(_main: Node) -> void:
	print("Starting Hull Builder (M22) Tests")

	_test_frame()                     # item 1
	_test_mirror_y_and_mirror_x()     # item 2
	_test_rotate_90()                 # item 3
	_test_armor_box()                 # item 4
	_test_zipper()                    # item 5
	_test_lac_re_expression()         # item 6 (gate)
	_test_station_shell_re_expression() # item 7 (gate)
	_test_determinism()               # item 8

	if failures.is_empty():
		print(">>> [TEST PASSED] test_hull_builders <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_hull_builders <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# Item 1: frame() -- exactly 4 walls; pairwise non-overlap; mutually
# connected (each touches >=1 other); outer envelope equals the requested
# rect; cavity probe points covered by no wall.
# ---------------------------------------------------------------------------

func _test_frame() -> void:
	var rect := Rect2(10.0, -20.0, 60.0, 40.0)
	var thickness := 5.0
	var walls: Array = HullBuilder.frame(rect, thickness, 100.0)

	_assert(walls.size() == 4, "Item 1: frame() should return exactly 4 walls, got %d" % walls.size())

	# Pairwise non-overlap (intersects(_, false): exclude touching edges).
	for i in range(walls.size()):
		for j in range(i + 1, walls.size()):
			var ra: Rect2 = walls[i]["rect"]
			var rb: Rect2 = walls[j]["rect"]
			_assert(not ra.intersects(rb, false), "Item 1: wall %d overlaps wall %d (%s vs %s)" % [i, j, ra, rb])

	# Mutually connected: each wall touches (or overlaps) >= 1 other wall.
	for i in range(walls.size()):
		var touches_any := false
		for j in range(walls.size()):
			if i == j:
				continue
			var ra: Rect2 = walls[i]["rect"]
			var rb: Rect2 = walls[j]["rect"]
			if ra.intersects(rb, true):
				touches_any = true
				break
		_assert(touches_any, "Item 1: wall %d (%s) does not touch any other wall" % [i, walls[i]["rect"]])

	# Outer envelope equals the requested rect exactly.
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for w in walls:
		var r: Rect2 = w["rect"]
		min_x = min(min_x, r.position.x)
		min_y = min(min_y, r.position.y)
		max_x = max(max_x, r.position.x + r.size.x)
		max_y = max(max_y, r.position.y + r.size.y)
	var envelope := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	_assert(envelope.is_equal_approx(rect), "Item 1: frame() envelope %s should equal requested rect %s" % [envelope, rect])

	# Cavity probe points: center + 4 corners inset by thickness+eps -- none
	# should be covered by any wall.
	var eps := 0.1
	var inset: float = thickness + eps
	var probes := [
		rect.position + rect.size / 2.0, # center
		rect.position + Vector2(inset, inset),
		rect.position + Vector2(rect.size.x - inset, inset),
		rect.position + Vector2(inset, rect.size.y - inset),
		rect.position + Vector2(rect.size.x - inset, rect.size.y - inset),
	]
	for p in probes:
		var covered := false
		for w in walls:
			var r: Rect2 = w["rect"]
			if r.has_point(p):
				covered = true
				break
		_assert(not covered, "Item 1: cavity probe point %s should not be covered by any wall" % p)

# ---------------------------------------------------------------------------
# Item 2: mirror_y()/mirror_x() -- exact rect math on a known input; heading
# cases; id suffix swap both directions; involution (mirror twice reproduces
# the original exactly, headings within wrap-epsilon).
# ---------------------------------------------------------------------------

func _test_mirror_y_and_mirror_x() -> void:
	# --- mirror_y: exact rect math on a known input. ---
	var comp := {"id": "hull_port_wing", "type": "hull", "rect": Rect2(-15.0, -10.0, 25.0, 5.0), "heading": 0.0}
	var mirrored: Array = HullBuilder.mirror_y([comp])
	var m: Dictionary = mirrored[0]
	var expected_rect := Rect2(-15.0, 5.0, 25.0, 5.0) # (x, -y-h, w, h) = (-15, -(-10)-5, 25, 5)
	_assert(m["rect"].is_equal_approx(expected_rect), "Item 2: mirror_y rect math wrong, got %s expected %s" % [m["rect"], expected_rect])
	_assert(m["id"] == "hull_stbd_wing", "Item 2: mirror_y id suffix should swap port->stbd, got '%s'" % m["id"])

	# --- mirror_y: heading cases. ---
	var heading_cases := [
		[0.0, 0.0],
		[PI / 2.0, -PI / 2.0],
		[PI, PI],       # wrapped: -PI and PI are the same angle
		[PI / 4.0, -PI / 4.0],
	]
	for case in heading_cases:
		var input_h: float = case[0]
		var expected_h: float = case[1]
		var c := {"id": "x", "rect": Rect2(0, 0, 1, 1), "heading": input_h}
		var r: Array = HullBuilder.mirror_y([c])
		_assert(_angles_equal(r[0]["heading"], expected_h), "Item 2: mirror_y heading %s should wrap to %s, got %s" % [input_h, expected_h, r[0]["heading"]])

	# --- mirror_y: id suffix swap both directions. ---
	var stbd_comp := {"id": "hull_stbd_wing", "rect": Rect2(0, 0, 1, 1)}
	var back: Array = HullBuilder.mirror_y([stbd_comp])
	_assert(back[0]["id"] == "hull_port_wing", "Item 2: mirror_y id suffix should swap stbd->port, got '%s'" % back[0]["id"])

	# --- mirror_y: involution. ---
	var original := {"id": "hull_port_wing", "rect": Rect2(-15.0, -10.0, 25.0, 5.0), "heading": PI / 3.0}
	var once: Array = HullBuilder.mirror_y([original])
	var twice: Array = HullBuilder.mirror_y(once)
	_assert(twice[0]["rect"].is_equal_approx(original["rect"]), "Item 2: mirror_y(mirror_y(c)) rect should reproduce original, got %s expected %s" % [twice[0]["rect"], original["rect"]])
	_assert(_angles_equal(twice[0]["heading"], original["heading"]), "Item 2: mirror_y(mirror_y(c)) heading should reproduce original within wrap-epsilon, got %s expected %s" % [twice[0]["heading"], original["heading"]])
	_assert(twice[0]["id"] == original["id"], "Item 2: mirror_y(mirror_y(c)) id should reproduce original, got '%s' expected '%s'" % [twice[0]["id"], original["id"]])

	# --- mirror_x: same battery, PI-heading rule, fwd<->aft suffix. ---
	var comp_x := {"id": "hull_fwd_cap", "type": "hull", "rect": Rect2(60.0, -20.0, 10.0, 40.0), "heading": 0.0}
	var mirrored_x: Array = HullBuilder.mirror_x([comp_x])
	var mx: Dictionary = mirrored_x[0]
	var expected_rect_x := Rect2(-70.0, -20.0, 10.0, 40.0) # (-x-w, y, w, h) = (-60-10, -20, 10, 40)
	_assert(mx["rect"].is_equal_approx(expected_rect_x), "Item 2: mirror_x rect math wrong, got %s expected %s" % [mx["rect"], expected_rect_x])
	_assert(mx["id"] == "hull_aft_cap", "Item 2: mirror_x id suffix should swap fwd->aft, got '%s'" % mx["id"])

	var heading_cases_x := [
		[0.0, PI],       # PI - 0 = PI
		[PI / 2.0, PI / 2.0],  # PI - PI/2 = PI/2
		[PI, 0.0],       # PI - PI = 0 (wrapped)
		[PI / 4.0, 3.0 * PI / 4.0],
	]
	for case in heading_cases_x:
		var input_h: float = case[0]
		var expected_h: float = case[1]
		var c := {"id": "x", "rect": Rect2(0, 0, 1, 1), "heading": input_h}
		var r: Array = HullBuilder.mirror_x([c])
		_assert(_angles_equal(r[0]["heading"], expected_h), "Item 2: mirror_x heading %s should wrap to %s, got %s" % [input_h, expected_h, r[0]["heading"]])

	var aft_comp := {"id": "hull_aft_cap", "rect": Rect2(0, 0, 1, 1)}
	var back_x: Array = HullBuilder.mirror_x([aft_comp])
	_assert(back_x[0]["id"] == "hull_fwd_cap", "Item 2: mirror_x id suffix should swap aft->fwd, got '%s'" % back_x[0]["id"])

	var original_x := {"id": "hull_fwd_cap", "rect": Rect2(60.0, -20.0, 10.0, 40.0), "heading": PI / 5.0}
	var once_x: Array = HullBuilder.mirror_x([original_x])
	var twice_x: Array = HullBuilder.mirror_x(once_x)
	_assert(twice_x[0]["rect"].is_equal_approx(original_x["rect"]), "Item 2: mirror_x(mirror_x(c)) rect should reproduce original, got %s expected %s" % [twice_x[0]["rect"], original_x["rect"]])
	_assert(_angles_equal(twice_x[0]["heading"], original_x["heading"]), "Item 2: mirror_x(mirror_x(c)) heading should reproduce original within wrap-epsilon, got %s expected %s" % [twice_x[0]["heading"], original_x["heading"]])
	_assert(twice_x[0]["id"] == original_x["id"], "Item 2: mirror_x(mirror_x(c)) id should reproduce original, got '%s' expected '%s'" % [twice_x[0]["id"], original_x["id"]])

# ---------------------------------------------------------------------------
# Item 3: rotate_90() -- known rect at n=1 lands at hand-computed coords;
# n=4 is identity; directional heading advances n*PI/2; a TAU-arc omni
# sensor's arc_width is preserved (heading change is harmless for an
# all-around sensor).
# ---------------------------------------------------------------------------

func _test_rotate_90() -> void:
	# Known rect at n=1: rect (10, 5, 20, 8) -> corners (10,5),(30,5),(10,13),(30,13)
	# rotated 90 degrees CCW-by-our-convention ((x,y) -> (-y,x)):
	# (10,5)->(-5,10)  (30,5)->(-5,30)  (10,13)->(-13,10)  (30,13)->(-13,30)
	# AABB: x in [-13,-5], y in [10,30] -> Rect2(-13, 10, 8, 20)
	var comp := {"id": "r1", "rect": Rect2(10.0, 5.0, 20.0, 8.0), "heading": 0.0}
	var rotated: Array = HullBuilder.rotate_90([comp], 1)
	var expected_rect := Rect2(-13.0, 10.0, 8.0, 20.0)
	_assert(rotated[0]["rect"].is_equal_approx(expected_rect), "Item 3: rotate_90(n=1) rect wrong, got %s expected %s" % [rotated[0]["rect"], expected_rect])
	_assert(_angles_equal(rotated[0]["heading"], PI / 2.0), "Item 3: rotate_90(n=1) heading should advance by PI/2, got %s" % rotated[0]["heading"])

	# n=4 is identity (rects exact, headings wrap-equal).
	var comp2 := {"id": "r2", "rect": Rect2(10.0, 5.0, 20.0, 8.0), "heading": PI / 3.0}
	var rotated4: Array = HullBuilder.rotate_90([comp2], 4)
	_assert(rotated4[0]["rect"].is_equal_approx(comp2["rect"]), "Item 3: rotate_90(n=4) should be identity for rect, got %s expected %s" % [rotated4[0]["rect"], comp2["rect"]])
	_assert(_angles_equal(rotated4[0]["heading"], comp2["heading"]), "Item 3: rotate_90(n=4) should be identity for heading, got %s expected %s" % [rotated4[0]["heading"], comp2["heading"]])

	# Directional heading advances n*PI/2 (n=2,3 spot checks).
	for n in [2, 3]:
		var c := {"id": "r", "rect": Rect2(0, 0, 4, 4), "heading": 0.1}
		var r: Array = HullBuilder.rotate_90([c], n)
		var expected_h: float = wrapf(0.1 + n * (PI / 2.0), -PI, PI)
		_assert(_angles_equal(r[0]["heading"], expected_h), "Item 3: rotate_90(n=%d) heading should advance by n*PI/2, got %s expected %s" % [n, r[0]["heading"], expected_h])

	# TAU-arc omni sensor: heading change is harmless, arc_width preserved.
	var omni := {"id": "omni", "rect": Rect2(0, 0, 4, 4), "heading": 0.0, "arc_width": TAU}
	var rotated_omni: Array = HullBuilder.rotate_90([omni], 1)
	_assert(is_equal_approx(rotated_omni[0]["arc_width"], TAU), "Item 3: rotate_90 should preserve a TAU arc_width, got %s" % rotated_omni[0]["arc_width"])

# ---------------------------------------------------------------------------
# Item 4: armor_box() -- four segments enclose the inner rect on all sides
# (probe rays outward from inner-rect face centers cross a segment); none
# overlap the inner rect.
# ---------------------------------------------------------------------------

func _test_armor_box() -> void:
	var inner := Rect2(-5.0, -5.0, 10.0, 10.0)
	var thickness := 3.0
	var segments: Array = HullBuilder.armor_box(inner, thickness, 200.0)

	_assert(segments.size() == 4, "Item 4: armor_box() should return exactly 4 segments, got %d" % segments.size())

	# None overlap the inner rect.
	for s in segments:
		var r: Rect2 = s["rect"]
		_assert(not r.intersects(inner, false), "Item 4: armor_box segment %s overlaps inner rect %s" % [r, inner])

	# Probe rays outward from each face center must cross a segment.
	var face_centers := [
		inner.position + Vector2(inner.size.x / 2.0, 0.0),          # top face
		inner.position + Vector2(inner.size.x / 2.0, inner.size.y), # bottom face
		inner.position + Vector2(0.0, inner.size.y / 2.0),          # left face
		inner.position + Vector2(inner.size.x, inner.size.y / 2.0), # right face
	]
	var probe_dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for i in range(face_centers.size()):
		var probe_point: Vector2 = face_centers[i] + probe_dirs[i] * (thickness / 2.0)
		var crosses_segment := false
		for s in segments:
			var r: Rect2 = s["rect"]
			if r.has_point(probe_point):
				crosses_segment = true
				break
		_assert(crosses_segment, "Item 4: probe point %s (outward from face %d) should cross an armor_box segment" % [probe_point, i])

# ---------------------------------------------------------------------------
# Item 5: zipper() -- alternation matches the cells spec; expected count; no
# overlaps; chain connectivity end to end.
# ---------------------------------------------------------------------------

func _test_zipper() -> void:
	var weapon_a: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2.ZERO, {"id": "zip_laser_a"})
	var weapon_b: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2.ZERO, {"id": "zip_laser_b"})
	var cells: Array = [
		{"kind": "hull"},
		weapon_a,
		{"kind": "hull"},
		weapon_b,
		{"kind": "hull"},
	]
	var cell_w := 10.0
	var cell_h := 8.0
	var x0 := 0.0
	var x1 := x0 + cell_w * cells.size()
	var out: Array = HullBuilder.zipper(x0, x1, cell_w, cell_h, cells)

	_assert(out.size() == cells.size(), "Item 5: zipper() should produce one component per cell, got %d expected %d" % [out.size(), cells.size()])

	# Alternation matches the cells spec.
	for i in range(out.size()):
		var expect_hull: bool = cells[i] is Dictionary and cells[i].get("kind", "") == "hull"
		if expect_hull:
			_assert(out[i]["type"] == "hull", "Item 5: cell %d should be hull, got type '%s'" % [i, out[i]["type"]])
		else:
			_assert(out[i]["type"] == "weapons", "Item 5: cell %d should be the placed weapon, got type '%s'" % [i, out[i]["type"]])
			_assert(out[i]["id"] == cells[i]["id"], "Item 5: cell %d should preserve the pre-built weapon's id, got '%s' expected '%s'" % [i, out[i]["id"], cells[i]["id"]])
			_assert(is_equal_approx(out[i].get("damage", -1.0), cells[i]["damage"]), "Item 5: cell %d should preserve the pre-built weapon's stats verbatim" % i)

	# No overlaps.
	for i in range(out.size()):
		for j in range(i + 1, out.size()):
			var ra: Rect2 = out[i]["rect"]
			var rb: Rect2 = out[j]["rect"]
			_assert(not ra.intersects(rb, false), "Item 5: zipper cell %d overlaps cell %d" % [i, j])

	# Chain connectivity end to end (each cell touches its neighbor(s)).
	for i in range(out.size()):
		var touches_neighbor := false
		if i > 0 and out[i]["rect"].intersects(out[i - 1]["rect"], true):
			touches_neighbor = true
		if i < out.size() - 1 and out[i]["rect"].intersects(out[i + 1]["rect"], true):
			touches_neighbor = true
		_assert(touches_neighbor, "Item 5: zipper cell %d (%s) does not touch a chain neighbor" % [i, out[i]["rect"]])

# ---------------------------------------------------------------------------
# Item 6 (GATE): Re-expression proof. Rebuild LightAttackCraft's component
# set in-test from HullBuilder + M21 Parts, compare against a real
# LightAttackCraft.new() BEFORE _ready() normalization runs (Ship.new()
# without adding to the tree never calls _ready()).
# ---------------------------------------------------------------------------

func _build_lac_components() -> Array:
	# Hull shell: author the port-side pieces, mirror_y for the stbd side.
	# (See light_attack_craft.gd: port/stbd wing+fill+fwd pieces are exact
	# mirror_y images of each other -- verified by hand against the plan's
	# rect formula before writing this builder.)
	var port_wing: Dictionary = Parts.make("hull", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(-15.0, -10.0), {"id": "hull_port_wing", "size": Vector2(25.0, 5.0)})
	# fill_port/fwd_port are small shims (5x2.5 = 12.5 area) -- the catalog's
	# health_per_area formula lands them at 16.0, under the LIGHT hull band
	# floor of 80.0 (calibrated against HULL_REFERENCE_AREA, not these tiny
	# fill rects). Raw health override to match the fleet's authored flat
	# 80.0 -- grammar friction the design doc calls out (§3's "any other key
	# -- a raw field override, applied last"): small layout-driven fill
	# pieces need an explicit health override to land back in-band.
	var fill_port: Dictionary = Parts.make("hull", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(5.0, -5.0), {"id": "hull_fill_port", "size": Vector2(5.0, 2.5), "health": 80.0, "max_health": 80.0})
	var fwd_port: Dictionary = Parts.make("hull", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(10.0, -10.0), {"id": "hull_fwd_port", "size": Vector2(5.0, 2.5), "health": 80.0, "max_health": 80.0})

	var hull_port_side: Array = [port_wing, fill_port, fwd_port]
	var hull_stbd_side: Array = HullBuilder.mirror_y(hull_port_side)

	var reactor: Dictionary = Parts.make("reactor", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(-5.0, -5.0), {"id": "reactor_core"})
	var engine: Dictionary = Parts.make("engine", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(-15.0, -5.0), {"id": "engine_main"})
	var comms: Dictionary = Parts.make("comms", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(5.0, -2.5), {"id": "comms_array"})

	# Sensor: closest catalog kind is "dir_search" (forward-facing active
	# search/fire-control), but the LAC's authored arc/bins/range don't match
	# ANY of the 5 canned kinds exactly (PI/1.5 arc vs dir_search's PI/6, 60
	# bins vs 30, range 25000 vs the kind's formula) -- raw opts overrides
	# are the grammar-friction signal the design doc predicted (§3: "any
	# other key -- a raw field override, applied last").
	var sensor: Dictionary = Parts.make("sensor", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(10.0, -2.5), {
		"id": "omni_fwd_fc",
		"sensor_kind": "dir_search",
		"heading": 0.0,
		"arc_width": PI / 1.5,
		"num_bins": 60,
		"refresh_interval": 0.5,
		"range": 25000.0,
	})

	var laser: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(10.0, -7.5), {"id": "hp_fwd_laser", "heading": 0.0})
	var missile: Dictionary = Parts.make("missile", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(10.0, 2.5), {"id": "hp_fwd_missile", "heading": 0.0})

	var out: Array = []
	out.append_array(hull_port_side)
	out.append_array(hull_stbd_side)
	out.append(reactor)
	out.append(engine)
	out.append(comms)
	out.append(sensor)
	out.append(laser)
	out.append(missile)
	return out

func _type_rect_multiset(components: Array) -> Array:
	# Returns a sorted array of "type|x,y,w,h" strings -- a comparable
	# multiset representation (order-independent, duplicate-preserving).
	var entries: Array = []
	for c in components:
		var r: Rect2 = c["rect"]
		entries.append("%s|%s,%s,%s,%s" % [c["type"], r.position.x, r.position.y, r.size.x, r.size.y])
	entries.sort()
	return entries

func _violation_multiset(violations: Array) -> Array:
	var entries: Array = []
	for v in violations:
		entries.append("%s|%s|%s" % [v["component_id"], v["field"], v["severity"]])
	entries.sort()
	return entries

func _union_aabb(components: Array) -> Rect2:
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for c in components:
		var r: Rect2 = c["rect"]
		min_x = min(min_x, r.position.x)
		min_y = min(min_y, r.position.y)
		max_x = max(max_x, r.position.x + r.size.x)
		max_y = max(max_y, r.position.y + r.size.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _ship_mass(components: Array) -> float:
	var total := 0.0
	for c in components:
		var r: Rect2 = c["rect"]
		var area: float = r.size.x * r.size.y
		total += area * float(c["density"]) * Ship.MASS_SCALE
	return total

func _test_lac_re_expression() -> void:
	# Real LAC: Ship.new()-style instantiation never calls _ready() unless
	# added to the scene tree, so ship_components here is exactly the
	# _init()-authored array, untouched by normalization.
	var real_lac := LightAttackCraft.new()
	var real_components: Array = real_lac.ship_components.duplicate(true)

	var built_components: Array = _build_lac_components()

	# (a) component count equal.
	_assert(built_components.size() == real_components.size(), "Item 6: component count mismatch, built=%d real=%d" % [built_components.size(), real_components.size()])

	# (b) multiset of (type, rect) pairs exactly equal.
	var built_multiset: Array = _type_rect_multiset(built_components)
	var real_multiset: Array = _type_rect_multiset(real_components)
	_assert(built_multiset == real_multiset, "Item 6: (type,rect) multiset mismatch.\n  built=%s\n  real=%s" % [str(built_multiset), str(real_multiset)])

	# (c) ShipDesignValidator.validate verdicts equal (ok flag AND violation
	# multiset). Validate via throwaway Ship-derived holders so ship_tier /
	# max_speed / max_omega match the real LAC's handling stats.
	var built_ship := Ship.new()
	built_ship.ship_tier = real_lac.ship_tier
	built_ship.max_speed = real_lac.max_speed
	built_ship.max_omega = real_lac.max_omega
	built_ship.ship_components = built_components

	var real_result: Dictionary = ShipDesignValidator.validate(real_lac)
	var built_result: Dictionary = ShipDesignValidator.validate(built_ship)

	if real_result["ok"] != built_result["ok"] or _violation_multiset(real_result["violations"]) != _violation_multiset(built_result["violations"]):
		print("Item 6: validator verdict mismatch.")
		print("  real ok=", real_result["ok"], " violations=", real_result["violations"])
		print("  built ok=", built_result["ok"], " violations=", built_result["violations"])
	_assert(real_result["ok"] == built_result["ok"], "Item 6: validator ok flag mismatch, real=%s built=%s" % [real_result["ok"], built_result["ok"]])
	_assert(_violation_multiset(real_result["violations"]) == _violation_multiset(built_result["violations"]), "Item 6: validator violation multiset mismatch")

	# (d) derived mass within 1e-4.
	var real_mass: float = _ship_mass(real_components)
	var built_mass: float = _ship_mass(built_components)
	_assert(abs(real_mass - built_mass) < 1e-4, "Item 6: mass mismatch, real=%s built=%s" % [real_mass, built_mass])

	# (e) component-union AABB identical.
	var real_aabb: Rect2 = _union_aabb(real_components)
	var built_aabb: Rect2 = _union_aabb(built_components)
	_assert(real_aabb.is_equal_approx(built_aabb), "Item 6: AABB mismatch, real=%s built=%s" % [real_aabb, built_aabb])

# ---------------------------------------------------------------------------
# Item 7 (GATE): Station-shell proof. Reproduce small_station.gd's 4 hull
# caps + 8 flanks from ONE authored arm shell per axis (fwd @ length 40,
# port @ length 100 -- the two arm lengths that actually occur in the real
# station; see the plan's "reality note": arms are mirror-symmetric, not
# rotation-symmetric) via mirror_x/mirror_y composition. Multiset (type,
# rect) equality against the hand-authored values.
# ---------------------------------------------------------------------------

func _build_station_shell() -> Array:
	# Forward arm shell (dir=+X, offset=30, length=30, core width=40) mirrored
	# across X to produce the aft arm shell.
	var fwd_shell: Array = HullBuilder.arm(Vector2(1, 0), 30.0, 30.0, 40.0, 4000.0, {"id_prefix": "hull_fwd"})
	var aft_shell: Array = HullBuilder.mirror_x(fwd_shell)

	# Port arm shell (dir=-Y, offset=30, length=90, core width=40) mirrored
	# across Y to produce the stbd arm shell.
	var port_shell: Array = HullBuilder.arm(Vector2(0, -1), 30.0, 90.0, 40.0, 4000.0, {"id_prefix": "hull_port"})
	var stbd_shell: Array = HullBuilder.mirror_y(port_shell)

	var out: Array = []
	out.append_array(fwd_shell)
	out.append_array(aft_shell)
	out.append_array(port_shell)
	out.append_array(stbd_shell)
	return out

func _test_station_shell_re_expression() -> void:
	var real_station := SmallStation.new()
	var real_hull: Array = []
	for c in real_station.ship_components:
		if c.get("type", "") == "hull":
			real_hull.append(c)

	# The real station has 4 caps + 8 flanks = 12 hull pieces (comms_1's rect
	# is type "comms", not hull -- excluded above).
	_assert(real_hull.size() == 12, "Item 7: sanity check -- expected 12 hull pieces (4 caps + 8 flanks) on SmallStation, got %d" % real_hull.size())

	var built_shell: Array = _build_station_shell()
	_assert(built_shell.size() == real_hull.size(), "Item 7: built shell piece count %d should equal real station hull piece count %d" % [built_shell.size(), real_hull.size()])

	var built_multiset: Array = _type_rect_multiset(built_shell)
	var real_multiset: Array = _type_rect_multiset(real_hull)
	if built_multiset != real_multiset:
		print("Item 7: multiset mismatch.")
		print("  built=", built_multiset)
		print("  real=", real_multiset)
	_assert(built_multiset == real_multiset, "Item 7: (type,rect) multiset of built station shell should equal SmallStation's hand-authored hull caps+flanks")

# ---------------------------------------------------------------------------
# Item 8: Determinism. Two identical builder calls yield identical arrays
# (no RNG, no shared mutable state) -- checked across every builder.
# ---------------------------------------------------------------------------

func _components_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var ca: Dictionary = a[i]
		var cb: Dictionary = b[i]
		if ca.keys().size() != cb.keys().size():
			return false
		for k in ca.keys():
			if not cb.has(k):
				return false
			if ca[k] is Rect2:
				if not ca[k].is_equal_approx(cb[k]):
					return false
			elif ca[k] is float:
				if not is_equal_approx(ca[k], cb[k]) and ca[k] != cb[k]:
					return false
			else:
				if ca[k] != cb[k]:
					return false
	return true

func _test_determinism() -> void:
	var rect := Rect2(0.0, 0.0, 40.0, 20.0)

	var frame_a: Array = HullBuilder.frame(rect, 4.0, 100.0)
	var frame_b: Array = HullBuilder.frame(rect, 4.0, 100.0)
	_assert(_components_equal(frame_a, frame_b), "Item 8: frame() is not deterministic across two identical calls")

	var taper_a: Array = HullBuilder.taper(0.0, 20.0, [10.0, 6.0, 4.0])
	var taper_b: Array = HullBuilder.taper(0.0, 20.0, [10.0, 6.0, 4.0])
	_assert(_components_equal(taper_a, taper_b), "Item 8: taper() is not deterministic across two identical calls")

	var arm_a: Array = HullBuilder.arm(Vector2(1, 0), 30.0, 30.0, 40.0, 4000.0, {"id_prefix": "hull_fwd"})
	var arm_b: Array = HullBuilder.arm(Vector2(1, 0), 30.0, 30.0, 40.0, 4000.0, {"id_prefix": "hull_fwd"})
	_assert(_components_equal(arm_a, arm_b), "Item 8: arm() is not deterministic across two identical calls")

	var armor_a: Array = HullBuilder.armor_box(Rect2(-5, -5, 10, 10), 3.0, 200.0)
	var armor_b: Array = HullBuilder.armor_box(Rect2(-5, -5, 10, 10), 3.0, 200.0)
	_assert(_components_equal(armor_a, armor_b), "Item 8: armor_box() is not deterministic across two identical calls")

	var w1: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2.ZERO, {"id": "det_laser"})
	var cells: Array = [{"kind": "hull"}, w1.duplicate(true), {"kind": "hull"}]
	var zipper_a: Array = HullBuilder.zipper(0.0, 30.0, 10.0, 8.0, cells)
	var zipper_b: Array = HullBuilder.zipper(0.0, 30.0, 10.0, 8.0, cells)
	_assert(_components_equal(zipper_a, zipper_b), "Item 8: zipper() is not deterministic across two identical calls")

	var mirror_comps: Array = [{"id": "hull_port_x", "type": "hull", "rect": Rect2(1, 2, 3, 4), "heading": 0.5}]
	var mirror_y_a: Array = HullBuilder.mirror_y(mirror_comps)
	var mirror_y_b: Array = HullBuilder.mirror_y(mirror_comps)
	_assert(_components_equal(mirror_y_a, mirror_y_b), "Item 8: mirror_y() is not deterministic across two identical calls")

	var mirror_x_a: Array = HullBuilder.mirror_x(mirror_comps)
	var mirror_x_b: Array = HullBuilder.mirror_x(mirror_comps)
	_assert(_components_equal(mirror_x_a, mirror_x_b), "Item 8: mirror_x() is not deterministic across two identical calls")

	var rotate_comps: Array = [{"id": "r", "rect": Rect2(1, 2, 3, 4), "heading": 0.2}]
	var rotate_a: Array = HullBuilder.rotate_90(rotate_comps, 1)
	var rotate_b: Array = HullBuilder.rotate_90(rotate_comps, 1)
	_assert(_components_equal(rotate_a, rotate_b), "Item 8: rotate_90() is not deterministic across two identical calls")
