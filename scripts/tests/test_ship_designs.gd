extends Node

const Frigate = preload("res://scripts/ships/frigate.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")

# M9b: validates ShipDesignValidator against the spec chart in
# component_spec.gd. Validation is synchronous/pure (reads ship_components +
# max_speed/max_omega/ship_tier off a fresh ship instance, no physics, no
# tree-add required) -- so setup() does everything and quits immediately.

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(_main: Node) -> void:
	print("Starting Ship Design Validator Tests")

	_test_frigate_validates_clean()
	_test_malformed_fixture_fails()
	_test_unvalidated_opt_out()
	_test_catalog_ships_validate_structurally()
	_test_pd_coherence()

	if failures.is_empty():
		print(">>> [TEST PASSED] test_ship_designs <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_ship_designs <<<")
		get_tree().quit(1)

# ---------------------------------------------------------------------------
# Case 1: Frigate validates clean.
# ---------------------------------------------------------------------------

func _test_frigate_validates_clean() -> void:
	var ship = Frigate.new()
	var r = ShipDesignValidator.validate(ship)
	if not r["ok"] or not r["violations"].is_empty():
		print("Frigate did NOT validate clean -- violations:")
		for v in r["violations"]:
			print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"], " severity=", v["severity"])
	_assert(r["ok"] == true, "Case 1: Frigate.new() should validate ok=true, got false")
	_assert(r["violations"].is_empty(), "Case 1: Frigate.new() should have no violations, got " + str(r["violations"].size()))

# ---------------------------------------------------------------------------
# Case 2: Malformed fixture fails with a distinct violation per broken rule.
# ---------------------------------------------------------------------------

func _test_malformed_fixture_fails() -> void:
	var ship = Frigate.new()
	ship.ship_tier = ComponentSpec.Tier.MEDIUM

	# Break 1: remove all reactors (rule 5 + rule 8 -- powered systems, no reactor).
	ship.ship_components = ship.ship_components.filter(func(c): return c["type"] != "reactor")

	# Break 2: set a laser's damage to 5 (below MEDIUM laser band [300, 1200]).
	for c in ship.ship_components:
		if c["id"] == "hp_fwd_laser":
			c["damage"] = 5.0

	# Break 3: max_omega of 0.1 (below MEDIUM handling band [1.2, 3.0]).
	ship.max_omega = 0.1

	# Break 4: duplicate a component id (hull_port duplicated as hull_stbd's id).
	for c in ship.ship_components:
		if c["id"] == "hull_port":
			c["id"] = "hull_stbd"
			break

	var r = ShipDesignValidator.validate(ship)
	_assert(r["ok"] == false, "Case 2: malformed fixture should validate ok=false")

	var violations: Array = r["violations"]
	print("Malformed fixture violations:")
	for v in violations:
		print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"], " severity=", v["severity"])

	var has_reactor_violation := violations.any(func(v): return v["field"] == "reactor" and v["severity"] == "error")
	var has_laser_damage_violation := violations.any(func(v): return v["component_id"] == "hp_fwd_laser" and v["field"] == "damage" and v["severity"] == "warning")
	var has_omega_violation := violations.any(func(v): return v["field"] == "max_omega" and v["severity"] == "warning")
	var has_duplicate_id_violation := violations.any(func(v): return v["field"] == "id" and v["component_id"] == "hull_stbd" and v["severity"] == "error")

	_assert(has_reactor_violation, "Case 2: expected an error-severity violation naming the missing reactor")
	_assert(has_laser_damage_violation, "Case 2: expected a warning-severity violation naming hp_fwd_laser's damage out of band")
	_assert(has_omega_violation, "Case 2: expected a warning-severity violation naming max_omega out of band")
	_assert(has_duplicate_id_violation, "Case 2: expected an error-severity violation naming the duplicate component id")

# ---------------------------------------------------------------------------
# Case 3: UNVALIDATED opt-out.
# ---------------------------------------------------------------------------

