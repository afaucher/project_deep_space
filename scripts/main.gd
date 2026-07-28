extends Node2D

@onready var ui_layer = $CanvasLayer
@onready var terminal_display = $CanvasLayer/TerminalDisplay
@onready var menu = $CanvasLayer/Menu
@onready var ship_select: OptionButton = $CanvasLayer/Menu/ShipSelect

const Frigate = preload("res://scripts/ships/frigate.gd")
const CargoShuttle = preload("res://scripts/ships/cargo_shuttle.gd")
const Buoy = preload("res://scripts/ships/buoy.gd")
const SensorDrone = preload("res://scripts/ships/sensor_drone.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const AITreeFactory = preload("res://scripts/ai/ai_tree_factory.gd")
const MenuCompass = preload("res://scripts/ui/menu_compass.gd")
const ControlsMenu = preload("res://scripts/ui/controls_menu.gd")
const ClusterManager = preload("res://scripts/cluster/cluster_manager.gd")
const ClusterLoader = preload("res://scripts/cluster/cluster_loader.gd")
const HomeCluster = preload("res://scripts/cluster/home_cluster.gd")
const HomeClusterOverlay = preload("res://scripts/story/home_cluster_overlay.gd")
const StoryCharacters = preload("res://scripts/story/characters.gd")
const ContractFeed = preload("res://scripts/story/contract_feed.gd")
const NavComputer = preload("res://scripts/nav/nav_computer.gd")
const NavAutopilot = preload("res://scripts/nav/nav_autopilot.gd")
const Standing = preload("res://scripts/combat/standing.gd")
const PirateGuild = preload("res://scripts/directors/pirate_guild.gd")
const TrafficGuild = preload("res://scripts/directors/traffic_guild.gd")
const StationEconomy = preload("res://scripts/directors/station_economy.gd")
const ClusterEntity = preload("res://scripts/cluster/cluster_entity.gd")

enum GameMode { SANDBOX, CAMPAIGN }

var is_host: bool = false
var game_mode: int = GameMode.SANDBOX
var debug_show_all_entities: bool = false
var players = {}
var asteroids = []
var _next_sandbox_id: int = 900
var menu_compass: Node2D
var controls_menu: Control
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
	# menu compass is added). Ordering is handled below, not here.
	var campaign_button := Button.new()
	campaign_button.name = "CampaignButton"
	campaign_button.text = "CAMPAIGN"
	campaign_button.pressed.connect(_on_campaign_pressed)
	menu.add_child(campaign_button)

	# Playtest C1: the ship dropdown used to sit ABOVE the campaign button,
	# which reads as "pick a ship, then pick a mode" -- so it looked like it
	# applied to the campaign. It does not: the campaign is hardcoded to a cargo
	# shuttle and the dropdown only ever affected the sandbox.
	#
	# Fixed by grouping rather than by position alone (the notes ask for both):
	# the dropdown now sits directly UNDER Sandbox with a label saying so, so
	# the association is visible even to someone who never reads down the list.
	var sandbox_ship_label := Label.new()
	sandbox_ship_label.name = "SandboxShipLabel"
	sandbox_ship_label.text = "Sandbox ship:"
	sandbox_ship_label.add_theme_font_size_override("font_size", 11)
	sandbox_ship_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	menu.add_child(sandbox_ship_label)
	ship_select.tooltip_text = "Sandbox only -- the campaign always starts you in a cargo shuttle."

	# Controls remapping -- button at the bottom of the menu, screen added in
	# code (same no-.tscn-edit pattern). While the screen is open the menu is
	# hidden, which also disarms the menu_start quick-start below.
	var controls_button := Button.new()
	controls_button.name = "ControlsButton"
	controls_button.text = "CONTROLS"
	controls_button.pressed.connect(_on_controls_pressed)
	menu.add_child(controls_button)

	# ONE declarative list decides menu order (playtest C1). The old code moved
	# a single button to a hardcoded index, which is unreadable the moment a
	# second entry moves and is how the dropdown ended up stranded above the
	# mode buttons. Anything not listed keeps its existing position; a listed
	# node that does not exist is skipped, so this cannot crash on a renamed
	# button.
	var menu_order: Array[String] = [
		"CampaignButton",     # the primary experience, first
		"LocalTestButton",    # "SANDBOX"
		"SandboxShipLabel",   # ...and its ship dropdown, grouped directly under it
		"ShipSelect",
		"HostButton",
		"JoinButton",
		"ControlsButton",
	]
	for i in menu_order.size():
		var n := menu.get_node_or_null(NodePath(menu_order[i]))
		if n != null:
			menu.move_child(n, i)

	controls_menu = ControlsMenu.new()
	ui_layer.add_child(controls_menu)
	controls_menu.closed.connect(_on_controls_closed)

	# Seed keyboard/gamepad focus so the menu is navigable without a mouse
	# (D-pad / left stick move focus, A activates via the built-in ui_* map).
	menu.get_node("LocalTestButton").grab_focus()

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

func _on_controls_pressed() -> void:
	menu.hide()
	controls_menu.open()

func _on_controls_closed() -> void:
	menu.show()
	menu.get_node("ControlsButton").grab_focus()

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
		# M48 -- declares non-combatant status; nobody's known_enemy_flags
		# includes it by default, so mobile homes read NEUTRAL, not auto-targeted.
		home.set_transponder_flag(Standing.FLAG_CIVILIAN)
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

func _spawn_player_ship(id: int, at = null, ship_script: Script = null) -> void:
	if ship_script == null:
		var selected_idx = ship_select.selected if is_instance_valid(ship_select) else 0
		if selected_idx < 0 or selected_idx >= ShipCatalog.SPAWNABLE.size():
			selected_idx = 0
		ship_script = ShipCatalog.SPAWNABLE[selected_idx]["script"]
	var ship = ship_script.new()
	ship.name = "Ship_" + str(id)
	ship.owner_id = id
	ship.iff_tags = ["TEAM_PLAYER"]
	# manual_undock=false (Ship's default) auto-releases from a berth after
	# dock_duration (~1.5s) -- correct for NPC/cargo traffic on a patrol
	# loop, but a HUMAN player docking to talk to a station's crew or sit for
	# repairs must not be yanked back out mid-conversation. This is the only
	# spawn path for a player-controlled ship (NPCs are spawned elsewhere via
	# their own AI/traffic systems), so it's safe to always set here.
	ship.manual_undock = true
	if at != null:
		ship.position = at
	else:
		ship.position = Vector2(randf_range(-100, 100), randf_range(-100, 100))
	add_child(ship)
	# M48 -- the player flies the home-faction flag (transponder defaults on
	# already); known_enemy_flags stays the Ship default ([FLAG_PIRATE]).
	ship.set_transponder_flag(Standing.FLAG_DRIFT)
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
	# M42 -- the real story overlay + character registry (see
	# scripts/story/home_cluster_overlay.gd, scripts/story/characters.gd).
	# ClusterLoader stays story-agnostic in mechanism; this is the one call
	# site that actually knows Stephanie exists.
	ClusterLoader.load_into(def, manager, HomeClusterOverlay, StoryCharacters)

	# M51 -- the pirate guild, a default-config director. Campaign only (NOT
	# the sandbox): the guild is an invisible hand behind the home cluster's
	# wormhole traffic, not a sandbox test fixture.
	manager.directors.append(PirateGuild.new())

	# M53b -- the traffic guild, a default-config director: population floor
	# per flag (the depletion fix -- authored haulers plus working piracy
	# otherwise thin the world permanently) plus transient wormhole freighters
	# (through-traffic on the beacon road). Campaign only, same as PirateGuild.
	manager.directors.append(TrafficGuild.new())

	# M53c Phase A -- the station economy: derives converter/sink/source
	# throughput for every STATION record each policy pass (design_ideas/
	# station_economy.md). Pure substrate -- nothing else reads stocks/market
	# yet -- but it must tick from campaign start so a played session's numbers
	# aren't frozen at their authored initial values.
	manager.directors.append(StationEconomy.new())

	var pid = multiplayer.get_unique_id()
	# M53a -- campaign player starts in the civilian hauler (slow, fragile,
	# unarmed; the escort fantasy makes you *be* the shuttle), not the
	# ship-select catalog's Frigate default. Sandbox spawns are untouched --
	# the other _spawn_player_ship call site (peer-connected / local-test)
	# passes no override, so it keeps using the ship_select selection.
	_spawn_player_ship(pid, def.player_start, CargoShuttle)

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
#
# M41 -- also appends contract entries (active-mission objectives, see
# scripts/story/contract_feed.gd) that have a resolved pos: contracts ARE nav
# destinations with mission context (roadmap: "it already routes to arbitrary
# positions internally; expose contracts as destinations"), named after the
# objective's title. Entries with pos == null (e.g. TALK_TO Todd -- no known
# position) are never destinations; there's nowhere to route to.
func nav_destinations() -> Array:
	if cluster_manager == null or cluster_manager.cluster_def == null:
		return []
	var out: Array = NavComputer.destinations(cluster_manager.cluster_def)
	var player = players.get(1, null)
	if player != null and is_instance_valid(player) and player.mission_log != null:
		for entry in ContractFeed.build(player.mission_log, cluster_manager):
			var pos = entry.get("pos", null)
			if pos == null:
				continue
			out.append({"name": entry.get("title", ""), "pos": pos})
	return out

func set_nav_destination(dest_name: String) -> bool:
	if cluster_manager == null or cluster_manager.cluster_def == null or not players.has(1):
		return false
	var player = players[1]
	var autopilot = player.get_node_or_null("NavAutopilot")
	if autopilot == null:
		return false
	# Routes over the SAME combined list nav_destinations() lists (beacon/
	# station/wormhole destinations + contract destinations), so a contract
	# destination named in the picker UI always resolves here too -- one
	# source of truth for "what names are valid", not two lists that could
	# drift apart.
	for d in nav_destinations():
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9 and not event.echo:
		debug_show_all_entities = not debug_show_all_entities
		print("Debug omniscience map mode: ", debug_show_all_entities)

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

	# M48 -- sandbox flags reproduce the pre-M48 iff-non-overlap warzone under
	# the standing model. Enemies and pirates fly the black flag (HOSTILE to
	# anyone flying the home flag -- the player and friendlies -- via their
	# known_enemy_flags); friendlies fly the home flag but stay allied to the
	# player through shared crypto iff_tags (FRIENDLY beats flag). Two ENEMY
	# ships both fly the black flag yet stay mutually allied because their
	# shared TEAM_ENEMY tag makes them crypto-FRIENDLY first; a PIRATE's
	# unique tag shares with no one, so pirates read every black flag
	# (including each other's) as HOSTILE -- the true-FFA behavior iff_for
	# documents. Set AFTER add_child so _ready() has normalized the comms
	# component that set_transponder_flag walks.
	if team == ShipCatalog.Team.FRIENDLY:
		ship.set_transponder_flag(Standing.FLAG_DRIFT)
	else:
		ship.set_transponder_flag(Standing.FLAG_PIRATE)
		ship.known_enemy_flags = [Standing.FLAG_PIRATE, Standing.FLAG_DRIFT]

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
	# M48 -- a friendly scout flies the home flag so non-crypto-linked home
	# ships read it as home rather than CAUTION (it's already FRIENDLY to
	# the player via shared TEAM_PLAYER tags).
	ship.set_transponder_flag(Standing.FLAG_DRIFT)

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
	PerfProbe.begin("distribute_state")
	_distribute_state()
	PerfProbe.end("distribute_state")

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
			# M46 follow-up -- departing_slip (ship.gd's own comment): a
			# {"authority","slip_id"} shape mirroring just enough of
			# docking_grant for navigation_panel to keep drawing the exit
			# channel toward a berth this ship JUST released from, until it
			# actually clears the disc. {} once cleared/not departing.
			"departing_slip": ship.departing_slip,
			# M35 -- current_port_zone is just the authority NAME string (see
			# ship.gd), the same small-value-with-no-other-path-in shape as
			# M34's docking_grant field above (see that milestone's "Packet
			# vs. instance_from_id" note for why docking_grant rides the
			# packet). navigation_panel.gd/terminal_display.gd resolve the
			# authority name back to its owning station's port_zone dict live
			# via the "ships" group scan (same pattern _draw_docking_nav_aids
			# already uses to resolve a grant's authority to a station).
			"current_port_zone": ship.current_port_zone,
			# M41 -- contracts are NAV-layer data (a known coordinate/area,
			# never a sensor detection -- see scripts/story/contract_feed.gd's
			# header), built fresh once per client per tick from this ship's
			# own MissionLog + the campaign ClusterManager (null in sandbox,
			# where ContractFeed.build() degrades to marker_sid entries
			# resolving to null pos -- still listed, never drawn). Consumed by
			# navigation_panel.gd (markers/rings) and contacts_panel.gd (the
			# "Contracts" section). NEVER merged into "contacts" above.
			"contracts": ContractFeed.build(ship.mission_log, cluster_manager),
			# M41 -- comms panel's "Missions" section: active missions' titles
			# + current objective text, straight off MissionLog (NOT filtered
			# by indicators_visible -- that flag only mutes map/contacts-panel
			# declutter, not "can I review what I accepted").
			"missions": _missions_summary(ship.mission_log),
			# M49 -- hail protocol (design_ideas/comms_verbs.md). "last_hails"/
			# "pending_demand"/"compelled_stop" feed the comms panel's HAILS
			# section + honored-stop banner. "sent_hails" (M52d) is the
			# sender-side memory for the panel's vessel-grouped list --
			# vessels WE hailed stay listed for tracking/cancel. (M52 follow-
			# up: SOS is now a real "DISTRESS CALL"-classified entry inside
			# "contacts" above -- implementation_plans/m52_sos_as_contact.md
			# -- so there is no more separate "sos" packet field.)
			"last_hails": ship.last_hails.duplicate(true),
			"sent_hails": ship.sent_hails.duplicate(true),
			"pending_demand": ship.pending_demand.duplicate(true),
			"compelled_stop": ship.compelled_stop.duplicate(true),
			"debug_entities": _get_debug_entities() if debug_show_all_entities else []
		}
		if client_id == multiplayer.get_unique_id():
			# Update host's local terminal
			_update_terminal(packet)
		elif client_id in multiplayer.get_peers():
			# Send targeted RPC to client
			rpc_id(client_id, "receive_perceived_state", packet)
			
		ship.transient_events.clear()

