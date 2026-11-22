extends CharacterBody3D
## База врагов ада (19.11.26, план «Боты 16.11.26» в объёме арены ада):
## FSM Стоит → Преследование → Атака → Кулдаун. Урон — % ОТ МАКС HP игрока
## (верб. юзера: ближники 5% / кд 3 с, дальники 2% / кд 5 с). После смерти
## враг респавнится через 10 с на своей точке спавна.

const GRAVITY := 9.8

func _configure() -> void:
	pass # подкласс задаёт статы и цвет

@export var max_health := 100
@export var move_speed := 3.5
@export var attack_range := 2.2 # ближний: дистанция удара; дальний: до игрока
@export var attack_cooldown := 3.0
@export var damage_pct := 5 # % от MAX_HP игрока
@export var aggro_range := 40.0
@export var respawn_delay := 10.0 # верб. юзера: респавн через 10 с

var current_health := 100
var is_dead := false
var spawn_pos: Vector3
var body_color := Color(0.55, 0.08, 0.06)

## Патруль + навмеш-преследование (заказ юзера 18.11.26): waypoints вокруг
## спавна, навмеш печётся рантайм в HellArena (геометрия = статические коллайдеры).
const PATROL_SPEED_K := 0.45  # патруль ходит неспешно
const DISENGAGE_K := 1.5      # гистерезис: бой сбрасываем дальше aggro × 1.5
const REPATH_INTERVAL := 0.3  # перепрокладка пути (10 врагов × 60 Гц — не каждый тик)
@export var patrol_radius := 5.0

var _patrol_points := PackedVector3Array()
var _patrol_idx := 0
var _engaged := false
var _nav: NavigationAgent3D = null
var _nav_repath := 0.0
var _cd_left := 0.0
var _player: Node = null
var _last_hit_amount := 0
var _last_hit_dir := Vector3.ZERO

var mesh_node: Node3D  # визуал: GraphicsWrapper скина либо красная капсула
var hp_bar: ProgressBar
var floating_sprite: Sprite3D

func _ready():
	add_to_group("aim_targets") # AIM ASSIST Q29: враг ада — цель «вражеских» скиллов
	_configure()
	current_health = max_health
	spawn_pos = global_position
	_build_body()
	_build_hp_bar()
	# Рэгдолл-смерть (PhysicalBones3D, заказ юзера 18.11.26): кукла в цвет сущности.
	var rag := Node.new()
	rag.name = "Ragdoll"
	rag.set_script(load("res://Graphics/RagdollComponent.gd"))
	rag.set("tint", body_color)
	add_child(rag)

	# Навмеш-агент: преследование и патруль обходят камни/шпили по пути.
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.8
	_nav.target_desired_distance = 0.8
	_nav.radius = 0.5
	add_child(_nav)

	# Waypoints-патруль: 4 точки вокруг спавна (радиус задают подклассы).
	for i in 4:
		var ang := TAU * i / 4.0 + randf_range(0.0, 0.6)
		_patrol_points.append(spawn_pos + Vector3(cos(ang), 0.0, sin(ang)) * patrol_radius)

func _build_body() -> void:
	# Скиннутый враг (enemy_<skin>.tscn, заказ юзера 18.11.26): визуал = GraphicsWrapper,
	# капсула остаётся только физическим коллайдером. Нет скина — красная капсула.
	var wrap := get_node_or_null("GraphicsWrapper")
	if wrap:
		mesh_node = wrap
	else:
		mesh_node = MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.45
		cap.height = 1.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		cap.material = mat
		mesh_node.mesh = cap
		mesh_node.position.y = 0.9
		add_child(mesh_node)

	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45
	sh.height = 1.8
	cs.shape = sh
	cs.position.y = 0.9
	add_child(cs)

## Полоска HP над головой — тот же приём, что у HealthComponent (SubViewport).
func _build_hp_bar() -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2(250, 40)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	hp_bar = ProgressBar.new()
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.show_percentage = false
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.9, 0.1, 0.1, 1.0)
	hp_bar.add_theme_stylebox_override("background", sb_bg)
	hp_bar.add_theme_stylebox_override("fill", sb_fg)
	viewport.add_child(hp_bar)
	floating_sprite = Sprite3D.new()
	floating_sprite.texture = viewport.get_texture()
	floating_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	floating_sprite.position.y = 2.5
	add_child(floating_sprite)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_cd_left = maxf(0.0, _cd_left - delta)
	_player = _acquire_target()
	if _player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist <= aggro_range:
		_engaged = true
		_behaviour(dist, to_p.normalized())
	elif _engaged and dist < aggro_range * DISENGAGE_K:
		_stand()  # гистерезис: игрок у границы агро — не дёргаемся в патруль
	else:
		_engaged = false
		_patrol()
	# Фейсинг скина: в бою — на игрока, в патруле — по движению (mixamo смотрит
	# +Z, та же конвенция, что у игрока — PlayerController:186).
	if _engaged:
		_face(_player.global_position, delta)
	elif velocity.length() > 0.3:
		_face(global_position + velocity, delta)
	move_and_slide()

