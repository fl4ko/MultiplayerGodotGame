extends CharacterBody2D

@export var projectile: PackedScene
@export var starting_gun: PackedScene

@onready var gun: Node2D = $Gun
@onready var gun_sprite: Sprite2D = $Gun/GunSprite
@onready var projectile_spawn: Node2D = $Gun/ProjectileSpawn
@onready var player: CharacterBody2D = $"."
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

const SPEED = 300.0
const JUMP_VELOCITY = -700.0

var current_gun: Node = null

var facing_right:bool = true
var is_holding_gun: bool = false

func _ready() -> void:
	add_to_group("player")
	if starting_gun:
		equip_starting_gun()
	if anim:
		play_animation("default")

func equip_starting_gun():
	for child in gun.get_children():
		child.queue_free()
		
	var gun_instance = starting_gun.instantiate()
	$Gun.add_child(gun_instance)
	
	gun_sprite = gun_instance.get_node("GunSprite")
	projectile_spawn = gun_instance.get_node("ProjectileSpawn")

	current_gun = gun_instance
	is_holding_gun = true

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		play_animation("jump")

	# Handle shooting

	if Input.is_action_just_pressed("Shoot") and is_holding_gun:
		current_gun.start_firing()

	if Input.is_action_just_released("Shoot") and is_holding_gun:
		current_gun.stop_firing()
	
	if Input.is_action_just_pressed("Drop_Gun") and is_holding_gun:
		drop_gun()

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
		
		if direction > 0 and not facing_right:
			flip_sprite(true)
		elif direction < 0 and facing_right:
			flip_sprite(false)

		if is_on_floor() and anim.animation != "run":
			play_animation("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if is_on_floor() and anim.animation != "default":
			play_animation("default")
	
	# If jumping/falling
	if not is_on_floor() and velocity.y < 0:
		play_animation("jump")

	move_and_slide()

func play_animation(anim_name: String):
	if anim.animation != anim_name:
		anim.play(anim_name)

func flip_sprite(face_right: bool):
	if face_right == facing_right:
		return

	facing_right = face_right

	# Flip both player sprite and gun
	anim.flip_h = not face_right

	if is_holding_gun:
		gun.scale.x *= -1
		gun.position.x *= -1

func drop_gun():
	if is_holding_gun:
		gun.free()
		is_holding_gun = false

func handle_being_hit():
	handle_death()

func handle_death():
	queue_free()
