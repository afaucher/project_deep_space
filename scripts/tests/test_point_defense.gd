extends Node

const Ship = preload("res://scripts/ship.gd")
const Missile = preload("res://scripts/missile.gd")

var f_ship
var e_missile

func setup(main) -> void:
	print("Test test_point_defense initialized.")
	
	# Add Friendly Ship
	f_ship = Ship.new()
	f_ship.name = "FriendlyShip"
	f_ship.owner_id = 1
	f_ship.iff_tags = ["TEAM_A"]
	f_ship.position = Vector2(0, 0)
	main.add_child(f_ship)
	# Target ship (Hostile)
	e_missile = Missile.new()
	e_missile.name = "Missile_2"
	e_missile.owner_id = 2
	e_missile.iff_tags = ["TEAM_B"]
	e_missile.position = Vector2(0, -800)
	e_missile.rotation = PI / 2.0 # Point DOWN at the friendly ship
	
	main.add_child(e_missile)
	
	# Set velocity on missile since it's a RigidBody2D
	e_missile.linear_velocity = Vector2(0, 500)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(e_missile) or e_missile.is_queued_for_deletion() or e_missile.is_dead:
		print(">>> [TEST PASSED] Point defense destroyed missile.")
		get_tree().quit(0)
		
	if is_instance_valid(e_missile) and e_missile.position.distance_to(f_ship.position) < 50:
		print(">>> [TEST FAILED] Missile hit the ship.")
		get_tree().quit(1)
		
	if Engine.get_physics_frames() == 300:
		print(">>> [TEST FAILED] Timeout. Missile Pos: ", e_missile.position)
		get_tree().quit(1)
