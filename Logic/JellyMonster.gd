extends SoftBody3D
## Желе-монстр (QUEUE Q6 → Q25 v6 «мувер-цилиндр + узкое кольцо + FSM-мозг»,
## 22.11.26, по ответу спеца). Хроника каналов воздействия:
## - v1-v3: CharacterBody3D (move_and_slide) и Area3D-снаряды НЕ передают
##   импульс SoftBody3D; единственный канал — контакты с RigidBody3D.
## - v4 «БЕЗ ПИНОВ»: шары-толкатели RigidBody3D. Репорт юзера 21.11.26:
##   «прибит к месту» + Q25-B «упал под землю сразу при спавне». Изолят
##   probe_softcontact доказал: контакт SoftBody3D-vs-RigidBody3D в
##   GodotPhysics3d 4.8-beta3 СЛОМАН В ПРИНЦИПЕ (шар 28 кг дефолт-масок
##   пролетает купол насквозy) — v4-пинки физически не работали вовсе.
## - Q25-B: контакт софтбоди со СТАТИКОЙ нестабилен: скан probe_jelly_arena
##   mono4 16 точек — покой только в центре, 15/16 дайвят под пол
##   (precision/pressure/mass/damping/drag/stiffness/friction/шум — все не лечат).
## - v5 (Тест №1 спеца, гейт MOVEPOINT PASS 4/4): риг «мувер + пин-кольцо».
## - v6 (ответ спеца на Q25_jelly_consult_report_v52b.md): (1) ГЛАВНОЕ —
##   обмотка икосферы была CCW (OpenGL-канон), а Godot ArrayMesh ждёт CW:
##   cull_back отсекал БЛИЖНЮЮ стенку, рисовал внутренность ДАЛЬНЕЙ — вот вся
##   «прозрачность»/«подкова»/«застрял в полу»; (2) узкое пин-кольцо 0.4 м с
##   естественными оффсетами (полоса 1.3 м сминала 222 точки в плоскость);
##   (3) мувер-цилиндр (не закатывается на валуны) + steering в мозге;
##   (4) FSM поведения по КРОМКЕ купола (было «в упор»); (5) subdiv 2 +
##   precision 7 (масса вниз ×8-10, пол невидим — precision 18 не нужен).

const BrainScript = preload("res://Logic/JellyBrain.gd")
const HealthScript = preload("res://Logic/JellyHealth.gd")
const HitboxScript = preload("res://Logic/JellyHitbox.gd")

@export var radius := 2.6
@export var idle_wobble := true
# Q49 (заказ юзера 22.11.26): два вида желе. false = зелёный дружественный
# (нынешний FSM, безобидный); true = КРАСНЫЙ вражеский: сам атакует игрока
# (стейт ATTACK в мозге), имеет HP, дамажится скиллами через хитбокс.
@export var aggressive := false
@export var body_color := Color(0.32, 0.85, 0.42) # меш строится в _ready по цвету

const COLOR_FRIENDLY := Color(0.32, 0.85, 0.42)
const COLOR_AGGRESSIVE := Color(0.78, 0.16, 0.12)
const JELLY_HP := 100

const GROUP_NAME := "jelly_monster"
const JOLT_COOLDOWN_MS := 700
const PUSH_STRENGTH := 10.0 # отжим при давлении (10/9 базы → слайд ~2 м, догоняемо)

# Q25 v6 риг «мувер-цилиндр + узкое пин-кольцо» (ответ спеца 22.11.26).
const RIG_CYL_R := 2.0   # радиус ЦИЛИНДРА-мувера: вертикальные стенки не
# дают закатываться на валуны (сфера r1.6 залезала вверх — вердикт «застревает»)
const RIG_HALF_H := 0.75 # полу-высота цилиндра (h=1.5): дно мувера = center−0.75
const RIG_MASS := 40.0   # масса мувера
const RIG_BAND := 0.4    # высота УЗКОГО донного кольца пинов (спец: полоса
# 1.3 м сминала 222 точки в одну плоскость y=−0.5 — растяжение/разрывы)
const RIG_SETTLE := 0.12 # лёгкая посадка кольца вниз, оффсеты ЕСТЕСТВЕННЫЕ
const RIG_MP_SPEED := 12.0 # макс скорость move_point за тик (не рвать оболочку)
const RIG_PIN_LERP := 0.08 # сглаживание выезда кольца к посадке за тик
const RIG_LIFT_MARGIN := 0.55 # глубже (дно мувера−0.55) точки мягко выталкиваются наверх
const RIG_LIFT_K := 6.0  # Н на 1 м глубины лифт-гварда
const RIG_LIFT_CLAMP := 1.0 # кламп глубины в силе (м)
const RIG_KICK := 160.0  # Н·с муверу на контактный отжим (база strength=9)
const PINK_PEAK := 0.85  # Н·с на точку купола в эпицентре (просадка ~0.3 м, гейт DENT)
const DOME_ZONE := 1.4   # радиус зоны удара по куполу (линейный декей от точки удара)

