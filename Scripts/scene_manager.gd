extends Node2D

@export var player_scene: PackedScene

func _ready() -> void:
	var player_counter = 0
	var player_ids := _get_player_ids_for_round()

	for player_id in player_ids:
		var current_player = player_scene.instantiate()
		current_player.name = str(player_id)
		add_child(current_player)

		for spawn_location in get_tree().get_nodes_in_group("SpawnPoint"):
			if spawn_location.name == str(player_counter):
				current_player.global_position = spawn_location.global_position
		player_counter += 1

	
	
	GameManager.push_cached_scoreboard_to_scene()

	var deathbox := get_node_or_null("DeathBox")
	if not deathbox.is_connected("body_entered", Callable(self, "_on_deathbox_body_entered")):
		deathbox.connect("body_entered", Callable(self, "_on_deathbox_body_entered"))


func _get_player_ids_for_round() -> Array[int]:
	var ids: Array[int] = []

	for id in GameManager.connected_players.keys():
		ids.append(int(id))

	if ids.size() == 0:
		ids.append(multiplayer.get_unique_id())
		for peer_id in multiplayer.get_peers():
			ids.append(int(peer_id))

	ids.sort()
	return ids


func update_scoreboard(board: Dictionary, _round_num: int) -> void:
	var scoreboard_node = get_node("HUD/Scoreboard")

	var entries := []
	for k in board:
		entries.append({"id": int(k), "score": int(board[k])})

	entries.sort_custom(Callable(self, "sort_score_desc"))

	var row_count := scoreboard_node.get_child_count()
	for i in range(row_count):
		var row = scoreboard_node.get_child(i)
		var name_label = row.get_node_or_null("PlayerName")
		var score_label = row.get_node_or_null("PlayerScore")
		if i < entries.size():
			var e = entries[i]
			var display_name := "P" + str(e.id)
			if GameManager.connected_players.has(e.id):
				display_name = str(GameManager.connected_players[e.id].player_name).strip_edges()
				if display_name == "":
					display_name = str(e.id)
			name_label.text = display_name
			score_label.text = str(e.score)
		else:
			name_label.text = ""
			score_label.text = ""


func sort_score_desc(a: Dictionary, b: Dictionary) -> int:
	if a["score"] > b["score"]:
		return -1
	elif a["score"] < b["score"]:
		return 1
	if a["id"] < b["id"]:
		return -1
	elif a["id"] > b["id"]:
		return 1
	return 0


func _on_deathbox_body_entered(body: Node) -> void:
	var n: Node = body
	while n and not n.is_in_group("Player"):
		n = n.get_parent()
	if not n:
		return
	if not bool(n.get("is_dead")):
		n.set("is_dead", true)
		n.handle_death()
