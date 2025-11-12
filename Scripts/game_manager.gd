extends Node
var connected_players = {}

# Round / Match settings
@export var min_players: int = 2
@export var max_players: int = 4
@export var rounds_to_win: int = 3
@export var round_restart_delay: float = 3.0
@export var round_scene_path: String = "res://MultiplayerGodotGame/Scenes/test_scene.tscn"
@export var control_scene_path: String = "res://MultiplayerGodotGame/Scenes/Multiplayer/control.tscn"

var scores: Dictionary = {}
var round_active: bool = false
var current_round: int = 0
var player_states: Dictionary = {}

# Cache last scoreboard so freshly loaded round scenes can immediately display it
var _last_scoreboard: Dictionary = {}
var _last_round_num: int = 0

# Internal state
var _match_active: bool = false
var _last_started_round: int = -1

func _ready() -> void:
	# GameManager no longer auto-starts a match on server startup.
	# Matches must be explicitly requested (e.g. via GameController/UI).
	pass


func register_controller(controller: Node) -> void:
	# Keep a connection to the controller's start signal so GameManager can handle start requests centrally
	if controller and controller.has_signal("start_pressed"):
		# Use a safe connect so duplicate connects aren't made
		if not controller.is_connected("start_pressed", Callable(self, "_on_controller_start_pressed")):
			controller.connect("start_pressed", Callable(self, "_on_controller_start_pressed"))


func register_player(player_node: Node) -> void:
	# Called by player instances (on ready) to let GameManager connect to their death signal.
	# Only the server needs to track player states for round adjudication.
	if not multiplayer.is_server():
		return
	if not player_node:
		return
	# try to find player id from node name
	var pid: int = -1
	if player_node.name and str(player_node.name).is_valid_int():
		pid = int(str(player_node.name))
	else:
		return

	# connect to died signal if present
	if player_node.has_signal("died"):
		if not player_node.is_connected("died", Callable(self, "_on_player_died")):
			player_node.connect("died", Callable(self, "_on_player_died"))

	# mark player alive for this round
	player_states[pid] = true
	print("GameManager: registered player", pid)


func _on_player_died(player_id: int) -> void:
	# Only server should process death events for round logic
	if not multiplayer.is_server():
		return
	print("GameManager: received died signal for", player_id)
	player_states[player_id] = false
	_evaluate_round_end()


func _evaluate_round_end() -> void:
	# Count how many connected players are still alive according to player_states
	var alive_ids := []
	for id in player_states:
		if player_states[id]:
			alive_ids.append(id)

	print("GameManager: _evaluate_round_end -> alive_ids=", alive_ids)

	if alive_ids.size() == 1:
		_end_round(int(alive_ids[0]))
	elif alive_ids.size() == 0:
		_end_round(-1)


func _on_controller_start_pressed() -> void:
	# Called locally when any controller emits the start_pressed signal
	# If this is the server, start match directly (with player count check)
	if multiplayer.is_server():
		var player_count := connected_players.size()
		if player_count < min_players:
			print("GameManager: start request ignored on server - not enough players (", player_count, ")")
			return
		print("GameManager: start pressed on server - starting match")
		start_match()
	else:
		# If this is a client, request the server to start the match
		print("GameManager: client requested start - forwarding to server")
		rpc_request_start_match.rpc_id(1)

func _process(_delta: float) -> void:
	# Only the server should govern round state
	if not multiplayer.is_server():
		return

	# Do not auto-start matches here. Matches must be explicitly requested by the host/UI.
	# If you want a server to auto-start when enough players are present, implement that
	# in a controlled place (for example, respond to a signal or explicit request).

	# If a round is active, check for round end conditions
	# if _match_active and round_active:
	# 	_check_round_end()


func start_match() -> void:
	print("GameManager: starting match")
	# Initialize scores for connected players
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
	print("GameManager: starting round", current_round)
	# Instruct all peers (including server) to load the round scene so everyone resets
	rpc_start_round.rpc(round_scene_path, current_round)
	rpc_update_scoreboard()


@rpc("any_peer", "call_local")
func rpc_start_round(scene_path: String, round_num: int) -> void:
	# Ignore duplicate starts for the same round (prevents constant reloads)
	if _last_started_round == round_num:
		return
	_last_started_round = round_num
	print("rpc_start_round: loading round scene", scene_path, "round", round_num)
	get_tree().change_scene_to_file(scene_path)