# Поведение v6 — Logic/JellyBrain.gd (FSM APPROACH/ORBIT/FLEE/RECOVER,
# дистанции ОТ КРОМКИ купола, 3-лучевой steering, unstuck). Здесь остались
# только подскоки (мирные фазы зовут m._hop()).
const HOP_UP := 380.0         # Н·с вертикали (масса 40 → v=9.5; damp 2.0 гасит
                              # слабый импульс за долю секунды → «икание»,
                              # вердикт юзера 22.11.26 «не поднимается над землёй»)
const HOP_SIDE := 60.0        # Н·с случайного бокового сноса прыжка
const HOP_MAX_S := 1.8        # таймаут фазы подскока: если приземление не
                              # поймалось (сел на камень выше дна мувера) —
                              # vy-кламп НЕ залипает выключенным

var _last_jolt_ms := -100000
var _threat_bodies: Array = [] # CharacterBody3D внутри FeelerArea (непрерывная отдача)
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
# v6: мозг (FSM+steering, JellyBrain.gd) — подведён вместо импульсной _alive.
var _brain = BrainScript.new()
# фаза подскока: вне неё vy мувера клампится ≤0.5 (не «висит» на камнях — спец)
var _hop_active := false
var _hop_left := 0.0 # таймаут фазы подскока (HOP_MAX_S)
# ЖИВОЙ центр/верх тела (AABB точек каждый физ-тик): узел желе уходит в
# identity, тело оседает и расползается — все «прицепы» (глаза, зона, толчки)
# должны следовать за реальным телом, а не за стартовым _home (вердикт
# юзера 19.11.26: «глаза отдельно от желе»).
var _live_center := Vector3.ZERO
var _live_top := Vector3.ZERO
var _eyes: Array = []
# v6: горизонтальный «взгляд» на игрока (глаза едут вперёд по нему + look_at).
var _eye_fwd := Vector3(0, 0, 1)
# v6 риг: мувер-цилиндр (RigidBody3D на полу) + узкое пин-кольцо низа.
var _mover: RigidBody3D = null
# Q49: HP-компонент (полоска над куполом) + детект-хитбокс (AnimatableBody3D
# слой 8, заезжает за живым центром — софтбоди в физ-запросах ненадёжен).
var _health = null
var _hitbox = null
var _dying := false
var _rig_rid: RID
var _rig_pins := PackedInt32Array()
var _rig_cur: Array[Vector3] = [] # текущие оффсеты кольца в локале мувера
var _rig_tgt: Array[Vector3] = [] # целевые оффсеты (естественные + посадка −0.12)

func _ready() -> void:
	# Дом = трансформация из сцены, снимаем ДО возможного назначения меша.
	# ФАКТ 4.8-beta (probe 19.11.26): точки SoftBody3D инициализируются в
	# ГЛОБАЛЬНОМ пространстве по трансформу узла при создании тела, после чего
	# трансформ узла КАЖДЫЙ физ-синк перезаписывается в identity. Узел «в
	# origin» — норма; позиция желе = _home, дети ставятся через top_level.
	_home = global_position
	if mesh == null:
		# Фолбэк для .new()-тестов: в бою меш ставит генератор ДО add_child.
		mesh = build_blob_mesh(radius, 0.04, body_color)
	_setup_physics()
	_rig_setup_deferred()
	add_to_group(GROUP_NAME)
	_brain.aggressive = aggressive # красный: FSM → ATTACK (JellyBrain._attack_tick)
	_add_eyes()
	_add_feeler_area()
	_add_health_and_hitbox()
	if idle_wobble:
		var t := Timer.new()
		t.wait_time = 2.4
		t.autostart = true
		t.timeout.connect(_idle_poke)
		add_child(t)

