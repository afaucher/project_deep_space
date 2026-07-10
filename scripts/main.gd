extends Node2D

@onready var ui_layer = $CanvasLayer
@onready var terminal_display = $CanvasLayer/TerminalDisplay
@onready var menu = $CanvasLayer/Menu
@onready var ship_select: OptionButton = $CanvasLayer/Menu/ShipSelect

const Frigate = preload("res://scripts/ships/frigate.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const SensorDrone = preload("res://scripts/ships/sensor_drone.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const MenuCompass = preload("res://scripts/ui/menu_compass.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const NavComputer = preload("res://scripts/nav/nav_computer.gd")
const NavAutopilot = preload("res://scripts/nav/nav_autopilot.gd")

enum GameMode { SANDBOX, CAMPAIGN }

var is_host: bool = false
var game_mode: int = GameMode.SANDBOX
var players = {}
var asteroids = []
var _next_sandbox_id: int = 900
var menu_compass: Node2D
var cluster_manager = null   # the live campaign ClusterManager (null in sandbox)

func _ready() -> void:
	# Check for automated tests
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--run-test" and i + 1 < args.size():
			_run_test(args[i+1])
			return
		elif args[i] == "--run-tactical-sim" and i + 1 < args.size():
			_run_tactical_sim(args[i+1])
			return
			
	SteamManager.connection_established.connect(_on_connection_established)
	
	# Populate ship selection dropdown from catalog
	for entry in ShipCatalog.SPAWNABLE:
		ship_select.add_item(entry["name"])
	ship_select.selected = 0
	
	# Menu UI hookups
	menu.get_node("HostButton").pressed.connect(_on_host_pressed)
	menu.get_node("JoinButton").pressed.connect(_on_join_pressed)
	menu.get_node("LocalTestButton").pressed.connect(_on_local_test_pressed)

	# Campaign entry -- added in code so no .tscn edit is needed (mirrors how the
	# menu compass is added). Placed just under the ship dropdown, above Sandbox.
	var campaign_button := Button.new()
	campaign_button.name = "CampaignButton"
	campaign_button.text = "CAMPAIGN"
	campaign_button.pressed.connect(_on_campaign_pressed)
	menu.add_child(campaign_button)
	menu.move_child(campaign_button, 1)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Decorative slowly-rotating compass behind the opening menu (index 0 = under the UI).
	menu_compass = MenuCompass.new()
	ui_layer.add_child(menu_compass)
	ui_layer.move_child(menu_compass, 0)

func _run_test(test_name: String) -> void:
	print("Starting automated test: ", test_name)
	is_host = true
	menu.hide()

	# Deterministic RNG for every test. The global randi/randf -- per-frame sensor
	# position/velocity noise (ship.gd), missile jink (missile_controller.gd),
	# ship-name picks -- is otherwise auto-seeded from entropy each launch, so
	# combat-OUTCOME tests (who kills whom) were flaky run-to-run. This was the
	# real cause of the "flaky test" timeouts/failures, NOT parallelism or
	# --fixed-fps (fixed delta already makes physics/AI deterministic; only the
	# RNG stream was free). One fixed seed here -> a repeatable draw sequence for
	# the whole run.
	seed(20260708)

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

func _run_tactical_sim(sim_name: String) -> void:
	print("Starting tactical simulation: ", sim_name)
	is_host = true
	menu.hide()
	
	var sim_script_path = "res://tactical_analysis/sim_runners/" + sim_name + ".gd"
	if ResourceLoader.exists(sim_script_path):
		var sim_script = load(sim_script_path)
		var sim_node = Node.new()
		sim_node.set_script(sim_script)
		add_child(sim_node)
		if sim_node.has_method("setup"):
			sim_node.setup(self)
	else:
		printerr("[SIM FAILED] Tactical sim script not found: ", sim_script_path)
		get_tree().quit(1)

func _on_host_pressed() -> void:
	SteamManager.create_lobby()

func _on_local_test_pressed() -> void:
	# Offline local singleplayer / testing mode
	game_mode = GameMode.SANDBOX
	_on_connection_established(true)

func _on_campaign_pressed() -> void:
	# Offline single-player campaign (the bubble is one-viewpoint; co-op deferred).
	game_mode = GameMode.CAMPAIGN
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
	if is_instance_valid(menu_compass): menu_compass.queue_free()
	terminal_display.show()
	
	if is_host:
		print("I am the authoritative host.")
		if game_mode == GameMode.CAMPAIGN:
			_bootstrap_campaign()
		else:
			_spawn_asteroids()
			_spawn_mobile_homes()
			#_spawn_bouys() # Temporarily disabled
			_spawn_player_ship(multiplayer.get_unique_id())
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

func _spawn_mobile_homes() -> void:
	# Spread a few out where mining activity might be (in the asteroid field)
	for i in range(3):
		var home = ShipCatalog.SPAWNABLE[12]["script"].new() # Index 12 is Mobile Home
		var home_id = _next_sandbox_id
		_next_sandbox_id += 1
		
		home.name = "MobileHome_" + str(home_id)
		home.owner_id = home_id
		home.iff_tags = ["TEAM_CIVILIAN"] # A neutral civilian tag
		home.position = Vector2(randf_range(-8000, 8000), randf_range(-8000, 8000))
		# Start them with zero velocity (holding station)
		home.linear_velocity = Vector2.ZERO
		
		add_child(home)
		players[home_id] = home
		
		# Give it the station AI so it holds its ground
		home.add_child(AITreeFactory.build_station())

func _spawn_bouys() -> void:
	for i in range(5):
		var b = Buoy.new()
		b.name = "Buoy_" + str(i)
		# Spawn them somewhat close so they are within sensor range (40km)
		b.position = Vector2(randf_range(-15000, 15000), randf_range(-15000, 15000))
		b.linear_velocity = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		add_child(b)

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if is_host:
		_spawn_player_ship(id)

func _spawn_player_ship(id: int, at = null) -> void:
	var selected_idx = ship_select.selected if is_instance_valid(ship_select) else 0
	if selected_idx < 0 or selected_idx >= ShipCatalog.SPAWNABLE.size():
		selected_idx = 0
	var ship_script = ShipCatalog.SPAWNABLE[selected_idx]["script"]
	var ship = ship_script.new()
	ship.name = "Ship_" + str(id)
	ship.owner_id = id
	ship.iff_tags = ["TEAM_PLAYER"]
	if at != null:
		ship.position = at
	else:
		ship.position = Vector2(randf_range(-100, 100), randf_range(-100, 100))
	add_child(ship)
	players[id] = ship

# Campaign bootstrap: load the home cluster into a self-ticking ClusterManager,
# spawn the player at the authored start, and point the bubble's viewpoint at it.
# The tested loader does the work (see test_cluster_loader); this is thin glue.
func _bootstrap_campaign() -> void:
	var def = HomeCluster.build()
	var manager = ClusterManager.new()
	manager.name = "ClusterManager"
	# Live entities parent to main (where sandbox ships live) so transforms and
	# rendering match exactly; the manager node just bookkeeps.
	manager.live_parent = self
	add_child(manager)
	ClusterLoader.load_into(def, manager)

	var pid = multiplayer.get_unique_id()
	_spawn_player_ship(pid, def.player_start)

	manager.viewpoint_node = players[pid]
	manager.viewpoint = def.player_start
	manager.cluster_def = def
	cluster_manager = manager

	# Nav autopilot on the player -- the destination picker (UI) calls
	# set_nav_destination() to route + engage it.
	var autopilot = NavAutopilot.new()
	autopilot.name = "NavAutopilot"
	players[pid].add_child(autopilot)

	manager.tick(0.0)   # initial promote around the player before the first frame
	print("Campaign '", def.name, "': loaded ", manager.records.size(), " entities; player at ", def.player_start)

# Nav hooks for the destination-picker UI. nav_destinations() lists named targets;
# set_nav_destination() routes from the player's current position over the beacon
# graph and engages the autopilot.
func nav_destinations() -> Array:
	if cluster_manager == null or cluster_manager.cluster_def == null:
		return []
	return NavComputer.destinations(cluster_manager.cluster_def)

func set_nav_destination(dest_name: String) -> bool:
	if cluster_manager == null or cluster_manager.cluster_def == null or not players.has(1):
		return false
	var player = players[1]
	var autopilot = player.get_node_or_null("NavAutopilot")
	if autopilot == null:
		return false
	for d in NavComputer.destinations(cluster_manager.cluster_def):
		if d["name"] == dest_name:
			autopilot.engage(NavComputer.route(cluster_manager.cluster_def, player.position, d["pos"]))
			return true
	return false

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if is_host and players.has(id):
		players[id].queue_free()
		players.erase(id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("system_exit"):
		get_tree().quit()
		
	if menu.visible and event.is_action_pressed("menu_start"):
		_on_local_test_pressed()

	if is_host and event.is_action_pressed("debug_spawn_enemy") and not event.is_echo():
		_spawn_drone()

	if is_host and event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F4:
			_spawn_buoy()

# ----------------------------------------------------
# M10 Sandbox Spawn Director
# ----------------------------------------------------
# Generalizes _spawn_drone(): instantiate any catalog hull on any of the three
# sandbox teams. Host-only, same assumption as the rest of spawning.
func _spawn_ship(ship_script: Script, team: int) -> Node:
	var spawn_id = _next_sandbox_id
	_next_sandbox_id += 1

	var ship = ship_script.new()
	ship.name = "Ship_" + str(spawn_id)
	ship.owner_id = spawn_id

	var player_tags = ["TEAM_PLAYER"]
	if players.has(1) and players[1].iff_tags.size() > 0:
		player_tags = players[1].iff_tags
	ship.iff_tags = ShipCatalog.iff_for(team, spawn_id, player_tags)

	var player_pos = Vector2.ZERO
	if players.has(1): player_pos = players[1].position

	var angle = randf() * TAU
	ship.position = player_pos + Vector2(cos(angle), sin(angle)) * 15000.0

	add_child(ship)
	players[spawn_id] = ship

	if ship.ship_tier == ComponentSpec.Tier.STRUCTURE:
		ship.add_child(AITreeFactory.build_station())
	else:
		ship.add_child(AITreeFactory.build_default())
	print("Spawned ", ship_script.resource_path, " (id ", spawn_id, ", team ", team, ") at ", ship.position)
	return ship

# Resolve a catalog hull by display name (sent by the terminal's combined spawn
# control via the request_spawn_ship RPC) and spawn it on the given team.
func _spawn_ship_by_name(ship_name: String, team: int) -> void:
	for entry in ShipCatalog.SPAWNABLE:
		if entry["name"] == ship_name:
			_spawn_ship(entry["script"], team)
			return
	push_warning("Spawn request for unknown ship: " + ship_name)

func _spawn_drone(is_friendly: bool = false) -> void:
	var team = ShipCatalog.Team.FRIENDLY if is_friendly else ShipCatalog.Team.ENEMY
	_spawn_ship(Frigate, team)

func _spawn_sensor_drone() -> void:
	var drone_id = 1000 + players.size()
	var ship = SensorDrone.new()
	ship.name = "SensorDrone_" + str(drone_id)
	ship.owner_id = drone_id
	ship.iff_tags = ["TEAM_PLAYER"]
	
	var player_pos = Vector2.ZERO
	if players.has(1): player_pos = players[1].position
	
	var angle = randf() * TAU
	ship.position = player_pos + Vector2(cos(angle), sin(angle)) * 5000.0
	
	add_child(ship)
	players[drone_id] = ship
	
	print("Spawned Sensor Drone ", drone_id, " at ", ship.position)

func _spawn_buoy() -> void:
	var buoy_id = 800 + players.size()
	var ship = Buoy.new()
	ship.name = "Buoy_" + str(buoy_id)
	
	var player_pos = Vector2.ZERO
	if players.has(1): player_pos = players[1].position
	
	# Spawn buoy randomly around player
	var angle = randf() * TAU
	ship.position = player_pos + Vector2(cos(angle), sin(angle)) * 8000.0
	
	add_child(ship)
	
	print("Spawned Target Buoy ", buoy_id, " at ", ship.position)

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
		# A vaporized player ship leaves a freed reference here; skip it so the
		# host doesn't touch a dead instance. The client's terminal simply stops
		# receiving packets (its view holds at the last frame) until respawn.
		if not is_instance_valid(ship):
			continue
		var packet = {
			"ship_name": ship.ship_name,
			"pos": ship.position,
			"rot": ship.rotation,
			"vel": ship.linear_velocity,
			"throttle": ship.actual_throttle,
			"steering_mode": ship.steering_mode,
			"linear_mode": ship.linear_mode,
			"sensors": ship.active_sensor_sweeps.duplicate(true),
			"sensor_config": ship.get_components_by_type("sensors"),
			"comms_range": ship.get_comms_range(),
			"contacts": ship.active_contacts.duplicate(true),
			"transponders": ship.active_transponders.duplicate(true),
			"comms_ledger": ship.comms_ledger.get_packet_data(),
			"weapons": ship.get_components_by_type("weapons"),
			"engineering": {
				"ship_components": ship.ship_components.duplicate(true),
				"current_heat": ship.current_heat,
				"max_heat": ship.max_heat,
				"heat_gen": ship.current_heat_gen,
				"heat_dissipation_rate": ship.heat_dissipation_rate,
				"em_signature": ship.em_signature,
				"hit_traces": ship.hit_traces.duplicate(true),
				# M40 -- engineering log (see Ship.log_event/eng_log). Same
				# current_state-polling shape as everything else in this
				# packet -- the panel diffs against what it last rendered
				# rather than the host pushing incremental deltas.
				"eng_log": ship.eng_log.duplicate(true)
			},
			"transient_events": ship.transient_events.duplicate(true),
			"docking_grant": ship.docking_grant,
			# M35 -- current_port_zone is just the authority NAME string (see
			# ship.gd), the same small-value-with-no-other-path-in shape as
			# M34's docking_grant field above (see that milestone's "Packet
			# vs. instance_from_id" note for why docking_grant rides the
			# packet). navigation_panel.gd/terminal_display.gd resolve the
			# authority name back to its owning station's port_zone dict live
			# via the "ships" group scan (same pattern _draw_docking_nav_aids
			# already uses to resolve a grant's authority to a station).
			"current_port_zone": ship.current_port_zone
		}
		if client_id == multiplayer.get_unique_id():
			# Update host's local terminal
			_update_terminal(packet)
		elif client_id in multiplayer.get_peers():
			# Send targeted RPC to client
			rpc_id(client_id, "receive_perceived_state", packet)
			
		ship.transient_events.clear()

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

