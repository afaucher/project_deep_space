extends Node

# M23 acceptance -- mechanized layout checks (hull coverage + active surfaces).
# See implementation_plans/m23_layout_coverage_checks_design.md for the fixture
# battery this file implements (items 1-8; items 9-10 are the fleet-audit
# ratchet in test_ship_designs.gd). Validation is synchronous/pure -- both new
# checks operate on a components array alone, no Ship instance or physics
# needed -- so setup() does everything and quits immediately, same pattern as
# test_ship_designs.gd. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_layout_checks

const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main: Node) -> void:
	print("Starting Layout Checks (M23) Tests")

	_test_enclosed_weapon_clean()
	_test_exposed_flank_exact_one()
	_test_masked_active_face()
	_test_engine_protrusion_semantics()
	_test_omni_sensor()
	_test_directional_sensor()
	_test_severity_contract()
	_test_negative_control()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_layout_checks <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_layout_checks <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# Shared fixture helpers -- minimal component dicts. Only the fields the two
# layout checks (and, for a couple of cases, full validate()) look at are
# populated; unused type-specific fields are omitted where harmless.
# ---------------------------------------------------------------------------

func _hull(id: String, rect: Rect2) -> Dictionary:
	return {"id": id, "type": "hull", "rect": rect, "health": 100.0, "max_health": 100.0, "density": 20.0}

func _weapon(id: String, rect: Rect2, heading: float, arc_width: float = PI / 3.0) -> Dictionary:
	# Lasers are reactor-powered, not ammo-fed -- no "ammo" field authored (see
	# ship.gd's normalization / weapon_behavior.gd).
	return {"id": id, "type": "weapons", "rect": rect, "health": 100.0, "max_health": 100.0, "density": 20.0,
		"weapon_type": "laser", "cooldown_max": 1.0, "range": 4000.0, "damage": 250.0,
		"heading": heading, "arc_width": arc_width}

func _sensor(id: String, rect: Rect2, heading: float, arc_width: float) -> Dictionary:
	return {"id": id, "type": "sensors", "rect": rect, "health": 50.0, "max_health": 50.0, "density": 20.0,
		"sensor_type": "active", "active": true, "range": 20000.0, "arc_width": arc_width,
		"num_bins": 36, "refresh_interval": 1.0, "heading": heading}

func _engine(id: String, rect: Rect2) -> Dictionary:
	return {"id": id, "type": "engines", "rect": rect, "health": 100.0, "max_health": 100.0, "density": 20.0,
		"power_rating": 50.0, "thrust_rating": 3000.0, "torque_rating": 6000.0}

# Runs both new checks directly on a components array (no Ship instance, per
# the plan: "static, operating on the components array only").
func _layout_violations(components: Array) -> Array:
	var violations: Array = []
	ShipDesignValidator._check_hull_coverage(components, violations)
	ShipDesignValidator._check_active_surface(components, violations)
	return violations

func _print_violations(label: String, violations: Array) -> void:
	print(label, ":")
	for v in violations:
		print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"], " severity=", v["severity"])

# ---------------------------------------------------------------------------
# Item 1: Enclosed weapon -- hull on three faces, active face at the AABB
# edge -> zero warnings.
# ---------------------------------------------------------------------------

func _test_enclosed_weapon_clean() -> void:
	var weapon := _weapon("hp_test", Rect2(0, -5, 10, 10), 0.0)
	var components: Array = [
		weapon,
		_hull("hull_aft", Rect2(-10, -5, 10, 10)),   # covers -X
		_hull("hull_port", Rect2(0, -15, 10, 10)),   # covers -Y
		_hull("hull_stbd", Rect2(0, 5, 10, 10)),     # covers +Y
		# +X (active face) reaches the AABB edge at x=10 with nothing beyond.
	]
	var violations: Array = _layout_violations(components)
	_print_violations("Item 1 (enclosed weapon)", violations)
	_assert(violations.is_empty(), "Item 1: enclosed weapon with active face at AABB edge should have zero layout warnings, got %d" % violations.size())

# ---------------------------------------------------------------------------
# Item 2: Exposed flank -- same as Item 1 but one flanking hull removed ->
# exactly ONE coverage warning, naming the component AND the face direction.
# ---------------------------------------------------------------------------

