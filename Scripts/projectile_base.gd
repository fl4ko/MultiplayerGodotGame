extends Area2D
class_name ProjectileBase

# --- exported parameters (safe names) ---
@export var bullet_speed: float = 900.0              # pixels per second
@export var direction: int = 1                       # 1 = right, -1 = left
@export var bullet_range: float = 800.0              # total distance before despawn
@export var projectile_gravity: float = 0.0              # downward acceleration (pixels/s^2)
@export var drop_start_distance: float = 0.0         # distance before gravity applies
@export var damage: int = 1

# --- internal state ---
var travelled: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var prev_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	velocity = Vector2(bullet_speed * direction, 0)
	prev_position = global_position
	monitoring = true

func _physics_process(delta: float) -> void:
	# Apply gravity after specified distance
	if projectile_gravity != 0.0 and travelled >= drop_start_distance:
		velocity.y += projectile_gravity * delta

	var motion = velocity * delta
	var new_pos = global_position + motion

	var space = get_world_2d().direct_space_state
	var from = prev_position
	var to = new_pos

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	query.collision_mask = collision_mask

	var result = space.intersect_ray(query)

	if result:
		_on_hit(result)
		return

	global_position = new_pos
	prev_position = global_position

	travelled += motion.length()
	if travelled >= bullet_range:
		queue_free()

func _on_hit(result: Dictionary) -> void:
	var collider = result.get("collider")
	if collider and collider.is_in_group("player"):
		if collider.has_method("handle_being_hit"):
			collider.handle_being_hit()
	queue_free()

# helper to initialize projectile from a gun
func setup_from_gun(
	p_speed: float,
	p_dir: int,
	p_range: float,
	p_gravity: float,
	p_damage: int = 1,
	p_drop_start: float = 0.0
) -> void:
	bullet_speed = p_speed
	direction = p_dir
	bullet_range = p_range
	projectile_gravity = p_gravity
	damage = p_damage
	drop_start_distance = p_drop_start
	velocity = Vector2(bullet_speed * direction, 0)
