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
	
	# Past East boundary
	res = FoamPhysics.calculate_forces(Vector2(251000, 0), mass)
	assert(res.force.x < 0, "Should push IN (West)")
	assert(res.force.y > 0, "Should push South towards South Pole")
	assert(res.teleport == false, "Should not teleport")
	
	# Past North boundary
	res = FoamPhysics.calculate_forces(Vector2(0, -251000), mass)
	assert(res.force.y > 0, "Should push IN (South)")
	
	# Deep breach (teleport)
	res = FoamPhysics.calculate_forces(Vector2(280000, 0), mass)
	assert(res.teleport == true, "Should teleport to pole")
	assert(res.new_pos.x == 0.0, "Should teleport to x=0")
	assert(abs(res.new_pos.y) == 245000.0, "Should teleport near pole")

