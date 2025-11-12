extends Control

signal start_pressed

# @export var ip_address = "127.0.0.1"

const MAX_CONNECTIONS = 4
const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1"
const DEFAULT_SCENE_FILE_PATH = "res://MultiplayerGodotGame/Scenes/test_scene.tscn"

var player_info = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if "--server" in OS.get_cmdline_args():
		host_game()

	# Register this controller with the GameManager so it can listen for start signals
	if GameManager:
		GameManager.register_controller(self)
		
	# Mark as a lobby controller so GameManager can refresh UI on return-to-lobby
	add_to_group("LobbyController")

	# Populate lobby labels immediately on scene load using current GameManager state
	_update_lobby_labels()
		

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

# Clinet and Server
func _on_player_connected(id):
	print("Player connected " + str(id))
	_update_lobby_labels()

func _on_player_disconnected(id):
	print("Player disconnected " + str(id))
	GameManager.connected_players.erase(id)
	var all_players = get_tree().get_nodes_in_group("Player")
	for player in all_players:
		if player.name == str(id):
			player.queue_free()
	_update_lobby_labels()

# Clinet only
func _on_connected_ok():
	print("Connected to server successfully")
	send_player_info.rpc_id(1, multiplayer.get_unique_id(), $ButtonsMapLayer/NameBox.text)
	_update_lobby_labels()

func _on_connected_fail():
	print("Failed to connect to server")

func _on_server_disconnected():
	print("Disconnected from server")

# Button handlers

func _on_host_button_down():
	host_game()
	send_player_info(multiplayer.get_unique_id(), $ButtonsMapLayer/NameBox.text)
	_update_lobby_labels()

func _on_join_button_down(address = ""):	
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

	print("Joined the server")
	pass

func _on_start_button_down():
	# Emit a local signal that GameManager listens to. GameManager will request the server to start the match.
	emit_signal("start_pressed")
	pass

func refresh_lobby_from_gamemanager() -> void:
	# Public hook for GameManager to force a lobby UI refresh after scene changes
	_update_lobby_labels()

@rpc("any_peer", "call_local")
func start_game(_game_scene_file_path: String = "") -> void:
	# Instead of directly changing scenes on every peer, request the server to start the match.
	# Server will handle scene loading for all peers via GameManager.
	if multiplayer.get_unique_id() == 1:
		# If this is the server, request directly (will call start_match on server)
		GameManager.rpc_request_start_match()
	else:
		# Ask the server (peer id 1) to start the match
		GameManager.rpc_request_start_match.rpc_id(1)


func host_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)

	if error:
		return error

	multiplayer.multiplayer_peer = peer

	print("Server hosted")
	pass

@rpc("any_peer")
func send_player_info(id, player_name):
	if not GameManager.connected_players.has(id):
		GameManager.connected_players[id] = {
			"id": id,
			"player_name": player_name
		}
	
	if multiplayer.is_server():
		for i in GameManager.connected_players:
			send_player_info.rpc(i, GameManager.connected_players[i].player_name)

	# Refresh the lobby UI when player list changes
	_update_lobby_labels()


func _get_lobby_vbox() -> VBoxContainer:
	# Find a VBoxContainer child that contains at least 4 Label nodes.
	for child in get_children():
		if child is VBoxContainer:
			var label_count := 0
			for gc in child.get_children():
				if gc is Label:
					label_count += 1
			if label_count >= 4:
				return child
	# Fallback: search recursively in the scene
	var all_nodes := get_tree().get_nodes_in_group("")
	for n in all_nodes:
		if n is VBoxContainer:
			var label_count := 0
			for gc in n.get_children():
				if gc is Label:
					label_count += 1
			if label_count >= 4:
				return n
	return null


func _sort_keys_numeric(a, b) -> int:
	var ai := 0
	var bi := 0
	if str(a).is_valid_int():
		ai = int(str(a))
	if str(b).is_valid_int():
		bi = int(str(b))
	return ai - bi


func _update_lobby_labels() -> void:
	var vbox := _get_lobby_vbox()
	if not vbox:
		return
	# Collect label children in order
	var labels := []
	for c in vbox.get_children():
		if c is Label:
			labels.append(c)
	if labels.size() == 0:
		return

	# Build a sorted list of player ids
	var keys := []
	for k in GameManager.connected_players:
		keys.append(k)
	if keys.size() > 1:
		keys.sort_custom(Callable(self, "_sort_keys_numeric"))

	# Fill labels (up to labels.size())
	for i in range(labels.size()):
		var text := ""
		if i < keys.size():
			var key = keys[i]
			var info = GameManager.connected_players[key]
			var display_name := ""
			if typeof(info) == TYPE_DICTIONARY and info.has("player_name"):
				display_name = str(info.player_name)
			else:
				display_name = str(key)
			if display_name.strip_edges() == "":
				display_name = str(key)
			text = display_name
		labels[i].text = text
