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

# Shot modifiers
@export var projectiles_per_shot: int = 1
@export var spread_degrees: float = 0.0

# Ammo / pickup / throw properties
@export var has_infinite_ammo: bool = false
@export var ammo: int = 0 # remaining ammo (ignored when has_infinite_ammo is true)
@export var max_ammo: int = 0

# Thrown weapon simulation
@export var throw_strength: float = 800.0
@export var throw_lifetime: float = 2.0
@export var throw_gravity: float = 1800.0
@export var land_distance_offset: float = 4.0

var is_thrown: bool = false
var throw_velocity: Vector2 = Vector2.ZERO
var _throw_timer: float = 0.0
var pickup_enabled: bool = false

var can_fire: bool = true
var is_firing: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if $GunSprite:
		if gun_texture:
			$GunSprite.texture = gun_texture
		else:
			push_warning("Gun has no gun_texture assigned!")
	# Always mark as a weapon. When thrown, we'll add it to the "DroppedWeapon" group.
	add_to_group("Weapon")

	# If max_ammo wasn't set in the inspector, use initial ammo as max
	if max_ammo <= 0:
		max_ammo = ammo

	# Notify listeners about initial ammo state
	emit_signal("ammo_changed", ammo, max_ammo)

	# If this gun is placed in the world (not parented to a Player), make it pickable
	if not _is_parented_to_player():
		pickup_enabled = true
		# ensure it's discoverable by players scanning for dropped weapons
		if not is_in_group("DroppedWeapon"):
			add_to_group("DroppedWeapon")
		# disable firing while world-placed (until picked up)
		can_fire = false
	else:
		# If it's inside a player already, ensure it's not in dropped group
		if is_in_group("DroppedWeapon"):
			remove_from_group("DroppedWeapon")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if fire_mode == "full_auto" and is_firing and can_fire:
		fire_projectile()

	# If thrown, update simple trajectory and landing state
	if is_thrown:
		# Apply gravity for this frame
		throw_velocity.y += throw_gravity * delta
		# Predict next position
		var from_pos: Vector2 = global_position
		var to_pos: Vector2 = global_position + throw_velocity * delta

		# Raycast to detect floor/obstacle collisions between current and next position
		var space := get_world_2d().direct_space_state
		var params := PhysicsRayQueryParameters2D.new()
		params.from = from_pos
		params.to = to_pos
		params.exclude = [self]
		params.collide_with_bodies = true
		params.collide_with_areas = true
		var col := space.intersect_ray(params)
		if col.size() > 0:
			# Hit something: place at impact point and mark landed
			# Move the gun slightly out along the collision normal so it doesn't sink into the floor
			var offset_pos: Vector2 = col.position
			if col.has("normal"):
				offset_pos += col.normal * land_distance_offset
			global_position = offset_pos
			is_thrown = false
			pickup_enabled = true
			can_fire = false
			throw_velocity = Vector2.ZERO
			add_to_group("DroppedWeapon")
			# Optionally play a landing sound here
			return
		else:
			# No collision: commit movement
			global_position = to_pos
			_throw_timer -= delta
			if _throw_timer <= 0:
				# Timer expired without collision: land at current position
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

	# Block firing if out of ammo (for limited weapons)
	if not has_infinite_ammo and ammo <= 0:
		# Optionally play an empty-click sound here
		return

	can_fire = false

	var base_dir: int = int(sign(global_transform.basis_xform(Vector2.RIGHT).x))

	# Spawn multiple projectiles per shot (shotgun-style) with spread
	for i in range(projectiles_per_shot):
		var proj: Node = projectile_scene.instantiate()
		# compute angle in degrees: 0 = right, 180 = left
		var base_angle_deg: float = 0.0 if base_dir > 0 else 180.0
		var offset: float = 0.0
		if spread_degrees != 0.0:
			offset = randf_range(-spread_degrees * 0.5, spread_degrees * 0.5)
		var angle_deg: float = base_angle_deg + offset

		proj.position = $ProjectileSpawn.global_position
		# initialize projectile properly (uses angle to set velocity)
		if proj.has_method("setup_from_gun"):
			proj.setup_from_gun(bullet_speed, base_dir, fire_range, projectile_gravity, 1, 0.0, angle_deg)
		else:
			# fallback for older projectile implementations
			proj.direction = base_dir
			proj.bullet_speed = bullet_speed
			proj.bullet_range = fire_range
			proj.projectile_gravity = projectile_gravity

		get_tree().current_scene.add_child(proj)
	# play sound once per shot
	play_fire_sound.rpc()


	# Deplete ammo for limited weapons
	if not has_infinite_ammo:
		ammo = max(ammo - 1, 0)
		emit_signal("ammo_changed", ammo, max_ammo)
		if ammo <= 0:
			# disable further firing until picked up/rewritten
			can_fire = false

	await get_tree().create_timer(fire_rate).timeout
	can_fire = true


func throw_from_player(direction: int, strength: float = -1.0) -> void:
	# Called when player throws this weapon. This preserves ammo in this instance.
	if strength <= 0:
		strength = throw_strength

	# Compute world transform before reparenting so we preserve position/scale
	var world_xform := global_transform

	var old_parent := get_parent()
	# Capture the tree reference before removing the node (removing clears get_tree())
	var tree := get_tree()
	if old_parent:
		old_parent.remove_child(self)

	if tree:
		tree.current_scene.add_child(self)
	else:
		# As a fallback, try to add to the root if available
		var root := Engine.get_main_loop()
		if root and root is SceneTree:
			(root as SceneTree).current_scene.add_child(self)

	# Restore the global transform so the gun keeps its visual size/rotation
	global_transform = world_xform

	# Start thrown simulation
	is_thrown = true
	pickup_enabled = false
	_throw_timer = throw_lifetime
	# Ensure any firing is stopped before the weapon leaves the player
	if is_firing:
		stop_firing()
		is_firing = false
	can_fire = false
	throw_velocity = Vector2(direction * strength, -strength * 0.6)

	# Tag as dropped weapon for pickup scanning
	add_to_group("DroppedWeapon")

	# Disable firing while dropped
	can_fire = false

	# Play throw sound if present
	if has_node("ShotSoundPlayer"):
		$ShotSoundPlayer.play()


func pick_up(by_player: Node) -> void:
	# Attach to player's Gun node, preserve ammo and state
	if is_thrown:
		is_thrown = false
	pickup_enabled = false

	# remove from dropped group
	if is_in_group("DroppedWeapon"):
		remove_from_group("DroppedWeapon")

	# Reparent into player's Gun container
	var target_container: Node = null
	var tree := get_tree()
	if by_player and by_player.has_node("Gun"):
		target_container = by_player.get_node("Gun")
	else:
		if tree:
			target_container = tree.current_scene
		else:
			target_container = null

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	if target_container:
		target_container.add_child(self)
		# Reset local transform so it sits properly on player's Gun container
		position = Vector2.ZERO
		rotation = 0
		scale = Vector2.ONE

	# Allow firing again when equipped
	can_fire = true

	# Update player's state if possible
	if by_player:
		# set player's variables so they know they hold this
		if by_player.has_method("_on_gun_picked_up"):
			by_player._on_gun_picked_up(self)


func _is_parented_to_player() -> bool:
	var node := get_parent()
	while node:
		if node.is_in_group("Player"):
			return true
		node = node.get_parent()
	return false
