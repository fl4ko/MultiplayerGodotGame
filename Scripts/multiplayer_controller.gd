extends Control

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
		

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# Clinet and Server
func _on_player_connected(id):
	print("Player connected " + str(id))

func _on_player_disconnected(id):
	print("Player disconnected " + str(id))
	GameManager.connected_players.erase(id)
	var all_players = get_tree().get_nodes_in_group("Player")
	for player in all_players:
		if player.name == str(id):
			player.queue_free()

# Clinet only
func _on_connected_ok():
	print("Connected to server successfully")
	send_player_info.rpc_id(1, multiplayer.get_unique_id(), $NameBox.text)

func _on_connected_fail():
	print("Failed to connect to server")

func _on_server_disconnected():
	print("Disconnected from server")

# Button handlers

func _on_host_button_down():
	host_game()
	send_player_info(multiplayer.get_unique_id(), $NameBox.text)

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
	start_game.rpc()
	pass

@rpc("any_peer", "call_local")
func start_game(game_scene_file_path: String = "") -> void:
	if game_scene_file_path.is_empty():
		game_scene_file_path = DEFAULT_SCENE_FILE_PATH

	get_tree().change_scene_to_file(game_scene_file_path)


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
