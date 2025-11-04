extends Node2D
class_name GunItem

@export var gun_name: String = "BigHandgun"
@export var gun_texture: Texture2D
@export var projectile_scene: PackedScene

@export_enum("semi_auto", "full_auto") var fire_mode: String = "semi_auto"
@export var fire_rate: float = 0.3
@export var fire_range: float = 600.0
@export var bullet_speed: float = 800.0
@export var projectile_gravity: float = 0.0

var can_fire: bool = true
var is_firing: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if $GunSprite:
		if gun_texture:
			$GunSprite.texture = gun_texture
		else:
			push_warning("Gun has no gun_texture assigned!")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if fire_mode == "full_auto" and is_firing and can_fire:
		fire_projectile()

func start_firing():
	is_firing = true
	if fire_mode == "semi_auto":
		fire_projectile()

func stop_firing():
	is_firing = false

func fire_projectile():
	if not can_fire or not projectile_scene:
		return
	
	can_fire = false
	var projectile = projectile_scene.instantiate()
	projectile.direction = sign(global_transform.basis_xform(Vector2.RIGHT).x)
	projectile.position = $ProjectileSpawn.global_position

	projectile.bullet_speed = bullet_speed
	projectile.bullet_range = fire_range
	projectile.projectile_gravity = projectile_gravity

	get_tree().current_scene.add_child(projectile)

	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
