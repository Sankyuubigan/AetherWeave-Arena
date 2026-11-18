extends "res://Logic/Enemies/HellEnemyBase.gd"
## Враг дальнего боя ада (19.11.26, верб. юзера): держит дистанцию, кидает
## фаербол — 2% макс HP игрока, кулдаун 5 с. Без прямой видимости (за камнем) —
## подходит ближе, пока не увидит.

const HellFireball = preload("res://Logic/Enemies/HellFireball.gd")

const STOP_RANGE := 12.0  # с этой дистанции стоит и стреляет
const RETREAT_RANGE := 8.0 # ближе — пятится, держит дистанцию

func _configure() -> void:
	max_health = 60
	move_speed = 3.0
	attack_range = 30.0 # стреляет издалека (в пределах aggro)
	attack_cooldown = 5.0
	damage_pct = 2
	body_color = Color(0.80, 0.30, 0.10) # огненно-оранжевый

func _behaviour(dist: float, dir: Vector3) -> void:
	var los := _has_los()
	if dist < RETREAT_RANGE:
		# Пятится от игрока (спина медленнее лица — дистанцию держит).
		velocity.x = -dir.x * move_speed * 0.7
		velocity.z = -dir.z * move_speed * 0.7
	elif dist > STOP_RANGE or not los:
		# Преследование по навмешу (обход камней/шпилей), как у ближника.
		var d := _nav_dir_to(_player.global_position, get_physics_process_delta_time())
		velocity.x = d.x * move_speed
		velocity.z = d.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cd_left <= 0.0 and los:
			_attack()
			_cd_left = attack_cooldown

func _attack() -> void:
	if _player == null or not is_inside_tree():
		return
	var fb := HellFireball.new()
	fb.damage = _damage_amount()
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_parent()
	scene.add_child(fb)
	var from := global_position + Vector3(0, 1.4, 0)
	var to: Vector3 = _player.global_position + Vector3(0, 0.8, 0)
	fb.global_position = from
	fb.direction = (to - from).normalized()

## Прямая видимость игрока: рейкаст из груди врага в грудь игроку.
func _has_los() -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.4, 0)
	var to: Vector3 = _player.global_position + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit["collider"] == _player