## Риг ставится СТРОГО после первого полного физ-тика: в _ready тело софтбоди
## ещё не создано в физ-сервере — soft_body_pin_point/move_point на RID,
## полученный раньше, уходят в никуда (поймано mono4-гейтом: тело свободно
## ныряло). probe_movepoint PASS ставил риг ровно этой схемой
## (add_child → await physics_frame → пины).
func _rig_setup_deferred() -> void:
	await get_tree().physics_frame
	_add_mover_rig()

func _physics_process(delta: float) -> void:
	if _dying:
		return # труп разлетается: риг/мозг/хитбокс не тикают
	# Живой AABB тела + лифт-гвард в одном проходе.
	var count := get_point_count()
	if count == 0 or _mover == null:
		return # тик 1 до рига: падение ~3 мм — не заметно
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var lift_y := _mover.global_position.y - RIG_HALF_H - RIG_LIFT_MARGIN
	for i in count:
		var p := get_point_transform(i)
		lo = lo.min(p)
		hi = hi.max(p)
		if p.y < lift_y:
			apply_force(i, Vector3(0,
					minf(lift_y - p.y, RIG_LIFT_CLAMP) * RIG_LIFT_K, 0))
	if lo.x > hi.x:
		return
	_live_center = (lo + hi) * 0.5
	_live_top = Vector3(_live_center.x, hi.y, _live_center.z)
	# Хитбокс едет за живым центром (его позицию видят рейкаст/АоЕ/снаряды).
	if _hitbox != null and is_instance_valid(_hitbox):
		_hitbox.global_position = _live_center
	# Кольцо пинов каждый тик: оффсеты сглаживаются к посадке, точки двигаются
	# за мувером; шаг move_point КЛАМПИТСЯ (RIG_MP_SPEED) — оболочку не рвёт
	# (спец: при рывках move_point растягивал купол → вывороты).
	for k in _rig_pins.size():
		_rig_cur[k] = _rig_cur[k].lerp(_rig_tgt[k], RIG_PIN_LERP)
		var goal: Vector3 = _mover.to_global(_rig_cur[k])
		var curp: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(
				_rig_rid, _rig_pins[k])
		var step: Vector3 = goal - curp
		var maxstep: float = RIG_MP_SPEED * delta
		if step.length() > maxstep:
			step = step.normalized() * maxstep
		PhysicsServer3D.soft_body_move_point(_rig_rid, _rig_pins[k], curp + step)
	# Вне прыжка vy мувера клампится ≤0.5: цилиндр не «задирается» вверх
	# по камню при тяге (спец §БАГ-C.3: «запрет висеть на камне»).
	if not _hop_active and _mover.linear_velocity.y > 0.5:
		_mover.linear_velocity.y = 0.5
	if _hop_active:
		_hop_left -= delta
		if _mover.global_position.y <= RIG_HALF_H + 0.05 or _hop_left <= 0.0:
			_hop_active = false
	# Глаза едут за «взглядом» на игрока (спец §БАГ-D.3): forward сглаживается,
	# позиция на передней поверхности купола + look_at (зрачок на −Z).
	var dome := hi.y - _live_center.y
	var fwd := Vector3(0, 0, 1)
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		var tf: Vector3 = (players[0] as Node3D).global_position - _live_center
		tf.y = 0.0
		if tf.length_squared() > 0.001:
			fwd = tf.normalized()
	_eye_fwd = _eye_fwd.lerp(fwd, 0.15)
	var right := Vector3(-_eye_fwd.z, 0.0, _eye_fwd.x)
	for k in _eyes.size():
		var side := 1.0 if k == 0 else -1.0
		var target := _live_center + _eye_fwd * radius * 0.75 \
				+ right * (side * radius * 0.28) + Vector3(0, dome * 0.45, 0)
		(_eyes[k] as Node3D).global_position = \
				(_eyes[k] as Node3D).global_position.lerp(target, 0.35)
		(_eyes[k] as Node3D).look_at(_live_center + _eye_fwd * radius * 2.0)
	var area := get_node_or_null("FeelerArea")
	if area:
		area.global_position = _live_center
	# НЕПРЕРЫВНАЯ ОТДАЧА: пока тело давит на желе (идёт в него или прижалось
	# вплотную) — отжимаем; кулдаун jolt_from задаёт каденс.
	var threat: Node3D = null
	for b in _threat_bodies:
		if is_instance_valid(b):
			threat = b
			break
	if threat != null and _want_push(threat):
		# scary=false: контактный отжим — не «испуг», иначе FSM-мозг
		# включал бы FLEE от самого факта «игрок просто идёт к желе».
		jolt_from(threat.global_position, PUSH_STRENGTH, false)
	# Поведение v6: FSM-мозг (APPROACH/ORBIT/FLEE/RECOVER + steering + прыжки).
	_brain.tick(delta, self)