func _test_unvalidated_opt_out() -> void:
	var ship = Ship.new()
	_assert(ship.ship_tier == ComponentSpec.Tier.UNVALIDATED, "Case 3: bare Ship.new() should default to ship_tier UNVALIDATED")
	var r = ShipDesignValidator.validate(ship)
	_assert(r["ok"] == true, "Case 3: UNVALIDATED ship should validate ok=true (opt-out, not failure)")
	_assert(r["violations"].is_empty(), "Case 3: UNVALIDATED ship should have empty violations")

# ---------------------------------------------------------------------------
# Case 4: M9b forward-link -- every ShipCatalog.SPAWNABLE entry instantiates
# and validates with zero error-severity (structural) violations. Warnings
# (band/handling deviations) are allowed and printed, not asserted on, per
# M9c's "don't band everything today."
# ---------------------------------------------------------------------------

func _test_catalog_ships_validate_structurally() -> void:
	for entry in ShipCatalog.SPAWNABLE:
		var ship_name: String = entry["name"]
		var ship = entry["script"].new()
		var r = ShipDesignValidator.validate(ship)

		var error_violations: Array = r["violations"].filter(func(v): return v["severity"] == "error")
		var warning_violations: Array = r["violations"].filter(func(v): return v["severity"] == "warning")

		# Debug readout (M9c): achieved mass/thrust/accel per catalog ship, so
		# the report can compare against the design table's targets.
		var mass: float = ship.get_ship_mass()
		var thrust: float = ship.get_ship_max_thrust()
		var accel: float = thrust / mass if mass > 0.0 else 0.0
		print("[M9c] ", ship_name, ": mass=", mass, " thrust=", thrust, " accel=", accel, " max_speed=", ship.max_speed, " max_omega=", ship.max_omega)

		if not error_violations.is_empty():
			print(ship_name, " has error-severity violations:")
			for v in error_violations:
				print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"])
		if not warning_violations.is_empty():
			print(ship_name, " band/handling WARNINGS:")
			for v in warning_violations:
				print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"])

		_assert(error_violations.is_empty(), "Case 4: " + ship_name + " should have zero error-severity violations, got " + str(error_violations.size()))
		_assert(r["ok"] == true, "Case 4: " + ship_name + " should validate ok=true")

# ---------------------------------------------------------------------------
# Case 5: PD coherence -- a ship with laser (PD) weapons but every sensor too
# slow to aim them gets a warning-severity pd_sensor violation (the "turrets
# with no eyes" case that had stations firing off a 1.0s search dish). It's a
# warning, so ok stays true; and a clean frigate (Case 1) must NOT warn.
# ---------------------------------------------------------------------------

func _test_pd_coherence() -> void:
	# Positive: slow every sensor below the PD-tracking threshold. The frigate
	# keeps its lasers, so it should now warn about having nothing to aim them.
	var ship = Frigate.new()
	ship.ship_tier = ComponentSpec.Tier.MEDIUM
	for c in ship.ship_components:
		if c["type"] == "sensors":
			c["refresh_interval"] = 1.0
	var r = ShipDesignValidator.validate(ship)

	var pd_warnings: Array = r["violations"].filter(func(v): return v["field"] == "pd_sensor" and v["severity"] == "warning")
	var pd_errors: Array = r["violations"].filter(func(v): return v["field"] == "pd_sensor" and v["severity"] == "error")
	_assert(not pd_warnings.is_empty(), "Case 5: frigate with only slow sensors + lasers should warn about no PD-capable sensor")
	_assert(pd_errors.is_empty(), "Case 5: pd_sensor violation must be warning severity, not error")

	# Negative: a stock frigate has its 0.1s PD dish, so it must NOT warn.
	var clean = Frigate.new()
	var rc = ShipDesignValidator.validate(clean)
	var clean_pd: Array = rc["violations"].filter(func(v): return v["field"] == "pd_sensor")
	_assert(clean_pd.is_empty(), "Case 5: stock frigate should have no pd_sensor violation")
