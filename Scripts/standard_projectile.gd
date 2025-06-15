extends CharacterBody2D

const SPEED = 7000.0

var direction: = 1

func _ready():
	if direction == -1:
		scale.x = -abs(scale.x)  # Flip horizontally
		# Adjust collision position if needed
		$CollisionShape2D.position.x *= -1

func _physics_process(delta: float) -> void:
	velocity = Vector2(SPEED * direction, 0)
	move_and_slide()
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_collider().is_in_group("player"):
			collision.get_collider().handle_being_hit()
			queue_free()
	
	if get_last_slide_collision():
		handle_collision()

func handle_collision():
	queue_free()
