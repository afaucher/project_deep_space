extends Node

# M52 playtest fix -- overheat disengage + death-cause attribution (calling
# session, 2026-07-22). Two related fixes to the "pirates died right after
# hailing me, no collision, no console line" investigation:
#
# 1. ShouldDisengageLeaf now also fires SUCCESS (flee) once current_heat/
#    max_heat crosses DISENGAGE_HEAT_FRACTION (0.9), the same "hurt, so run"
#    logic already applied to health -- a ship that's about to take direct
#    reactor damage from its own heat can't fight effectively like that.
#    Complements job_steps.gd's _thermal_derate (a local softening inside
#    the M52c pacing math specifically): this is the general backstop for
#    ANY sustained-heat cause, not just two pirates fighting each other's
#    avoidance.
# 2. The reactor-overheat health drain (ship.gd's current_heat >= max_heat
#    check, separate from take_damage() entirely) now populates last_
#    damage_attacker_name/iid ("unattributed thermal") and prints a
#    [Damage]-style console line the first tick it engages -- previously
#    this path was invisible to every cross-ship-visible log (pirate_guild.
#    gd's "killed by" line, the shared console), even though the ship's own
#    eng_log DID quietly record "Thermal overload" (useless for an NPC
#    nobody's looking at).
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_overheat_disengage

const ShouldDisengageLeaf = preload("res://scripts/ai/leaves/should_disengage_leaf.gd")
const ArmedPinnace = preload("res://scripts/ships/armed_pinnace.gd")

var main_node: Node = null
var failures: Array = []
var spawned: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

func _make_ship(script, ship_name: String, owner: int, pos: Vector2, tags: Array) -> Node:
	var s = script.new()
	s.name = ship_name
	s.owner_id = owner
	s.iff_tags = tags
	s.position = pos
	main_node.add_child(s)
	spawned.append(s)
	return s

func setup(main) -> void:
	main_node = main
	print("Starting Overheat Disengage + Attribution Tests")

	_test_disengage_fires_on_critical_heat()
	_test_disengage_stays_failure_below_threshold()
	await _test_self_cooked_death_is_attributed()

	_finish()

# ---------------------------------------------------------------------------
# ShouldDisengageLeaf fires on heat alone, full health.
# ---------------------------------------------------------------------------
func _test_disengage_fires_on_critical_heat() -> void:
	print("\n--- ShouldDisengage: fires on critical heat, health untouched ---")
	var ship = _make_ship(ArmedPinnace, "HotShip", 800, Vector2.ZERO, ["TEAM_HOT"])
	ship.current_heat = ship.max_heat * (ShouldDisengageLeaf.DISENGAGE_HEAT_FRACTION + 0.02)

	var leaf := ShouldDisengageLeaf.new()
	var result: int = leaf.tick(ship, null)

	_assert(result == leaf.SUCCESS, "disengage fires once heat crosses DISENGAGE_HEAT_FRACTION (%.2f), even at full health"
		% ShouldDisengageLeaf.DISENGAGE_HEAT_FRACTION)

	_free_all()

# ---------------------------------------------------------------------------
# Below the threshold, full health -- no disengage.
# ---------------------------------------------------------------------------
func _test_disengage_stays_failure_below_threshold() -> void:
	print("\n--- ShouldDisengage: stays FAILURE below the heat threshold ---")
	var ship = _make_ship(ArmedPinnace, "WarmShip", 801, Vector2.ZERO, ["TEAM_WARM"])
	ship.current_heat = ship.max_heat * (ShouldDisengageLeaf.DISENGAGE_HEAT_FRACTION - 0.05)

	var leaf := ShouldDisengageLeaf.new()
	var result: int = leaf.tick(ship, null)

	_assert(result == leaf.FAILURE, "no disengage below the threshold, full health")

	_free_all()

# ---------------------------------------------------------------------------
# A ship whose heat is forced to max_heat and left there cooks its own
# reactor via ship.gd's periodic check (not take_damage()) -- confirms the
# death gets attributed ("unattributed thermal") and dies, instead of
# vanishing with last_damage_attacker_name left blank/stale.
# ---------------------------------------------------------------------------
func _test_self_cooked_death_is_attributed() -> void:
	print("\n--- self-cooked reactor death: attributed, not a silent mystery ---")
	var ship = _make_ship(ArmedPinnace, "CookingShip", 802, Vector2.ZERO, ["TEAM_COOK"])
	# Force-peg heat every tick (cheaper/more deterministic than actually
	# driving throttle high enough via movement commands -- this test is
	# about the DEATH-CAUSE PLUMBING, not re-proving heat generation itself,
	# which test_multi_pirate_thermal.gd already covers).
	var reactor_hp_before := 0.0
	for c in ship.ship_components:
		if c.get("type", "") == "reactor":
			reactor_hp_before = c.get("health", 0.0)
	_assert(reactor_hp_before > 0.0, "setup sanity: ArmedPinnace has a reactor with positive health")

	var attributed := false
	var died := false
	for i in range(3600): # up to 60s -- OVERHEAT_DAMAGE_RATE is a slow drain
		# Comfortably ABOVE max_heat, not exactly at it -- this tick's own net
		# heat_gen-minus-dissipation (usually negative while idle) would
		# otherwise pull an exact max_heat assignment back under the >=
		# max_heat check before it ever evaluates. The clampf(...,0.0,
		# max_heat) inside _physics_process pins the actual value to max_heat
		# either way; only the CHECK needs a cushion to survive one tick's
		# worth of dissipation.
		ship.current_heat = ship.max_heat + 1000.0
		await main_node.get_tree().physics_frame
		if ship.last_damage_attacker_name == "unattributed thermal":
			attributed = true
		if ship.is_dead:
			died = true
			break

	_assert(attributed, "last_damage_attacker_name reads 'unattributed thermal' once the reactor starts draining")
	_assert(ship.last_damage_attacker_iid == -1, "last_damage_attacker_iid is -1 (self-inflicted, not an external attacker)")
	_assert(died, "the ship actually died from the sustained self-cook (is_dead)")

	_free_all()

func _free_all() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()

func _finish() -> void:
	if failures.is_empty():
		print(">>> [TEST PASSED] test_overheat_disengage <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_overheat_disengage <<<")
		get_tree().quit(1)
