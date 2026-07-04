extends Node

# M21 acceptance -- parts catalog. Proves Parts.make() builds every family x
# tier x mark combination in-band (via the SHARED ShipDesignValidator helper,
# not a private re-check), schema-complete, monotonic mark-over-mark, with
# correct placement/identity, that the shared band-check helper itself is not
# vacuous (negative control), that a minimal catalog-built ship validates and
# runs headlessly, and that STANDARD marks reproduce the fleet's own authored
# numbers (LAC laser, frigate engine). Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_parts_catalog
# Needs a few physics frames for item 7, so it drives that phase in
# _physics_process like test_docking.gd/test_patrol.gd. Pass marker per
# CLAUDE.md.

const Parts = preload("res://scripts/components/parts_catalog.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const Frigate = preload("res://scripts/ships/frigate.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

# Phase-7 (integration smoke) state.
var smoke_ship = null
var smoke_frames: int = 0
const SMOKE_FRAMES_REQUIRED := 60
var smoke_heat_before: float = 0.0
var smoke_timer_before: float = 0.0
var smoke_started: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Parts Catalog (M21) Tests")

	_test_enumeration_completeness()
	_test_band_conformance()
	_test_schema_completeness()
	_test_monotonic_marks()
	_test_placement_and_identity()
	_test_negative_control()
	_test_standard_reproduces_fleet()

	# Item 7 (integration smoke) needs physics frames -- kick it off here,
	# _physics_process drives it to completion and finalizes the test.
	_start_integration_smoke()

# ---------------------------------------------------------------------------
# Item 1: Enumeration completeness.
# ---------------------------------------------------------------------------

const EXPECTED_FAMILIES := ["laser", "missile", "engine", "rcs", "reactor", "sensor", "comms", "hull"]
const ALL_TIERS := [ComponentSpec.Tier.DRONE, ComponentSpec.Tier.LIGHT, ComponentSpec.Tier.MEDIUM, ComponentSpec.Tier.HEAVY, ComponentSpec.Tier.STRUCTURE]
const ALL_MARKS := [Parts.Mark.COMPACT, Parts.Mark.STANDARD, Parts.Mark.HEAVY]
const SENSOR_KINDS := ["omni_search", "omni_pd", "dir_search", "passive_em", "collision"]

func _test_enumeration_completeness() -> void:
	var families: Array = Parts.families()
	for f in EXPECTED_FAMILIES:
		_assert(families.has(f), "Item 1: Parts.families() missing expected family '%s'" % f)
	_assert(families.size() == EXPECTED_FAMILIES.size(), "Item 1: Parts.families() has unexpected extra/missing entries: %s" % str(families))

	# "engine" must have an explicit, non-crashing absence at STRUCTURE tier
	# (structures have no engines -- ship_design_validator.gd rule 6).
	var engine_tiers: Array = Parts.supported_tiers("engine")
	_assert(not engine_tiers.has(ComponentSpec.Tier.STRUCTURE), "Item 1: 'engine' family must NOT list STRUCTURE as a supported tier (structures have no engines)")

	for family in families:
		var tiers: Array = Parts.supported_tiers(family)
		_assert(not tiers.is_empty(), "Item 1: family '%s' has zero supported tiers" % family)
		for tier in tiers:
			for mark in ALL_MARKS:
				var opts := {}
				if family == "hull":
					opts["size"] = Vector2(10, 10)
				if family == "sensor":
					for kind in SENSOR_KINDS:
						var sk_opts := opts.duplicate()
						sk_opts["sensor_kind"] = kind
						var comp: Dictionary = Parts.make(family, tier, mark, Vector2.ZERO, sk_opts)
						_assert(not comp.is_empty(), "Item 1: %s/%s/%s tier=%d mark=%d failed to construct" % [family, kind, "", tier, mark])
				else:
					var comp: Dictionary = Parts.make(family, tier, mark, Vector2.ZERO, opts)
					_assert(not comp.is_empty(), "Item 1: %s tier=%d mark=%d failed to construct" % [family, tier, mark])

# ---------------------------------------------------------------------------
# Helper: build one instance of every family x tier x mark (x sensor kind),
# reused by items 2-5.
# ---------------------------------------------------------------------------

func _hull_reference_size(tier: int) -> Vector2:
	# Square rect whose area equals Parts.HULL_REFERENCE_AREA[tier] -- the
	# area the catalog's hull health_per_area marks were calibrated against.
	var area: float = Parts.HULL_REFERENCE_AREA.get(tier, 100.0)
	var side: float = sqrt(area)
	return Vector2(side, side)

func _all_parts() -> Array:
	var parts: Array = []
	for family in Parts.families():
		for tier in Parts.supported_tiers(family):
			for mark in ALL_MARKS:
				if family == "hull":
					var comp: Dictionary = Parts.make(family, tier, mark, Vector2(100, 100), {"size": _hull_reference_size(tier)})
					parts.append({"family": family, "tier": tier, "mark": mark, "comp": comp})
				elif family == "sensor":
					for kind in SENSOR_KINDS:
						var comp: Dictionary = Parts.make(family, tier, mark, Vector2(100, 100), {"sensor_kind": kind})
						parts.append({"family": family, "tier": tier, "mark": mark, "kind": kind, "comp": comp})
				else:
					var comp: Dictionary = Parts.make(family, tier, mark, Vector2(100, 100))
					parts.append({"family": family, "tier": tier, "mark": mark, "comp": comp})
	return parts

# ---------------------------------------------------------------------------
# Item 2: Band conformance -- the core gate. MUST go through the shared
# ShipDesignValidator.check_component_bands helper.
# ---------------------------------------------------------------------------

func _test_band_conformance() -> void:
	var entries: Array = _all_parts()
	for entry in entries:
		var comp: Dictionary = entry["comp"]
		var tier: int = entry["tier"]
		var violations: Array = ShipDesignValidator.check_component_bands(comp, tier)
		if not violations.is_empty():
			print("Item 2: band violations for ", entry.get("family"), " tier=", tier, " mark=", entry.get("mark"), ":")
			for v in violations:
				print("  ", v)
		_assert(violations.is_empty(), "Item 2: %s tier=%d mark=%d has %d band violation(s)" % [entry.get("family"), tier, entry.get("mark"), violations.size()])

# ---------------------------------------------------------------------------
# Item 3: Schema completeness. Every part carries REQUIRED_KEYS plus its
# type-specific fields; NONE hand-set runtime scratch (cooldown/timer/
# powered_on absent from what the catalog authors -- Ship._ready() owns those).
#
# Note: "powered_on"/"switchable" default state and weapon "cooldown"/"ammo"
# defaulting are Ship._ready() normalization's job per CLAUDE.md (weapons:
# cooldown/ammo; sensors: timer). The catalog must not set "cooldown" on
# weapons or "timer" on sensors. "powered_on"/"switchable" themselves are
# authored on hand-built ships today (see frigate.gd/light_attack_craft.gd)
# as a design field (whether a component CAN be switched / starts on), not a
# per-frame scratch counter -- so the catalog authoring "powered_on" is
# consistent with fleet convention. The scratch fields this test polices are
# the ones ship.gd explicitly calls out as scratch: weapon "cooldown", sensor
# "timer".
# ---------------------------------------------------------------------------

const REQUIRED_KEYS := ["id", "type", "rect", "health", "max_health", "density"]
const SCRATCH_KEYS_BY_TYPE := {
	"weapons": ["cooldown"],
	"sensors": ["timer"],
}

func _test_schema_completeness() -> void:
	var entries: Array = _all_parts()
	for entry in entries:
		var comp: Dictionary = entry["comp"]
		var label: String = "%s tier=%d mark=%d" % [entry.get("family"), entry.get("tier"), entry.get("mark")]

		for key in REQUIRED_KEYS:
			_assert(comp.has(key), "Item 3: %s missing REQUIRED_KEYS entry '%s'" % [label, key])

		var type: String = comp.get("type", "")
		match type:
			"weapons":
				for f in ["weapon_type", "cooldown_max", "range", "heading", "arc_width"]:
					_assert(comp.has(f), "Item 3: %s (weapon) missing field '%s'" % [label, f])
				var has_damage: bool = comp.has("damage")
				var has_ammo: bool = comp.has("ammo")
				_assert(has_damage or has_ammo, "Item 3: %s (weapon) must have 'damage' or 'ammo'" % label)
			"sensors":
				for f in ["sensor_type", "range", "arc_width", "num_bins", "refresh_interval", "heading"]:
					_assert(comp.has(f), "Item 3: %s (sensor) missing field '%s'" % [label, f])
			"engines":
				for f in ["thrust_rating", "torque_rating", "power_rating"]:
					_assert(comp.has(f), "Item 3: %s (engine) missing field '%s'" % [label, f])
			"reactor":
				_assert(comp.has("power_rating"), "Item 3: %s (reactor) missing field 'power_rating'" % label)
			"comms":
				_assert(comp.has("range"), "Item 3: %s (comms) missing field 'range'" % label)

		# Scratch keys must be ABSENT -- Ship._ready() normalization's job.
		var scratch_keys: Array = SCRATCH_KEYS_BY_TYPE.get(type, [])
		for key in scratch_keys:
			_assert(not comp.has(key), "Item 3: %s must NOT hand-set runtime scratch key '%s'" % [label, key])

# ---------------------------------------------------------------------------
# Item 4: Monotonic-marks invariant. Within each family x tier (x sensor kind
# where applicable), COMPACT <= STANDARD <= HEAVY in BOTH primary stat AND
# rect area, with the primary stat strictly increasing.
# ---------------------------------------------------------------------------

func _primary_stat(family: String, comp: Dictionary) -> float:
	match family:
		"laser":
			return comp["damage"]
		"missile", "comms":
			return comp["range"]
		"engine":
			return comp["thrust_rating"]
		"reactor":
			return comp["power_rating"]
		"sensor":
			return Parts.sensor_quality_score(comp)
		"rcs":
			return comp["thrust_rating"]
		"hull":
			return comp["health"]
		_:
			return 0.0

func _rect_area(comp: Dictionary) -> float:
	var r: Rect2 = comp["rect"]
	return r.size.x * r.size.y

func _test_monotonic_marks() -> void:
	for family in Parts.families():
		for tier in Parts.supported_tiers(family):
			if family == "sensor":
				for kind in SENSOR_KINDS:
					_check_monotonic_group(family, tier, kind)
			else:
				_check_monotonic_group(family, tier, "")

func _check_monotonic_group(family: String, tier: int, sensor_kind: String) -> void:
	var stats: Array = []
	var areas: Array = []
	for mark in ALL_MARKS:
		var opts := {}
		if family == "hull":
			opts["size"] = _hull_reference_size(tier) # health_per_area marks were calibrated at this area
		if family == "sensor":
			opts["sensor_kind"] = sensor_kind
		var comp: Dictionary = Parts.make(family, tier, mark, Vector2.ZERO, opts)
		stats.append(_primary_stat(family, comp))
		areas.append(_rect_area(comp))

	var label: String = "%s%s tier=%d" % [family, (" kind=" + sensor_kind) if sensor_kind != "" else "", tier]

	_assert(stats[0] < stats[1], "Item 4: %s primary stat not strictly increasing COMPACT(%s) < STANDARD(%s)" % [label, stats[0], stats[1]])
	_assert(stats[1] < stats[2], "Item 4: %s primary stat not strictly increasing STANDARD(%s) < HEAVY(%s)" % [label, stats[1], stats[2]])

	if family != "hull":
		# Hull area is test-supplied (layout-driven), so only non-hull families'
		# CATALOG-owned rect sizes are checked for area monotonicity here.
		_assert(areas[0] <= areas[1], "Item 4: %s rect area not monotonic COMPACT(%s) <= STANDARD(%s)" % [label, areas[0], areas[1]])
		_assert(areas[1] <= areas[2], "Item 4: %s rect area not monotonic STANDARD(%s) <= HEAVY(%s)" % [label, areas[1], areas[2]])

# ---------------------------------------------------------------------------
# Item 5: Placement & identity.
# ---------------------------------------------------------------------------

func _test_placement_and_identity() -> void:
	var pos := Vector2(123.0, -45.0)
	var comp: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, pos, {"heading": 1.25, "id": "test_laser_id"})
	var rect: Rect2 = comp["rect"]
	_assert(rect.position == pos, "Item 5: rect.position should equal pos, got %s expected %s" % [rect.position, pos])
	_assert(is_equal_approx(comp["heading"], 1.25), "Item 5: opts.heading should land in the dict, got %s" % comp["heading"])
	_assert(comp["id"] == "test_laser_id", "Item 5: opts.id should be respected, got %s" % comp["id"])

	var a: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, pos)
	var b: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, pos)
	_assert(a["id"] != b["id"], "Item 5: two calls without an id should yield distinct ids, both got '%s'" % a["id"])

