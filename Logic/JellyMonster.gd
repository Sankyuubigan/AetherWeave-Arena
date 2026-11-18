extends SoftBody3D
## Желе-монстр (QUEUE Q6 → переработка Q25; фидбэк юзера 19.11.26: «идеально
## круглый, не реагирует никак, не толкается, стоит на месте — в чем его суть?»).
##
## Почему так было: сфера с давлением 1.6 натягивалась в идеальный шар,
## единственный пин держал его намертво, а толкать было НЕЧЕМ: CharacterBody3D
## (move_and_slide) физически НЕ передаёт импульс SoftBody3D, Area3D-снаряды
## тем более. Точечных импульсов у SoftBody3D в 4.8 нет (apply_point_impulse /
## set_point_transform отсутствуют, get_point_transform -> Vector3) — единственный
## канал внешнего воздействия на точки: контакты с RigidBody3D.
##
## Как устроено теперь:
## - рест-шейп: сфера сплющена по Y (x0.88) + детерминированный шум вершин —
##   оседает рваной блобой, а не шаром (шум считается ПО Позиции вершины:
##   дубликаты на сферических швах сдвигаются одинаково — поверхность не рвётся);
## - пин-штатив: 3 нижние точки по азимут-секторам (120°) вместо одной;
## - давление 1.05, дэмпинг 0.012, precision 6 — мягкая долгая дрожь;
## - РЕАКЦИЯ НА ИГРОКА: Area3D-фидер вокруг желе, на вход CharacterBody3D
##   спавнит невидимый RigidBody3D-шар-толкатель из точки игрока в желе;
## - ФАЕРБОЛЫ/МЕТЕОР: ProjectileComponent call_group("jelly_monster", "jolt_from",
##   точка удара) — желе дёргается от взрывов (дальние фильтрует по дистанции);
## - фоновая дрожь (idle_wobble): раз в ~2.4 с маленький шар-толкатель тыкает
##   случайный бок — желе постоянно подрагивает.
## В headless get_point_transform = (0,0,0): штатив вырождается в 1 пин
## (азимут всех точек 0) — реальную форму проверяет рендер-проба и юзер.

@export var radius := 2.6
@export var idle_wobble := true

const GROUP_NAME := "jelly_monster"
const JOLT_COOLDOWN_MS := 700

var _last_jolt_ms := -100000
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
# ЖИВОЙ центр/верх тела (AABB точек каждый физ-тик): узел желе уходит в
# identity, тело оседает и расползается — все «прицепы» (глаза, зона, толчки)
# должны следовать за реальным телом, а не за стартовым _home (вердикт
# юзера 19.11.26: «глаза отдельно от желе»).
var _live_center := Vector3.ZERO
var _live_top := Vector3.ZERO
var _eyes: Array = []

func _ready() -> void:
	# Дом = трансформация из сцены, снимаем ДО возможного назначения меша.
	# ФАКТ 4.8-beta (probe 19.11.26): точки SoftBody3D инициализируются в
	# ГЛОБАЛЬНОМ пространстве по трансформу узла при создании тела, после чего
	# трансформ узла КАЖДЫЙ физ-синк перезаписывается в identity. Узел «в
	# origin» — норма; позиция желе = _home, дети ставятся через top_level.
	_home = global_position
	if mesh == null:
		# Фолбэк для .new()-тестов: в бою меш ставит генератор ДО add_child.
		mesh = _build_blob_mesh()
	_setup_physics()
	add_to_group(GROUP_NAME)
	_add_eyes()
	_add_feeler_area()
	if idle_wobble:
		var t := Timer.new()
		t.wait_time = 2.4
		t.autostart = true
		t.timeout.connect(_idle_poke)
		add_child(t)
	# Пин-юбка — deferred: точки должны быть инициализированы телом.
	_pin_skirt.call_deferred()

func _reanchor() -> void:
	_pin_skirt()

func _physics_process(_delta: float) -> void:
	# Живой AABB тела: в headless трансформы (0,0,0) → lo==hi → скип.
	var count := get_point_count()
	if count == 0:
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in count:
		var p := get_point_transform(i)
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x > hi.x:
		return
	_live_center = (lo + hi) * 0.5
	_live_top = Vector3(_live_center.x, hi.y, _live_center.z)
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

func _setup_physics() -> void:
	pressure_coefficient = 1.35 # v3: купол держит форму (1.05 оседал лужей, 1.6 = «идеальный шар»)
	damping_coefficient = 0.02
	simulation_precision = 10 # жёстче соединения — меньше вяло-дрягающейся лужи (вердикт юзера)
	collision_mask = 1 # мир + шары-толкатели (layer 1)
	total_mass = 40.0

