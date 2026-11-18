extends Node3D
## Арена ада (19.11.26, верб. юзера): «хаос как в аду Майнкрафта, но без
## кубов» — рельеф TerrainBuilder тема hell (камень PolyHaven × багровая
## палитра), багровый свет/туман, базальтовые шпили, камни, лава-лужи.
## Враги: 5 ближних + 5 дальних (HellEnemyBase FSM), респавн 10 с.
## Смерть игрока → респавн на MainArena (PlayerController.take_damage).

const TERRAIN_SIZE := 200.0
## Чанк скаттера: свой MultiMeshInstance3D на чанк (ревью спеца §4, паттерн
## ProceduralArena) — иначе гигантский AABB группы ломает frustum culling.
const SCATTER_CHUNK := 32.0

const HellMeleeEnemy = preload("res://Logic/Enemies/HellMeleeEnemy.gd")
const HellRangedEnemy = preload("res://Logic/Enemies/HellRangedEnemy.gd")
const NPCTeleporter = preload("res://Logic/NPCTeleporter.gd")

## Скины врагов (заказ юзера 18.11.26: одно поведение = один скин):
## мили-брут — Demon T Wiezzorek, кастер фаерболов — Ganfaul M Aure.
## Нет сцены скина (тесты/чистый headless) — фолбэк на красную капсулу.
const MELEE_SKIN := "res://Scenes/enemy_Demon_T_Wiezzorek.tscn"
const RANGED_SKIN := "res://Scenes/enemy_Ganfaul_M_Aure.tscn"

var _noise: FastNoiseLite
var _loading_layer: CanvasLayer
var _loading_label: Label

func _ready():
	print("Runtime: Generating Hell Arena...")
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	# Хаотичнее лесной карты: чаще, больше октав, амплитуда 5 м.
	_noise.frequency = 0.02
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.fractal_gain = 0.55

	# Генерация БЕЗ фриза (17.11.26: фриз → юзер долбил телепорт → петля
	# регенераций; паттерн ProceduralArena: шаги по кадрам + оверлей стадии).
	_generate_async()

func _generate_async() -> void:
	_make_loading_overlay()
	await get_tree().process_frame
	await _gen_step("Рельеф ада...", _add_terrain)
	await _gen_step("Шпили и камни...", _add_rocks)
	await _gen_step("Навигация мобов...", _add_navmesh)
	await _gen_step("Лава и свет...", _add_lava)
	await _gen_step("Существа и игрок...", _add_entities)

	var profiler = preload("res://Logic/Diagnostics/MapProfiler.gd").new()
	profiler.name = "MapProfiler"
	add_child(profiler)

	print("Runtime: Hell Arena generation complete!")
	_loading_layer.queue_free()

func _gen_step(text: String, fn: Callable) -> void:
	_loading_label.set_text(text)
	await get_tree().process_frame
	fn.call()
	await get_tree().process_frame

