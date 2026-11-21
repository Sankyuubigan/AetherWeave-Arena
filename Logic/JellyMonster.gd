extends SoftBody3D
## Желе-монстр (QUEUE Q6 → Q25 v5 «Mover-риг», 26.11.26).
##
## Хроника каналов воздействия (все пойманы пробами, не теорией):
## - v1-v3: CharacterBody3D (move_and_slide) и Area3D-снаряды НЕ передают
##   импульс SoftBody3D; единственный канал — контакты с RigidBody3D.
## - v4 «БЕЗ ПИНОВ»: шары-толкатели RigidBody3D. Репорт юзера 21.11.26:
##   «прибит к месту» + Q25-B «упал под землю сразу при спавне». Изолят
##   probe_softcontact доказал: контакт SoftBody3D-vs-RigidBody3D в
##   GodotPhysics3d 4.8-beta3 СЛОМАН В ПРИНЦИПЕ (шар 28 кг дефолт-масок
##   пролетает купол насквозь) — v4-пинки физически не работали вовсе.
## - Q25-B: контакт софтбоди со СТАТИКОЙ нестабилен: скан probe_jelly_arena
##   mono4 16 точек — покой только в центре бокса, 15/16 дайвят под пол
##   (precision/pressure/mass/damping/drag/stiffness/friction/шум — все не лечат).
## - v5 (Тест №1 спеца из tasks/Q25B_softbody_specialist_report.md, гейт
##   MOVEPOINT PASS 4/4): НЕ-WATERTIGHT SphereMesh течёт объёмом при
##   pressure>0 (купол 2.07→1.35 навсегда) → икосфера с уникальными
##   вершинами; риг «мувер + пин-кольцо»: RigidBody3D-мувер лежит на полу
##   (слой 1, контакты движка — железобетон), нижняя полоса точек пинится
##   через PhysicsServer3D.soft_body_pin_point и КАЖДЫЙ ТИК двигается
##   soft_body_move_point за мувером (пин = кинематика, но точку можно
##   двигать — докс PhysicsServer3D). Желе НЕ контактирует с полом вовсе
##   (mask 2), опора = кольцо; лифт-гвард возвращает точки, проскочившие
##   кольцо при рывках. Пинки = серии apply_impulse(point_index) по куполу
##   + центральный импульс муверу (сдвиг тела). Jolt не нужен.
##
## В headless трансформы точек реальны (probe_movepoint мерил lo/hi) —
## гейты гоняются без окна.

@export var radius := 2.6
@export var idle_wobble := true

const GROUP_NAME := "jelly_monster"
const JOLT_COOLDOWN_MS := 700
const PUSH_STRENGTH := 10.0 # отжим при давлении (10/9 базы → слайд ~2 м, догоняемо)

# Q25-B v5 риг «мувер + пин-кольцо» (все константы из probe_movepoint PASS).
const RIG_MOVER_R := 1.6 # радиус сферы-мувера
const RIG_MASS := 40.0   # масса мувера
const RIG_BAND := 1.3    # высота полосы НИЗА тела, пинящейся к муверу (м над lowest)
const RIG_SMUSH := 0.5   # посадка низа кольца ниже пола (одобренный промин JELLY4)
const RIG_PIN_LERP := 0.08 # сглаживание выезда кольца к посадке за тик
const RIG_LIFT_MARGIN := 0.55 # глубже (пол−0.55) точки мягко выталкиваются наверх
const RIG_LIFT_K := 6.0  # Н на 1 м глубины лифт-гварда
const RIG_LIFT_CLAMP := 1.0 # кламп глубины в силе (м)
const RIG_KICK := 160.0  # Н·с муверу на толчок (база strength=9): скольжение ~2 м
const PINK_PEAK := 0.85  # Н·с на точку купола в эпицентре (просадка ~0.3 м, гейт DENT)
const DOME_ZONE := 1.4   # радиус зоны удара по куполу (линейный декей от точки удара)