## Подскок (мирные фазы зовут через мозг): только с земли, случайный снос.
func _hop() -> void:
	if _mover == null or _hop_active:
		return
	var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
			_rng.randf_range(-1.0, 1.0))
	if side.length_squared() < 0.001:
		side = Vector3(1, 0, 0)
	side = side.normalized() * HOP_SIDE
	_hop_active = true
	_hop_left = HOP_MAX_S
	_mover.apply_central_impulse(Vector3(side.x, HOP_UP, side.z))

func _setup_physics() -> void:
	pressure_coefficient = 1.35 # купол как у одобренного JELLY4
	damping_coefficient = 0.02
	simulation_precision = 7 # 18 был против протекания сквозь ПОЛ, но пол
	# невидим (mask 2) — 7 достаточно, CPU ×2.5 легче (спец §8.5)
	# Слой/маска 2: пол (слой 1) и мувер ИСКЛЮЧЕНЫ из контактов желе —
	# опора = пин-кольцо на мувере, движковых контактов софтбоди нет вовсе.
	collision_layer = 2
	collision_mask = 2
	total_mass = 40.0

## Watertight-икосфера (Q25-B): SphereMesh 32×20 не замкнут — UV-шов с
## дублированными вершинами, при pressure>0 объём ТЕЧЁТ насквозь (купол
## 2.07→1.35 навсегда, поймано probe_movepoint). Икосфера subdiv 2 = 162
## уникальные вершины, без шва и полюсов (спец §8.5: CPU ×8-10 легче, вид тот же
## со сглаженными нормалями). ГРАБЛЯ-ССОТ (спец 22.11.26, «главная находка»):
## Godot ArrayMesh лицевая грань = CW — (v1−v0).cross(v2−v0).dot(outward) < 0
## (OpenGL-доки/туториалы говорят CCW!). Обмотка CCW = купол «наизнанку»:
## cull_back отсекает БЛИЖНЮЮ стенку → «прозрачность», «видна внутренняя
## сторона», «подкова». _ico_subdiv пишет индексы [a, c, b] — CW.
## Форма: ПЛОСКОЕ ШИРОКОЕ ДНО запечено в rest-меш (v.y<0 → y·0.25, верх
## 0.85) — купол с первого кадра стоит на полу; прежняя посадка пин-кольцом
## сминала полосу 1.3 м в плоскость (спец §БАГ-B). Шум по v*r до squash.
## STATIC + вызывается ГЕНЕРАТОРОМ ДО add_child: назначение меша рантаймом
## (узел уже в дереве) сбрасывает трансформ SoftBody3D в identity.
static func build_blob_mesh(r: float, noise_amp: float = 0.04,
		body_color: Color = COLOR_FRIENDLY) -> ArrayMesh:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var vlist: Array[Vector3] = [
		Vector3(-1, phi, 0).normalized(), Vector3(1, phi, 0).normalized(),
		Vector3(-1, -phi, 0).normalized(), Vector3(1, -phi, 0).normalized(),
		Vector3(0, -1, phi).normalized(), Vector3(0, 1, phi).normalized(),
		Vector3(0, -1, -phi).normalized(), Vector3(0, 1, -phi).normalized(),
		Vector3(phi, 0, -1).normalized(), Vector3(phi, 0, 1).normalized(),
		Vector3(-phi, 0, -1).normalized(), Vector3(-phi, 0, 1).normalized()]
	# Грани икосаэдра: НЕ копировать «канон» из туториалов — там дубликат
	# [3,6,8]+[8,6,3] и пропавший [6,7,8] (меш не замкнут: рёбра 6_7/7_8
	# кратности 1, 3_6/3_8 кратности 3, Эйлер 65 вместо 2 → щипки → дыры
	# на рендере; поймано probe_ico_edges). Фикс: [8,6,3] → [6,7,8],
	# кратность всех 30 рёбер = 2, V=642/E=1920/F=1280, Эйлер=2.
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [6, 7, 8], [9, 8, 1]]
	var ilist := PackedInt32Array()
	var mid := {}
	for f in faces:
		_ico_subdiv(f[0], f[1], f[2], 2, vlist, ilist, mid) # subdiv 2: 162/320
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for v in vlist:
		var q := v * r
		# ПЛОСКОЕ ШИРОКОЕ ДНО в rest-меш (спец §БАГ-B.1): низ жмётся до 0.25,
		# верх до 0.85 — купол стоит на полу сам, кольцо не сминает полусферу.
		q.y *= (0.25 if v.y < 0.0 else 0.85)
		q += _noise3(v * r) * r * noise_amp
		verts.append(q)
		norms.append(v)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = ilist
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	# НЕПРОЗРАЧНЫЙ (вердикты юзера 26.11.26 «внешняя сторона прозрачная, видна
	# только внутренняя» ×2): полупрозрачность на SoftBody3D (и чистый ALPHA,
	# и ALPHA_DEPTH_PRE_PASS) показывает внутренность дальних граней — купол
	# читается как полый «полумесяц», «застрявший в полу». Обмотка/манифолд
	# верифицированы probe_ico_winding (0 вывернутых из 1280, рёбра 60/60 с
	# парами) — дело в самой полупрозрачности. Радикальный фикс: solid-купол,
	# артефакт невозможен в принципе. (Грабля-ССОТ: enum в этом билде —
	# ..._DEPTH_PRE_PASS с подчёркиванием, онлайн-доки говорят PREPASS.)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = body_color
	mat.roughness = 0.12
	mat.rim_enabled = true
	mat.rim = 0.7
	mat.rim_tint = 0.4
	am.surface_set_material(0, mat)
	return am

