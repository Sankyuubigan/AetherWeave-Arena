extends SoftBody3D
## Желе-монстр (QUEUE.md Q6, заказ юзера 19.11.26: «сделай монстра желе...
## по больше размером здоровенным, поставь на карту — посмотрю»): гигантский
## полупрозрачный слизень на SoftBody3D — демо soft body, юзер смотрит и
## решает судьбу фичи.
##
## Как устроено: сфера r≈2.6 м с alpha-материалом; давление (pressure_coefficient)
## надувает шар, нижняя точка запинена — желе стоит на месте и дрожит всей
## массой; маска коллизий 1 — игрок физически толкает желе, оно отвечает
## волнами. Глаза — дети узла (деформацию меша не отслеживают, но при пине
## тело почти не уезжает).
##
## ВАЖНО (поймано 19.11.26): SoftBody3D 4.8-beta НЕ имеет apply_point_impulse,
## get_point_transform возвращает Vector3 (позицию, не Transform3D) —
## покачивание импульсами невозможно; желе дрожит от физики: поселенческие
## колебания + толчки игрока (collision_mask 1).

@export var radius := 2.6

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 20
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.32, 0.85, 0.42, 0.62)
	mat.roughness = 0.12
	mat.rim_enabled = true
	mat.rim = 0.7
	mat.rim_tint = 0.4
	sphere.material = mat
	mesh = sphere

	pressure_coefficient = 1.6 # «надутый» слизень — без давления сфера сдувается
	damping_coefficient = 0.04
	simulation_precision = 8
	collision_mask = 1 # мир + игрок: желе отзывчиво на толчки
	total_mass = 40.0

	# Пин нижней вершины — deferred: точки софт-тела инициализируются после
	# входа в дерево, в _ready transform'ы ещё нулевые (поймано в headless).
	_pin_lowest.call_deferred()

	_add_eyes()

## Пин нижней вершины: монстр на месте, дрожит. get_point_transform(i) —
## Vector3-позиция точки (не Transform3D — см. шапку).
func _pin_lowest() -> void:
	if get_point_count() == 0:
		return
	var lowest := 0
	var best := INF
	for i in get_point_count():
		var y := get_point_transform(i).y
		if y < best:
			best = y
			lowest = i
	set_point_pinned(lowest, true)

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
		eye.position = Vector3(side * radius * 0.34, radius * 0.42, radius * 0.86)
		add_child(eye)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = radius * 0.06
		pm.height = radius * 0.12
		pm.material = black
		pupil.mesh = pm
		pupil.position = Vector3(0, 0, radius * 0.12)
		eye.add_child(pupil)