func _test_exposed_flank_exact_one() -> void:
	var weapon := _weapon("hp_test", Rect2(0, -5, 10, 10), 0.0)
	var components: Array = [
		weapon,
		_hull("hull_aft", Rect2(-10, -5, 10, 10)),   # covers -X
		_hull("hull_port", Rect2(0, -15, 10, 10)),   # covers -Y
		# hull_stbd removed -- +Y is now exposed (flanking hull gone).
	]
	var violations: Array = _layout_violations(components)
	_print_violations("Item 2 (exposed flank)", violations)
	_assert(violations.size() == 1, "Item 2: exposed flank should yield exactly ONE warning, got %d" % violations.size())
	if violations.size() == 1:
		var v: Dictionary = violations[0]
		_assert(v["component_id"] == "hp_test", "Item 2: warning should name component 'hp_test', got '%s'" % v["component_id"])
		_assert(v["field"] == "hull_coverage", "Item 2: warning should be a hull_coverage warning, got field '%s'" % v["field"])
		_assert(v["reason"].find("+Y") != -1, "Item 2: warning reason should name the exposed face direction (+Y), got '%s'" % v["reason"])
		_assert(v["severity"] == "warning", "Item 2: severity should be 'warning', got '%s'" % v["severity"])

# ---------------------------------------------------------------------------
# Item 3: Masked active face -- hull rect directly in front of a laser's
# heading -> exactly one active-surface warning.
# ---------------------------------------------------------------------------

func _test_masked_active_face() -> void:
	var weapon := _weapon("hp_test", Rect2(0, -5, 10, 10), 0.0)
	var components: Array = [
		weapon,
		_hull("hull_aft", Rect2(-10, -5, 10, 10)),    # covers -X
		_hull("hull_port", Rect2(0, -15, 10, 10)),    # covers -Y
		_hull("hull_stbd", Rect2(0, 5, 10, 10)),      # covers +Y
		_hull("hull_front", Rect2(10, -5, 10, 10)),   # blocks +X (the active face)
	]
	var violations: Array = _layout_violations(components)
	_print_violations("Item 3 (masked active face)", violations)
	_assert(violations.size() == 1, "Item 3: masked active face should yield exactly ONE warning, got %d" % violations.size())
	if violations.size() == 1:
		var v: Dictionary = violations[0]
		_assert(v["component_id"] == "hp_test", "Item 3: warning should name component 'hp_test', got '%s'" % v["component_id"])
		_assert(v["field"] == "active_surface", "Item 3: warning should be an active_surface warning, got field '%s'" % v["field"])
		_assert(v["reason"].find("+X") != -1, "Item 3: warning reason should name the masked face direction (+X), got '%s'" % v["reason"])

# ---------------------------------------------------------------------------
# Item 4: Engine semantics -- engine protruding aft past hull: NO coverage
# warning for the aft face (it's the active face, always -X for engines
# regardless of heading); a rect placed behind the engine -> masked warning.
# ---------------------------------------------------------------------------

func _test_engine_protrusion_semantics() -> void:
	# 4a: clean protrusion -- engine's -X (aft) face sticks past the hull into
	# open space. This must NOT be flagged by hull-coverage (aft is the active
	# face, exempt from coverage) and must NOT be flagged as masked (nothing
	# blocks it before the AABB edge).
	var engine := _engine("engine_main", Rect2(-20, -5, 10, 10))
	var clean_components: Array = [
		engine,
		_hull("hull_inboard", Rect2(-10, -15, 10, 30)),  # covers +X
		_hull("hull_top", Rect2(-20, 5, 10, 10)),        # covers +Y
		_hull("hull_bottom", Rect2(-20, -15, 10, 10)),   # covers -Y
		# -X (aft/active) protrudes past all hull into open space.
	]
	var clean_violations: Array = _layout_violations(clean_components)
	_print_violations("Item 4a (engine clean protrusion)", clean_violations)
	_assert(clean_violations.is_empty(), "Item 4a: engine's aft protrusion should be exempt (active face), got %d warning(s)" % clean_violations.size())

	# 4b: same layout, but a rect placed directly behind (further aft of) the
	# engine -> the aft/active face is now masked.
	var blocked_components: Array = clean_components.duplicate(true)
	blocked_components.append(_hull("hull_block", Rect2(-30, -5, 10, 10)))
	var blocked_violations: Array = _layout_violations(blocked_components)
	_print_violations("Item 4b (engine blocked-behind)", blocked_violations)
	_assert(blocked_violations.size() == 1, "Item 4b: rect placed behind engine should yield exactly ONE masked-active-face warning, got %d" % blocked_violations.size())
	if blocked_violations.size() == 1:
		var v: Dictionary = blocked_violations[0]
		_assert(v["component_id"] == "engine_main", "Item 4b: warning should name 'engine_main', got '%s'" % v["component_id"])
		_assert(v["field"] == "active_surface", "Item 4b: warning should be an active_surface warning, got field '%s'" % v["field"])
		_assert(v["reason"].find("-X") != -1, "Item 4b: warning reason should name the masked face direction (-X), got '%s'" % v["reason"])

# ---------------------------------------------------------------------------
# Item 5: Omni sensor -- fully enclosed omni -> zero warnings (enclosure is
# good, no masking concept applies); omni with an exposed face -> coverage
# warning.
# ---------------------------------------------------------------------------

