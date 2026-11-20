extends CharacterBody3D
## Q32 тест-болванка: ходьба по прямой без ввода (probe_soft_ground).
## Класть ПОСЛЕ add_child в группу "player" — стемпит следы компонентом.

@export var move_dir := Vector2(1, 0)  # направление XZ (нормализовать самому)
@export var speed := 2.0

func _physics_process(delta: float) -> void:
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.y * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()
