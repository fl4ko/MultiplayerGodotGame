extends CharacterBody2D

signal died(player_id)

@export var projectile: PackedScene
@export var starting_gun: PackedScene

@onready var gun: Node2D = $Gun
@onready var gun_sprite: Sprite2D = $Gun/GunSprite
@onready var projectile_spawn: Node2D = $Gun/ProjectileSpawn
@onready var player: CharacterBody2D = $"."
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var ammo_bar: ProgressBar = $AmmoBar
@onready var camera: Camera2D = $Camera2D

@export var speed: float = 230.0
@export_range(0, 1) var deceleration: float = 0.4
@export_range(0, 1) var acceleration: float = 0.4
@export var jump_height: float = -700.0
@export_range(0, 1) var jump_timing: float = 0.5

@export var pickup_range: float = 48.0

var current_gun: GunItem = null

var facing_right:bool = true
var is_holding_gun: bool = false
var is_dead: bool = false

var ammo_signal_source: Node = null

func _enter_tree() -> void:
	_apply_network_authority()


func _ready() -> void:
	_apply_network_authority()
	add_to_group("Player")

	if GameManager:
		GameManager.register_player(self)

	if starting_gun:
		equip_starting_gun()

	camera.enabled = is_local_player()

	ammo_bar.visible = false
	anim.play("default")
	print("Player ready name=", name, " local_id=", multiplayer.get_unique_id(), " authority=", get_multiplayer_authority(), " is_local=", is_multiplayer_authority())


func _apply_network_authority() -> void:
	if not str(name).is_valid_int():
		return
	var authority_id := str(name).to_int()
	if authority_id <= 0:
		return
	set_multiplayer_authority(authority_id)
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(authority_id)

func equip_starting_gun():
	for child in gun.get_children():
		child.queue_free()
		
	var gun_instance = starting_gun.instantiate()
	$Gun.add_child(gun_instance)
	
	gun_sprite = gun_instance.get_node("GunSprite")
	projectile_spawn = gun_instance.get_node("ProjectileSpawn")

	current_gun = gun_instance
	is_holding_gun = true

	if is_local_player():
		attach_ammo_bar_to_gun(current_gun)

func _physics_process(delta: float) -> void:
	if not is_local_player() or is_dead:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = jump_height
		anim.play("jump")

	if Input.is_action_just_released("Jump") and velocity.y < 0:
		velocity.y *= jump_timing

	# Handle shooting
	if Input.is_action_just_pressed("Shoot") and is_holding_gun:
		rpc_fire.rpc()

	if Input.is_action_just_released("Shoot") and is_holding_gun:
		rpc_stop_fire.rpc()

	# Throw or pick up weapon
	if Input.is_action_just_pressed("Throw_Or_Pick_Up_Weapon"):
		try_throw_or_pickup()


	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = move_toward(velocity.x, direction * speed, speed * acceleration)
		
		if direction > 0 and not facing_right:
			flip_sprite(true)
		elif direction < 0 and facing_right:
			flip_sprite(false)

		if is_on_floor() and anim.animation != "run":
			anim.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, speed * deceleration)
		if is_on_floor() and anim.animation != "default":
			anim.play("default")
	
	# If jumping/falling
	if not is_on_floor() and velocity.y < 0:
		anim.play("jump")

	move_and_slide()

func flip_sprite(face_right: bool):
	if face_right == facing_right:
		return

	facing_right = face_right

	anim.flip_h = not face_right

	if is_holding_gun:
		gun.scale.x *= -1
		gun.position.x *= -1


func attach_ammo_bar_to_gun(gun_node: GunItem) -> void:
	if gun_node.has_infinite_ammo:
		ammo_bar.visible = false
		return

	ammo_bar.max_value = gun_node.max_ammo if gun_node.max_ammo > 0 else max(gun_node.ammo, 1)
	ammo_bar.value = gun_node.ammo
	ammo_bar.visible = true

	clear_ammo_signal()
	gun_node.connect("ammo_changed", Callable(self, "_on_gun_ammo_changed"))
	ammo_signal_source = gun_node



