extends CharacterBody2D

@export var projectile: PackedScene
@export var starting_gun: PackedScene

@onready var gun: Node2D = $Gun
@onready var gun_sprite: Sprite2D = $Gun/GunSprite
@onready var projectile_spawn: Node2D = $Gun/ProjectileSpawn
@onready var player: CharacterBody2D = $"."

const SPEED = 300.0
const JUMP_VELOCITY = -700.0

var facing_right:bool = true
var is_holding_gun: bool = false

func _ready() -> void:
	add_to_group("player")
	equip_staring_gun()

func equip_staring_gun():
	for child in gun.get_children():
		child.queue_free()
		
	var gun_instance = starting_gun.instantiate()
	$Gun.add_child(gun_instance)
	
	gun_sprite = gun_instance.get_node("GunSprite")
	projectile_spawn = gun_instance.get_node("ProjectileSpawn")
	is_holding_gun = true

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("Shoot") and is_holding_gun:
		fire_projectile()

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
		
		if direction > 0 and not facing_right:
			flip_gun(true)
		elif direction < 0 and facing_right:
			flip_gun(false)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
	
func flip_gun(face_right: bool):
	if face_right == facing_right:
		return

	facing_right = face_right

	# Flip the entire gun node (including position)
	gun.scale.x *= -1
	gun.position.x *= -1
	

func fire_projectile():
	var projectile = preload("res://MultiplayerGodotGame/Scenes/standard_projectile.tscn").instantiate()
	projectile.direction = 1 if facing_right else -1
	# Position the projectile at the gun's position
	projectile.position = projectile_spawn.global_position
	get_parent().add_child(projectile)

func handle_being_hit():
	handle_death()

func handle_death():
	queue_free()
