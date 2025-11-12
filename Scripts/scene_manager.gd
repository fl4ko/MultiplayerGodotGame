extends Node2D

@export var player_scene: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var player_counter = 0
	
	for player in GameManager.connected_players:
		var current_player = player_scene.instantiate()
		current_player.name = str(GameManager.connected_players[player].id)
		add_child(current_player)

		for spawn_location in get_tree().get_nodes_in_group("SpawnPoint"):
			if spawn_location.name == str(player_counter):
				current_player.global_position = spawn_location.global_position
		player_counter += 1

	# Ensure scoreboard is shown after this scene loads
	if GameManager and GameManager.has_method("push_cached_scoreboard_to_scene"):
		GameManager.push_cached_scoreboard_to_scene()

	# Connect DeathBox hazard if present to instantly kill entering players
	var deathbox := get_node_or_null("DeathBox")
	if deathbox and deathbox.has_signal("body_entered"):
		if not deathbox.is_connected("body_entered", Callable(self, "_on_deathbox_body_entered")):
			deathbox.connect("body_entered", Callable(self, "_on_deathbox_body_entered"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func update_scoreboard(board: Dictionary, _round_num: int) -> void:
	# Update the Scoreboard VBox in the scene.
	# `board` comes as { "<pid>": score, ... }
	var scoreboard_node: Node = null
	if has_node("Scoreboard"):
		scoreboard_node = get_node("Scoreboard")
	else:
		# try root path lookup to be safe
		scoreboard_node = get_node_or_null("/root/TestScene/Scoreboard")

	if not scoreboard_node:
		print("SceneManager: no Scoreboard node found to update")
		return

	# Convert board dict to array of pairs and sort by score desc
	var entries := []
	for k in board:
		var id_int := -1
		if str(k).is_valid_int():
			id_int = int(str(k))
		entries.append({"id": id_int, "score": int(board[k])})

	entries.sort_custom(Callable(self, "_sort_score_desc"))

	# Fill rows (Scoreboard child HBoxContainers). Each row is expected to have
	# a Label child named "PlayerName" and another named "PlayerScore".
	var row_count := scoreboard_node.get_child_count()
	for i in range(row_count):
		var row = scoreboard_node.get_child(i)
		if not row:
			continue
		var name_label = row.get_node_or_null("PlayerName")
		var score_label = row.get_node_or_null("PlayerScore")
		if i < entries.size():
			var e = entries[i]
			var display_name := "P" + str(e.id)
			if GameManager.connected_players.has(e.id):
				var pdata = GameManager.connected_players[e.id]
				# Prefer dictionary field `player_name` pushed by multiplayer_controller
				if typeof(pdata) == TYPE_DICTIONARY and pdata.has("player_name"):
					display_name = str(pdata["player_name"]).strip_edges()
					if display_name == "":
						display_name = "P" + str(e.id)
			if name_label:
				name_label.text = display_name
			if score_label:
				score_label.text = str(e.score)
		else:
			if name_label:
				name_label.text = ""
			if score_label:
				score_label.text = ""


func _sort_score_desc(a: Dictionary, b: Dictionary) -> int:
	# Comparator for sort_custom: highest score first, then lower id
	if a["score"] > b["score"]:
		return -1
	elif a["score"] < b["score"]:
		return 1
	# tie-breaker: smaller id first
	if a["id"] < b["id"]:
		return -1
	elif a["id"] > b["id"]:
		return 1
	return 0


func _on_deathbox_body_entered(body: Node) -> void:
	# Walk up to find the player root (node in group "Player")
	var n: Node = body
	while n and not n.is_in_group("Player"):
		n = n.get_parent()
	if not n:
		return
	# Kill the player once
	if n.has_method("handle_death") and not bool(n.get("is_dead")):
		n.set("is_dead", true)
		n.call("handle_death")