## Рекурсивное дробление грани икосаэдра: mid-точки кешируются ГЛОБАЛЬНО
## (ключ mini/maxi) — вершины уникальны, шва нет.
static func _ico_subdiv(a: int, b: int, c: int, depth: int,
		vlist: Array[Vector3], ilist: PackedInt32Array, mid: Dictionary) -> void:
	if depth == 0:
		# CW-обмотка для Godot ArrayMesh (спец 22.11.26, главная находка):
		# лицевая грань — (v1−v0)×(v2−v0)·outward < 0. CCW (OpenGL-канон
		# туториалов) давал купол «наизнанку»: cull_back отсекал БЛИЖНЮЮ
		# стенку → «прозрачность», «видна внутренняя сторона».
		for i in [a, c, b]:
			ilist.append(i)
		return
	var ab := _ico_mid(a, b, vlist, mid)
	var bc := _ico_mid(b, c, vlist, mid)
	var ca := _ico_mid(c, a, vlist, mid)
	_ico_subdiv(a, ab, ca, depth - 1, vlist, ilist, mid)
	_ico_subdiv(ab, b, bc, depth - 1, vlist, ilist, mid)
	_ico_subdiv(ca, bc, c, depth - 1, vlist, ilist, mid)
	_ico_subdiv(ab, bc, ca, depth - 1, vlist, ilist, mid)

static func _ico_mid(a: int, b: int, vlist: Array[Vector3], mid: Dictionary) -> int:
	var key := "%d_%d" % [mini(a, b), maxi(a, b)]
	if mid.has(key):
		return mid[key]
	var m := ((vlist[a] + vlist[b]) * 0.5).normalized()
	vlist.append(m)
	var idx := vlist.size() - 1
	mid[key] = idx
	return idx

