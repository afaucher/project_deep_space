extends Node

signal lobby_created(connect_code, lobby_id)
signal lobby_joined(lobby_id, steam_id)
signal lobby_match_list(lobbies)
signal connection_established(is_host)

var is_on_steam_deck: bool = false
var is_online: bool = false
var is_owned: bool = false
var steam_app_id: int = 480
var steam_id: int = 0
var steam_username: String = ""

# Lobby data
var lobby_data = []
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_max_members: int = 4
var lobby_vote_kick: bool = false

func _ready() -> void:
	_initialize_steam()

func _initialize_steam() -> void:
	var init = Steam.steamInit()
	printerr("[Steam] Status: " + str(init))

	if init != true:
		printerr("[Steam] Failed to initialize!")
		return

	is_online = Steam.loggedOn()
	is_owned = Steam.isSubscribed()
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	is_on_steam_deck = Steam.isSteamRunningOnSteamDeck()

	print("[Steam] User: " + steam_username + " (ID: " + str(steam_id) + ")")
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(_on_join_requested)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func create_lobby() -> void:
	if steam_id == 0:
		printerr("[Steam] Cannot create lobby: Steam not initialized")
		return
		
	if lobby_id == 0:
		print("[Steam] Creating lobby...")
		Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, lobby_max_members)

func list_lobbies() -> void:
	if steam_id == 0:
		printerr("[Steam] Cannot list lobbies: Steam not initialized")
		return
		
	print("[Steam] Requesting lobby list...")
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", "project_deep_space", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func join_lobby(id: int) -> void:
	if steam_id == 0:
		printerr("[Steam] Cannot join lobby: Steam not initialized")
		return
		
	print("[Steam] Joining lobby: " + str(id))
	Steam.joinLobby(id)

func leave_lobby() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
		lobby_members.clear()
		close_connection()

func close_connection() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _on_lobby_created(connect: int, id: int) -> void:
	if connect == 1:
		lobby_id = id
		print("[Steam] Created Lobby: " + str(lobby_id))
		
		Steam.setLobbyData(lobby_id, "name", str(steam_username) + "'s Deep Space Lobby")
		Steam.setLobbyData(lobby_id, "game", "project_deep_space")
		
		emit_signal("lobby_created", connect, id)
		setup_steam_peer(true)
	else:
		printerr("[Steam] Failed to create lobby: " + str(connect))

func _on_lobby_match_list(lobbies: Array) -> void:
	print("[Steam] Found " + str(lobbies.size()) + " lobbies")
	lobby_data = lobbies
	emit_signal("lobby_match_list", lobbies)

func _on_lobby_joined(id: int, permissions: int, locked: bool, response: int) -> void:
	if response == 1:
		lobby_id = id
		print("[Steam] Joined Lobby: " + str(lobby_id))
		emit_signal("lobby_joined", id, steam_id)
		setup_steam_peer(false)
	else:
		var error = "Unknown"
		match response:
			2: error = "Full"
			3: error = "No longer exists"
			4: error = "No connection"
			5: error = "Access denied"
		printerr("[Steam] Failed to join lobby: ", error, " (", response, ")")

func _on_lobby_chat_update(id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	pass

func _on_join_requested(id: int, friend_id: int) -> void:
	join_lobby(id)

func setup_steam_peer(is_host: bool) -> void:
	print("[Steam] Setting up SteamMultiplayerPeer...")
	var peer = SteamMultiplayerPeer.new()
	
	if is_host:
		print("[Steam] Starting as Host")
		peer.create_host(0)
	else:
		var owner_id = Steam.getLobbyOwner(lobby_id)
		print("[Steam] Starting as Client, connecting to ", owner_id)
		peer.create_client(owner_id, 0)
		
	multiplayer.multiplayer_peer = peer
	print("[Steam] MultiplayerPeer set.")
	emit_signal("connection_established", is_host)
