extends Node

const Frigate = preload("res://scripts/ships/frigate.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")

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
			print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"])
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
		print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"])

	var has_reactor_violation := violations.any(func(v): return v["field"] == "reactor")
	var has_laser_damage_violation := violations.any(func(v): return v["component_id"] == "hp_fwd_laser" and v["field"] == "damage")
	var has_omega_violation := violations.any(func(v): return v["field"] == "max_omega")
	var has_duplicate_id_violation := violations.any(func(v): return v["field"] == "id" and v["component_id"] == "hull_stbd")

	_assert(has_reactor_violation, "Case 2: expected a violation naming the missing reactor")
	_assert(has_laser_damage_violation, "Case 2: expected a violation naming hp_fwd_laser's damage out of band")
	_assert(has_omega_violation, "Case 2: expected a violation naming max_omega out of band")
	_assert(has_duplicate_id_violation, "Case 2: expected a violation naming the duplicate component id")

# ---------------------------------------------------------------------------
# Case 3: UNVALIDATED opt-out.
# ---------------------------------------------------------------------------

func _test_unvalidated_opt_out() -> void:
	var ship = Ship.new()
	_assert(ship.ship_tier == ComponentSpec.Tier.UNVALIDATED, "Case 3: bare Ship.new() should default to ship_tier UNVALIDATED")
	var r = ShipDesignValidator.validate(ship)
	_assert(r["ok"] == true, "Case 3: UNVALIDATED ship should validate ok=true (opt-out, not failure)")
	_assert(r["violations"].is_empty(), "Case 3: UNVALIDATED ship should have empty violations")