# ---------------------------------------------------------------------------
# Item 6: Negative control (test the test). A test-local malformed part
# (damage 10x over band) run through the SAME shared helper MUST yield a
# violation. Guards against a vacuous band check.
# ---------------------------------------------------------------------------

func _test_negative_control() -> void:
	var comp: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2.ZERO)
	# LIGHT laser damage band is [100, 600] -- 10x the STANDARD mark's 250 is
	# 2500, well over the ceiling.
	comp["damage"] = comp["damage"] * 10.0

	var violations: Array = ShipDesignValidator.check_component_bands(comp, ComponentSpec.Tier.LIGHT)
	var has_damage_violation: bool = violations.any(func(v): return v["field"] == "damage")
	_assert(not violations.is_empty(), "Item 6: malformed part (damage 10x over band) should trip check_component_bands, got zero violations")
	_assert(has_damage_violation, "Item 6: expected a 'damage' field violation, got %s" % str(violations))

# ---------------------------------------------------------------------------
# Item 8: STANDARD-reproduces-fleet spot check. laser/LIGHT/STANDARD equals
# LAC's authored laser on damage/range/cooldown_max and rect size;
# engine/MEDIUM/STANDARD matches the frigate's engine thrust/torque (and size).
# ---------------------------------------------------------------------------

