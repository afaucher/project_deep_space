extends Node

const Frigate = preload("res://scripts/ships/frigate.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const Freighter = preload("res://scripts/ships/freighter.gd")
const Pinnace = preload("res://scripts/ships/pinnace.gd")
const Mine = preload("res://scripts/ships/mine.gd")
const DefencePod = preload("res://scripts/ships/defence_pod.gd")
const AsteroidStation = preload("res://scripts/ships/asteroid_station.gd")

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
	_test_layout_warnings_ratchet()
	_test_m27_parameter_table_conformance()

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
#
# M23 note: the frigate's weapon sponsons predate the ship-design skill's
# hull-first rule (SKILL.md 4a) -- it's the skill's own "BAD" example -- so
# the two new layout checks (hull_coverage/active_surface) now legitimately
# warn on it. That's the ratchet in Case 6/_test_layout_warnings_ratchet's
# job (ok stays true; the exact warning set is frozen and reviewed there per
# the plan's DONE-note default: accept as historical). This case's original
# "zero violations of any kind" guarantee is preserved for every OTHER field/
# severity by filtering out just the two new layout fields here -- nothing
# this case previously exercised has been weakened.
# ---------------------------------------------------------------------------

func _test_frigate_validates_clean() -> void:
	var ship = Frigate.new()
	var r = ShipDesignValidator.validate(ship)
	var non_layout_violations: Array = r["violations"].filter(func(v): return v["field"] != "hull_coverage" and v["field"] != "active_surface")
	if not r["ok"] or not non_layout_violations.is_empty():
		print("Frigate did NOT validate clean -- violations:")
		for v in r["violations"]:
			print("  component_id=", v["component_id"], " field=", v["field"], " reason=", v["reason"], " severity=", v["severity"])
	_assert(r["ok"] == true, "Case 1: Frigate.new() should validate ok=true, got false")
	_assert(non_layout_violations.is_empty(), "Case 1: Frigate.new() should have no non-layout violations, got " + str(non_layout_violations.size()))

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
#
# M24: extended additively to also iterate ShipCatalog.VARIANTS through the
# same structural validation -- every future variant is validated by existing
# without new test code (design doc's stated goal). Variants are skins of an
# already-validated base, so they get no bypass: same zero-error-violations
# gate as any SPAWNABLE hull.
# ---------------------------------------------------------------------------

func _all_catalog_entries() -> Array:
	return ShipCatalog.SPAWNABLE + ShipCatalog.VARIANTS

func _test_catalog_ships_validate_structurally() -> void:
	for entry in _all_catalog_entries():
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

# ---------------------------------------------------------------------------
# Case 6/M23: Fleet-audit ratchet for the two layout checks (hull_coverage +
# active_surface) added in ship_design_validator.gd. See
# implementation_plans/m23_layout_coverage_checks_design.md items 9-10.
#
# EXPECTED_LAYOUT_WARNINGS is a per-ship (by ShipCatalog.SPAWNABLE "name")
# FROZEN set of {component_id, field} pairs -- enumerated by actually running
# the validator against the current fleet, then reviewed line-by-line against
# the plan's sanity anchors before being accepted here. Any future change to a
# ship's layout (or to the check logic) that adds/removes a warning must
# update this registry explicitly -- that's the ratchet: warnings can neither
# silently appear nor silently vanish.
#
# Sanity-anchor review notes (plan's three anchors):
#  - Frigate: port/stbd tubes + broadside lasers DO flag exposed faces (the
#    sponson layout predates the hull-first skill rule; it's the skill's own
#    "BAD" example). Confirmed below -- 8 weapon components flagged, plus the
#    engine (exposed +Y/-Y, the frigate's engine box is narrower than its
#    aft hull) and the forward laser/missile (each missing one Y flank).
#  - Small/medium station PD turrets: the plan anchor guessed "~3-face
#    exposure". Actual ray tracing finds 2 faces exposed per turret (+Y/-Y),
#    NOT 3 -- the turret's inboard face (toward the arm) DOES touch the hull
#    cap (e.g. small station's pd_fwd at x 70-90 vs hull_fwd_cap at x 60-70,
#    which is adjacent, not gapped), so only the two flank faces are exposed,
#    plus the arm's flank hull (30 wide) doesn't reach the turret's outboard
#    x-extent at all. Investigated and confirmed correct given the authored
#    geometry (not a check bug) -- see M23 report.
#  - Destroyer: near-clean, confirmed -- only 2 warnings total on a ~50
#    component ship (one aft PD turret's -Y flank exposed, and the forward
#    fire-control dish masked by a hull plate directly in front of it,
#    `hull_spine_mid3`, since the dish sits recessed in the spine rather than
#    flush with the true bow at hull_bow_main).
# ---------------------------------------------------------------------------

const EXPECTED_LAYOUT_WARNINGS := {
	"Frigate": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "hp_fwd_laser", "field": "hull_coverage"},
		{"component_id": "hp_fwd_missile", "field": "hull_coverage"},
		{"component_id": "hp_fwd_missile", "field": "hull_coverage"},
		{"component_id": "hp_port_laser_1", "field": "hull_coverage"},
		{"component_id": "hp_port_tube_1", "field": "hull_coverage"},
		{"component_id": "hp_port_tube_3", "field": "hull_coverage"},
		{"component_id": "hp_port_laser_2", "field": "hull_coverage"},
		{"component_id": "hp_stbd_laser_1", "field": "hull_coverage"},
		{"component_id": "hp_stbd_tube_1", "field": "hull_coverage"},
		{"component_id": "hp_stbd_tube_3", "field": "hull_coverage"},
		{"component_id": "hp_stbd_laser_2", "field": "hull_coverage"},
	],
	"Cargo Shuttle": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
	],
	"Light Attack Craft": [],
	"Destroyer": [
		{"component_id": "hp_aft_pd", "field": "hull_coverage"},
		{"component_id": "dir_high_res", "field": "active_surface"},
	],
	"Buoy": [],
	"Small Station": [
		# dock_main: docking port added in the Universal Docking Refactor; its
		# exposed faces + active surface are expected (a port, not armor).
		{"component_id": "dock_main", "field": "active_surface"},
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "omni_short_pd", "field": "hull_coverage"},
		{"component_id": "omni_short_pd", "field": "hull_coverage"},
		{"component_id": "pd_fwd", "field": "hull_coverage"},
		{"component_id": "pd_fwd", "field": "hull_coverage"},
		{"component_id": "pd_aft", "field": "hull_coverage"},
		{"component_id": "pd_aft", "field": "hull_coverage"},
		{"component_id": "pd_port", "field": "hull_coverage"},
		{"component_id": "pd_port", "field": "hull_coverage"},
		{"component_id": "pd_stbd", "field": "hull_coverage"},
		{"component_id": "pd_stbd", "field": "hull_coverage"},
	],
	"Medium Station": [
		{"component_id": "omni_short_pd", "field": "hull_coverage"},
		{"component_id": "omni_short_pd", "field": "hull_coverage"},
		{"component_id": "pd_fwd", "field": "hull_coverage"},
		{"component_id": "missile_fwd", "field": "hull_coverage"},
		{"component_id": "pd_aft", "field": "hull_coverage"},
		{"component_id": "missile_aft", "field": "hull_coverage"},
		{"component_id": "pd_port", "field": "hull_coverage"},
		{"component_id": "missile_port", "field": "hull_coverage"},
		{"component_id": "pd_stbd", "field": "hull_coverage"},
		{"component_id": "missile_stbd", "field": "hull_coverage"},
	],
	# M24 -- delta variants. Frozen the same way as the rest of this table:
	# enumerated by running the validator against the actual variant geometry,
	# then reviewed line-by-line before being accepted here.
	#  - Pirate LAC: base LAC validates with ZERO layout warnings (see "Light
	#    Attack Craft" above), so any warnings here are a direct consequence of
	#    this variant's one GEOMETRY delta (removing hull_fwd_port). Filled in
	#    below from an actual validator run against the variant's real
	#    geometry (not guessed) -- see the M24 report for the run transcript.
	#  - Ore Shuttle: STATS_ONLY deltas only (tune ops, no remove) -- so its
	#    layout-warning set must be IDENTICAL to the base "Cargo Shuttle"
	#    entry above (tunes never touch geometry).
	"Pirate LAC": [
		{"component_id": "hp_fwd_laser", "field": "hull_coverage"},
	],
	"Ore Shuttle": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
	],
	# M27 -- freighter (spine + cargo pods, HEAVY) and pinnace (tapered dart,
	# LIGHT). Both frozen the same way as the rest of this table: enumerated
	# by running the validator against the actual authored geometry, then
	# reviewed line-by-line before being accepted here.
	#  - Freighter: engine_main's flanks (+/-Y) are open to the side, same
	#    idiom as cargo_shuttle/ore_shuttle's engine_main above (an engine
	#    bolted onto the aft face of a frame, narrower than the frame's own
	#    wall thickness on its sides) -- expected, not a design flaw.
	"Freighter": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
	],
	#  - Pinnace: unarmored dart per the M27 plan ("thin/no hull plating IS
	#    the point") -- the bow sensor's tip (+X, nothing beyond the hull's
	#    own nose) and both flanks (+/-Y, a 10x8 station with no side
	#    coverage) are honestly exposed, plus the aft engine's flanks
	#    (same idiom as every other hull's engine_main above). Accepted as
	#    real, not re-wrapped -- per the plan's explicit "accept the honest
	#    coverage warnings" option for this ship.
	"Pinnace": [
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
	],
	# M27 stage 2 -- mine (5-rect plus, DRONE) and defence pod (ring, STRUCTURE).
	# Enumerated by running the validator against the actual authored geometry,
	# then reviewed line-by-line before being accepted here, same as every
	# other entry in this table.
	#  - Mine: engine_main's -Y face and laser_main's -Y face are open (the SW/
	#    NE quadrant parts of the functional core only touch neighbors on 2-3
	#    of their 4 sides at this DRONE-tiny scale, same idiom as every other
	#    hull's engine_main above); sensor_passive's +Y face is likewise open
	#    (it sits under the laser with nothing further +Y beyond it within the
	#    hull's own AABB). All three are honest exposure on a small, thin-
	#    walled drone hull -- not re-wrapped, same acceptance rationale as
	#    Pinnace's.
	"Mine": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "laser_main", "field": "hull_coverage"},
		{"component_id": "sensor_passive", "field": "hull_coverage"},
	],
	#  - Defence Pod: all 8 weapon turrets (pd/missile x 4 quadrants) show one
	#    exposed face each -- the face BETWEEN the paired laser and missile
	#    tube on each quadrant (e.g. pd_fwd's -Y face, missile_fwd's +Y face)
	#    is open since the two turrets are stacked with nothing filling the
	#    gap on their far sides from each other. Same "turret projecting past
	#    the hull, partially open" pattern already accepted for
	#    small_station/medium_station's pd_fwd/pd_aft/pd_port/pd_stbd above --
	#    consistent with the fleet convention, not a design flaw.
	"Defence Pod": [
		{"component_id": "pd_fwd", "field": "hull_coverage"},
		{"component_id": "missile_fwd", "field": "hull_coverage"},
		{"component_id": "pd_aft", "field": "hull_coverage"},
		{"component_id": "missile_aft", "field": "hull_coverage"},
		{"component_id": "pd_stbd", "field": "hull_coverage"},
		{"component_id": "missile_stbd", "field": "hull_coverage"},
		{"component_id": "pd_port", "field": "hull_coverage"},
		{"component_id": "missile_port", "field": "hull_coverage"},
	],
	#  - Asteroid Station: only the two PD lasers (pd_north/pd_south) flag --
	#    each is an 8-wide turret flush-mounted against the 30-wide core
	#    column's N/S rock face, so its two SIDE faces (+X/-X, perpendicular
	#    to its outward heading) project past the narrower turret footprint
	#    with nothing beside it -- same "turret projecting past the hull"
	#    pattern already accepted for every station/pod's PD turrets above.
	#    Every embedded module (reactor/cargo_bay/living_quarters/comms/
	#    sensor_search/rcs/sensor_pd) is fully enclosed by its sandwiching
	#    rock column and neighboring columns -- zero warnings on any of them,
	#    confirming the modules really are embedded IN the rock, not merely
	#    adjacent to it (the plan's explicit sanity check for this archetype).
	"Asteroid Station": [
		# dock_main: docking port added in the Universal Docking Refactor.
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "pd_north", "field": "hull_coverage"},
		{"component_id": "pd_north", "field": "hull_coverage"},
		{"component_id": "pd_south", "field": "hull_coverage"},
		{"component_id": "pd_south", "field": "hull_coverage"},
	],
	# Mobile Home (MobileHome ship, Universal Docking Refactor era). Its aft
	# engine (exposed +Y/-Y) and its outboard docking port each flag two
	# exposed faces -- expected for a small mobile hull with a stuck-out port.
	"Mobile Home": [
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "dock_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
	],
	# M50 -- pirate hulls (implementation_plans/m50_pirate_tree_design.md).
	# Enumerated the same way as every other entry: run the validator against
	# the actual authored geometry, then review before freezing.
	#  - Pirate Ore Shuttle: identical to "Ore Shuttle"'s own engine_main
	#    warnings (inherited layout, untouched by this delta) plus the new
	#    mining_laser's two flank faces (+Y/-Y) -- it's bolted onto hull_fwd's
	#    open +X face with nothing beside it, same "turret projecting past
	#    the hull" idiom already accepted fleet-wide.
	"Pirate Ore Shuttle": [
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "mining_laser", "field": "hull_coverage"},
		{"component_id": "mining_laser", "field": "hull_coverage"},
	],
	#  - Armed Pinnace: identical to "Pinnace"'s own sensor_fwd/engine_main
	#    warnings (inherited, untouched by this delta) plus the new
	#    hp_dorsal_laser's -X face -- it sits flush against rcs_main's dorsal
	#    edge (covered from that side) but open on its outboard -X flank with
	#    nothing else nearby; its active face (+Y) reaches the hull's own
	#    edge unmasked, so no active_surface warning.
	"Armed Pinnace": [
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "sensor_fwd", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "engine_main", "field": "hull_coverage"},
		{"component_id": "hp_dorsal_laser", "field": "hull_coverage"},
	],
}