# «Оживление» v5.2 (выбор юзера 26.11.26: Б любопытство + В прыгун).
const CURIOSITY_RANGE := 22.0 # дальше игроку желе «не замечает» его
const CURIOSITY_FAR := 4.5    # ближе этой дистанции не подползает (личное пространство)
const CURIOSITY_FORCE := 700.0 # Н постоянной тяги (probe_curiosity: импульсы
# 90 Н·с тонут в damp 2.0 — путь 1.8 м за 4 с = «на месте»; сила 700 Н → ~1.25 м/с)
const SCARE_HOLDS_S := 0.9    # с после ИСПУГА (снаряд/взрыв) тяга и прыжок молчат
const HOP_MIN_S := 3.0        # пауза между подскоками (случайный диапазон)
const HOP_MAX_S := 6.0
const HOP_UP := 140.0         # Н·с вертикали (масса 40 → v=3.5 → высота ~0.6 м)
const HOP_SIDE := 25.0        # Н·с случайного бокового сноса прыжка

var _last_jolt_ms := -100000
var _threat_bodies: Array = [] # CharacterBody3D внутри FeelerArea (непрерывная отдача)
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
# ЖИВОЙ центр/верх тела (AABB точек каждый физ-тик): узел желе уходит в
# identity, тело оседает и расползается — все «прицепы» (глаза, зона, толчки)
# должны следовать за реальным телом, а не за стартовым _home (вердикт
# юзера 19.11.26: «глаза отдельно от желе»).
var _live_center := Vector3.ZERO
var _live_top := Vector3.ZERO
var _eyes: Array = []
# v5 риг: мувер (RigidBody3D на полу) + пин-кольцо низа.
var _mover: RigidBody3D = null
var _rig_rid: RID
var _rig_pins := PackedInt32Array()
var _rig_cur: Array[Vector3] = [] # текущие оффсеты кольца в локале мувера
var _rig_tgt: Array[Vector3] = [] # целевые оффсеты (посадка на пол−RIG_SMUSH)
# «Оживление»: обратный отсчёт до подскока; отдельный таймер ИСПУГА
# (только снаряды/взрывы) — отжим при касании испугом НЕ считается:
# иначе идущий к желе игрок держит его в вечном испуге и любопытство
# никогда не просыпается (поймано вердиктом «ко мне не идёт» 26.11.26).
var _hop_wait := 4.0
var _last_scare_ms := -100000

func _ready() -> void:
	# Дом = трансформация из сцены, снимаем ДО возможного назначения меша.
	# ФАКТ 4.8-beta (probe 19.11.26): точки SoftBody3D инициализируются в
	# ГЛОБАЛЬНОМ пространстве по трансформу узла при создании тела, после чего
	# трансформ узла КАЖДЫЙ физ-синк перезаписывается в identity. Узел «в
	# origin» — норма; позиция желе = _home, дети ставятся через top_level.
	_home = global_position
	if mesh == null:
		# Фолбэк для .new()-тестов: в бою меш ставит генератор ДО add_child.
		mesh = build_blob_mesh(radius)
	_setup_physics()
	_rig_setup_deferred()
	add_to_group(GROUP_NAME)
	_add_eyes()
	_add_feeler_area()
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
	# Живой AABB тела + лифт-гвард в одном проходе.
	var count := get_point_count()
	if count == 0 or _mover == null:
		return # тик 1 до рига: падение ~3 мм — не заметно
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	# Порог лифт-гварда = дно мувера − RIG_LIFT_MARGIN (мувер лежит на полу:
	# центр на полу+RIG_MOVER_R). Точки глубже — мягкий подъём силой.
	var lift_y := _mover.global_position.y - RIG_MOVER_R - RIG_LIFT_MARGIN
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
	# Кольцо пинов каждый тик: оффсеты сглаживаются к посадке, точки двигаются
	# за мувером (кинематика через soft_body_move_point — пин не отслеживает
	# анкеры, но его можно двигать; докс PhysicsServer3D).
	for k in _rig_pins.size():
		_rig_cur[k] = _rig_cur[k].lerp(_rig_tgt[k], RIG_PIN_LERP)
		PhysicsServer3D.soft_body_move_point(_rig_rid, _rig_pins[k],
				_mover.to_global(_rig_cur[k]))
	# Глаза едут за верхней поверхностью (top_level — узел желе в identity).
	# lerp 0.35 — глаза догоняют тело плавно, без дрожи по точкам.
	var dome := hi.y - _live_center.y
	for k in _eyes.size():
		var side := 1.0 if k == 0 else -1.0
		var target := _live_center \
				+ Vector3(side * radius * 0.30, dome * 0.72, radius * 0.50)
		(_eyes[k] as Node3D).global_position = \
				(_eyes[k] as Node3D).global_position.lerp(target, 0.35)
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
		# scary=false: контактный отжим — не «испуг», иначе любопытство
		# никогда не просыпается (вердикт «ко мне не идёт» 26.11.26).
		jolt_from(threat.global_position, PUSH_STRENGTH, false)
	_alive(delta)

