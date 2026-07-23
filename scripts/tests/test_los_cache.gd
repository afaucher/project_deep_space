extends Node

# M45b -- direct test of ship.gd's _has_los() same-tick LOS cache
# (implementation_plans/m45b_datalink_relay_perf.md "Tests" section).
#
# The datalink_relay regression suite (test_comms_relay.gd et al.) already
# exercises LOS gating end-to-end through the relay, so this test is
# deliberately narrow: it checks the CACHING MECHANISM itself, not relay
# behavior again.
#
# A and B use non-overlapping IFF tags so the real datalink_relay loop in
# ship.gd's own _physics_process never reaches its LOS check for this pair
# (its IFF gate short-circuits first) -- this isolates the test to direct
# calls against the helper, uncontaminated by incidental relay traffic
# populating the cache first.
#
# Verifies:
#   1. Correctness: _has_los() agrees with a direct, uncached raycast built
#      the same way the pre-M45b code did (both the clear-LOS and
#      blocked-LOS cases).
#   2. Shared cache key: after A asks first, B asking about the SAME pair
#      does not create a second cache entry -- _los_cache holds exactly one
#      entry, keyed by the unordered instance-id pair, and B reads the
#      value A computed rather than raycasting again.

const Ship = preload("res://scripts/ships/frigate.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var main_node: Node = null
var a = null
var b = null
var scenario_idx: int = -1
var scenario_frames: int = 0
const FRAMES_PER_SCENARIO := 30  # generous settle margin, same spirit as test_comms_relay
const NUM_SCENARIOS := 2
var failures: Array = []
var spawned: Array = []

func setup(main) -> void:
	main_node = main
	print("Test test_los_cache initialized.")
	_start_scenario(0)

func _manual_los(from_ship: Node, to_ship: Node) -> bool:
	# Mirrors the exact pre-M45b inline check in datalink_relay -- an
	# independent, uncached ground truth to compare _has_los() against.
	var space_state = from_ship.get_world_2d().direct_space_state
	var ray_query = PhysicsRayQueryParameters2D.create(from_ship.position, to_ship.position)
	ray_query.exclude = [from_ship]
	var ray_res = space_state.intersect_ray(ray_query)
	return not (ray_res and ray_res.collider != to_ship)

func _pair_key(x: Node, y: Node) -> String:
	var x_iid := x.get_instance_id()
	var y_iid := y.get_instance_id()
	return "%d:%d" % [min(x_iid, y_iid), max(x_iid, y_iid)]

func _cleanup() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	a = null
	b = null

func _start_scenario(idx: int) -> void:
	scenario_idx = idx
	scenario_frames = 0
	_cleanup()

	match idx:
		0:
			print("\n--- Scenario 1: clear LOS -- correctness + shared cache key ---")
			a = Ship.new()
			a.name = "LosA"
			a.iff_tags = ["TEST_LOS_A"]
			a.position = Vector2(0, 0)
			main_node.add_child(a)
			spawned.append(a)

			b = Ship.new()
			b.name = "LosB"
			b.iff_tags = ["TEST_LOS_B"]  # deliberately non-overlapping with A -- see header comment
			b.position = Vector2(10000, 0)
			main_node.add_child(b)
			spawned.append(b)
		1:
			print("\n--- Scenario 2: blocked LOS -- correctness with an obstacle ---")
			a = Ship.new()
			a.name = "LosA2"
			a.iff_tags = ["TEST_LOS_A"]
			a.position = Vector2(0, 0)
			main_node.add_child(a)
			spawned.append(a)

			b = Ship.new()
			b.name = "LosB2"
			b.iff_tags = ["TEST_LOS_B"]
			b.position = Vector2(10000, 0)
			main_node.add_child(b)
			spawned.append(b)

			var rock = Asteroid.new()
			rock.name = "LosRock"
			rock.position = Vector2(5000, 0)  # sits directly on the A-B line
			main_node.add_child(rock)
			spawned.append(rock)
		_:
			if failures.is_empty():
				print(">>> [TEST PASSED] test_los_cache <<<")
				get_tree().quit(0)
			else:
				for msg in failures:
					printerr("  FAIL: ", msg)
				printerr(">>> [TEST FAILED] test_los_cache <<<")
				get_tree().quit(1)

func _physics_process(_delta: float) -> void:
	if scenario_idx < 0 or scenario_idx >= NUM_SCENARIOS:
		return
	scenario_frames += 1
	if scenario_frames < FRAMES_PER_SCENARIO:
		return

	var ok := false
	match scenario_idx:
		0: ok = _check_scenario_0()
		1: ok = _check_scenario_1()

	if not ok:
		printerr(">>> [TEST FAILED] test_los_cache <<<")
		get_tree().quit(1)
		return

	_start_scenario(scenario_idx + 1)

func _check_scenario_0() -> bool:
	var expected: bool = _manual_los(a, b)
	var ok_result := true

	if not expected:
		printerr("  ASSERT FAILED: test setup bug -- manual raycast reports LOS blocked with no obstacle present.")
		return false

	var got_ab: bool = a._has_los(b)
	if got_ab != expected:
		printerr("  ASSERT FAILED: A._has_los(B) = ", got_ab, " expected ", expected)
		ok_result = false

	var key := _pair_key(a, b)
	if not Ship._los_cache.has(key):
		printerr("  ASSERT FAILED: pair key '", key, "' missing from Ship._los_cache after A asked.")
		ok_result = false
	elif Ship._los_cache[key] != expected:
		printerr("  ASSERT FAILED: Ship._los_cache[", key, "] = ", Ship._los_cache[key], " expected ", expected)
		ok_result = false

	var cache_size_after_a := Ship._los_cache.size()
	var got_ba: bool = b._has_los(a)
	if got_ba != expected:
		printerr("  ASSERT FAILED: B._has_los(A) = ", got_ba, " expected ", expected)
		ok_result = false
	if Ship._los_cache.size() != cache_size_after_a:
		printerr("  ASSERT FAILED: B asking about the same pair grew the cache (expected the SAME shared entry, not a new one) -- size ",
			cache_size_after_a, " -> ", Ship._los_cache.size())
		ok_result = false

	if ok_result:
		print("  [PASS] clear LOS: both directions match a direct raycast and share one normalized cache entry.")
	return ok_result

func _check_scenario_1() -> bool:
	var expected: bool = _manual_los(a, b)
	if expected:
		printerr("  ASSERT FAILED: test setup bug -- manual raycast reports LOS clear despite the blocking asteroid.")
		return false

	var got_ab: bool = a._has_los(b)
	var ok_result := true
	if got_ab != expected:
		printerr("  ASSERT FAILED: A._has_los(B) = ", got_ab, " expected ", expected, " (blocking asteroid on the line)")
		ok_result = false

	if ok_result:
		print("  [PASS] blocked LOS: _has_los correctly reports false, matching a direct raycast.")
	return ok_result