## Сфера -> рваная блоба: сплющивание по Y + шум вершин. Индексы/UV не трогаем,
## поверхность остаётся замкнутой. PrimitiveMesh.get_mesh_arrays есть, Mesh.get_mesh_arrays —
## НЕТ (поймано пробой 19.11.26). STATIC + вызывается ГЕНЕРАТОРОМ ДО add_child:
## назначение меша рантаймом (узел уже в дереве) сбрасывает трансформ SoftBody3D
## в identity (probe 19.11.26) — в сцене меш должен существовать ДО входа в дерево.
static func build_blob_mesh(r: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 32
	sphere.rings = 20
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		v.y *= 0.72 # v3: приземистый купол-рест — осевшее тело = слизень-купол, не лужа
		v += _noise3(v) * r * 0.04
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.32, 0.85, 0.42, 0.78)
	mat.roughness = 0.12
	mat.rim_enabled = true
	mat.rim = 0.7
	mat.rim_tint = 0.4
	am.surface_set_material(0, mat)
	return am

func _build_blob_mesh() -> ArrayMesh:
	return build_blob_mesh(radius)

## Детерминированный от ПОЗИЦИИ шум: дубликаты вершин (шов сферы, полюса)
## получают одинаковый сдвиг — меш не рвётся по швам. fract() в 4.8-beta3
## НЕТ (Parse Error, поймано test_jelly) — дробная часть через floorf.
static func _noise3(v: Vector3) -> Vector3:
	var f1 := _frac(sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453)
	var f2 := _frac(sin(v.y * 93.989 + v.z * 67.345 + v.x * 12.9898) * 24634.6345)
	var f3 := _frac(sin(v.z * 41.234 + v.x * 53.123 + v.y * 29.345) * 15987.123)
	return Vector3(f1 - 0.5, f2 - 0.5, f3 - 0.5)

static func _frac(x: float) -> float:
	return x - floorf(x)

## Пин-ЮБКА (v3, диагноз «хотдог-гамак» от юзера): 3 пина при провисшем теле
## = мешок, растянутый между опорами. Пиним ВСЕ точки нижних ~18% высоты —
## тело стоит куполом на «подоле», верх живо дрожит от толчков. Headless-
## грабля: трансформы (0,0,0) → span 0 → пинится всё; для теста сойдёт.
func _pin_skirt() -> void:
	var count := get_point_count()
	if count == 0:
		return
	var lo_y := 1e9
	var hi_y := -1e9
	for i in count:
		var y := get_point_transform(i).y
		lo_y = minf(lo_y, y)
		hi_y = maxf(hi_y, y)
	var threshold := lo_y + (hi_y - lo_y) * 0.18
	for i in count:
		if get_point_transform(i).y <= threshold:
			set_point_pinned(i, true)

## Area3D-фидер: игрок (CharacterBody3D) вошёл в зону — толкаем. top_level +
## мировая позиция: трансформ узла желе физ-синк сбрасывает в identity, дети
## узла уезжали бы в origin.
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
		jolt_from(body.global_position, 9.0)

## Толчок из точки from_pos (вход игрока в зону или взрыв снаряда рядом):
## невидимый RigidBody3D-шар летит в желе и физически пушит точки. Взрывы
## дальше radius*3+3 м игнорируются; повторные толчки — с кулдауном.
## Центр берём от _home: трансформ узла желе всегда identity (факт 4.8).
func jolt_from(from_pos: Vector3, strength := 9.0) -> void:
	var base := _live_center if _live_center != Vector3.ZERO else _home
	var center := base + Vector3(0, radius * 0.3, 0)
	var to_center := center - from_pos
	if to_center.length() > radius * 3.0 + 3.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_jolt_ms < JOLT_COOLDOWN_MS:
		return
	_last_jolt_ms = now
	var dir := to_center.normalized()
	# Шар стартует в 1.3 м от источника в сторону желе (вне капсулы игрока),
	# на высоте центра масс — влетает в бок софтбоди.
	_make_pusher(from_pos + dir * 1.3 + Vector3(0, radius * 0.25, 0), dir * strength, 9.0)

## Фоновая дрожь: маленький шар тыкает случайный бок — желе постоянно
## подрагивает, даже когда никто не рядом (вердикт «он не желе»).
func _idle_poke() -> void:
	var ang := _rng.randf() * TAU
	var dir := Vector3(cos(ang), -0.2, sin(ang)).normalized()
	var base := _live_center if _live_center != Vector3.ZERO else _home
	var center := base + Vector3(0, radius * 0.35, 0)
	_make_pusher(center - dir * (radius + 0.7), dir * 2.8, 4.0)

func _make_pusher(pos: Vector3, vel: Vector3, mass_kg: float) -> void:
	var ball := RigidBody3D.new()
	ball.collision_layer = 1 # софтбоди (mask 1) видит шар; сам шар ни с чем не считается
	ball.collision_mask = 0
	ball.gravity_scale = 0.0
	ball.continuous_cd = true
	ball.mass = mass_kg
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.4
	cs.shape = ss
	ball.add_child(cs)
	var holder := get_parent()
	if holder == null:
		holder = self
	holder.add_child(ball)
	ball.global_position = pos
	ball.linear_velocity = vel
	get_tree().create_timer(0.6).timeout.connect(ball.queue_free)

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