func _test_standard_reproduces_fleet() -> void:
	var lac := LightAttackCraft.new()
	var lac_laser: Dictionary = lac.get_component("hp_fwd_laser")
	_assert(not lac_laser.is_empty(), "Item 8: LAC should have a component 'hp_fwd_laser'")

	var cat_laser: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2.ZERO)
	_assert(is_equal_approx(cat_laser["damage"], lac_laser["damage"]), "Item 8: laser/LIGHT/STANDARD damage %s should equal LAC's %s" % [cat_laser["damage"], lac_laser["damage"]])
	_assert(is_equal_approx(cat_laser["range"], lac_laser["range"]), "Item 8: laser/LIGHT/STANDARD range %s should equal LAC's %s" % [cat_laser["range"], lac_laser["range"]])
	_assert(is_equal_approx(cat_laser["cooldown_max"], lac_laser["cooldown_max"]), "Item 8: laser/LIGHT/STANDARD cooldown_max %s should equal LAC's %s" % [cat_laser["cooldown_max"], lac_laser["cooldown_max"]])
	var lac_rect: Rect2 = lac_laser["rect"]
	var cat_rect: Rect2 = cat_laser["rect"]
	_assert(cat_rect.size == lac_rect.size, "Item 8: laser/LIGHT/STANDARD rect size %s should equal LAC's %s" % [cat_rect.size, lac_rect.size])

	var frig := Frigate.new()
	var frig_engine: Dictionary = frig.get_component("engine_main")
	_assert(not frig_engine.is_empty(), "Item 8: Frigate should have a component 'engine_main'")

	var cat_engine: Dictionary = Parts.make("engine", ComponentSpec.Tier.MEDIUM, Parts.Mark.STANDARD, Vector2.ZERO)
	_assert(is_equal_approx(cat_engine["thrust_rating"], frig_engine["thrust_rating"]), "Item 8: engine/MEDIUM/STANDARD thrust_rating %s should equal frigate's %s" % [cat_engine["thrust_rating"], frig_engine["thrust_rating"]])
	_assert(is_equal_approx(cat_engine["torque_rating"], frig_engine["torque_rating"]), "Item 8: engine/MEDIUM/STANDARD torque_rating %s should equal frigate's %s" % [cat_engine["torque_rating"], frig_engine["torque_rating"]])
	var frig_rect: Rect2 = frig_engine["rect"]
	var cat_engine_rect: Rect2 = cat_engine["rect"]
	_assert(cat_engine_rect.size == frig_rect.size, "Item 8: engine/MEDIUM/STANDARD rect size %s should equal frigate's %s" % [cat_engine_rect.size, frig_rect.size])

