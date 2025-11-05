extends CharacterBody2D

@export var projectile: PackedScene
@export var starting_gun: PackedScene

@onready var gun: Node2D = $Gun
@onready var gun_sprite: Sprite2D = $Gun/GunSprite
@onready var projectile_spawn: Node2D = $Gun/ProjectileSpawn
@onready var player: CharacterBody2D = $"."
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

@export var speed: float = 230.0
@export_range(0, 1) var deceleration: float = 0.4
@export_range(0, 1) var acceleration: float = 0.4
@export var jump_height: float = -700.0
@export_range(0, 1) var jump_timing: float = 0.5

var current_gun: Node = null

var facing_right:bool = true
var is_holding_gun: bool = false
var is_dead: bool = false

func _ready() -> void:
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())
	add_to_group("Player")

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
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		if not is_dead:
			# Add the gravity.
			if not is_on_floor():
				velocity += get_gravity() * delta

			# Handle jump.
			if Input.is_action_just_pressed("Jump") and is_on_floor():
				velocity.y = jump_height
				play_animation("jump")

			if Input.is_action_just_released("Jump") and velocity.y < 0:
				velocity.y *= jump_timing

			# Handle shooting
			if Input.is_action_just_pressed("Shoot") and is_holding_gun:
				rpc_fire.rpc()

			if Input.is_action_just_released("Shoot") and is_holding_gun:
				rpc_stop_fire.rpc()
			
			if Input.is_action_just_pressed("Drop_Gun") and is_holding_gun:
				drop_gun()

			# Get the input direction and handle the movement/deceleration.
			# As good practice, you should replace UI actions with custom gameplay actions.
			var direction := Input.get_axis("ui_left", "ui_right")
			if direction:
				velocity.x = move_toward(velocity.x, direction * speed, speed * acceleration)
				
				if direction > 0 and not facing_right:
					flip_sprite(true)
				elif direction < 0 and facing_right:
					flip_sprite(false)

				if is_on_floor() and anim.animation != "run":
					play_animation("run")
			else:
				velocity.x = move_toward(velocity.x, 0, speed * deceleration)
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

@rpc("any_peer", "call_local")
func rpc_fire():
	current_gun.start_firing()

@rpc("any_peer", "call_local")
func rpc_stop_fire():
	current_gun.stop_firing()

func drop_gun():
	if is_holding_gun:
		gun.free()
		is_holding_gun = false

@rpc("any_peer", "call_local")
func play_shoot_sound():
	return

@rpc("any_peer", "call_local")
func play_death_sound():
	$DeathSoundPlayer.play()

func handle_being_hit(hit_direction: int):
	is_dead = true
	play_animation("dead")

	var end_pos := global_position + Vector2(50 * hit_direction, -30)
	var tween := create_tween()
	tween.tween_property(self, "global_position", end_pos, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", global_position + Vector2(80 * hit_direction, 0), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	await tween.finished

	# Disable player input and stop processing further player control
	set_physics_process(false)
	handle_death()

func handle_death():
	$CollisionBox.free()
	play_death_sound.rpc()
	drop_gun()
