extends Node2D

@onready var ui_layer = $CanvasLayer
@onready var terminal_display = $CanvasLayer/TerminalDisplay
@onready var menu = $CanvasLayer/Menu

const Ship = preload("res://scripts/ship.gd")
const Asteroid = preload("res://scripts/asteroid.gd")

var is_host: bool = false
var players = {}
var asteroids = []

func _ready() -> void:
	# Check for automated tests
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--run-test" and i + 1 < args.size():
			_run_test(args[i+1])
			return
			
	SteamManager.connection_established.connect(_on_connection_established)
	
	# Menu UI hookups
	menu.get_node("HostButton").pressed.connect(_on_host_pressed)
	menu.get_node("JoinButton").pressed.connect(_on_join_pressed)
	menu.get_node("LocalTestButton").pressed.connect(_on_local_test_pressed)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _run_test(test_name: String) -> void:
	print("Starting automated test: ", test_name)
	is_host = true
	menu.hide()
	
	var test_script_path = "res://scripts/tests/" + test_name + ".gd"
	if ResourceLoader.exists(test_script_path):
		var test_script = load(test_script_path)
		var test_node = Node.new()
		test_node.set_script(test_script)
		add_child(test_node)
		# Pass reference to main so test can control players and simulation
		test_node.setup(self)
	else:
		printerr("[TEST FAILED] Test script not found: ", test_script_path)
		get_tree().quit(1)

func _on_host_pressed() -> void:
	SteamManager.create_lobby()

func _on_local_test_pressed() -> void:
	# Offline local singleplayer / testing mode
	_on_connection_established(true)

func _on_join_pressed() -> void:
	# For Phase 1 we can just join the first lobby we find, or we can request list
	# To keep it simple we'll request lobby list and join the first one
	SteamManager.lobby_match_list.connect(_auto_join_first_lobby, CONNECT_ONE_SHOT)
	SteamManager.list_lobbies()

func _auto_join_first_lobby(lobbies: Array) -> void:
	if lobbies.size() > 0:
		SteamManager.join_lobby(lobbies[0])
	else:
		print("No lobbies found to join.")

func _on_connection_established(hosting: bool) -> void:
	is_host = hosting
	menu.hide()
	terminal_display.show()
	
	if is_host:
		print("I am the authoritative host.")
		_spawn_asteroids()
		#_spawn_bouys() # Temporarily disabled
		_spawn_ship(multiplayer.get_unique_id())
	else:
		print("I am a client terminal.")

func _spawn_asteroids() -> void:
	for i in range(10):
		var ast = Asteroid.new()
		ast.name = "Asteroid_" + str(i)
		# Spread them out far
		ast.position = Vector2(randf_range(-10000, 10000), randf_range(-10000, 10000))
		# Give them some drift
		ast.linear_velocity = Vector2(randf_range(-50, 50), randf_range(-50, 50))
		add_child(ast)
		asteroids.append(ast)

func _spawn_bouys() -> void:
	var BouyClass = load("res://scripts/bouy.gd")
	for i in range(5):
		var b = BouyClass.new()
		b.name = "Bouy_" + str(i)
		# Spawn them somewhat close so they are within sensor range (40km)
		b.position = Vector2(randf_range(-15000, 15000), randf_range(-15000, 15000))
		b.linear_velocity = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		add_child(b)

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if is_host:
		_spawn_ship(id)

func _spawn_ship(id: int) -> void:
	var ship = Ship.new()
	ship.name = "Ship_" + str(id)
	ship.position = Vector2(randf_range(-100, 100), randf_range(-100, 100))
	add_child(ship)
	players[id] = ship

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if is_host and players.has(id):
		players[id].queue_free()
		players.erase(id)

func _unhandled_input(event: InputEvent) -> void:
	if is_host and event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_spawn_drone()

func _spawn_drone() -> void:
	var drone_id = 900 + players.size()
	var ship = Ship.new()
	ship.name = "Ship_" + str(drone_id)
	
	var player_pos = Vector2.ZERO
	if players.has(1): player_pos = players[1].position
	
	var angle = randf() * TAU
	ship.position = player_pos + Vector2(cos(angle), sin(angle)) * 15000.0
	
	add_child(ship)
	players[drone_id] = ship
	
	var ai = AIDroneController.new()
	ship.add_child(ai)
	print("Spawned AI Drone ", drone_id, " at ", ship.position)

# ----------------------------------------------------
# Host Simulation Loop
# ----------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_host:
		return
		
	# Filter and distribute state to clients
	_distribute_state()

func _distribute_state() -> void:
	# Host filters the world state on a per-client basis
	for client_id in players.keys():
		var ship = players[client_id]
		var packet = {
			"pos": ship.position,
			"rot": ship.rotation,
			"vel": ship.linear_velocity,
			"throttle": ship.actual_throttle,
			"sensors": ship.active_sensor_sweeps.duplicate(true),
			"sensor_config": ship.sensor_hardware.duplicate(true),
			"contacts": ship.active_contacts.duplicate(true),
			"weapons": ship.weapons.duplicate(true),
			"engineering": {
				"subsystems": ship.subsystems.duplicate(true),
				"ship_components": ship.ship_components.duplicate(true),
				"current_heat": ship.current_heat,
				"max_heat": ship.max_heat,
				"heat_gen": ship.current_heat_gen,
				"heat_dissipation_rate": ship.heat_dissipation_rate,
				"silent_running": ship.silent_running,
				"em_signature": ship.em_signature
			}
		}
		if client_id == multiplayer.get_unique_id():
			# Update host's local terminal
			_update_terminal(packet)
		elif client_id in multiplayer.get_peers():
			# Send targeted RPC to client
			rpc_id(client_id, "receive_perceived_state", packet)

# ----------------------------------------------------
# Client Terminal / RPC Pipeline
# ----------------------------------------------------
@rpc("authority", "call_remote", "unreliable")
func receive_perceived_state(packet: Dictionary) -> void:
	if is_host: return # Safety check
	
	# Terminals parse, decay, and display parameters strictly received here
	_update_terminal(packet)

func _update_terminal(packet: Dictionary) -> void:
	# Pass data to the low-level UI
	terminal_display.update_data(packet)

# ----------------------------------------------------
# Client Input Pipeline (Phase 2.5)
# ----------------------------------------------------

func send_helm_input(thrust: float, target_velocity: float, heading: float, steering_mode: int, linear_mode: int) -> void:
	# Handle local offline test mode
	if is_host and (not multiplayer.has_multiplayer_peer() or multiplayer.get_unique_id() == 1):
		receive_helm_input(thrust, target_velocity, heading, steering_mode, linear_mode)
		return
		
	if not multiplayer.has_multiplayer_peer(): return
	# Send input to host
	rpc_id(1, "receive_helm_input", thrust, target_velocity, heading, steering_mode, linear_mode)

@rpc("any_peer", "call_remote", "unreliable")
func receive_helm_input(thrust: float, target_velocity: float, heading: float, steering_mode: int, linear_mode: int) -> void:
	if not is_host: return
	
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id() # Fallback for local direct calls
		
	if players.has(sender_id):
		var ship = players[sender_id]
		# Apply control inputs
		ship.apply_control_input(clamp(thrust, -1.0, 1.0), target_velocity, heading, steering_mode, linear_mode)