## Детерминированный от ПОЗИЦИИ шум: дубликаты вершин (если появятся)
## получают одинаковый сдвиг — меш не рвётся. fract() в 4.8-beta3
## НЕТ (Parse Error, поймано test_jelly) — дробная часть через floorf.
static func _noise3(v: Vector3) -> Vector3:
	var f1 := _frac(sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453)
	var f2 := _frac(sin(v.y * 93.989 + v.z * 67.345 + v.x * 12.9898) * 24634.6345)
	var f3 := _frac(sin(v.z * 41.234 + v.x * 53.123 + v.y * 29.345) * 15987.123)
	return Vector3(f1 - 0.5, f2 - 0.5, f3 - 0.5)

static func _frac(x: float) -> float:
	return x - floorf(x)

## Area3D-фидер: игрок (CharacterBody3D) вошёл в зону — отжим. top_level +
## мировая позиция: трансформ узла желе физ-синк сбрасывает в identity, дети
## узла уезжали бы в origin. Выход из зоны снимает с непрерывной отдачи.
func _add_feeler_area() -> void:
	var area := Area3D.new()
	area.name = "FeelerArea"
	area.top_level = true
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = radius * 1.45
	cs.shape = ss
	area.add_child(cs)
	area.body_entered.connect(_on_feeler_body)
	# БАГ A (спец 22.11.26): этой строки НЕ БЫЛО — игрок навсегда оставался
	# в _threat_bodies после первого входа → _want_push срабатывал с 10 м
	# при беге в сторону желе.
	area.body_exited.connect(_on_feeler_body_exit)
	add_child(area)
	area.global_position = _home

func _on_feeler_body(body: Node3D) -> void:
	if body is CharacterBody3D:
		if not _threat_bodies.has(body):
			_threat_bodies.append(body)
		# Вход в зону НЕ отжимает (вердикт юзера 26.11.26: «прыгает от меня,
		# даже подойти не могу»): желе только «замечает» — лёгкая дрожь купола.
		# Отжим — только при давлении/касании (см. _want_push в тике).
		var base := _live_center if _live_center != Vector3.ZERO else _home
		var to_body := (body.global_position - base).normalized()
		_poke_dome(base + to_body * radius * 0.8, -to_body, 0.35)

func _on_feeler_body_exit(body: Node3D) -> void:
	_threat_bodies.erase(body)

## Давит ли тело на желе прямо сейчас: РЕАЛЬНОЕ КАСАНИЕ (внутри 0.55 радиуса —
## подойти и разглядывать можно, вердикт юзера 26.11.26) или активное
## сближение на скорости. Стоящий рядом на 2+ м — не триггерит.
func _want_push(threat: Node3D) -> bool:
	var base := _live_center if _live_center != Vector3.ZERO else _home
	var to_jelly := base - threat.global_position
	to_jelly.y = 0.0
	if to_jelly.length() < radius * 0.55:
		return true
	if to_jelly.length_squared() < 0.0001:
		return true
	return threat.velocity.dot(to_jelly.normalized()) > 0.5 \
			and threat.velocity.length() > 2.5

## Толчок из точки from_pos (вход игрока в зону, прижатие или взрыв снаряда).
## Канал удара (контакт софтбоди-ригид сломан — изолят probe_softcontact):
## (1) купол мнётся серией apply_impulse(point_index) с линейным декеймом от
## точки удара на ближней стороне; (2) мувер получает центральный импульс —
## тело СДВИГАЕТСЯ ОТ источника (подвижность, вердикт «прибит к месту»).
## Взрывы дальше radius*3+3 м игнорируются; повторные — с кулдауном.
## strength — масштаб (9 = база ProjectileComponent; 10 = отжим угрозой).
func jolt_from(from_pos: Vector3, strength := 9.0, scary := true) -> void:
	var base := _live_center if _live_center != Vector3.ZERO else _home
	var center := base + Vector3(0, radius * 0.3, 0)
	var to_center := center - from_pos
	if to_center.length() > radius * 3.0 + 3.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_jolt_ms < JOLT_COOLDOWN_MS:
		return
	_last_jolt_ms = now
	var k := strength / 9.0
	# Отжим СТРОГО горизонтальный: вертикальная компонента (center выше
	# игрока) подбрасывала мувера — желе «прыгало лягушкой» (вердикт юзера).
	var away := center - from_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	_poke_dome(base - away * radius * 0.8, away, PINK_PEAK * k)
	if scary and not aggressive:
		# Испуг v6 = FSM-фаза FLEE в мозге: старт-кик 280·k + активная тяга
		# бегства 950 Н на 4-5 с (спец §БАГ-D: отлёт ~1 м и «секунда испуга»
		# не давали отхода; вердикт юзера «отходит на 1 метр и прилипает»).
		# Q49: КРАСНЫЙ (aggressive) НЕ пугается выстрелов — каждое попадание
		# уводило бы его на 8 м, дамажить невозможно. Физ-ответ = кик.
		_brain.scare(self, away, k)
	else:
		_kick_mover(away, RIG_KICK * k)

