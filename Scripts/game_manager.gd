extends Node
var connected_players = {}

@export var min_players: int = 2
@export var max_players: int = 4
@export var rounds_to_win: int = 3
@export var min_rounds_to_win: int = 1
@export var max_rounds_to_win: int = 10
@export var round_restart_delay: float = 3.0
@export var round_scene_path: String = "res://MultiplayerGodotGame/Scenes/test_scene.tscn"
@export var control_scene_path: String = "res://MultiplayerGodotGame/Scenes/Multiplayer/control.tscn"

var lobby_settings: Dictionary = {}

var scores: Dictionary = {}
var round_active: bool = false
var current_round: int = 0
var player_states: Dictionary = {}

var _match_active: bool = false
var _last_started_round: int = -1
var _last_scoreboard: Dictionary = {}
var _last_round_num: int = 0
var return_to_lobby_after_match: bool = false

func _ready() -> void:
	_apply_lobby_settings({"rounds_to_win": rounds_to_win})

func get_lobby_settings_snapshot() -> Dictionary:
	return lobby_settings.duplicate(true)

func set_lobby_setting(setting_key: String, setting_value: Variant) -> void:
	if not multiplayer.is_server():
		return

	var updated_settings := lobby_settings.duplicate(true)
	updated_settings[setting_key] = setting_value
	_apply_lobby_settings(updated_settings)
	broadcast_lobby_settings()

func sync_lobby_settings_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc_receive_lobby_settings.rpc_id(peer_id, get_lobby_settings_snapshot())

func broadcast_lobby_settings() -> void:
	if not multiplayer.is_server():
		return
	rpc_receive_lobby_settings.rpc(get_lobby_settings_snapshot())

@rpc("authority", "call_local")
func rpc_receive_lobby_settings(new_settings: Dictionary) -> void:
	_apply_lobby_settings(new_settings)
	call_deferred("notify_lobby_ui_refresh")

func _apply_lobby_settings(new_settings: Dictionary) -> void:
	var normalized_settings := lobby_settings.duplicate(true)
	if normalized_settings.is_empty():
		normalized_settings = {"rounds_to_win": rounds_to_win}

	if new_settings.has("rounds_to_win"):
		normalized_settings["rounds_to_win"] = clampi(
			int(new_settings["rounds_to_win"]),
			min_rounds_to_win,
			max_rounds_to_win
		)

	lobby_settings = normalized_settings
	rounds_to_win = int(lobby_settings.get("rounds_to_win", rounds_to_win))

func register_controller(controller: Node) -> void:
	if controller and controller.has_signal("start_pressed"):
		if not controller.is_connected("start_pressed", Callable(self, "_on_controller_start_pressed")):
			controller.connect("start_pressed", Callable(self, "_on_controller_start_pressed"))


func register_player(player_node: Node) -> void:
	if not multiplayer.is_server():
		return

	if not player_node:
		return

	var pid: int = -1
	if player_node.name and str(player_node.name).is_valid_int():
		pid = int(str(player_node.name))
	else:
		return

	if player_node.has_signal("died"):
		if not player_node.is_connected("died", Callable(self, "_on_player_died")):
			player_node.connect("died", Callable(self, "_on_player_died"))

	player_states[pid] = true
	print("GM: registered player", pid)


func _on_player_died(player_id: int) -> void:
	print("GM: received died signal for", player_id)
	player_states[player_id] = false
	check_round()


func check_round() -> void:
	var alive_count := 0
	var last_alive := -1

	for id in player_states:
		if player_states[id]:
			alive_count += 1
			last_alive = id

	print("GM: check round: alive =", alive_count)

	if alive_count == 1:
		end_round(last_alive)
	elif alive_count == 0:
		end_round(-1)


func _on_controller_start_pressed() -> void:
	if multiplayer.is_server():
		var player_count := connected_players.size()
		if player_count < min_players:
			print("GM: not enough players (", player_count, ")")
			return
		print("GM: start pressed on server")
		start_match()
	else:
		print("GM: start pressed on client")
		rpc_request_start_match.rpc_id(1)

