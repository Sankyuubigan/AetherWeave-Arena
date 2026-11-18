extends SceneTree
## Гейты ИИ-мобов Ада (план «18.11.26 Рэгдолл и ИИ-мобы Ада.md», B + C):
##  B1) waypoints-патруль: враг вне гистерезиса ходит вокруг спавна и не убегает
##      дальше patrol_radius × 2.5
##  B2) гистерезис: бой сбрасывается не сразу — в полосе aggro..aggro×1.5 враг стоит
##  B3) преследование: игрок в aggro — дистанция сокращается
##  C1) навмеш: синхронный бейк из статических коллайдеров даёт полигоны
##  C2) преследование ЗА стеной: враг обходит препятствие (|x| > 2.5 на линии
##      стены), а не упирается «лбом» (без навмеша агент дал бы прямую линию)
##  C3) дошёл до игрока за стеной
## Ожидания — create_timer (сим-время): SceneTree.physics_frame в режиме -s
## НЕ эмитится (зонд: 0 тиков за 1 с), фазика при этом шагает штатно.

const HellMeleeEnemy = preload("res://Logic/Enemies/HellMeleeEnemy.gd")

var _fails := 0

func _init() -> void:
	_run()

func _run() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	# Плоский пол 140×140 (статический коллайдер = геометрия бейка навмеша).
	var floor_body := StaticBody3D.new()
	world.add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(140, 1, 140)
	fcs.shape = fsh
	fcs.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))
	floor_body.add_child(fcs)

	# Настоящий player.tscn: MAX_HP / take_damage / группа "player".
	var player: CharacterBody3D = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 38.0)
	world.add_child(player)

	# E1: патрульный — aggro зажат, чтобы игрок не тревожил его.
	var e1: CharacterBody3D = HellMeleeEnemy.new()
	e1.aggro_range = 8.0
	e1.patrol_radius = 5.0
	e1.position = Vector3(6, 1.0, 6)
	world.add_child(e1)

	# E3: боец (aggro 40) — гистерезис, преследование, навмеш. Далеко от игрока
	# B1-фазы (dist 48 > 60×...): не вмешивается, пока его не подведут к бою.
	var e3: CharacterBody3D = HellMeleeEnemy.new()
	e3.position = Vector3(-30, 1.0, 0)
	world.add_child(e3)

	await wait(0.3)

	# ── B1: патруль ──
	var spawn1: Vector3 = e1.spawn_pos
	var p0 := e1.global_position
	await wait(2.5)
	var moved := xz_dist(e1.global_position, p0)
	var from_spawn := xz_dist(e1.global_position, spawn1)
	check("B1 патруль: враг движется по точкам (%.2f м)" % moved, moved > 0.5)
	check("B1 патруль: не дальше patrol_radius×2.5 от спавна (%.2f м)" % from_spawn,
			from_spawn <= 5.0 * 2.5 + 1.0)

	# ── B2: гистерезис — сначала войти в бой, затем игрок в полосу 40..60 ──
	e3.global_position = Vector3(0, 1.0, -8.0)  # dist 28 < 40 → бой
	reset_interp(e3)
	player.global_position = Vector3(0, 1.0, 20.0)
	await wait(1.0)
	check("B2 вход в бой: _engaged=true", e3._engaged)
	player.global_position = Vector3(0, 1.0, 45.0)
	reset_interp(e3)
	var h0 := e3.global_position
	await wait(1.0)
	var drift := xz_dist(e3.global_position, h0)
	check("B2 гистерезис: враг стоит в полосе aggro..aggro×1.5 (дрейф %.2f м)" % drift,
			drift < 0.3 and e3._engaged)

	# ── B3: преследование (игрок снова в aggro) ──
	player.global_position = Vector3(0, 1.0, 20.0)
	reset_interp(e3)
	await wait(0.1)
	var d0 := xz_dist(e3.global_position, player.global_position)
	await wait(1.5)
	var d1 := xz_dist(e3.global_position, player.global_position)
	check("B3 преследование: дистанция сократилась %.1f → %.1f м" % [d0, d1], d1 < d0 - 1.0)

	# ── C1: бейк навмеша из статических коллайдеров ──
	var wall := StaticBody3D.new()
	world.add_child(wall)
	var wcs := CollisionShape3D.new()
	var wsh := BoxShape3D.new()
	wsh.size = Vector3(16, 2.4, 0.6)  # x −8..8, между врагом и игроком
	wcs.shape = wsh
	wcs.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 18.0))
	wall.add_child(wcs)

	var region := NavigationRegion3D.new()
	world.add_child(region)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.6
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 46.0
	nm.cell_size = 0.3
	nm.cell_height = 0.3
	region.navigation_mesh = nm
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, data, world)
	NavigationServer3D.bake_from_source_geometry_data(nm, data)
	check("C1 навмеш забекен: %d полигонов" % nm.get_polygon_count(), nm.get_polygon_count() > 0)
	await wait(0.2)  # синк навигационной карты

	# ── C2/C3: обход стены и выход к игроку ──
	e3.global_position = Vector3(0, 1.0, 2.0)  # стена z=18 между ним и игроком
	reset_interp(e3)
	player.global_position = Vector3(0, 1.0, 26.0)
	var detour := false
	var reached := false
	for i in 140:  # 14 с сим-времени
		await wait(0.1)
		var gp := e3.global_position
		if absf(gp.z - 18.0) < 2.5 and absf(gp.x) > 2.5:
			detour = true
		if gp.z > 19.0 and detour:
			reached = true
			break
	check("C2 обход стены по навмешу (|x| > 2.5 на линии стены)", detour)
	check("C3 дошёл до игрока за стеной", reached)

	_finish()

func reset_interp(body: Node3D) -> void:
	body.global_position.y = 1.0
	body.velocity = Vector3.ZERO
	body.reset_physics_interpolation()

func xz_dist(a: Vector3, b: Vector3) -> float:
	var d := a - b
	d.y = 0.0
	return d.length()

func check(name: String, ok: bool) -> void:
	if ok:
		print("HELL-AI: PASS — " + name)
	else:
		_fails += 1
		print("HELL-AI: FAIL — " + name)

func _finish() -> void:
	if _fails == 0:
		print("HELL-AI ALL PASS")
		quit(0)
	else:
		print("HELL-AI FAILED: %d" % _fails)
		quit(1)

func wait(sec: float) -> void:
	await create_timer(sec).timeout