## Q49: урон от скиллов (приёмщик — JellyHitbox, слой 8; duck-typing
## take_damage у хитскана/AoE/проектайлов). Физ-ответ: дрожь купола + кик
## мувера от точки удара; FSM-испуга нет (см. jolt_from).
func take_damage(amount: int, impulse_dir: Vector3 = Vector3.ZERO) -> void:
	if _dying or _health == null:
		return
	var base := _live_center if _live_center != Vector3.ZERO else _home
	var away := impulse_dir
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
				_rng.randf_range(-1.0, 1.0))
	away = away.normalized()
	_health.take(amount)
	_poke_dome(base - away * radius * 0.8, away, PINK_PEAK * 1.2)
	_kick_mover(away, RIG_KICK * 0.8)

## Q49: HP + хитбокс. Хитбокс — AnimatableBody3D слой 8 детект-only (mask 0):
## ни с чем не коллизится физически, но виден лучам/AoE/Area-контактам.
func _add_health_and_hitbox() -> void:
	_health = HealthScript.new()
	_health.name = "JellyHealth"
	add_child(_health)
	_health.setup(JELLY_HP, radius * 1.4)
	_health.died.connect(_die)
	_hitbox = HitboxScript.new()
	_hitbox.name = "JellyHitbox"
	_hitbox.jelly = self
	add_child(_hitbox)
	var hcs := CollisionShape3D.new()
	var hsph := SphereShape3D.new()
	hsph.radius = radius
	hcs.shape = hsph
	_hitbox.add_child(hcs)
	_hitbox.global_position = _home + Vector3(0, radius * 0.35, 0)

## Смерть желе: пины снять (кольцо иначе стянет взрыв в блин), всем точкам
## импульс наружу+вверх («разлетается»), мувер/хитбокс убрать, труп удалить.
func _die() -> void:
	if _dying:
		return
	_dying = true
	if _rig_rid.is_valid():
		PhysicsServer3D.soft_body_remove_all_pinned_points(_rig_rid)
	var n := get_point_count()
	var base := _live_center if _live_center != Vector3.ZERO else _home
	for i in n:
		var out := (get_point_transform(i) - base).normalized()
		if out.length_squared() < 0.001:
			out = Vector3.UP
		apply_impulse(i, (out * 0.5 + Vector3.UP * 0.7).normalized()
				* _rng.randf_range(0.5, 1.1))
	if _hitbox != null and is_instance_valid(_hitbox):
		_hitbox.queue_free()
		_hitbox = null
	if _mover != null and is_instance_valid(_mover):
		_mover.queue_free()
		_mover = null
	get_tree().create_timer(1.2).timeout.connect(queue_free)

## Фоновая дрожь: лёгкий тычок в случайный бок — желе постоянно подрагивает,
## даже когда никто не рядом (вердикт «он не желе»). Без сдвига мувера.
func _idle_poke() -> void:
	var ang := _rng.randf() * TAU
	var dir := Vector3(cos(ang), -0.2, sin(ang)).normalized()
	var base := _live_center if _live_center != Vector3.ZERO else _home
	_poke_dome(base - dir * radius * 0.8, dir, 0.35)

## Удар по куполу: серия apply_impulse(point_index) по вершинам в зоне
## DOME_ZONE от точки удара с линейным декеймом. Гейт DENT probe_movepoint:
## peak 0.85 Н·с → просадка купола 0.32 м с полным восстановлением (икосфера).
## Кламп 1.2 Н·с на вершину (спец §8.1: потолок импульса — без выворотов).
func _poke_dome(hit: Vector3, dir: Vector3, peak: float) -> void:
	var pk := minf(peak, 1.2)
	var n := get_point_count()
	for i in n:
		var d := get_point_transform(i).distance_to(hit)
		if d < DOME_ZONE:
			apply_impulse(i, dir * (1.0 - d / DOME_ZONE) * pk)

