extends Node

const FoamPhysics = preload("res://scripts/cluster/foam_physics.gd")

func setup(main) -> void:
	print("Starting automated test: test_foam_currents")
	test_foam_forces()
	print(">>> [TEST PASSED] test_foam_currents <<<")
	get_tree().quit(0)

func test_foam_forces() -> void:
	var mass = 100.0

	# Inside boundary: no force
	var res = FoamPhysics.calculate_forces(Vector2(0, 0), mass)
	assert(res.force == Vector2.ZERO, "Inside boundary should have no force")

	# Past East boundary -- M53a: BOUNDARY tracks the 2x cluster (250000 ->
	# 500000), so probe points scale with it (BOUNDARY + 1000, same margin).
	res = FoamPhysics.calculate_forces(Vector2(FoamPhysics.BOUNDARY + 1000.0, 0), mass)
	assert(res.force.x < 0, "Should push IN (West)")
	assert(res.force.y > 0, "Should push South towards South Pole")
	assert(res.teleport == false, "Should not teleport")

	# Past North boundary
	res = FoamPhysics.calculate_forces(Vector2(0, -(FoamPhysics.BOUNDARY + 1000.0)), mass)
	assert(res.force.y > 0, "Should push IN (South)")

	# Deep breach (teleport) -- BOUNDARY + 30000 depth, same margin as before
	# (30000 > TELEPORT_DEPTH's 20000, which did NOT change -- behavior tuning).
	res = FoamPhysics.calculate_forces(Vector2(FoamPhysics.BOUNDARY + 30000.0, 0), mass)
	assert(res.teleport == true, "Should teleport to pole")
	assert(res.new_pos.x == 0.0, "Should teleport to x=0")
	assert(abs(res.new_pos.y) == FoamPhysics.BOUNDARY - 5000.0, "Should teleport near pole")

