extends SceneTree

const Ship = preload("res://scripts/ship.gd")

func _init() -> void:
	print("Test test_classifiers initialized.")
	
	var passed = 0
	var failed = 0
	
	# Test Cases: [Signature Dictionary, Observer ID, Expected Output]
	var test_cases = [
		[{"cross_section": 2.0, "heat": 10.0, "em_noise": 0.0, "owner_id": 1}, 1, "FRIENDLY ORDNANCE"],
		[{"cross_section": 2.0, "heat": 0.0, "em_noise": 10.0, "owner_id": 2}, 1, "INCOMING ORDNANCE"],
		[{"cross_section": 10.0, "heat": 10.0, "em_noise": 0.0, "owner_id": 1}, 1, "FRIENDLY VESSEL"],
		[{"cross_section": 200.0, "heat": 0.0, "em_noise": 500.0, "owner_id": 901}, 1, "UNIDENTIFIED VESSEL"],
		[{"cross_section": 250.0, "heat": 0.0, "em_noise": 0.0, "density": 90.0}, 1, "WRECKAGE"],
		[{"cross_section": 250.0, "heat": 0.0, "em_noise": 0.0, "density": 800.0}, 1, "ASTEROID"],
		[{"cross_section": 2.0, "heat": 0.0, "em_noise": 0.0, "density": 90.0}, 1, "WRECKAGE"], # Cold missile wreckage
	]
	
	for i in range(test_cases.size()):
		var case = test_cases[i]
		var sig = case[0]
		var observer_id = case[1]
		var expected = case[2]
		
		var result = Ship.classify_contact(sig, observer_id)
		
		if result == expected:
			passed += 1
		else:
			failed += 1
			printerr("[TEST FAILED] Case ", i, " Expected: ", expected, " Got: ", result)
			
	if failed == 0:
		print("[TEST PASSED] test_classifiers. Passed ", passed, "/", test_cases.size(), " cases.")
		quit(0)
	else:
		printerr("[TEST SUITE FAILED] ", failed, " tests failed.")
		quit(1)