# ---------------------------------------------------------------------------
# Item 7: Integration smoke. Assemble a minimal ship in-test (raw hull frame +
# catalog reactor/engine/sensor/laser), run the full ShipDesignValidator ->
# ok == true, and instantiate it on a Ship-derived node headlessly to prove
# _ready() normalization accepts catalog parts (no script errors for 60
# physics frames).
# ---------------------------------------------------------------------------

func _start_integration_smoke() -> void:
	smoke_ship = Ship.new()
	smoke_ship.name = "PartsCatalogSmokeShip"
	smoke_ship.owner_id = 999
	smoke_ship.ship_tier = ComponentSpec.Tier.LIGHT
	smoke_ship.max_speed = 2000.0
	smoke_ship.max_omega = 4.0

	var reactor: Dictionary = Parts.make("reactor", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(-5, -5), {"id": "smoke_reactor"})
	var engine: Dictionary = Parts.make("engine", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(-15, -5), {"id": "smoke_engine"})
	var sensor: Dictionary = Parts.make("sensor", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(5, -2.5), {"id": "smoke_sensor", "sensor_kind": "omni_search"})
	var laser: Dictionary = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(5, 5), {"id": "smoke_laser"})

	# Raw hull frame around the parts above -- a simple enclosing box, split
	# into pieces so every component (hull + parts) ends up edge-adjacent to
	# at least one other (connectivity rule). Layout:
	#   x: -15 .. 10   y: -5 .. 10
	var hull_south: Dictionary = {"id": "hull_south", "type": "hull", "rect": Rect2(-15, -10, 25, 5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}
	var hull_north: Dictionary = {"id": "hull_north", "type": "hull", "rect": Rect2(-15, 10, 25, 5), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}
	var hull_east: Dictionary = {"id": "hull_east", "type": "hull", "rect": Rect2(10, -5, 5, 15), "health": 80.0, "max_health": 80.0, "density": 20.0, "heat": 0.0, "em_emission": 0.0, "switchable": false}
	var comms: Dictionary = Parts.make("comms", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD, Vector2(0, 5), {"id": "smoke_comms"})

	smoke_ship.ship_components = [hull_south, hull_north, hull_east, reactor, engine, sensor, laser, comms]

	var r: Dictionary = ShipDesignValidator.validate(smoke_ship)
	if not r["ok"]:
		print("Item 7: smoke ship failed to validate:")
		for v in r["violations"]:
			print("  ", v)
	_assert(r["ok"] == true, "Item 7: minimal catalog-built ship should validate ok=true")

	main_node.add_child(smoke_ship)
	smoke_heat_before = smoke_ship.current_heat
	smoke_timer_before = 0.0
	for c in smoke_ship.ship_components:
		if c.get("type", "") == "sensors":
			smoke_timer_before = c.get("timer", 0.0)
	smoke_started = true

func _physics_process(_delta: float) -> void:
	if finished or not smoke_started or smoke_ship == null:
		return

	smoke_frames += 1
	if smoke_frames >= SMOKE_FRAMES_REQUIRED:
		_assert(is_finite(smoke_ship.position.x) and is_finite(smoke_ship.position.y), "Item 7: ship position must stay finite after %d physics frames" % SMOKE_FRAMES_REQUIRED)
		_assert(is_finite(smoke_ship.current_heat), "Item 7: current_heat must stay finite after %d physics frames" % SMOKE_FRAMES_REQUIRED)
		# current_heat is updated deep inside _physics_process, well after the
		# weapon-cooldown/steering/RCS logic -- if an earlier statement threw
		# (e.g. a missing scratch field never normalized), this update never
		# runs and current_heat would stay frozen at its starting value.
		_assert(not is_equal_approx(smoke_ship.current_heat, smoke_heat_before), "Item 7: current_heat should have changed over %d physics frames (proxy for _physics_process completing without error)" % SMOKE_FRAMES_REQUIRED)

		var sensor_timer_after: float = -1.0
		for c in smoke_ship.ship_components:
			if c.get("type", "") == "sensors":
				sensor_timer_after = c.get("timer", -1.0)
		_assert(sensor_timer_after != smoke_timer_before, "Item 7: sensor timer should have ticked over %d physics frames" % SMOKE_FRAMES_REQUIRED)

		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_parts_catalog <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_parts_catalog <<<")
		get_tree().quit(1)
