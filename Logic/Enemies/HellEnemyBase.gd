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

var _cd_left := 0.0
var _player: Node = null
var _last_hit_amount := 0
var _last_hit_dir := Vector3.ZERO

var mesh_node: MeshInstance3D
var hp_bar: ProgressBar
var floating_sprite: Sprite3D

func _ready():
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

func _build_body() -> void:
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
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > aggro_range:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_behaviour(dist, to_p.normalized())
	move_and_slide()

## Поведение в бою. База = ближний бой: сближение → удар вплотную на кулдауне.
func _behaviour(dist: float, dir: Vector3) -> void:
	if dist > attack_range:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cd_left <= 0.0:
			_attack()
			_cd_left = attack_cooldown

func _attack() -> void:
	if _player and _player.has_method("take_damage"):
		_player.take_damage(_damage_amount())

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
	current_health = max_health
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	is_dead = false
	mesh_node.show()
	floating_sprite.show()
	var col := get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", false)
