extends Node

var drone_ship: Ship
var bouy: Bouy

func setup(main_node: Node) -> void:
	print("Starting E2E Test: Drone vs Bouy")
	
	# Create Drone
	drone_ship = Ship.new()
	drone_ship.name = "Ship_1"
	drone_ship.owner_id = 1
	drone_ship.iff_tags = ["TEAM_A"]
	drone_ship.position = Vector2(0, 0)
	drone_ship.rotation = 0.0 # Pointing right
	main_node.add_child(drone_ship)
	
	# Add Drone Controller
	var ai = AIDroneController.new()
	ai.name = "AIDroneController"
	drone_ship.add_child(ai)
	
	# Add Bouy
	bouy = Bouy.new()
	bouy.name = "Bouy_1"
	bouy.position = Vector2(5000.0, 0) # 5km away
	main_node.add_child(bouy)

var frames = 0
func _physics_process(delta: float) -> void:
	frames += 1
	# Run for up to 30 seconds (1800 frames at 60fps)
	if frames >= 1800:
		if bouy.is_dead or bouy.health <= 0:
			print(">>> [TEST PASSED] Bouy was destroyed by drone.")
			get_tree().quit(0)
		else:
			print(">>> [TEST FAILED] Bouy survived after 30 seconds. Health: ", bouy.health)
			get_tree().quit(1)
			
	# If buoy dies early, we win!
	if bouy.is_dead or bouy.health <= 0:
		print(">>> [TEST PASSED] Bouy was destroyed early at frame ", frames)
		get_tree().quit(0)
