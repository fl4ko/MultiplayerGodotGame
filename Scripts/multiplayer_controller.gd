extends Control

signal start_pressed

# @export var ip_address = "127.0.0.1"

const MAX_CONNECTIONS = 4
const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1"
const DEFAULT_SCENE_FILE_PATH = "res://MultiplayerGodotGame/Scenes/test_scene.tscn"

var player_info = {}

@onready var player_list: VBoxContainer = $PlayerList

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if "--server" in OS.get_cmdline_args():
		host_game()

	if GameManager:
		GameManager.register_controller(self)
		
	add_to_group("LobbyController")

	update_lobby_labels()

# Clinet and Server

func _on_player_connected(id):
	print("Player connected " + str(id))
	update_lobby_labels()

func _on_player_disconnected(id):
	print("Player disconnected " + str(id))
	GameManager.connected_players.erase(id)
	var all_players = get_tree().get_nodes_in_group("Player")
	for player in all_players:
		if player.name == str(id):
			player.queue_free()
	update_lobby_labels()

# Clinet only

func _on_connected_ok():
	print("Connected to server successfully")
	send_player_info.rpc_id(1, multiplayer.get_unique_id(), $ButtonsMapLayer/NameBox.text)
	update_lobby_labels()

func _on_connected_fail():
	print("Failed to connect to server")

func _on_server_disconnected():
	print("Disconnected from server")

# Buttons

func _on_host_button_down():
	host_game()
	send_player_info(multiplayer.get_unique_id(), $ButtonsMapLayer/NameBox.text)
	update_lobby_labels()

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
	emit_signal("start_pressed")
	pass

func refresh_lobby_from_gamemanager() -> void:
	update_lobby_labels()

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

	update_lobby_labels()

func update_lobby_labels():
	var labels = player_list.get_children()
	var ids = GameManager.connected_players.keys()
	ids.sort()

	for i in range(labels.size()):
		if i < ids.size():
			var id = ids[i]
			var info = GameManager.connected_players[id]

			var palyer_name = info.player_name
			if palyer_name.strip_edges() == "":
				palyer_name = str(id)

			labels[i].text = palyer_name
		else:
			labels[i].text = ""
		
