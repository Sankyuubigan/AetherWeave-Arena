extends "res://Logic/Enemies/HellEnemyBase.gd"
## FFA-БОТ (QUEUE Q10, план «Боты 16.11.26»): агрессивный ИИ «бот против бота
## и бот против игрока». Переиспользует FSM/навмеш/патруль/рэгдолл/респавн
## HellEnemyBase, но вместо контактного удара КАСТУЕТ скиллы через
## SpellCasterComponent (лего-компонент игрока, data-driven SkillDB).
## Цель = ближайший живой враг (игрок или другой бот, override
## _acquire_target). Анимационные узлы/ActionBar у бота отсутствуют — все
## обращения в SpellCasterComponent под get_node_or_null.

const BOT_SKILLS := ["fireball", "ball_lightning"]
const AIM_CAM_Y := 1.6
const AIM_AT_Y := 0.9 # центр капсулы цели (origin+0.9), не выше макушки

var _sc: Node = null
var _aim_cam: Camera3D = null
var _skill_idx := 0

func _configure() -> void:
	max_health = 150
	move_speed = 4.2
	attack_range = 16.0 # каст-дистанция: стоит и стреляет, не лезет в упор
	attack_cooldown = 2.6
	damage_pct = 0 # урон наносится скиллами, не контактной формулой базы
	aggro_range = 45.0
	patrol_radius = 8.0
	body_color = Color(0.16, 0.45, 0.62) # рэгдолл-труп бота — сине-стальной

func _ready() -> void:
	super._ready()
	add_to_group("ffa_bot")
	_sc = Node.new()
	_sc.name = "SpellCasterComponent"
	_sc.set_script(load("res://Logic/SpellCasterComponent.gd"))
	_sc.set("show_cast_bar", false)
	add_child(_sc)
	# Aim-риг для _aim_context: путь ЖЁСТКИЙ «SpringArm3D/Camera3D» (тот же,
	# что у игрока). Камера не current — рендерит только игрокова, стоимость 0.
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.position = Vector3(0, AIM_CAM_Y, 0)
	arm.spring_length = 0.0
	add_child(arm)
	_aim_cam = Camera3D.new()
	# Жёсткий путь _aim_context: player.get_node_or_null("SpringArm3D/Camera3D").
	# Camera3D.new() без имени получает автонейм @Camera3D@N — каст бота молча
	# отменялся пустым контекстом (test_ffa_bots FAIL 19.11.26).
	_aim_cam.name = "Camera3D"
	arm.add_child(_aim_cam)

## Ближайший ЖИВОЙ враг: игрок или другой FFA-бот (мёртвые не таргетятся —
## пока лежит кукла, драка идёт между живыми).
func _acquire_target() -> Node:
	var best: Node = null
	var best_d := 1e12
	var pool := get_tree().get_nodes_in_group("player")
	pool.append_array(get_tree().get_nodes_in_group("ffa_bot"))
	for n in pool:
		if n == self or not is_instance_valid(n):
			continue
		if n.get("is_dead"):
			continue
		var d: float = global_position.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

## Атака = каст скилла. Прицельная камера смотрит точно в цель — рейкаст
## _aim_context честный (прямо в капсулу цели); requires_target-скиллы
## валидируются как у игрока. Промах жжёт кулдаун — бот просто перевыдохнет.
func _attack() -> void:
	if _sc == null or _player == null or not is_instance_valid(_player):
		return
	# Прицел в ЦЕНТР коллизии цели (+0.9): точка +1.0 оказывалась на 0.1
	# выше капсулы (тест Q10) — рейкаст мимо, каст пустой. Позицию камеры
	# даёт родитель-arm на теле бота, look_at только разворачивает.
	var aim_at: Vector3 = _player.global_position + Vector3(0, AIM_AT_Y, 0)
	if _aim_cam.global_position.distance_squared_to(aim_at) > 0.0001:
		_aim_cam.look_at(aim_at)
	var sid: String = BOT_SKILLS[_skill_idx % BOT_SKILLS.size()]
	_skill_idx += 1
	_sc.cast_skill(sid)
