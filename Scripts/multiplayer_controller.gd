extends Control

signal start_pressed

const MAX_CONNECTIONS = 4
const DEFAULT_PORT = 7000
const MIN_PORT = 7000
const MAX_PORT = 7999
const DEFAULT_SERVER_IP = "127.0.0.1"

var player_info = {}
var lobby_port: int = DEFAULT_PORT
var is_lobby_host: bool = false
var _pending_join_ip: String = ""
var _pending_join_port: int = DEFAULT_PORT
var _should_retry_localhost: bool = false

@onready var player_list: VBoxContainer = $PlayerList
@onready var menu_panel: Control = $MainMenuPanel
@onready var join_panel: Control = $JoinPanel
@onready var lobby_panel: Control = $LobbyPanel

@onready var name_box: LineEdit = $MainMenuPanel/MenuContainer/NameBox
@onready var join_code_input: LineEdit = $JoinPanel/JoinContainer/JoinCodeInput
@onready var join_status_label: Label = $JoinPanel/JoinContainer/JoinStatusLabel
@onready var lobby_code_value_label: Label = $LobbyPanel/LobbyContainer/JoinCodeRow/JoinCodeValue
@onready var lobby_status_label: Label = $LobbyPanel/LobbyContainer/LobbyStatusLabel
@onready var start_button: Button = $LobbyPanel/LobbyContainer/LobbyButtons/StartButton

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
	show_main_menu()
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
	if multiplayer.is_server() and not GameManager.connected_players.has(multiplayer.get_unique_id()):
		send_player_info(multiplayer.get_unique_id(), name_box.text)

# Clinet only

func _on_connected_ok():
	print("Connected to server successfully")
	join_status_label.text = "Connected. Waiting for host..."
	send_player_info.rpc_id(1, multiplayer.get_unique_id(), name_box.text)
	is_lobby_host = false
	show_lobby()
	update_lobby_labels()

func _on_connected_fail():
	print("Failed to connect to server")
	if _should_retry_localhost and _pending_join_ip != "127.0.0.1" and _pending_join_ip != "localhost":
		_should_retry_localhost = false
		join_status_label.text = "LAN connect failed. Retrying localhost..."
		_join_with_ip_and_port("127.0.0.1", _pending_join_port)
		return

	join_status_label.text = "Could not join this lobby. Check code and try again."

func _on_server_disconnected():
	print("Disconnected from server")
	lobby_status_label.text = "Disconnected from host."
	show_main_menu()
	GameManager.connected_players.clear()
	update_lobby_labels()

# Buttons

func _on_host_button_down() -> void:
	host_game()
	is_lobby_host = true
	send_player_info(multiplayer.get_unique_id(), name_box.text)
	lobby_status_label.text = "Lobby created. Share the join code."
	show_lobby()
	update_lobby_labels()

func _on_join_button_down(address = ""):
	var code := join_code_input.text.strip_edges()
	if not address.is_empty():
		code = address

	var parsed := _parse_join_code(code)
	if parsed.is_empty():
		join_status_label.text = "Use code format: IP:PORT"
		return ERR_INVALID_PARAMETER

	var target_ip: String = parsed["ip"]
	var target_port: int = parsed["port"]
	var error := _join_with_ip_and_port(target_ip, target_port)
	if error:
		join_status_label.text = "Could not connect to %s" % code
		return error

	_pending_join_ip = target_ip
	_pending_join_port = target_port
	_should_retry_localhost = target_ip != "127.0.0.1" and target_ip != "localhost"
	lobby_port = target_port
	join_status_label.text = "Connecting to %s..." % code

	print("Joined the server")
	return OK

func _on_start_button_down() -> void:
	if not multiplayer.is_server():
		return
	emit_signal("start_pressed")

func _on_exit_button_down() -> void:
	get_tree().quit()

func _on_menu_join_button_down() -> void:
	show_join_screen()

func _on_menu_host_button_down() -> void:
	_on_host_button_down()

func _on_join_back_button_down() -> void:
	if lobby_panel.visible:
		_leave_lobby()
	show_main_menu()

func _on_copy_code_button_down() -> void:
	DisplayServer.clipboard_set(lobby_code_value_label.text)
	lobby_status_label.text = "Join code copied to clipboard."