## «Оживление» желе (вердикт юзера 26.11.26 «тупо стоит»; выбор: любопытство
## + прыгун). Канал тот же, что у пинков, — импульсы муверу, физика рига не
## меняется. Любопытство: игрок в группе "player" в 6-22 м — ленивая тяга с
## боковым сносом («кружит рядом»); испуг (jolt) держит паузу SCARE_HOLDS_S,
## потом желе возвращается. Прыгун: подскок ~0.6 м с случайным сносом, только
## с земли. В пробах игрока нет — тяга молчит, гейты покоя не задевает.
func _alive(delta: float) -> void:
	if _mover == null:
		return
	var scared := Time.get_ticks_msec() - _last_scare_ms < int(SCARE_HOLDS_S * 1000.0)
	# --- Любопытство: ПОСТОЯННАЯ тяга, НЕ импульсы (probe_curiosity 26.11.26:
	# кики 90 Н·с каждые 1.2 с тонут в damp 2.0 — путь 1.8 м за 4 с, «на
	# месте»; сила 700 Н → видимые ~1.25 м/с). Боковой вобл по синусу —
	# «кружит рядом», не по струне. В пробах игрока нет — тяга молчит.
	var players := get_tree().get_nodes_in_group("player")
	if not scared and players.size() > 0 and is_instance_valid(players[0]):
		var pl := players[0] as Node3D
		var base := _live_center if _live_center != Vector3.ZERO else _home
		var to_pl := pl.global_position - base
		to_pl.y = 0.0
		var dist := to_pl.length()
		if dist > CURIOSITY_FAR and dist < CURIOSITY_RANGE \
				and to_pl.length_squared() > 0.001:
			var wobble := sin(Time.get_ticks_msec() / 1000.0 * 1.3) * 0.35
			var dir := (to_pl.normalized() \
					+ Vector3(-to_pl.z, 0.0, to_pl.x).normalized() * wobble).normalized()
			_mover.apply_central_force(dir * CURIOSITY_FORCE)
	# --- Прыгун ---
	_hop_wait -= delta
	if _hop_wait <= 0.0:
		_hop_wait = _rng.randf_range(HOP_MIN_S, HOP_MAX_S)
		if not scared and _mover.global_position.y <= RIG_MOVER_R + 0.1:
			var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
					_rng.randf_range(-1.0, 1.0))
			if side.length_squared() < 0.001:
				side = Vector3(1, 0, 0)
			side = side.normalized() * HOP_SIDE
			_mover.apply_central_impulse(Vector3(side.x, HOP_UP, side.z))

func _setup_physics() -> void:
	pressure_coefficient = 1.35 # купол как у одобренного JELLY4
	damping_coefficient = 0.02
	simulation_precision = 18 # против протекания точек сквозь статику (docsgodot
	# «Using SoftBody3D» + issue #65588)
	# Слой/маска 2: пол (слой 1) и мувер ИСКЛЮЧЕНЫ из контактов желе —
	# опора = пин-кольцо на мувере, движковых контактов софтбоди нет вовсе.
	collision_layer = 2
	collision_mask = 2
	total_mass = 40.0

