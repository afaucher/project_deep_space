extends Node

const Ship = preload("res://scripts/ships/frigate.gd")

func setup(main) -> void:
	print("Test test_classifiers initialized.")
	
	var passed = 0
	var failed = 0
	
	# Test Cases: [Signature Dictionary, Observer IFF Tags, Expected Output]
	var test_cases = [
		[{"cross_section": 2.0, "heat": 10.0, "em_noise": 0.0, "iff_tags": ["TEAM_A"]}, ["TEAM_A"], "FRIENDLY ORDNANCE"],
		[{"cross_section": 2.0, "heat": 0.0, "em_noise": 10.0, "iff_tags": ["TEAM_B"]}, ["TEAM_A"], "INCOMING ORDNANCE"],
		[{"cross_section": 10.0, "heat": 15.0, "em_noise": 0.0, "iff_tags": ["TEAM_A"]}, ["TEAM_A"], "FRIENDLY VESSEL"],
		[{"cross_section": 200.0, "heat": 0.0, "em_noise": 500.0, "iff_tags": ["TEAM_C"]}, ["TEAM_A"], "UNIDENTIFIED VESSEL"],
		[{"cross_section": 250.0, "heat": 0.0, "em_noise": 0.0, "density": 90.0}, ["TEAM_A"], "WRECKAGE"],
		[{"cross_section": 250.0, "heat": 0.0, "em_noise": 0.0, "density": 800.0}, ["TEAM_A"], "ASTEROID"],
		[{"cross_section": 2.0, "heat": 0.0, "em_noise": 0.0, "density": 90.0}, ["TEAM_A"], "WRECKAGE"], # Cold missile wreckage
	]
	
	for i in range(test_cases.size()):
		var case = test_cases[i]
		var sig = case[0]
		var observer_tags = case[1]
		var expected = case[2]
		
		var result = Ship.classify_contact(sig, observer_tags)
		
		if result == expected:
			passed += 1
		else:
			failed += 1
			printerr("[TEST FAILED] Case ", i, " Expected: ", expected, " Got: ", result)
			
	if failed == 0:
		print("[TEST PASSED] test_classifiers. Passed ", passed, "/", test_cases.size(), " cases.")
		get_tree().quit(0)
	else:
		printerr("[TEST SUITE FAILED] ", failed, " tests failed.")
		get_tree().quit(1)