# Multiset key: "component_id|field" repeated per occurrence (a component can
# legitimately rack up more than one warning of the same field, e.g. two
# exposed flank faces), so plain Dictionary-of-pairs set equality would
# under-count duplicates. Sort both sides' key lists and compare as multisets.
func _layout_warning_keys(violations: Array) -> Array:
	var keys: Array = []
	for v in violations:
		if v["field"] == "hull_coverage" or v["field"] == "active_surface":
			keys.append(str(v["component_id"]) + "|" + str(v["field"]))
	keys.sort()
	return keys

# M24: extended additively to also iterate ShipCatalog.VARIANTS -- both new
# variants get EXPECTED_LAYOUT_WARNINGS entries above, frozen the same way as
# every SPAWNABLE hull's. This is also the auto-enumeration proof for
# test_ship_variants.gd item 9: _all_catalog_entries()'s size is
# SPAWNABLE.size() + VARIANTS.size(), so this loop demonstrably iterates more
# ships than it did pre-M24, by exactly the variant count.
func _test_layout_warnings_ratchet() -> void:
	var pre_variant_count: int = ShipCatalog.SPAWNABLE.size()
	var all_entries: Array = _all_catalog_entries()
	_assert(all_entries.size() == pre_variant_count + ShipCatalog.VARIANTS.size(), "Case 6 (M24 auto-enumeration): combined catalog entry count should equal SPAWNABLE + VARIANTS")

	for entry in all_entries:
		var ship_name: String = entry["name"]
		var ship = entry["script"].new()
		var r: Dictionary = ShipDesignValidator.validate(ship)

		_assert(r["ok"] == true, "Case 6: " + ship_name + " should still validate ok=true with layout checks active")

		if not EXPECTED_LAYOUT_WARNINGS.has(ship_name):
			_assert(false, "Case 6: no EXPECTED_LAYOUT_WARNINGS entry registered for catalog ship '" + ship_name + "'")
			continue

		var expected_keys: Array = []
		for pair in EXPECTED_LAYOUT_WARNINGS[ship_name]:
			expected_keys.append(str(pair["component_id"]) + "|" + str(pair["field"]))
		expected_keys.sort()

		var actual_keys: Array = _layout_warning_keys(r["violations"])

		if actual_keys != expected_keys:
			print("Case 6: layout-warning mismatch for ", ship_name, ":")
			print("  expected: ", expected_keys)
			print("  actual:   ", actual_keys)

		_assert(actual_keys == expected_keys, "Case 6: " + ship_name + " actual layout-warning set must exactly match EXPECTED_LAYOUT_WARNINGS (both directions)")

