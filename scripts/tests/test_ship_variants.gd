extends Node

# M24 acceptance -- delta variants (Variants.apply/classify + Pirate LAC/Ore
# Shuttle). See implementation_plans/m24_delta_variants_design.md's 9-item
# test plan and design_ideas/hull_shape_grammar.md §5/§7. Validation
# (items 1-7, 9) is synchronous/pure; item 8 (spawn smoke) needs physics
# frames, so it's driven in _physics_process same as test_parts_catalog.gd's
# item 7/test_docking.gd. Run:
#   ./Godot_v4.4.1-stable_win64.exe --headless --run-test test_ship_variants

const Variants = preload("res://scripts/components/ship_variants.gd")
const Parts = preload("res://scripts/components/parts_catalog.gd")
const ComponentSpec = preload("res://scripts/components/component_spec.gd")
const ShipDesignValidator = preload("res://scripts/components/ship_design_validator.gd")
const Ship = preload("res://scripts/ships/ship.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const LightAttackCraft = preload("res://scripts/ships/light_attack_craft.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const PirateLAC = preload("res://scripts/ships/pirate_lac.gd")
const OreShuttle = preload("res://scripts/ships/ore_shuttle.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false

# Item 8 (spawn smoke) phase state.
var smoke_ships: Array = []
var smoke_frames: int = 0
const SMOKE_FRAMES_REQUIRED := 60
var smoke_started: bool = false

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Ship Variants (M24) Tests")

	_test_op_mechanics()
	_test_size_mismatch_swap_rejected()
	_test_classify_correctness()
	_test_geometry_deltas_caught_by_validator()
	_test_design_extraction_fidelity()
	_test_pirate_lac_gates()
	_test_ore_shuttle_gates()
	_test_auto_enumeration()

	# Item 8 needs physics frames -- kick it off here, _physics_process drives
	# it to completion and finalizes the test.
	_start_spawn_smoke()

# ---------------------------------------------------------------------------
# Shared fixture helpers.
# ---------------------------------------------------------------------------

func _hull(id: String, rect: Rect2, density: float = 20.0) -> Dictionary:
	return {"id": id, "type": "hull", "rect": rect, "health": rect.size.x * rect.size.y * density * 0.05, "max_health": rect.size.x * rect.size.y * density * 0.05, "density": density, "heat": 0.0, "em_emission": 0.0, "switchable": false}

func _fixture_array() -> Array:
	# A minimal, self-contained fixture with one of everything the op table
	# needs to exercise: a laser (swap/tune target), a hull piece (remove
	# target + bridge), and a second hull piece so removal still leaves the
	# rest connected. hp_laser's rect is 5x5 -- deliberately the SAME size as
	# laser/LIGHT/STANDARD (so a same-mark-family swap matches) but DIFFERENT
	# from laser/LIGHT/HEAVY's 5x8 (so item 2's mismatch case is real).
	return [
		_hull("hull_a", Rect2(0, -5, 10, 10)),
		_hull("hull_b", Rect2(10, -5, 10, 10)),
		{"id": "hp_laser", "type": "weapons", "rect": Rect2(20, -2.5, 5, 5), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "cooldown": 0.0, "cooldown_max": 1.0, "range": 3000.0, "damage": 250.0, "heading": 0.0, "arc_width": PI / 3.0},
	]

func _fixture_array_wide_laser() -> Array:
	# Same fixture, but hp_laser's rect is 5x8 -- matches laser/LIGHT/HEAVY's
	# catalog size exactly, so item 1 (op mechanics) can exercise a genuinely
	# successful same-size swap (as opposed to item 2, which specifically
	# wants a mismatch). damage is deliberately NOT 480 (HEAVY's catalog
	# value) so the swap's "stats actually changed" assertion is meaningful.
	return [
		_hull("hull_a", Rect2(0, -5, 10, 10)),
		_hull("hull_b", Rect2(10, -5, 10, 10)),
		{"id": "hp_laser", "type": "weapons", "rect": Rect2(20, -4, 5, 8), "health": 50.0, "max_health": 50.0, "density": 20.0, "heat": 0.0, "base_em_emission": 0.0, "em_emission": 0.0, "switchable": true, "powered_on": true,
			"weapon_type": "laser", "cooldown": 0.0, "cooldown_max": 1.0, "range": 3000.0, "damage": 50.0, "heading": 0.0, "arc_width": PI / 3.0},
	]

# ---------------------------------------------------------------------------
# Item 1: Op mechanics -- swap preserves rect exactly while changing stats;
# tune changes only the named field (full dict-diff); remove drops exactly
# one component; apply never mutates the input array.
# ---------------------------------------------------------------------------

func _test_op_mechanics() -> void:
	var base := _fixture_array()
	var base_copy_for_mutation_check: Array = base.duplicate(true)

	# --- swap: same rect (position AND size), different stats. Uses the
	# wide-laser fixture (5x8, matching laser/LIGHT/HEAVY's catalog size)
	# specifically so this swap succeeds -- item 2 covers the mismatch case. ---
	var swap_base := _fixture_array_wide_laser()
	var swap_base_copy_for_mutation_check: Array = swap_base.duplicate(true)
	var swap_result: Array = Variants.apply(swap_base, [
		{"swap": "hp_laser", "part": ["laser", ComponentSpec.Tier.LIGHT, Parts.Mark.HEAVY]},
	])
	_assert(not swap_result.is_empty(), "Item 1: swap on a valid same-size target should succeed")
	var orig_swap_laser: Dictionary = {}
	for c in swap_base:
		if c["id"] == "hp_laser":
			orig_swap_laser = c
	var new_laser: Dictionary = {}
	for c in swap_result:
		if c["id"] == "hp_laser":
			new_laser = c
	_assert(not new_laser.is_empty(), "Item 1: swapped component should still be present under the same id")
	if not new_laser.is_empty() and not orig_swap_laser.is_empty():
		var orig_rect: Rect2 = orig_swap_laser["rect"]
		var new_rect: Rect2 = new_laser["rect"]
		_assert(new_rect.position == orig_rect.position, "Item 1: swap must preserve rect.position exactly, got %s expected %s" % [new_rect.position, orig_rect.position])
		_assert(new_rect.size == orig_rect.size, "Item 1: swap must preserve rect.size exactly (same footprint), got %s expected %s" % [new_rect.size, orig_rect.size])
		_assert(new_laser["damage"] != orig_swap_laser["damage"], "Item 1: swap to a HEAVY mark should change stats (damage), got same value %s" % new_laser["damage"])
	_assert(_arrays_deep_equal(swap_base, swap_base_copy_for_mutation_check), "Item 1: apply() must never mutate its `base` input array -- swap_base changed after the swap call above")

	# --- tune: full dict-diff -- ONLY the named field changes. ---
	var orig_laser: Dictionary = {}
	for c in base:
		if c["id"] == "hp_laser":
			orig_laser = c
	var tune_result: Array = Variants.apply(base, [
		{"tune": "hp_laser", "field": "cooldown_max", "value": 0.15},
	])
	var tuned_laser: Dictionary = {}
	for c in tune_result:
		if c["id"] == "hp_laser":
			tuned_laser = c
	_assert(is_equal_approx(tuned_laser.get("cooldown_max", -1.0), 0.15), "Item 1: tune should set the named field, got %s" % tuned_laser.get("cooldown_max", -1.0))
	var diff_keys: Array = []
	for key in orig_laser.keys():
		var same := tuned_laser.has(key) and _values_equal(orig_laser[key], tuned_laser[key])
		if not same:
			diff_keys.append(key)
	_assert(diff_keys == ["cooldown_max"], "Item 1: tune must change ONLY the named field -- diff was %s" % str(diff_keys))

	# --- remove: drops exactly one component. ---
	var remove_result: Array = Variants.apply(base, [{"remove": "hull_b"}])
	_assert(remove_result.size() == base.size() - 1, "Item 1: remove should drop exactly one component, base had %d, result has %d" % [base.size(), remove_result.size()])
	var still_has_hull_b: bool = remove_result.any(func(c): return c["id"] == "hull_b")
	_assert(not still_has_hull_b, "Item 1: removed component id should no longer be present")

	# --- apply never mutates the input array (deep-copy contract). ---
	_assert(_arrays_deep_equal(base, base_copy_for_mutation_check), "Item 1: apply() must never mutate its `base` input array -- base changed after swap/tune/remove calls above")

func _values_equal(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
			return is_equal_approx(float(a), float(b))
	return a == b

func _arrays_deep_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var da: Dictionary = a[i]
		var db: Dictionary = b[i]
		if da.keys().size() != db.keys().size():
			return false
		for key in da.keys():
			if not db.has(key) or not _values_equal(da[key], db[key]):
				return false
	return true

# ---------------------------------------------------------------------------
# Item 2: Size-mismatch swap rejected -- swapping a 5x5 laser slot with a
# HEAVY 5x8 part must raise/return an error, not silently resize. Contract
# picked (documented in ship_variants.gd): apply() push_errors and returns []
# (empty array) on any size mismatch.
# ---------------------------------------------------------------------------

func _test_size_mismatch_swap_rejected() -> void:
	var base := _fixture_array()  # hp_laser is a 5x5 rect (LIGHT/STANDARD-shaped fixture)
	# laser/LIGHT/HEAVY catalog size is 5x8 -- mismatched vs the fixture's 5x5.
	var result: Array = Variants.apply(base, [
		{"swap": "hp_laser", "part": ["laser", ComponentSpec.Tier.LIGHT, Parts.Mark.HEAVY]},
	])
	# NOTE: this fixture's hp_laser rect is 5x5 (same as LIGHT/STANDARD), so a
	# swap to LIGHT/HEAVY (5x8) IS a mismatch -- verify the sizes really do
	# differ (guards this test against a future catalog change silently
	# aligning the sizes and making the assertion vacuous).
	var heavy_size: Vector2 = Parts.make("laser", ComponentSpec.Tier.LIGHT, Parts.Mark.HEAVY, Vector2.ZERO)["rect"].size
	_assert(heavy_size != Vector2(5, 5), "Item 2 (self-check): laser/LIGHT/HEAVY size %s must differ from the fixture's 5x5 for this test to be meaningful" % heavy_size)
	_assert(result.is_empty(), "Item 2: size-mismatched swap must return an empty array (hard error), got %d component(s)" % result.size())

	# Same-size swap (STANDARD -> STANDARD, same family/tier) must still work,
	# proving the rejection above is specifically about size, not swaps in
	# general.
	var ok_result: Array = Variants.apply(base, [
		{"swap": "hp_laser", "part": ["laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD]},
	])
	_assert(not ok_result.is_empty(), "Item 2: a same-size swap (LIGHT/STANDARD, 5x5) must succeed")

# ---------------------------------------------------------------------------
# Item 3: classify() correctness -- swap/tune -> STATS_ONLY; any op list
# containing remove -> GEOMETRY.
# ---------------------------------------------------------------------------

func _test_classify_correctness() -> void:
	var swap_only: Array = [{"swap": "a", "part": ["laser", ComponentSpec.Tier.LIGHT, Parts.Mark.STANDARD]}]
	var tune_only: Array = [{"tune": "a", "field": "damage", "value": 1.0}]
	var swap_and_tune: Array = swap_only + tune_only
	var with_remove: Array = swap_and_tune + [{"remove": "b"}]
	var remove_only: Array = [{"remove": "a"}]

	_assert(Variants.classify(swap_only) == Variants.DeltaClass.STATS_ONLY, "Item 3: swap-only ops should classify STATS_ONLY")
	_assert(Variants.classify(tune_only) == Variants.DeltaClass.STATS_ONLY, "Item 3: tune-only ops should classify STATS_ONLY")
	_assert(Variants.classify(swap_and_tune) == Variants.DeltaClass.STATS_ONLY, "Item 3: swap+tune ops should classify STATS_ONLY")
	_assert(Variants.classify(with_remove) == Variants.DeltaClass.GEOMETRY, "Item 3: any op list containing a remove should classify GEOMETRY")
	_assert(Variants.classify(remove_only) == Variants.DeltaClass.GEOMETRY, "Item 3: remove-only ops should classify GEOMETRY")

# ---------------------------------------------------------------------------
# Item 4: GEOMETRY deltas are still caught by the validator -- removing a
# bridging hull piece from a minimal ship must surface as a disconnect error.
# Proves variants get no validation bypass.
# ---------------------------------------------------------------------------

func _test_geometry_deltas_caught_by_validator() -> void:
	# Three hull pieces in a row: a - b - c. Removing the middle bridge piece
	# disconnects a from c.
	var base: Array = [
		_hull("hull_a", Rect2(0, 0, 10, 10)),
		_hull("hull_bridge", Rect2(10, 0, 10, 10)),
		_hull("hull_c", Rect2(20, 0, 10, 10)),
		{"id": "reactor_core", "type": "reactor", "rect": Rect2(0, 10, 10, 10), "health": 50.0, "max_health": 50.0, "density": 20.0, "power_rating": 50.0},
	]
	var ops: Array = [{"remove": "hull_bridge"}]
	_assert(Variants.classify(ops) == Variants.DeltaClass.GEOMETRY, "Item 4 (self-check): removing a hull piece should classify GEOMETRY")

	var result: Array = Variants.apply(base, ops)
	_assert(result.size() == base.size() - 1, "Item 4: apply should drop exactly the bridge piece")

	var ship := Ship.new()
	ship.ship_tier = ComponentSpec.Tier.LIGHT
	ship.max_speed = 2000.0
	ship.max_omega = 4.0
	ship.ship_components = result
	var r: Dictionary = ShipDesignValidator.validate(ship)

	var has_disconnect_error: bool = r["violations"].any(func(v): return (v["component_id"] == "hull_a" or v["component_id"] == "hull_c") and v["severity"] == "error")
	if not has_disconnect_error:
		print("Item 4: violations were:")
		for v in r["violations"]:
			print("  ", v)
	_assert(has_disconnect_error, "Item 4: removing the bridging hull piece should surface a disconnect error naming hull_a or hull_c")
	_assert(r["ok"] == false, "Item 4: a ship with a disconnect error should validate ok=false")

# ---------------------------------------------------------------------------
# Item 5: design() extraction fidelity -- Base.design() multiset-equals the
# pre-refactor authored array. Pins a count + spot fields per base ship; the
# full behavioral guard is test_ship_designs staying green.
# ---------------------------------------------------------------------------

func _test_design_extraction_fidelity() -> void:
	# --- LightAttackCraft: 12 components, spot-check a few authored fields
	# from the pre-refactor literal (see light_attack_craft.gd history). ---
	var lac_design: Array = LightAttackCraft.design()
	_assert(lac_design.size() == 12, "Item 5: LightAttackCraft.design() should have 12 components, got %d" % lac_design.size())

	var lac_laser: Dictionary = {}
	var lac_engine: Dictionary = {}
	for c in lac_design:
		if c["id"] == "hp_fwd_laser":
			lac_laser = c
		if c["id"] == "engine_main":
			lac_engine = c
	_assert(not lac_laser.is_empty(), "Item 5: LAC design() should contain hp_fwd_laser")
	_assert(is_equal_approx(lac_laser.get("damage", -1.0), 250.0), "Item 5: LAC hp_fwd_laser damage should be 250.0 (authored value), got %s" % lac_laser.get("damage", -1.0))
	_assert(is_equal_approx(lac_laser.get("cooldown_max", -1.0), 0.8), "Item 5: LAC hp_fwd_laser cooldown_max should be 0.8 (authored value), got %s" % lac_laser.get("cooldown_max", -1.0))
	_assert(not lac_engine.is_empty(), "Item 5: LAC design() should contain engine_main")
	_assert(is_equal_approx(lac_engine.get("thrust_rating", -1.0), 2500.0), "Item 5: LAC engine_main thrust_rating should be 2500.0 (authored value), got %s" % lac_engine.get("thrust_rating", -1.0))
	var lac_engine_rect: Rect2 = lac_engine["rect"]
	_assert(lac_engine_rect == Rect2(-15, -5, 10, 10), "Item 5: LAC engine_main rect should be Rect2(-15,-5,10,10) (authored value), got %s" % lac_engine_rect)

	# design() must return a fresh array each call (no shared-mutable-state
	# leak across variants) -- mutating one call's result must not affect
	# another's.
	var lac_design_2: Array = LightAttackCraft.design()
	lac_design[0]["health"] = -999.0
	_assert(not is_equal_approx(lac_design_2[0]["health"], -999.0), "Item 5: LightAttackCraft.design() must return an independent array each call")

	# --- CargoShuttle: 8 components, spot-check. ---
	var shuttle_design: Array = CargoShuttle.design()
	_assert(shuttle_design.size() == 9, "Item 5: CargoShuttle.design() should have 9 components, got %d" % shuttle_design.size())

	var shuttle_reactor: Dictionary = {}
	var shuttle_hull_port: Dictionary = {}
	for c in shuttle_design:
		if c["id"] == "reactor_core":
			shuttle_reactor = c
		if c["id"] == "hull_port":
			shuttle_hull_port = c
	_assert(not shuttle_reactor.is_empty(), "Item 5: CargoShuttle design() should contain reactor_core")
	_assert(is_equal_approx(shuttle_reactor.get("power_rating", -1.0), 50.0), "Item 5: CargoShuttle reactor_core power_rating should be 50.0 (authored value), got %s" % shuttle_reactor.get("power_rating", -1.0))
	_assert(not shuttle_hull_port.is_empty(), "Item 5: CargoShuttle design() should contain hull_port")
	var shuttle_hull_port_rect: Rect2 = shuttle_hull_port["rect"]
	_assert(shuttle_hull_port_rect == Rect2(-15, -15, 30, 10), "Item 5: CargoShuttle hull_port rect should be Rect2(-15,-15,30,10) (authored value), got %s" % shuttle_hull_port_rect)

	var shuttle_design_2: Array = CargoShuttle.design()
	shuttle_design[0]["health"] = -999.0
	_assert(not is_equal_approx(shuttle_design_2[0]["health"], -999.0), "Item 5: CargoShuttle.design() must return an independent array each call")

# ---------------------------------------------------------------------------
# Item 6: Pirate LAC gates -- validator ok==true; expected layout warnings
# (the removed plate surfaces as a coverage warning); thrust_rating strictly
# > base LAC's; mass <= base (plate removed); derived accel strictly > base.
# ---------------------------------------------------------------------------

func _test_pirate_lac_gates() -> void:
	var base := LightAttackCraft.new()
	var variant := PirateLAC.new()

	var base_r: Dictionary = ShipDesignValidator.validate(base)
	var variant_r: Dictionary = ShipDesignValidator.validate(variant)
	_assert(base_r["ok"] == true, "Item 6 (self-check): base LAC should validate ok=true")
	_assert(variant_r["ok"] == true, "Item 6: Pirate LAC should validate ok=true, got false. Violations: %s" % str(variant_r["violations"]))

	# The removed plate (hull_fwd_port) should surface as a hull_coverage
	# warning on at least one neighboring active component whose flank it used
	# to cover.
	var coverage_warnings: Array = variant_r["violations"].filter(func(v): return v["field"] == "hull_coverage")
	if coverage_warnings.is_empty():
		print("Item 6: Pirate LAC violations were:")
		for v in variant_r["violations"]:
			print("  ", v)
	_assert(not coverage_warnings.is_empty(), "Item 6: removing hull_fwd_port should surface at least one hull_coverage warning")

	var base_thrust: float = base.get_ship_max_thrust()
	var variant_thrust: float = variant.get_ship_max_thrust()
	_assert(variant_thrust > base_thrust, "Item 6: Pirate LAC thrust_rating (%s) must be strictly greater than base LAC's (%s)" % [variant_thrust, base_thrust])

	var base_mass: float = base.get_ship_mass()
	var variant_mass: float = variant.get_ship_mass()
	_assert(variant_mass <= base_mass, "Item 6: Pirate LAC mass (%s) must be <= base LAC's mass (%s) (a plate was removed)" % [variant_mass, base_mass])

	var base_accel: float = base_thrust / base_mass if base_mass > 0.0 else 0.0
	var variant_accel: float = variant_thrust / variant_mass if variant_mass > 0.0 else 0.0
	_assert(variant_accel > base_accel, "Item 6: Pirate LAC derived accel (%s) must be strictly greater than base LAC's (%s) -- must actually BE faster" % [variant_accel, base_accel])

	# Laser cooldown tune landed.
	var laser: Dictionary = variant.get_component("hp_fwd_laser")
	_assert(not laser.is_empty(), "Item 6: Pirate LAC should still have hp_fwd_laser")
	_assert(is_equal_approx(laser.get("cooldown_max", -1.0), 0.6), "Item 6: Pirate LAC hp_fwd_laser cooldown_max should be tuned to 0.6, got %s" % laser.get("cooldown_max", -1.0))

	# Removed plate is actually gone.
	_assert(variant.get_component("hull_fwd_port").is_empty(), "Item 6: Pirate LAC should NOT have hull_fwd_port (removed)")

	# Band-cleanliness: a variant's tunes must stay inside the spec bands --
	# out-of-band tunes defeat the catalog discipline (M24 validation caught
	# the ore shuttle's comms tuned below the LIGHT band floor; this pins it
	# for both variants). Only the two M23 layout-check fields are expected.
	_assert_only_layout_warnings(variant_r, "Item 6", "Pirate LAC")

# ---------------------------------------------------------------------------
# Item 7: Ore shuttle gates -- validator ok; unarmed still; mass > base
# shuttle (heavier plating); dockable flag preserved.
# ---------------------------------------------------------------------------

func _test_ore_shuttle_gates() -> void:
	var base := CargoShuttle.new()
	var variant := OreShuttle.new()

	var variant_r: Dictionary = ShipDesignValidator.validate(variant)
	_assert(variant_r["ok"] == true, "Item 7: Ore Shuttle should validate ok=true, got false. Violations: %s" % str(variant_r["violations"]))

	var weapons: Array = variant.get_components_by_type("weapons")
	_assert(weapons.is_empty(), "Item 7: Ore Shuttle should still be unarmed, found %d weapon component(s)" % weapons.size())

	var base_mass: float = base.get_ship_mass()
	var variant_mass: float = variant.get_ship_mass()
	_assert(variant_mass > base_mass, "Item 7: Ore Shuttle mass (%s) must be strictly greater than base shuttle's (%s) (heavier plating)" % [variant_mass, base_mass])

	_assert(variant.dockable == true, "Item 7: Ore Shuttle dockable flag must be preserved (true)")

	# Band-cleanliness (see Item 6's note) -- the ore shuttle's tunes must not
	# leave any spec band.
	_assert_only_layout_warnings(variant_r, "Item 7", "Ore Shuttle")

# A variant's violation list may contain ONLY the two M23 layout-check fields
# (frozen in test_ship_designs.gd's ratchet) -- any other field means a tune
# left a spec band or broke a structural/handling/pd rule.
func _assert_only_layout_warnings(result: Dictionary, item: String, label: String) -> void:
	var non_layout: Array = result["violations"].filter(func(v): return v["field"] != "hull_coverage" and v["field"] != "active_surface")
	if not non_layout.is_empty():
		print(item, ": ", label, " has non-layout violations:")
		for v in non_layout:
			print("  ", v)
	_assert(non_layout.is_empty(), "%s: %s must have no violations besides layout warnings, got %d" % [item, label, non_layout.size()])

# ---------------------------------------------------------------------------
# Item 9: Auto-enumeration -- ShipCatalog.VARIANTS non-empty; test_ship_designs
# demonstrably iterates it (assert its ship count grew by the variant count).
# ---------------------------------------------------------------------------

func _test_auto_enumeration() -> void:
	_assert(not ShipCatalog.VARIANTS.is_empty(), "Item 9: ShipCatalog.VARIANTS should be non-empty")
	# M24 shipped 2 (Pirate LAC, Ore Shuttle); M50 added 2 more pirate hulls
	# (Pirate Ore Shuttle, Armed Pinnace -- implementation_plans/
	# m50_pirate_tree_design.md), same registration surface, same auto-
	# enumeration proof below.
	_assert(ShipCatalog.VARIANTS.size() == 4, "Item 9: ShipCatalog.VARIANTS should have 4 entries as of M50, got %d" % ShipCatalog.VARIANTS.size())

	# Demonstrate test_ship_designs.gd actually iterates VARIANTS: every
	# variant must appear in its EXPECTED_LAYOUT_WARNINGS registry (Case 6's
	# ratchet dict), which is this milestone's proof that the ship-count grew
	# by the variant count -- test_ship_designs.gd asserts this file-for-file,
	# this test just confirms the registration surface it depends on exists.
	for entry in ShipCatalog.VARIANTS:
		_assert(entry.has("name") and entry.has("script"), "Item 9: each VARIANTS entry needs 'name' and 'script' keys, got %s" % str(entry))
		_assert(entry.has("role_key"), "Item 9: each VARIANTS entry needs a 'role_key' (promotion-rule documentation), got %s" % str(entry))
		var ship = entry["script"].new()
		_assert(ship != null, "Item 9: VARIANTS entry '%s' script should instantiate" % entry.get("name", "<unnamed>"))

# ---------------------------------------------------------------------------
# Item 8: Spawn smoke -- instantiate both variants headless, run 60 physics
# frames, zero script errors (proves _ready() normalization + AI attach paths
# accept variant-built ships).
# ---------------------------------------------------------------------------

func _start_spawn_smoke() -> void:
	var pirate := PirateLAC.new()
	pirate.name = "SmokePirateLAC"
	pirate.owner_id = 901
	pirate.position = Vector2(1000, 0)

	var ore := OreShuttle.new()
	ore.name = "SmokeOreShuttle"
	ore.owner_id = 902
	ore.position = Vector2(-1000, 0)

	smoke_ships = [pirate, ore]
	for s in smoke_ships:
		main_node.add_child(s)

	smoke_started = true

func _physics_process(_delta: float) -> void:
	if finished or not smoke_started or smoke_ships.is_empty():
		return

	smoke_frames += 1
	if smoke_frames >= SMOKE_FRAMES_REQUIRED:
		for s in smoke_ships:
			_assert(is_finite(s.position.x) and is_finite(s.position.y), "Item 8: %s position must stay finite after %d physics frames" % [s.name, SMOKE_FRAMES_REQUIRED])
			_assert(is_finite(s.current_heat), "Item 8: %s current_heat must stay finite after %d physics frames" % [s.name, SMOKE_FRAMES_REQUIRED])
			_assert(not s.is_dead, "Item 8: %s must not have died from spawning alone after %d physics frames" % [s.name, SMOKE_FRAMES_REQUIRED])

		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_ship_variants <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_ship_variants <<<")
		get_tree().quit(1)
