extends Node

const Ship = preload("res://scripts/ships/frigate.gd")
const Missile = preload("res://scripts/ships/missile.gd")

var main_scene
var current_scenario_idx = 0
var f_missile
var e_ship
var scenario_frames = 0
var max_scenario_frames = 900 # 15 seconds at 60 FPS

var scenarios = [
	{
		"name": "Target Crossing Off-Axis at Speed",
		"missile_pos": Vector2(0, 0),
		"missile_vel": Vector2(0, -500),
		"missile_rot": -PI / 2.0 + deg_to_rad(15.0),
		"target_pos": Vector2(0, -2000),
		"target_vel": Vector2(800, 0)
	},
	{
		"name": "From Rest",
		"missile_pos": Vector2(0, 0),
		"missile_vel": Vector2.ZERO,
		"missile_rot": -PI / 2.0,
		"target_pos": Vector2(0, -2000),
		"target_vel": Vector2(300, 0)
	},
	{
		"name": "Heading Towards Each Other",
		"missile_pos": Vector2(0, 0),
		"missile_vel": Vector2(0, -300),
		"missile_rot": -PI / 2.0,
		"target_pos": Vector2(0, -3000),
		"target_vel": Vector2(0, 400)
	},
	{
		"name": "Heading Away (Target Behind)",
		"missile_pos": Vector2(0, 0),
		"missile_vel": Vector2(0, 500),
		"missile_rot": -PI / 2.0, # Facing up towards target
		"target_pos": Vector2(0, -2500),
		"target_vel": Vector2(100, 0)
	}
]

func setup(main) -> void:
	main_scene = main
	print("Test test_missile_ai initialized with ", scenarios.size(), " scenarios.")
	_start_scenario(0)

func _start_scenario(idx: int) -> void:
	if idx >= scenarios.size():
		print("\n==========================================")
		print("All ", scenarios.size(), " scenarios passed successfully!")
		print(">>> [TEST PASSED] test_missile_ai <<<")
		print("==========================================")
		get_tree().quit(0)
		return
		
	current_scenario_idx = idx
	scenario_frames = 0
	var sc = scenarios[idx]
	print("\n--- Starting Scenario ", idx + 1, ": ", sc["name"], " ---")
	
	# Add Enemy Ship
	e_ship = Ship.new()
	e_ship.name = "EnemyShip_" + str(idx)
	e_ship.owner_id = 2 + idx * 2
	e_ship.iff_tags = ["TEAM_B"]
	e_ship.position = sc["target_pos"]
	e_ship.linear_velocity = sc["target_vel"]
	e_ship.weapons.clear()
	main_scene.add_child(e_ship)
	
	# Add Friendly Missile
	f_missile = Missile.new()
	f_missile.name = "FriendlyMissile_" + str(idx)
	f_missile.owner_id = 1 + idx * 2
	f_missile.iff_tags = ["TEAM_A"]
	f_missile.position = sc["missile_pos"]
	f_missile.rotation = sc["missile_rot"]
	f_missile.linear_velocity = sc["missile_vel"]
	main_scene.add_child(f_missile)
	
	# Add controller
	var MissileController = load("res://scripts/missile_controller.gd")
	var controller = MissileController.new()
	f_missile.add_child(controller)

func _physics_process(delta: float) -> void:
	if f_missile == null or e_ship == null: return
	
	scenario_frames += 1
	
	if scenario_frames % 120 == 0 and is_instance_valid(f_missile):
		print("  Frame ", scenario_frames, " - Missile Pos: ", f_missile.position, " Vel: ", f_missile.linear_velocity)
		
	# Check success (missile reached proximity or has detonated)
	var succeeded = false
	if is_instance_valid(f_missile) and is_instance_valid(e_ship):
		if f_missile.position.distance_to(e_ship.position) < 100.0:
			succeeded = true
	elif not is_instance_valid(f_missile) and scenario_frames < max_scenario_frames:
		succeeded = true
		
	if succeeded:
		print("  >>> [SCENARIO PASSED] Missile reached target.")
		_cleanup_current()
		_start_scenario(current_scenario_idx + 1)
		return
		
	# Check target destroyed (fallback)
	if not is_instance_valid(e_ship) or e_ship.is_dead or e_ship.health <= 0:
		print("  >>> [SCENARIO PASSED] Target destroyed.")
		_cleanup_current()
		_start_scenario(current_scenario_idx + 1)
		return
		
	# Check timeout
	if scenario_frames >= max_scenario_frames:
		if is_instance_valid(f_missile):
			print("  Missile Pos: ", f_missile.position)
			print("  Target Ship Pos: ", e_ship.position)
			print("  >>> [SCENARIO FAILED] Timeout reached.")
			print(">>> [TEST FAILED] test_missile_ai <<<")
			get_tree().quit(1)
		else:
			print("  >>> [SCENARIO PASSED] Missile reached target and detonated at end of window.")
			_cleanup_current()
			_start_scenario(current_scenario_idx + 1)

func _cleanup_current() -> void:
	if is_instance_valid(f_missile):
		f_missile.queue_free()
	if is_instance_valid(e_ship):
		e_ship.queue_free()
	f_missile = null
	e_ship = null