# ---------------------------------------------------------------------------
# Case 7/M27: parameter-table conformance for the freighter + pinnace --
# derived mass within +/-10% of the target row in
# design_ideas/ship_parameter_table.md's M27 pre-step table, derived accel
# within the row's stated band, and max_speed/max_omega inside the ship's
# own tier's HANDLING_BANDS (a real assert, not just a printed warning, per
# the M27 test plan item 2).
# ---------------------------------------------------------------------------

const M27_TARGETS := {
	"Freighter": {"mass": 300.0, "mass_tolerance": 0.10, "accel_lo": 8.0, "accel_hi": 12.0, "tier": ComponentSpec.Tier.HEAVY},
	"Pinnace": {"mass": 109.0, "mass_tolerance": 0.10, "accel_lo": 70.0, "accel_hi": 90.0, "tier": ComponentSpec.Tier.LIGHT},
	# Stage 2 (mine/defence pod) targets are rougher order-of-magnitude figures
	# in the parameter table (not pre-authored-geometry-derived like the stage
	# 1 pair above), so these use a wider mass tolerance. The defence pod is
	# STRUCTURE-tier (immobile, no engines) -- accel is not a meaningful stat
	# for it (n/a per the parameter table), so its accel band is left null and
	# skipped below rather than asserted against a fabricated number.
	"Mine": {"mass": 4.0, "mass_tolerance": 1.0, "accel_lo": 0.0, "accel_hi": INF, "tier": ComponentSpec.Tier.DRONE},
	"Defence Pod": {"mass": 900.0, "mass_tolerance": 0.5, "accel_lo": null, "accel_hi": null, "tier": ComponentSpec.Tier.STRUCTURE},
	# Asteroid Station: the parameter table's row is explicitly "~4000+
	# (density >= 300 shell)" and explicitly NOT back-solvable from the
	# fleet's usual density-20 area*0.036 shortcut (see that doc's M27
	# pre-step note) -- so this uses a wide asymmetric tolerance expressed as
	# an explicit floor via a generous mass_tolerance around a midpoint,
	# same rough order-of-magnitude treatment as Mine/Defence Pod above
	# rather than a tight +/-10% band. STRUCTURE tier -- accel is n/a
	# (immobile by construction), same as Defence Pod.
	"Asteroid Station": {"mass": 5000.0, "mass_tolerance": 0.3, "accel_lo": null, "accel_hi": null, "tier": ComponentSpec.Tier.STRUCTURE},
}

