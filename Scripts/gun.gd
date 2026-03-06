extends Node2D
class_name GunItem

signal ammo_changed(current: int, max: int)

@export var gun_name: String = "BigHandgun"
@export var gun_texture: Texture2D
@export var projectile_scene: PackedScene
@export_enum("semi_auto", "full_auto") var fire_mode: String = "semi_auto"
@export var fire_rate: float = 0.3
@export var fire_range: float = 600.0
@export var bullet_speed: float = 800.0
@export var projectile_gravity: float = 0.0

@export var projectiles_per_shot: int = 1
@export var spread_degrees: float = 0.0

@export var has_infinite_ammo: bool = false
@export var ammo: int = 0
@export var max_ammo: int = 0

@export var throw_strength: float = 800.0
@export var throw_lifetime: float = 2.0
@export var throw_gravity: float = 1800.0
@export var land_distance_offset: float = 4.0
@export var wall_slide_damp: float = 0.85
@export var floor_normal_y_threshold: float = -0.6

var is_thrown: bool = false
var throw_velocity: Vector2 = Vector2.ZERO
var throw_timer: float = 0.0
var pickup_enabled: bool = false

var can_fire: bool = true
var is_firing: bool = false


func _ready() -> void:
	if gun_texture:
		$GunSprite.texture = gun_texture

	add_to_group("Weapon")

	if max_ammo <= 0:
		max_ammo = ammo

	emit_signal("ammo_changed", ammo, max_ammo)

	if not is_parented_to_player():
		pickup_enabled = true

		if not is_in_group("DroppedWeapon"):
			add_to_group("DroppedWeapon")
			
		can_fire = false
	else:
		if is_in_group("DroppedWeapon"):
			remove_from_group("DroppedWeapon")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if fire_mode == "full_auto" and is_firing and can_fire:
		fire_projectile()

	# Simulate throw
	if is_thrown:
		throw_velocity.y += throw_gravity * delta
		var from_pos: Vector2 = global_position
		var to_pos: Vector2 = global_position + throw_velocity * delta

		var space := get_world_2d().direct_space_state
		var params := PhysicsRayQueryParameters2D.new()
		params.from = from_pos
		params.to = to_pos
		params.exclude = [self]
		params.collide_with_bodies = true
		params.collide_with_areas = true
		
		# Check hit
		var col := space.intersect_ray(params)
		if col.size() > 0:
			var hit_normal: Vector2 = col.normal
			var offset_pos: Vector2 = col.position + hit_normal * land_distance_offset
			global_position = offset_pos

			# Stop on floor
			var is_floor := hit_normal.y <= floor_normal_y_threshold
			if is_floor:
				is_thrown = false
				pickup_enabled = true
				can_fire = false
				throw_velocity = Vector2.ZERO
				add_to_group("DroppedWeapon")
				return
			else:
				# Slide on wall
				throw_velocity = throw_velocity.slide(hit_normal) * wall_slide_damp
				return
		else:
			# Keep flying
			global_position = to_pos
			throw_timer -= delta
			if throw_timer <= 0:
				is_thrown = false
				pickup_enabled = true
				can_fire = false
				throw_velocity = Vector2.ZERO
				add_to_group("DroppedWeapon")
				return


func start_firing() -> void:
	is_firing = true
	if fire_mode == "semi_auto":
		fire_projectile()


func stop_firing() -> void:
	is_firing = false
	
@rpc("any_peer", "call_local")
func play_fire_sound():
	$ShotSoundPlayer.play()

func fire_projectile() -> void:
	if not can_fire or not projectile_scene:
		return

	if not has_infinite_ammo and ammo <= 0:
		return

	can_fire = false

	var base_dir: int = int(sign(global_transform.basis_xform(Vector2.RIGHT).x))

	for i in range(projectiles_per_shot):
		var proj: Node = projectile_scene.instantiate()
		# 0 = right 180 = left
		var base_angle_deg: float = 0.0 if base_dir > 0 else 180.0
		var offset: float = 0.0
		if spread_degrees != 0.0:
			offset = randf_range(-spread_degrees * 0.5, spread_degrees * 0.5)
		var angle_deg: float = base_angle_deg + offset

		proj.position = $ProjectileSpawn.global_position
		proj.setup_from_gun(bullet_speed, base_dir, fire_range, projectile_gravity, 1, 0.0, angle_deg)


		get_tree().current_scene.add_child(proj)
	play_fire_sound.rpc()


	if not has_infinite_ammo:
		ammo = max(ammo - 1, 0)
		emit_signal("ammo_changed", ammo, max_ammo)
		if ammo <= 0:
			can_fire = false

	await get_tree().create_timer(fire_rate).timeout
	can_fire = true


func throw_from_player(direction: int, strength: float = -1.0) -> void:
	if strength <= 0:
		strength = throw_strength

	var world_xform := global_transform
	var tree := get_tree()

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)

	tree.current_scene.add_child(self)

	global_transform = world_xform

	is_thrown = true
	pickup_enabled = false
	throw_timer = throw_lifetime
	if is_firing:
		stop_firing()
		is_firing = false
	can_fire = false
	throw_velocity = Vector2(direction * strength, -strength * 0.6)

	add_to_group("DroppedWeapon")

	$ShotSoundPlayer.play()


func pick_up(by_player: Node) -> void:
	if is_thrown:
		is_thrown = false
	pickup_enabled = false

	if is_in_group("DroppedWeapon"):
		remove_from_group("DroppedWeapon")

	# Choose target parent
	var target_container: Node = null
	#var tree := get_tree()
	
	target_container = by_player.get_node("Gun")
	#target_container = tree.current_scene

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	if target_container:
		# Attach and reset local transform
		target_container.add_child(self)
		position = Vector2.ZERO
		rotation = 0
		scale = Vector2.ONE

		# Match player facing
		var desired_dir := 1
		if by_player:
			var facing = by_player.get("facing_right")
			if typeof(facing) == TYPE_BOOL and facing == false:
				desired_dir = -1
		# Read current facing
		var current_dir := int(sign(global_transform.basis_xform(Vector2.RIGHT).x))
		if current_dir == 0:
			current_dir = 1
		if current_dir != desired_dir:
			# Flip if needed
			scale.x = -scale.x

	can_fire = true

	by_player.on_gun_picked_up(self)


func is_parented_to_player() -> bool:
	var node := get_parent()
	while node:
		if node.is_in_group("Player"):
			return true
		node = node.get_parent()
	return false