func _check_round_end() -> void:
	# Count alive players (nodes in group "Player" that are not dead)
	var players := get_tree().get_nodes_in_group("Player")
	var alive := []
	for p in players:
		if not p:
			continue
		var dead := _node_is_dead(p)
		if not dead:
			alive.append(p)

	print("GameManager: _check_round_end -> total players=", players.size(), " alive=", alive.size())

	if alive.size() == 1:
		var winner: Node = alive[0]
		var winner_id: int = -1
		if winner and winner.name and str(winner.name).is_valid_int():
			winner_id = int(str(winner.name))
		print("GameManager: round winner detected:", winner.name)
		_end_round(winner_id)
	elif alive.size() == 0:
		print("GameManager: round ended with no survivors (draw)")
		_end_round(-1)

func _end_round(winner_id: int) -> void:
	# Award round if there is a winner
	round_active = false
	if winner_id >= 0:
		if not scores.has(winner_id):
			scores[winner_id] = 0
		scores[winner_id] += 1
		print("GameManager: awarding round to", winner_id, "total wins:", scores[winner_id])
	rpc_update_scoreboard()

	# Check for match winner
	var match_winner: int = -1
	for id in scores:
		if scores[id] >= rounds_to_win:
			match_winner = int(id)
			break

	if match_winner >= 0:
		print("GameManager: match winner:", match_winner)
		_end_match(match_winner)
		return

	# Schedule next round after delay
	_schedule_next_round()


func _node_is_dead(p: Node) -> bool:
	# Robustly determine whether the player node is dead.
	# Prefer calling a method named `is_dead()` if present. Otherwise try to read a boolean property `is_dead`.
	if not p:
		return true
	# If the node exposes a method, call it (method should return a boolean)
	if p.has_method("is_dead"):
		var res = p.call("is_dead")
		return bool(res)

	# Try to read a property named `is_dead` safely using get(); returns null if absent
	var val = p.get("is_dead")
	if typeof(val) == TYPE_BOOL:
		return val

	# Fallback: consider node alive by default
	return false

func _schedule_next_round() -> void:
	# Use a timer to restart the round after round_restart_delay seconds
	print("GameManager: scheduling next round in", round_restart_delay, "seconds")
	await get_tree().create_timer(round_restart_delay).timeout
	start_round()

func _end_match(winner_id: int) -> void:
	print("GameManager: ending match. Winner:", winner_id)
	# Ensure clients have the final scoreboard
	rpc_update_scoreboard()

	# Small delay so players can see final scores/animations before being returned to the lobby
	var end_delay: float = 3.0
	print("GameManager: waiting", end_delay, "seconds before returning to lobby")
	await get_tree().create_timer(end_delay).timeout

	# Broadcast RPC to all peers so every connected player returns to the control scene
	rpc("rpc_end_match", winner_id)

	# finalize match state on server
	_match_active = false


func rpc_update_scoreboard() -> void:
	# Broadcast scoreboard to clients.
	# Build a structured payload per player id: { "score": X, "player_name": Y }
	var board := {}
	for id in connected_players:
		var score_val := 0
		if scores.has(id):
			score_val = int(scores[id])
		var pname := "Player " + str(id)
		var pdata = connected_players[id]
		if typeof(pdata) == TYPE_DICTIONARY and pdata.has("player_name"):
			var raw_name = str(pdata["player_name"]).strip_edges()
			if raw_name != "":
				pname = raw_name
		board[str(id)] = {"score": score_val, "player_name": pname}

	_last_scoreboard = board
	_last_round_num = current_round

	# send via RPC to all peers
	rpc("rpc_receive_scoreboard", board, current_round)

@rpc("any_peer", "call_local")
func rpc_receive_scoreboard(board: Dictionary, round_num: int) -> void:
	# Clients receive and may display scoreboard.
	print("Scoreboard update (round", round_num, "):")
	for k in board:
		var entry = board[k]
		if typeof(entry) == TYPE_DICTIONARY:
			print("  ", entry.get("player_name", k), " -> ", entry.get("score", 0))
		else:
			print("  player", k, ":", entry)

	# Cache locally (client side) too so late-loaded scenes can pull it
	_last_scoreboard = board
	_last_round_num = round_num

	# Forward the scoreboard to the current scene if it implements `update_scoreboard`.
	var current_scene = get_tree().get_current_scene()
	if current_scene and current_scene.has_method("update_scoreboard"):
		current_scene.call("update_scoreboard", board, round_num)

@rpc("any_peer", "call_local")
func rpc_end_match(winner_id: int) -> void:
	print("rpc_end_match: winner is", winner_id, "- returning to control scene")
	# Optionally perform local cleanup here
	# Return to control scene for all peers
	get_tree().change_scene_to_file(control_scene_path)


@rpc("any_peer")
func rpc_request_start_match() -> void:
	# Called by any peer to request the server to start the match
	if multiplayer.is_server():
		# verify we have enough connected players before starting
		var player_count := connected_players.size()
		if player_count < min_players:
			print("GameManager: start match request rejected: not enough players (", player_count, ")")
			return
		print("GameManager: start match requested and accepted by server")
		start_match()