## Watertight-икосфера (Q25-B): SphereMesh 32×20 не замкнут — UV-шов с
## дублированными вершинами, при pressure>0 объём ТЕЧЁТ насквозь (купол
## 2.07→1.35 навсегда, поймано probe_movepoint). Икосфера subdiv 3 = 642
## уникальные вершины, без шва и полюсов. Рест-шейп: сплющивание по Y (x0.72)
## + детерминированный шум ПО направлению до squash (как в одобренном виде).
## STATIC + вызывается ГЕНЕРАТОРОМ ДО add_child: назначение меша рантаймом
## (узел уже в дереве) сбрасывает трансформ SoftBody3D в identity.
static func build_blob_mesh(r: float, noise_amp: float = 0.04) -> ArrayMesh:
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
		_ico_subdiv(f[0], f[1], f[2], 3, vlist, ilist, mid)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for v in vlist:
		var q := v * r
		q.y *= 0.72 # приземистый купол-рест — осевшее тело = слизень-купол
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
	mat.albedo_color = Color(0.32, 0.85, 0.42)
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
		for i in [a, b, c]:
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
	if scary:
		_last_scare_ms = now # испуг: тяга+прыжок молчат SCARE_HOLDS_S секунд
	var k := strength / 9.0
	# Отжим СТРОГО горизонтальный: вертикальная компонента (center выше
	# игрока) подбрасывала мувера — желе «прыгало лягушкой» (вердикт юзера).
	var away := center - from_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	_poke_dome(base - away * radius * 0.8, away, PINK_PEAK * k)
	_kick_mover(away, RIG_KICK * k)

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
func _poke_dome(hit: Vector3, dir: Vector3, peak: float) -> void:
	var n := get_point_count()
	for i in n:
		var d := get_point_transform(i).distance_to(hit)
		if d < DOME_ZONE:
			apply_impulse(i, dir * (1.0 - d / DOME_ZONE) * peak)

## Центральный импульс муверу: тело (вместе с пин-кольцом) СДВИГАЕТСЯ.
func _kick_mover(dir: Vector3, impulse_len: float) -> void:
	if _mover == null:
		return
	_mover.apply_central_impulse(dir * impulse_len)

## Q25-B v5 риг «мувер + пин-кольцо» (Тест №1, MOVEPOINT GATE PASS 4/4).
## Мувер = RigidBody3D сфера RIG_MOVER_R на полу (слой 1): контакты движка
## с полом железобетонны, мувер НЕ провалится (в отличие от софтбоди).
## Нижняя полоса точек (RIG_BAND над lowest) пинится через
## PhysicsServer3D.soft_body_pin_point и двигается soft_body_move_point за
## мувером КАЖДЫЙ ТИК. Желе контакта с полом не имеет вовсе (mask 2) —
## опора целиком на кольце; посадка низа на пол−RIG_SMUSH (промин JELLY4).
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
	_mover.collision_layer = 1
	_mover.collision_mask = 1
	_mover.lock_rotation = true
	_mover.top_level = true # узел желе уходит в identity — мувер живёт в мире
	var mcs := CollisionShape3D.new()
	var msph := SphereShape3D.new()
	msph.radius = RIG_MOVER_R
	mcs.shape = msph
	_mover.add_child(mcs)
	add_child(_mover)
	# Дно мувера на полу: центр = спавн−0.35 (низ блоба при спавне ~0.08 над
	# полом). Если спавн выше пола — мувер досядет физикой сам.
	_mover.global_position = _home + Vector3(0, -0.35, 0)
	_rig_rid = get_physics_rid()
	for i in n:
		var p: Vector3 = get_point_transform(i)
		if p.y > bottom + RIG_BAND:
			continue
		PhysicsServer3D.soft_body_pin_point(_rig_rid, i, true)
		_rig_pins.append(i)
		_rig_cur.append(_mover.to_local(p)) # старт без рывка
		# Цель посадки: XZ точки, Y = дно мувера − RIG_SMUSH (мировой пол).
		_rig_tgt.append(_mover.to_local(Vector3(p.x,
				_mover.global_position.y - RIG_MOVER_R - RIG_SMUSH, p.z)))

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
		pupil.position = Vector3(0, 0, radius * 0.12)
		eye.add_child(pupil)
