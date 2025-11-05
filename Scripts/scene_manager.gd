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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