func _make_loading_overlay() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 90
	add_child(_loading_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var label := Label.new()
	label.text = "Генерация карты..."
	label.custom_minimum_size = Vector2(280, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_loading_layer.add_child(panel)
	_loading_label = label

func _height(x: float, z: float) -> float:
	return _noise.get_noise_2d(x, z) * 5.0

func _add_terrain():
	var TerrainBuilder = preload("res://Logic/Procedural/TerrainBuilder.gd")
	TerrainBuilder.build(self, _height, TERRAIN_SIZE, "hell")

## Камни (нейро-проп) + базальтовые шпили (процедурные конусы) — хаос без кубов.
func _add_rocks():
	var rock_mesh: Mesh = load("res://Graphics/Environment/Props/test_stone/test_stone_mesh_0.res")
	if rock_mesh == null:
		var sphere = SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.3
		rock_mesh = sphere

	var spire_mesh := CylinderMesh.new()
	spire_mesh.top_radius = 0.15
	spire_mesh.bottom_radius = 0.8
	spire_mesh.height = 7.0
	var spire_mat := StandardMaterial3D.new()
	spire_mat.albedo_color = Color(0.07, 0.05, 0.05) # угольный базальт
	spire_mesh.material = spire_mat

	var rng := RandomNumberGenerator.new()
	var half := TERRAIN_SIZE / 2.0 - 10.0
	_add_scatter_group("Rocks", rock_mesh, 120, rng, half, 4.0, 10.0, 0.6, 2.4, true)
	_add_scatter_group("Spires", spire_mesh, 60, rng, half, 8.0, 10.0, 0.6, 1.8, true, true) # +окклюдеры (Q2)

## Сокращённый скаттер из ProceduralArena (чанки MultiMesh + коллизия-цилиндры).
func _add_scatter_group(group_name: String, mesh: Mesh, count: int, rng: RandomNumberGenerator, half: float, spacing: float, spawn_clear_radius: float, scale_lo: float, scale_hi: float, always_scale: bool, with_occluders: bool = false) -> void:
	rng.seed = randi()
	var aabb := mesh.get_aabb()
	var lift := -minf(aabb.position.y, 0.0) - aabb.size.y * 0.1
	var aabb_center := aabb.position + aabb.size * 0.5

	var positions := []
	for i in count * 3:
		var x = rng.randf_range(-half, half)
		var z = rng.randf_range(-half, half)
		# Центр (спавн игрока/непися) держим свободным.
		if abs(x) < spawn_clear_radius and abs(z) < spawn_clear_radius:
			continue
		var too_close := false
		for p in positions:
			if (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) < spacing * spacing:
				too_close = true
				break
		if too_close:
			continue
		positions.append(Vector3(x, _height(x, z), z))
		if positions.size() >= count:
			break
	if positions.is_empty():
		return

	var instance_transforms: Array[Transform3D] = []
	for i in positions.size():
		var s := 1.0
		if always_scale or rng.randf() > 0.5:
			s = rng.randf_range(scale_lo, scale_hi)
		var t := Transform3D.IDENTITY
		t.origin = positions[i] + Vector3(0, lift * s, 0)
		t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(0, PI * 2))
		if s != 1.0:
			t.basis = t.basis.scaled(Vector3(s, s, s))
		instance_transforms.append(t)

	var chunks := {}
	for t in instance_transforms:
		var key := Vector2i(floori(t.origin.x / SCATTER_CHUNK), floori(t.origin.z / SCATTER_CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t)

	var group_root := Node3D.new()
	group_root.name = group_name
	add_child(group_root)

	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = list.size()
		mm.mesh = mesh
		var caabb := AABB()
		var first := true
		for i in list.size():
			var t: Transform3D = list[i]
			mm.set_instance_transform(i, t)
			var ta: AABB = t * mesh.get_aabb()
			caabb = ta if first else caabb.merge(ta)
			first = false
		mm.custom_aabb = caabb.grow(2.0)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [group_name, key.x, key.y]
		mmi.multimesh = mm
		group_root.add_child(mmi)

	# Окклюдеры (QUEUE Q2): BoxOccluder3D на инстанс — в Godot 4 авто-окклюзии
	# без OccluderInstance3D нет; шпили — крупные укрытия, реально отсекают.
	if with_occluders:
		for t in instance_transforms:
			var occ := OccluderInstance3D.new()
			var box := BoxOccluder3D.new()
			box.size = aabb.size * t.basis.get_scale()
			occ.occluder = box
			occ.transform = t * Transform3D(Basis.IDENTITY, aabb_center)
			group_root.add_child(occ)

	# Коллизия: MultiMesh сам не коллизится — один StaticBody, цилиндр на инстанс.
	var body := StaticBody3D.new()
	body.name = group_name + "_Body"
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(maxf(aabb.size.x, aabb.size.z) * 0.45, 0.1)
	shape.height = maxf(aabb.size.y * 0.9, 0.2)
	for t in instance_transforms:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t * Transform3D(Basis.IDENTITY, aabb_center)
		body.add_child(cs)

## Навмеш мобов: СИНХРОННЫЙ бейк из статических коллайдеров (чанки TerrainBuilder —
## trimesh рельефа; камни/шпили — цилиндры). Мобы HellEnemyBase ходят путями
## NavigationAgent3D: обходят препятствия вместо упора «лбом в стену».
func _add_navmesh() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	add_child(region)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS  # 4.8-beta: префикс geometry_*
	nm.agent_radius = 0.6   # капсула моба r=0.45 + запас
	nm.agent_height = 2.1  # кратен cell_height 0.3 — иначе recast-варнинг точности
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 46.0  # рельеф до 5 м амплитуды
	nm.cell_size = 0.3
	nm.cell_height = 0.3
	region.navigation_mesh = nm
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, data, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, data)
	print("Runtime: navmesh baked: %d polygons" % nm.get_polygon_count())

## Лава-лужи: эмиссивные диски + оранжевые OmniLight — «хаос в аду».
func _add_lava():
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var half := TERRAIN_SIZE / 2.0 - 15.0
	var lava_root := Node3D.new()
	lava_root.name = "Lava"
	add_child(lava_root)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.08
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(1.0, 0.3, 0.02)
	disc_mat.emission_enabled = true
	disc_mat.emission = Color(1.0, 0.35, 0.02)
	disc_mat.emission_energy_multiplier = 3.0
	disc_mesh.material = disc_mat

	for i in 8:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if abs(x) < 12.0 and abs(z) < 12.0:
			continue # спавн игрока/непися не заливаем
		var r := rng.randf_range(1.6, 2.8)
		var pool := MeshInstance3D.new()
		pool.mesh = disc_mesh
		pool.scale = Vector3(r, 1.0, r)
		pool.position = Vector3(x, _height(x, z) + 0.06, z)
		lava_root.add_child(pool)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.35, 0.1)
		light.light_energy = 2.5
		light.omni_range = 14.0
		light.shadow_enabled = false
		light.position = Vector3(x, _height(x, z) + 1.6, z)
		lava_root.add_child(light)