func refresh_lobby_from_gamemanager() -> void:
	update_lobby_labels()
	if multiplayer.multiplayer_peer == null:
		show_main_menu()
	else:
		show_lobby()

func host_game():
	lobby_port = randi_range(MIN_PORT, MAX_PORT)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(lobby_port, MAX_CONNECTIONS)

	if error:
		lobby_port = DEFAULT_PORT
		error = peer.create_server(lobby_port, MAX_CONNECTIONS)

	if error:
		return error

	multiplayer.multiplayer_peer = peer
	GameManager.connected_players.clear()
	lobby_code_value_label.text = _build_join_code()

	print("Server hosted")
	return OK

@rpc("any_peer")
func send_player_info(id, player_name):
	if not GameManager.connected_players.has(id):
		GameManager.connected_players[id] = {
			"id": id,
			"player_name": player_name
		}
	
	if multiplayer.is_server():
		for i in GameManager.connected_players.keys():
			var info = GameManager.connected_players[i]
			send_player_info.rpc(info.id, info.player_name)

	update_lobby_labels()

func update_lobby_labels():
	var labels = player_list.get_children()
	var ids = GameManager.connected_players.keys()
	ids.sort()

	for i in range(labels.size()):
		if i < ids.size():
			var id = ids[i]
			var info = GameManager.connected_players[id]

			var player_name = info.player_name
			if player_name.strip_edges() == "":
				player_name = str(id)

			labels[i].text = player_name
		else:
			labels[i].text = ""

	if lobby_panel.visible:
		start_button.visible = multiplayer.is_server()
		if multiplayer.is_server():
			lobby_status_label.text = "Players connected: %d" % ids.size()
		elif multiplayer.multiplayer_peer != null:
			lobby_status_label.text = "Waiting for host to start the match..."

func show_main_menu() -> void:
	menu_panel.visible = true
	join_panel.visible = false
	lobby_panel.visible = false
	player_list.visible = false

func show_join_screen() -> void:
	menu_panel.visible = false
	join_panel.visible = true
	lobby_panel.visible = false
	player_list.visible = false
	join_status_label.text = ""

func show_lobby() -> void:
	menu_panel.visible = false
	join_panel.visible = false
	lobby_panel.visible = true
	player_list.visible = true
	start_button.visible = multiplayer.is_server()
	if multiplayer.is_server():
		lobby_code_value_label.text = _build_join_code()
	else:
		lobby_code_value_label.text = join_code_input.text.strip_edges()

func _leave_lobby() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_pending_join_ip = ""
	_pending_join_port = DEFAULT_PORT
	_should_retry_localhost = false
	GameManager.connected_players.clear()
	update_lobby_labels()

func _build_join_code() -> String:
	var ip := _get_local_ipv4()
	return "%s:%d" % [ip, lobby_port]

func _get_local_ipv4() -> String:
	var private_ips: Array[String] = []
	var other_ips: Array[String] = []

	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue
		if ip.begins_with("127."):
			continue
		if ip.begins_with("169.254."):
			continue

		if ip.begins_with("192.168.") or ip.begins_with("10.") or _is_172_private(ip):
			private_ips.append(ip)
		else:
			other_ips.append(ip)

	if private_ips.size() > 0:
		return private_ips[0]
	if other_ips.size() > 0:
		return other_ips[0]
	return DEFAULT_SERVER_IP

func _join_with_ip_and_port(ip: String, port: int) -> int:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error:
		return error

	multiplayer.multiplayer_peer = peer
	return OK

func _is_172_private(ip: String) -> bool:
	if not ip.begins_with("172."):
		return false
	var parts := ip.split(".")
	if parts.size() < 2:
		return false
	if not parts[1].is_valid_int():
		return false
	var second = int(parts[1])
	return second >= 16 and second <= 31

func _parse_join_code(code: String) -> Dictionary:
	if code.is_empty():
		return {}

	var parts := code.split(":")
	if parts.size() != 2:
		return {}

	var ip := parts[0].strip_edges()
	var port_text := parts[1].strip_edges()
	if ip.is_empty() or not port_text.is_valid_int():
		return {}

	var port := int(port_text)
	if port <= 0 or port > 65535:
		return {}

	return {"ip": ip, "port": port}