## Плавный разворот визуала к точке (yaw = atan2(x, z), «вперёд» = +Z).
func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	mesh_node.rotation.y = lerp_angle(mesh_node.rotation.y, atan2(to.x, to.z), delta * 10.0)

## Выбор цели (Q10: переопределяется FFA-ботом — ближайший живой враг).
func _acquire_target() -> Node:
	return get_tree().get_first_node_in_group("player")

## Поведение в бою. База = ближний бой: сближение → удар вплотную на кулдауне.
func _behaviour(dist: float, dir: Vector3) -> void:
	if dist > attack_range:
		# Преследование по навмешу: путь вокруг камней/шпилей, не «лбом в стену».
		var d := _nav_dir_to(_player.global_position, get_physics_process_delta_time())
		velocity.x = d.x * move_speed
		velocity.z = d.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cd_left <= 0.0:
			_attack()
			_cd_left = attack_cooldown

func _stand() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

## Патруль: точки вокруг спавна; после боя сначала возвращается домой, потом
## продолжает круг. y в точках = 0: враг идёт по рельефу на гравитации.
func _patrol() -> void:
	var target := _patrol_points[_patrol_idx]
	if global_position.distance_to(spawn_pos) > patrol_radius * 2.5:
		target = spawn_pos  # отдалился в бою — сначала домой
	var to_t := target - global_position
	to_t.y = 0.0
	if to_t.length() > 0.8:
		var d := _nav_dir_to(target, get_physics_process_delta_time())
		var spd := move_speed * PATROL_SPEED_K
		velocity.x = d.x * spd
		velocity.z = d.z * spd
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if global_position.distance_to(spawn_pos) <= patrol_radius * 2.5:
			_patrol_idx = (_patrol_idx + 1) % _patrol_points.size()

## Направление по навмешу: путь через NavigationAgent3D, перепрокладка не чаще
## REPATH_INTERVAL. Навмеш не готов (нет региона / путь не построен) — прямая
## линия: агент до бейка отдаёт саму цель.
func _nav_dir_to(target: Vector3, delta: float) -> Vector3:
	var straight := global_position.direction_to(target)
	straight.y = 0.0
	if straight.length() < 0.001:
		return Vector3.ZERO
	if _nav == null:
		return straight.normalized()
	_nav_repath -= delta
	if _nav_repath <= 0.0:
		_nav_repath = REPATH_INTERVAL
		_nav.target_position = target
	var next := _nav.get_next_path_position()
	var d := global_position.direction_to(next)
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else straight.normalized()

func _attack() -> void:
	if _player and _player.has_method("take_damage"):
		# Q16 Шаг 6: атакующий — для Ноты-Рикошета «Потока Гармонии».
		_player.take_damage(_damage_amount(), self)

## Урон = % от МАКС HP игрока (верб. юзера), не от текущего.
func _damage_amount() -> int:
	return ceili(_player.MAX_HP * damage_pct / 100.0)

func take_damage(amount: int, impulse_dir: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return
	_last_hit_amount = amount
	_last_hit_dir = impulse_dir
	# Боевой музон: урон по врагу — сигнал MusicDirector (как у манекенов).
	var md = get_node_or_null("/root/MusicDirector")
	if md:
		md.note_combat()
	current_health -= amount
	hp_bar.value = max(0, current_health)
	if current_health <= 0:
		die()

func die() -> void:
	is_dead = true
	# Кукла-труп в месте смерти, отброс ∝ смертельному урону (заказ 18.11.26).
	var rag := get_node_or_null("Ragdoll")
	if rag:
		rag.activate(_last_hit_amount, _last_hit_dir)
	mesh_node.hide()
	floating_sprite.hide()
	var col := get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)
	await get_tree().create_timer(respawn_delay).timeout
	# Смена сцены освобождает врага — корутина умрёт вместе с ним (безопасно).
	if not is_inside_tree():
		return
	respawn()

func respawn() -> void:
	global_position = spawn_pos
	_patrol_idx = 0
	_engaged = false
	current_health = max_health
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	is_dead = false
	mesh_node.show()
	floating_sprite.show()
	var col := get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", false)