func _test_omni_sensor() -> void:
	var omni := _sensor("omni_test", Rect2(0, 0, 10, 10), 0.0, TAU)
	var enclosed_components: Array = [
		omni,
		_hull("hull_e", Rect2(10, 0, 10, 10)),  # covers +X
		_hull("hull_w", Rect2(-10, 0, 10, 10)), # covers -X
		_hull("hull_n", Rect2(0, 10, 10, 10)),  # covers +Y
		_hull("hull_s", Rect2(0, -10, 10, 10)), # covers -Y
	]
	var enclosed_violations: Array = _layout_violations(enclosed_components)
	_print_violations("Item 5a (omni enclosed)", enclosed_violations)
	_assert(enclosed_violations.is_empty(), "Item 5a: fully enclosed omni sensor should have zero warnings, got %d" % enclosed_violations.size())

	# 5b: remove hull_n -- +Y now exposed on the omni (all four faces are
	# coverage-checked for omni, since it has no active face).
	var exposed_components: Array = [
		omni,
		_hull("hull_e", Rect2(10, 0, 10, 10)),
		_hull("hull_w", Rect2(-10, 0, 10, 10)),
		_hull("hull_s", Rect2(0, -10, 10, 10)),
	]
	var exposed_violations: Array = _layout_violations(exposed_components)
	_print_violations("Item 5b (omni exposed)", exposed_violations)
	_assert(exposed_violations.size() == 1, "Item 5b: omni with one exposed face should yield exactly ONE warning, got %d" % exposed_violations.size())
	if exposed_violations.size() == 1:
		var v: Dictionary = exposed_violations[0]
		_assert(v["component_id"] == "omni_test", "Item 5b: warning should name 'omni_test', got '%s'" % v["component_id"])
		_assert(v["field"] == "hull_coverage", "Item 5b: warning should be a hull_coverage warning, got field '%s'" % v["field"])
		_assert(v["reason"].find("+Y") != -1, "Item 5b: warning reason should name the exposed face (+Y), got '%s'" % v["reason"])

# ---------------------------------------------------------------------------
# Item 6: Directional sensor -- flush with the hull edge (active face at AABB
# boundary) -> no warning; buried one rect deep -> masked warning.
# ---------------------------------------------------------------------------

func _test_directional_sensor() -> void:
	var sensor := _sensor("dir_test", Rect2(0, -5, 10, 10), 0.0, PI / 6.0)
	var flush_components: Array = [
		sensor,
		_hull("hull_aft", Rect2(-10, -5, 10, 10)),   # covers -X
		_hull("hull_port", Rect2(0, -15, 10, 10)),   # covers -Y
		_hull("hull_stbd", Rect2(0, 5, 10, 10)),     # covers +Y
		# +X (active, sensor's heading) flush with the AABB edge.
	]
	var flush_violations: Array = _layout_violations(flush_components)
	_print_violations("Item 6a (directional sensor flush)", flush_violations)
	_assert(flush_violations.is_empty(), "Item 6a: directional sensor flush with hull edge should have zero warnings, got %d" % flush_violations.size())

	# 6b: buried one rect deep -- a hull rect placed in front of the sensor's
	# active face.
	var buried_components: Array = flush_components.duplicate(true)
	buried_components.append(_hull("hull_front", Rect2(10, -5, 10, 10)))
	var buried_violations: Array = _layout_violations(buried_components)
	_print_violations("Item 6b (directional sensor buried)", buried_violations)
	_assert(buried_violations.size() == 1, "Item 6b: buried directional sensor should yield exactly ONE masked-active-face warning, got %d" % buried_violations.size())
	if buried_violations.size() == 1:
		var v: Dictionary = buried_violations[0]
		_assert(v["component_id"] == "dir_test", "Item 6b: warning should name 'dir_test', got '%s'" % v["component_id"])
		_assert(v["field"] == "active_surface", "Item 6b: warning should be an active_surface warning, got field '%s'" % v["field"])

# ---------------------------------------------------------------------------
# Item 7: Severity contract -- a fixture with both warning types still
# returns ok == true, and every new violation dict carries
# severity == "warning" and the standard keys (component_id/field/reason).
# Runs the FULL validate() (not just the two static checks) on a structurally
# complete ship so the proof covers the real wiring in validate().
# ---------------------------------------------------------------------------