# F9 omniscience debug view -- returns every entity in the live campaign
# cluster (all ClusterEntity.Kind values: STATION, ASTEROID, BEACON, TRAFFIC,
# WORMHOLE, PLAYER), not just ships. Plain-serializable data only (Vector2 +
# int + String) since this rides the same per-client RPC packet as everything
# else in _distribute_state -- see that function's "debug_entities" field.
func _get_debug_entities() -> Array:
	var arr: Array = []
	if cluster_manager != null:
		for rec in cluster_manager.records:
			var entity_pos: Vector2 = rec.pos
			if rec.live_node != null and is_instance_valid(rec.live_node) and rec.live_node is Node2D:
				entity_pos = rec.live_node.global_position
			arr.append({"pos": entity_pos, "kind": rec.kind, "name": rec.name})
	return arr

# M41 -- plain-data summary of a MissionLog's active missions for the comms
# panel's "Missions" section: [{title, objective_text}, ...], one entry per
# active mission (regardless of indicators_visible -- see the packet-field
# comment above). Missing-key-safe throughout (a null mission_log, or an
# objective dict with no "text", just contributes an empty string rather than
# erroring the whole packet build for the frame -- CLAUDE.md's
# missing-Dictionary-key gotcha).
func _missions_summary(mission_log) -> Array:
	var out: Array = []
	if mission_log == null:
		return out
	for m in mission_log.active_missions():
		var obj: Dictionary = mission_log.get_active_objective(m.get("id", ""))
		out.append({
			"title": m.get("title", ""),
			"objective_text": obj.get("text", ""),
		})
	return out

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

