extends CharacterBody3D
## Q31 тест-болванка: падение с гравитацией без ввода (для probe_mushroom_bounce).

func _physics_process(delta: float) -> void:
	velocity.y -= 9.8 * delta
	move_and_slide()
