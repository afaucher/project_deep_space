extends Node

# Counter-detection -- "can that ship see ME?" -- as shown on the targeting
# computer (weapons_panel.gd's _update_counter_detection, via
# Utils.counter_detection).
#
# The point of this test is NOT that the arithmetic is right in isolation. It is
# that the READOUT AGREES WITH THE SIM. The estimate exists to tell a player
# whether ship.gd's passive-EM gate will fire on them, so any drift between the
# two makes the panel confidently wrong -- the worst possible failure for a
# stealth readout, because it is invisible until someone dies behind it.
# _test_agrees_with_sim_gate re-implements ship.gd's gate from ship.gd's OWN
# constants and demands the same verdict at every range.
#
# History: this replaced two raw numbers ("Our Emit" / "Det Limit") printed on
# every row of the tactical contacts list, where the player had to do the
# comparison themselves. That version hand-typed 10000/15 -- the two constants
# below -- and got the sub-floor case wrong; see _test_silent_hull.
#
# Run: ./Godot_v4.4.1-stable_win64.exe --headless --fixed-fps 60 --run-test test_counter_detection

const Ship = preload("res://scripts/ships/ship.gd")

var failures: Array = []

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)
	print(("  ok: " if condition else "  FAIL: "), msg)

# One omnidirectional emitter of a given strength. Type "reactor" deliberately:
# Utils.is_directional_emitter only treats sensors/weapons as cone emitters, so
# this exercises the rear-bias path every hull has rather than a special case.
func _hull(em: float) -> Array:
	return [{"type": "reactor", "em_emission": em}]

# The emission actually radiated toward an observer sitting at `their_pos`.
# Same call Utils.counter_detection makes internally -- used here to drive the
# independent re-implementation of the sim's gate below.
func _emit_toward(components: Array, my_rot: float, my_pos: Vector2, their_pos: Vector2) -> float:
	return Utils.get_directional_em(
		{"rot": my_rot, "em_emitters": components}, (my_pos - their_pos).angle())

func setup(_main) -> void:
	print("=== test_counter_detection: the stealth readout agrees with the sim ===")
	_test_agrees_with_sim_gate()
	_test_silent_hull()
	_test_bimodal_range()
	_test_bearing_matters()
	_finish()

# --- The one that matters ----------------------------------------------------
func _test_agrees_with_sim_gate() -> void:
	print("\n--- verdict matches ship.gd's passive-EM gate at every range ---")
	var comps: Array = _hull(60.0)
	var origin := Vector2.ZERO

	# Spread across the interesting region: well inside the falloff reference,
	# at it, and out past where a 60-unit emitter stops being audible.
	for dist in [0.0, 1000.0, 9999.0, 10000.0, 10001.0, 20000.0, 39999.0, 40000.0, 40001.0, 80000.0]:
		var their_pos := Vector2(dist, 0.0)
		var cd: Dictionary = Utils.counter_detection(comps, 0.0, origin, their_pos)

		# ship.gd's gate, rebuilt from ship.gd's own constants (_run_sensor_sweep):
		var emit: float = _emit_toward(comps, 0.0, origin, their_pos)
		var received: float = emit * (Ship.EM_FALLOFF_REFERENCE_DISTANCE
			/ maxf(Ship.EM_FALLOFF_REFERENCE_DISTANCE, dist))
		var sim_detects: bool = received >= Ship.PASSIVE_EM_NOISE_FLOOR

		_assert(cd["exposed"] == sim_detects,
			"at %.0f m the panel says exposed=%s and the sim gate says %s" % [
				dist, str(cd["exposed"]), str(sim_detects)])

# --- The bug the old inline version had --------------------------------------
func _test_silent_hull() -> void:
	print("\n--- a hull under the noise floor is invisible at ANY range ---")
	# Deliberately under PASSIVE_EM_NOISE_FLOOR even at full rear bias (1.5x):
	# 9.0 * 1.5 = 13.5 < 15.0, so no bearing can push it over.
	var quiet: Array = _hull(9.0)
	var cd_touching: Dictionary = Utils.counter_detection(quiet, 0.0, Vector2.ZERO, Vector2(1.0, 0.0))
	_assert(cd_touching["silent"], "a sub-floor hull reports SILENT, not merely CLEAR")
	_assert(not cd_touching["exposed"],
		"...and is NOT exposed even at 1 m -- inside the reference distance there is no falloff to save you")
	_assert(cd_touching["range"] == 0.0,
		"...and reports no detection range at all, rather than a confident wrong one")

	# This is exactly what the old per-row estimate got wrong: it computed
	# emit * (10000/15) unconditionally, so 9.0 read as "detectable to 6 km"
	# for a ship that could not be detected at any range whatsoever.
	var naive_range: float = 9.0 * (10000.0 / 15.0)
	_assert(naive_range > 0.0 and cd_touching["range"] == 0.0,
		"the naive formula would have claimed %s of exposure here" % Utils.format_dist(naive_range))

func _test_bimodal_range() -> void:
	print("\n--- above the floor, detection range is always >= the falloff reference ---")
	# No smooth ramp near zero: the falloff term is 1.0 inside REF, so the
	# instant a hull clears the floor it is audible to at least REF.
	for em in [15.0, 15.5, 20.0, 60.0, 300.0]:
		var cd: Dictionary = Utils.counter_detection(_hull(em), 0.0, Vector2.ZERO, Vector2(1.0e9, 0.0))
		_assert(not cd["silent"], "emit %.1f (at/above floor) is not SILENT" % em)
		_assert(cd["range"] >= Ship.EM_FALLOFF_REFERENCE_DISTANCE,
			"emit %.1f carries at least the reference distance (got %s)" % [em, Utils.format_dist(cd["range"])])

	_assert(not Utils.counter_detection(_hull(60.0), 0.0, Vector2.ZERO, Vector2(1.0e9, 0.0))["exposed"],
		"a contact a million km away is not reading us")

# --- Why the numbers stay on screen next to the verdict ----------------------
func _test_bearing_matters() -> void:
	print("\n--- emissions are directional, so the answer is a dial, not a fact ---")
	# Rear bias (ship.gd/Utils.get_directional_em_power) makes a hull louder
	# astern than ahead. Same ship, same range, two bearings.
	var comps: Array = _hull(60.0)
	var ahead: float = _emit_toward(comps, 0.0, Vector2.ZERO, Vector2(10000.0, 0.0))
	var astern: float = _emit_toward(comps, 0.0, Vector2.ZERO, Vector2(-10000.0, 0.0))
	_assert(ahead != astern,
		"the same hull radiates differently fore and aft (%.1f vs %.1f)" % [ahead, astern])

	var cd_ahead: Dictionary = Utils.counter_detection(comps, 0.0, Vector2.ZERO, Vector2(10000.0, 0.0))
	var cd_astern: Dictionary = Utils.counter_detection(comps, 0.0, Vector2.ZERO, Vector2(-10000.0, 0.0))
	_assert(cd_ahead["range"] != cd_astern["range"],
		"...so the counter-detection range differs by bearing, which is why the player can turn to change it")

func _finish() -> void:
	if failures.is_empty():
		print("\n>>> [TEST PASSED] test_counter_detection <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_counter_detection <<<")
		get_tree().quit(1)