## Центральный импульс муверу: тело (вместе с пин-кольцом) СДВИГАЕТСЯ.
func _kick_mover(dir: Vector3, impulse_len: float) -> void:
	if _mover == null:
		return
	_mover.apply_central_impulse(dir * impulse_len)

## Q25 v6 риг (спец §БАГ-B/C): мувер = RigidBody3D с ЦИЛИНДРОМ r=2.0 h=1.5 —
## вертикальные стенки физически не дают закатываться на валуны (сфера r1.6
## залезала вверх). Пин-кольцо УЗКОЕ (0.4 м над lowest, ~30-50 точек) с
## ЕСТЕСТВЕННЫМИ локальными оффсестами + посадка −0.12 м: полоса 1.3 м с
## смином 222 точек в плоскость y=−0.5 тянула оболочку на 1.88 м вниз
## (спец §БАГ-B) → растяжения/вывороты. Желе контакта с полом не имеет вовсе
## (mask 2) — опора целиком на кольце.
func _add_mover_rig() -> void:
	var n := get_point_count()
	if n == 0:
		return
	var bottom := 1e9
	for i in n:
		bottom = minf(bottom, get_point_transform(i).y)
	_mover = RigidBody3D.new()
	_mover.name = "RigMover"
	_mover.mass = RIG_MASS
	_mover.linear_damp = 2.0
	# Трение ≈ 0 (22.11.26, диагностика CURIOSITY FAIL): лимит статического
	# трения о пол μ1.0×вес40кг ≈ 392 Н ГЛОТИЛ все силы мозга ниже лимита
	# (долина пульса 245 Н, ORBIT 180 Н) → тело стояло/спало. Торможение —
	# linear_damp 2.0, а не трением.
	var mpm := PhysicsMaterial.new()
	mpm.friction = 0.05
	_mover.physics_material_override = mpm
	_mover.collision_layer = 1
	_mover.collision_mask = 1
	_mover.lock_rotation = true
	_mover.top_level = true # узел желе уходит в identity — мувер живёт в мире
	var mcs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RIG_CYL_R
	cyl.height = RIG_HALF_H * 2.0
	mcs.shape = cyl
	_mover.add_child(mcs)
	add_child(_mover)
	# Дно цилиндра на полу: центр = RIG_HALF_H (пол y=0). Спавн-высота узла
	# желе y=0.75 ставит дно меша (−0.55) у пола — посадка без рывка.
	_mover.global_position = Vector3(_home.x, RIG_HALF_H, _home.z)
	_rig_rid = get_physics_rid()
	for i in n:
		var p: Vector3 = get_point_transform(i)
		if p.y > bottom + RIG_BAND:
			continue
		PhysicsServer3D.soft_body_pin_point(_rig_rid, i, true)
		_rig_pins.append(i)
		# ЕСТЕСТВЕННЫЕ локальные оффсеты (не сминая в плоскость!), цель —
		# лёгкая посадка −RIG_SETTLE (спец §БАГ-B.2).
		_rig_cur.append(_mover.to_local(p))
		_rig_tgt.append(_mover.to_local(p) + Vector3(0, -RIG_SETTLE, 0))

## Area3D-фидер, глаза (см. _add_feeler_area) — прицепы тела.
func _add_eyes() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.96, 0.9)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.08)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = radius * 0.14
		em.height = radius * 0.28
		em.material = white
		eye.mesh = em
		eye.top_level = true # узел желе уходит в identity — глаза в мире (следит _physics_process)
		add_child(eye)
		eye.global_position = _home + Vector3(side * radius * 0.34, radius * 0.42, radius * 0.86)
		_eyes.append(eye)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = radius * 0.06
		pm.height = radius * 0.12
		pm.material = black
		pupil.mesh = pm
		# Зрачок на −Z: look_at направляет −Z на игрока — зрачок «спереди».
		pupil.position = Vector3(0, 0, -radius * 0.12)
		eye.add_child(pupil)
