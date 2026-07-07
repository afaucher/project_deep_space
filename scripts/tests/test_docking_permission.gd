extends Node

const SmallStation = preload("res://scripts/ships/small_station.gd")
const MediumStation = preload("res://scripts/ships/medium_station.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")

var main_node: Node = null
var failures: Array = []
var finished: bool = false
var t: float = 0.0

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		failures.append(msg)

func setup(main) -> void:
	main_node = main
	print("Starting Docking Permission (M32) Tests")
	
	# Test SmallStation (Open, no port_zone)
	var small = SmallStation.new()
	small.name = "Small"
	main_node.add_child(small)
	
	var shuttle1 = CargoShuttle.new()
	shuttle1.name = "Shuttle1"
	shuttle1.owner_id = 50
	main_node.add_child(shuttle1)
	
	var grant1 = small.issue_docking_grant(shuttle1)
	_assert(grant1 == null, "SmallStation should return null grant because it has no port_zone")
	
	# Test MediumStation (Controlled, has port_zone)
	var med = MediumStation.new()
	med.name = "Medium"
	main_node.add_child(med)
	
	var shuttle2 = CargoShuttle.new()
	shuttle2.name = "Shuttle2"
	shuttle2.owner_id = 51
	main_node.add_child(shuttle2)
	
	var grant2 = med.issue_docking_grant(shuttle2)
	_assert(grant2 != null, "MediumStation should return a valid grant")
	if grant2 != null:
		_assert(grant2.get("holder") == 51, "grant holder should match shuttle owner_id")
		_assert(typeof(grant2.get("slip_id")) == TYPE_STRING, "slip_id should be a String")
		_assert(grant2.get("slip_id") != "", "slip_id should not be empty for assigned policy")
		
		# Test that a second request returns null if there's only one bay and it's reserved
		var shuttle3 = CargoShuttle.new()
		shuttle3.name = "Shuttle3"
		shuttle3.owner_id = 52
		main_node.add_child(shuttle3)
		var grant3 = med.issue_docking_grant(shuttle3)
		_assert(grant3 == null, "Second grant should be denied because the only bay is reserved")

func _physics_process(delta: float) -> void:
	if finished: return
	t += delta
	# Finish after a few frames to allow _ready and setup to settle if needed
	if t > 0.05:
		_finalize()

func _finalize() -> void:
	if finished:
		return
	finished = true
	if failures.is_empty():
		print(">>> [TEST PASSED] test_docking_permission <<<")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("  FAIL: ", f)
		printerr(">>> [TEST FAILED] test_docking_permission <<<")
		get_tree().quit(1)