func start_match() -> void:
	print("GM: starting match")
	return_to_lobby_after_match = false
	scores.clear()
	for id in connected_players:
		scores[id] = 0

	_match_active = true
	current_round = 0
	rpc_update_scoreboard()
	start_round()

func start_round() -> void:
	if not multiplayer.is_server():
		return

	current_round += 1
	round_active = true
	print("GM: starting round", current_round)
	rpc_start_round.rpc(round_scene_path, current_round)
	rpc_update_scoreboard()


@rpc("any_peer", "call_local")
func rpc_start_round(scene_path: String, round_num: int) -> void:
	if _last_started_round == round_num:
		return

	_last_started_round = round_num
	get_tree().change_scene_to_file(scene_path)

func end_round(winner_id: int) -> void:
	round_active = false

	if winner_id >= 0:
		if not scores.has(winner_id):
			scores[winner_id] = 0

		scores[winner_id] += 1
		print("GM: round winner:", winner_id, "total wins:", scores[winner_id])

	rpc_update_scoreboard()

	for id in scores:
		if scores[id] >= rounds_to_win:
			var winner := int(id)
			print("GM: match winner:", winner)
			end_match(winner)
			return

	prepare_next_round()

func prepare_next_round() -> void:
	print("GM: next round in", round_restart_delay)
	await get_tree().create_timer(round_restart_delay).timeout
	start_round()

func end_match(winner_id: int) -> void:
	print("GM: ending match winner:", winner_id)
	rpc_update_scoreboard()

	rpc("rpc_show_winner_label", winner_id)

	var end_delay: float = 3.0
	await get_tree().create_timer(end_delay).timeout
	rpc("rpc_end_match", winner_id)
	_match_active = false


@rpc("any_peer", "call_local")
func rpc_show_winner_label(winner_id: int) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var label := scene.get_node("HUD/WinnerLabel")

	var winner_text := "Brak zwycięzcy"

	if winner_id >= 0:
		winner_text = str(winner_id)

		if connected_players.has(winner_id):
			var nm := str(connected_players[winner_id].player_name).strip_edges()
			if nm != "":
				winner_text = nm

	label.text = "Winner: " + winner_text
	label.visible = true


func rpc_update_scoreboard() -> void:
	rpc("rpc_receive_scoreboard", scores, current_round)

@rpc("any_peer", "call_local")
func rpc_receive_scoreboard(board: Dictionary, round_num: int) -> void:
	for k in board:
		print("  player", k, ":", board[k])

	_last_scoreboard = board.duplicate(true)
	_last_round_num = round_num

	var current_scene = get_tree().get_current_scene()
	if current_scene and current_scene.has_method("update_scoreboard"):
		current_scene.call("update_scoreboard", board, round_num)

	call_deferred("push_cached_scoreboard_to_scene")


func push_cached_scoreboard_to_scene() -> void:
	if _last_scoreboard.size() == 0:
		return
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("update_scoreboard"):
		scene.call("update_scoreboard", _last_scoreboard, _last_round_num)

@rpc("any_peer", "call_local")
func rpc_end_match(winner_id: int) -> void:
	print("rpc_end_match: winner is", winner_id, "- returning to control scene")
	return_to_lobby_after_match = true
	get_tree().change_scene_to_file(control_scene_path)
	call_deferred("notify_lobby_ui_refresh")


func notify_lobby_ui_refresh() -> void:
	get_tree().call_group("LobbyController", "refresh_lobby_from_gamemanager")


@rpc("any_peer")
func rpc_request_start_match() -> void:
	if multiplayer.is_server():
		var player_count := connected_players.size()
		if player_count < min_players:
			print("GM: start match request rejected not enough players")
			return
		print("GM: start match requested and accepted by server")
		start_match()
	