func _on_gun_ammo_changed(current: int, max_val: int) -> void:
	ammo_bar.max_value = max_val
	ammo_bar.value = current


func clear_ammo_signal() -> void:
	if ammo_signal_source:
		if ammo_signal_source.is_connected("ammo_changed", Callable(self, "_on_gun_ammo_changed")):
			ammo_signal_source.disconnect("ammo_changed", Callable(self, "_on_gun_ammo_changed"))
		ammo_signal_source = null


func clear_ammo_bar() -> void:
	clear_ammo_signal()
	ammo_bar.visible = false


func is_local_player() -> bool:
	return is_multiplayer_authority()

func try_throw_or_pickup() -> void:
	if is_holding_gun and current_gun:
		var dir := 1 if facing_right else -1
		rpc_throw_weapon.rpc(dir)
		if is_local_player():
			clear_ammo_bar()
	else:
		var weapon := find_nearest_dropped_weapon()
		if weapon:
			rpc_pickup_weapon.rpc(weapon.get_path())


@rpc("any_peer", "call_local")
func rpc_throw_weapon(direction: int) -> void:
	if current_gun:
		current_gun.throw_from_player(direction)
		current_gun = null
		is_holding_gun = false


@rpc("any_peer", "call_local")
func rpc_pickup_weapon(weapon_path: NodePath) -> void:
	var weapon: GunItem = get_node_or_null(weapon_path)
	if weapon:
		weapon.pick_up(self)
		current_gun = weapon
		is_holding_gun = true
		gun_sprite = current_gun.get_node("GunSprite")
		projectile_spawn = current_gun.get_node("ProjectileSpawn")

		if is_local_player():
			attach_ammo_bar_to_gun(current_gun)


func find_nearest_dropped_weapon() -> GunItem:
	var closest: GunItem = null
	var best_dist := 1e9
	for w in get_tree().get_nodes_in_group("DroppedWeapon"):
		var d := global_position.distance_to(w.global_position)
		if d < best_dist:
			best_dist = d
			closest = w
	if best_dist <= pickup_range:
		return closest
	return null


func on_gun_picked_up(gun_node: GunItem) -> void:
	current_gun = gun_node
	is_holding_gun = true
	gun_sprite = current_gun.get_node("GunSprite")
	projectile_spawn = current_gun.get_node("ProjectileSpawn")

	if is_local_player():
		attach_ammo_bar_to_gun(current_gun)


@rpc("any_peer", "call_local")
func rpc_fire():
	current_gun.start_firing()

@rpc("any_peer", "call_local")
func rpc_stop_fire():
	current_gun.stop_firing()

func drop_gun():
	if is_holding_gun and current_gun:
		var dir := 1 if facing_right else -1
		if is_local_player():
			clear_ammo_bar()
		current_gun.throw_from_player(dir, 5.0)
		current_gun = null
		is_holding_gun = false

@rpc("any_peer", "call_local")
func play_shoot_sound():
	return

@rpc("any_peer", "call_local")
func play_death_sound():
	$DeathSoundPlayer.play()

func handle_being_hit(hit_direction: int):
	if not is_dead:
		is_dead = true
		anim.play("dead")

		var end_pos := global_position + Vector2(50 * hit_direction, -30)
		var tween := create_tween()
		tween.tween_property(self, "global_position", end_pos, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "global_position", global_position + Vector2(80 * hit_direction, 0), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		await tween.finished

		set_physics_process(false)
		handle_death()

func handle_death():
	play_death_sound.rpc()
	drop_gun()
	$CollisionBox.disabled = true

	var pid: int = -1
	if name and str(name).is_valid_int():
		pid = int(str(name))
	else:
		pid = multiplayer.get_unique_id()
	emit_signal("died", pid)