func _test_severity_contract() -> void:
	var ship := Ship.new()
	ship.ship_tier = ComponentSpec.Tier.LIGHT
	ship.max_speed = 2000.0
	ship.max_omega = 4.0

	# Exposed weapon (missing one flank) + masked sensor (buried), on an
	# otherwise structurally-complete, non-overlapping, connected LIGHT ship.
	var weapon := _weapon("hp_exposed", Rect2(20, -5, 10, 10), 0.0)
	var sensor := _sensor("dir_masked", Rect2(-20, -5, 10, 10), PI, PI / 6.0) # heading -X, will be buried
	var reactor := {"id": "reactor_core", "type": "reactor", "rect": Rect2(0, -5, 10, 10), "health": 60.0, "max_health": 60.0, "density": 20.0, "power_rating": 60.0}
	var engine := _engine("engine_main", Rect2(-40, -5, 10, 10))

	var components: Array = [
		weapon,
		sensor,
		reactor,
		engine,
		# Weapon: covered on -X/+Y/-Y, +Y flank deliberately omitted below to
		# force an exposed-face warning; -X and -Y covered by hull.
		_hull("hull_weapon_aft", Rect2(10, -5, 10, 10)),   # covers weapon's -X (touches reactor too but that's fine, adjacency only)
		_hull("hull_weapon_south", Rect2(20, -15, 10, 10)), # covers weapon's -Y
		# (weapon's +Y left open on purpose -> exposed-face warning)

		# Sensor: heading PI means active face is -X; bury it with a rect in front.
		_hull("hull_sensor_block", Rect2(-30, -5, 10, 10)), # blocks sensor's -X (active) face
		_hull("hull_sensor_north", Rect2(-20, 5, 10, 10)),  # covers sensor's +Y
		_hull("hull_sensor_south", Rect2(-20, -15, 10, 10)), # covers sensor's -Y
		_hull("hull_sensor_east", Rect2(-10, -5, 10, 10)),  # covers sensor's +X, also bridges to reactor/engine run

		# Engine: aft (-X) protrudes past everything -- fine, exempt. Cover its
		# +X/+Y/-Y so it isn't ALSO flagged for coverage (keeps this fixture's
		# violation set limited to the two we're asserting on, though the
		# assertions below only check "at least one of each type", not counts).
		_hull("hull_engine_north", Rect2(-40, 5, 10, 10)),
		_hull("hull_engine_south", Rect2(-40, -15, 10, 10)),
	]
	ship.ship_components = components

	var r: Dictionary = ShipDesignValidator.validate(ship)
	_print_violations("Item 7 (severity contract) all violations", r["violations"])

	_assert(r["ok"] == true, "Item 7: ship with only layout warnings (plus otherwise-legal structure) should validate ok == true, got false")

	var coverage_warnings: Array = r["violations"].filter(func(v): return v["field"] == "hull_coverage")
	var active_warnings: Array = r["violations"].filter(func(v): return v["field"] == "active_surface")
	_assert(not coverage_warnings.is_empty(), "Item 7: expected at least one hull_coverage warning")
	_assert(not active_warnings.is_empty(), "Item 7: expected at least one active_surface warning")

	for v in coverage_warnings + active_warnings:
		_assert(v["severity"] == "warning", "Item 7: layout violation severity must be 'warning', got '%s' for %s" % [v["severity"], v])
		_assert(v.has("component_id"), "Item 7: violation missing 'component_id' key: %s" % v)
		_assert(v.has("field"), "Item 7: violation missing 'field' key: %s" % v)
		_assert(v.has("reason"), "Item 7: violation missing 'reason' key: %s" % v)

# ---------------------------------------------------------------------------
# Item 8: Negative control -- a deliberately terrible fixture (all guns
# hanging in space) must produce >= N warnings; guards against both checks
# silently no-opping.
# ---------------------------------------------------------------------------

const NEGATIVE_CONTROL_MIN_WARNINGS := 6

func _test_negative_control() -> void:
	# Four weapons scattered with big gaps between them and no hull anywhere --
	# every face of every weapon is either exposed (coverage) or, for the
	# active face, unmasked-but-still-exposed (active-surface only warns when
	# something BLOCKS the active face, so a fully floating weapon in fact
	# gets 3 coverage warnings + 0 active-surface warnings -- still comfortably
	# over the threshold across four weapons + a floating sensor).
	var components: Array = [
		_weapon("hp_1", Rect2(0, 0, 10, 10), 0.0),
		_weapon("hp_2", Rect2(100, 100, 10, 10), PI),
		_weapon("hp_3", Rect2(-100, -100, 10, 10), PI / 2.0),
		_weapon("hp_4", Rect2(200, -200, 10, 10), -PI / 2.0),
		_sensor("sn_1", Rect2(300, 300, 10, 10), 0.0, PI / 6.0),
	]
	var violations: Array = _layout_violations(components)
	_print_violations("Item 8 (negative control)", violations)
	_assert(violations.size() >= NEGATIVE_CONTROL_MIN_WARNINGS, "Item 8: negative-control fixture (all guns hanging in space) should yield >= %d warnings, got %d" % [NEGATIVE_CONTROL_MIN_WARNINGS, violations.size()])