func _add_entities():
	# Игрок в центре (смерть в аду возвращает его на MainArena).
	var player_scene = load("res://Scenes/player.tscn")
	if player_scene:
		var player = player_scene.instantiate()
		player.position = Vector3(0, _height(0, 0) + 1.5, 0)
		add_child(player)

	# Непись-телепортер — тот же, что на других картах (список 3 карт по Z).
	var npc := NPCTeleporter.new()
	npc.name = "NPCTeleporter"
	npc.position = Vector3(6, _height(6, 6) + 0.1, 6)
	add_child(npc)

	# 5 ближних кольцом r=16, 5 дальних r=26 (верб. юзера). Скин по поведению:
	# мили — Demon, дальний — Ganfaul; без сцены скина — капсульный фолбэк.
	var melee_skin: PackedScene = load(MELEE_SKIN) if ResourceLoader.exists(MELEE_SKIN) else null
	var ranged_skin: PackedScene = load(RANGED_SKIN) if ResourceLoader.exists(RANGED_SKIN) else null
	if melee_skin == null or ranged_skin == null:
		print("Runtime: скины врагов не найдены — красные капсулы (фолбэк)")
	for i in 5:
		var ang := TAU * i / 5.0
		var mx := cos(ang) * 16.0
		var mz := sin(ang) * 16.0
		var m = _spawn_enemy(HellMeleeEnemy, melee_skin)
		m.name = "Melee_%d" % i
		m.position = Vector3(mx, _height(mx, mz) + 0.2, mz)
		add_child(m)

		var rx := cos(ang + PI / 5.0) * 26.0
		var rz := sin(ang + PI / 5.0) * 26.0
		var r = _spawn_enemy(HellRangedEnemy, ranged_skin)
		r.name = "Ranged_%d" % i
		r.position = Vector3(rx, _height(rx, rz) + 0.2, rz)
		add_child(r)

## Враг скина: сцена (CharacterBody3D + модель) получает поведенческий скрипт
## ДО add_child — _ready отработает уже на скиннутом теле.
func _spawn_enemy(behavior: GDScript, skin: PackedScene) -> CharacterBody3D:
	if skin:
		var e = skin.instantiate()
		e.set_script(behavior)
		return e
	return behavior.new()
