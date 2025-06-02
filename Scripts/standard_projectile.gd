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