func _ship_for_m27_name(ship_name: String):
	match ship_name:
		"Freighter":
			return Freighter.new()
		"Pinnace":
			return Pinnace.new()
		"Mine":
			return Mine.new()
		"Defence Pod":
			return DefencePod.new()
		"Asteroid Station":
			return AsteroidStation.new()
	return null

func _test_m27_parameter_table_conformance() -> void:
	for ship_name in M27_TARGETS.keys():
		var target: Dictionary = M27_TARGETS[ship_name]
		var ship = _ship_for_m27_name(ship_name)

		var mass: float = ship.get_ship_mass()
		var thrust: float = ship.get_ship_max_thrust()
		var accel: float = thrust / mass if mass > 0.0 else 0.0

		var target_mass: float = target["mass"]
		var tolerance: float = target["mass_tolerance"]
		var mass_lo: float = target_mass * (1.0 - tolerance)
		var mass_hi: float = target_mass * (1.0 + tolerance)
		_assert(mass >= mass_lo and mass <= mass_hi, "Case 7: " + ship_name + " mass=" + str(mass) + " should be within +/-" + str(tolerance * 100.0) + "% of target " + str(target_mass) + " (band [" + str(mass_lo) + ", " + str(mass_hi) + "])")

		if target["accel_lo"] != null and target["accel_hi"] != null:
			_assert(accel >= target["accel_lo"] and accel <= target["accel_hi"], "Case 7: " + ship_name + " accel=" + str(accel) + " should be within target band [" + str(target["accel_lo"]) + ", " + str(target["accel_hi"]) + "]")

		var tier: int = target["tier"]
		var handling: Dictionary = ComponentSpec.HANDLING_BANDS.get(tier, {})
		var speed_band: Array = handling["max_speed"]
		var omega_band: Array = handling["max_omega"]
		_assert(ship.max_speed >= speed_band[0] and ship.max_speed <= speed_band[1], "Case 7: " + ship_name + " max_speed=" + str(ship.max_speed) + " should be inside tier " + str(tier) + " handling band " + str(speed_band))
		_assert(ship.max_omega >= omega_band[0] and ship.max_omega <= omega_band[1], "Case 7: " + ship_name + " max_omega=" + str(ship.max_omega) + " should be inside tier " + str(tier) + " handling band " + str(omega_band))

		print("[Case 7/M27] ", ship_name, ": mass=", mass, " accel=", accel, " max_speed=", ship.max_speed, " max_omega=", ship.max_omega)
