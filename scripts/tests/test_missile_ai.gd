extends Node

const Ship = preload("res://scripts/ship.gd")
const Missile = preload("res://scripts/missile.gd")

var f_missile
var e_ship

func setup(main) -> void:
	print("Test test_missile_ai initialized.")
	
	# Add Enemy Ship
	e_ship = Ship.new()
	e_ship.name = "EnemyShip"
	e_ship.owner_id = 2
	e_ship.iff_tags = ["TEAM_B"]
	e_ship.position = Vector2(0, -1000)
	main.add_child(e_ship)
	
	# Add Friendly Missile
	f_missile = Missile.new()
	f_missile.name = "FriendlyMissile"
	f_missile.owner_id = 1
	f_missile.iff_tags = ["TEAM_A"]
	f_missile.position = Vector2(0, 0)
	f_missile.rotation = -PI / 2.0 # Point UP at the enemy
	main.add_child(f_missile)
	
	# Add controller
	var MissileController = load("res://scripts/missile_controller.gd")
	var controller = MissileController.new()
	f_missile.add_child(controller)

func _physics_process(delta: float) -> void:
	if e_ship.is_dead or e_ship.health <= 0:
		print(">>> [TEST PASSED] Missile destroyed target.")
		get_tree().quit(0)
		
	if Engine.get_physics_frames() == 600:
		if is_instance_valid(f_missile):
			print("Missile Pos: ", f_missile.position)
			print("Target Ship Pos: ", e_ship.position)
			print(">>> [TEST FAILED] Missile failed to reach target in time.")
			get_tree().quit(1)
		else:
			print(">>> [TEST PASSED] Missile reached target and detonated.")
			get_tree().quit(0)
