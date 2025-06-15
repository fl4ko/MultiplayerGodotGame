extends Node2D
class_name GunItem

@export var gun_name: String = "Handgun"
@export var gun_texture: Texture2D
@export var projectile_type: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$GunSprite.texture = gun_texture


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
