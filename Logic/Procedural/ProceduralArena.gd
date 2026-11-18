extends Node3D

# Это скрипт, который запускается в реальном времени при телепорте.
# Задел на будущее: смена стилей карты.
@export var theme_style: String = "fantasy" 

const WFCModuleDB = preload("res://Logic/Procedural/WFCModuleDB.gd")
const WFCSolver = preload("res://Logic/Procedural/WFCSolver.gd")

const TILE_SIZE = 2.0
const GRID_W = 15
const GRID_D = 15
const TERRAIN_SIZE = 200.0
const TERRAIN_RES = 128
## Чанк скаттера: свой MultiMeshInstance3D на чанк — иначе гигантский AABB
## группы рисуется всегда целиком и frustum culling не отсекает ничего.
const SCATTER_CHUNK = 32.0

var _noise: FastNoiseLite

func _ready():
	print("Runtime: Generating Procedural Arena [Theme: " + theme_style + "]...")
	
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.015
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.5

	# Генерация БЕЗ фриза (17.11.26: зонд поймал 6 рестартов генерации подряд —
	# фриз во время синхронной генерации → юзер долбил телепорт → каждая клика
	# рестартила генерацию). Тяжёлые шаги разнесены по кадрам, поверх — оверлей
	# «Генерация карты...» с текущей стадией.
	_generate_async()

## Разнос генерации по кадрам: один тяжёлый вызов между process_frame,
## оверлей показывает стадию. Многосекундный фриз → короткие чанки с видимой
## стадией. Телепорт посреди генерации безопасен: объект освободится вместе со
## сценой, корутина оборвётся.
func _generate_async() -> void:
	_make_loading_overlay()
	await get_tree().process_frame  # оверлей должен отрисоваться до шага
	await _gen_step("Рельеф карты...", _add_terrain)
	await _gen_step("Растительность...", _add_nature)
	await _gen_step("Лагерь (WFC)...", _add_wfc_camp)
	await _gen_step("Существа и игрок...", _add_entities)

	# Профайлер карты (Шаг 4): метрики раз в 2с в лог — таблица до/после.
	var profiler = preload("res://Logic/Diagnostics/MapProfiler.gd").new()
	profiler.name = "MapProfiler"
	add_child(profiler)

	print("Runtime: Procedural Arena generation complete!")
	_loading_layer.queue_free()

## Один шаг генерации: подпись стадии → кадр → тяжёлый вызов → кадр.
func _gen_step(text: String, fn: Callable) -> void:
	_loading_label.set_text(text)
	await get_tree().process_frame
	fn.call()
	await get_tree().process_frame

## Оверлей «Генерация карты...»: CanvasLayer поверх 3D с панелью по центру.
var _loading_layer: CanvasLayer
var _loading_label: Label

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
	return _noise.get_noise_2d(x, z) * 4.0

func _add_terrain():
	# Рельеф вынесен в TerrainBuilder: чанки 4×4 со статическим LOD (ближние
	# плотные, дальние разреженные, юбки против щелей), вершинные цвета по
	# высоте/наклону, коллизия — единый trimesh 64×64 независимо от LOD.
	var TerrainBuilder = preload("res://Logic/Procedural/TerrainBuilder.gd")
	TerrainBuilder.build(self, _height, TERRAIN_SIZE, theme_style)

func _add_nature():
	var half = TERRAIN_SIZE / 2.0 - 10.0

	var tree_mesh = CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 0.6
	tree_mesh.height = 4.0
	var tree_mat = StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.08, 0.50, 0.08) if theme_style != "desert" else Color(0.4, 0.4, 0.1)
	tree_mesh.material = tree_mat

	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.08
	trunk_mesh.bottom_radius = 0.12
	trunk_mesh.height = 1.5
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.20, 0.08)
	trunk_mesh.material = trunk_mat

	# Камни: нейро-проп (trellis → префаб). Фолбэк — старая сфера, если ресурса нет.
	var rock_mesh: Mesh = load("res://Graphics/Environment/Props/test_stone/test_stone_mesh_0.res")
	if rock_mesh == null:
		var sphere = SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.3
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.45, 0.40, 0.35)
		sphere.material = rock_mat
		rock_mesh = sphere

	var rng = RandomNumberGenerator.new()

	_add_scatter_group("Trees", tree_mesh, 200, rng, half, 0.3, 25.0)
	# Trunks — тонкие столбики 1.5 м, их тень нечитаема → cast_shadow OFF (Шаг 5.2)
	_add_scatter_group("Trunks", trunk_mesh, 200, rng, half, 0.3, 25.0, 0.8, 1.3, false, false)
	# Камни: всегда масштабируем (разные размеры — вопрос юзера), диапазон шире деревьев.
	_add_scatter_group("Rocks", rock_mesh, 150, rng, half, 0.6, 20.0, 0.5, 2.5, true)

func _add_scatter_group(group_name: String, mesh: Mesh, count: int, rng: RandomNumberGenerator, half: float, spacing: float, camp_radius: float, scale_lo := 0.8, scale_hi := 1.3, always_scale := false, cast_shadows := true):
	rng.seed = randi()

	# Сажаем проп за низ AABB: origin меша бывает в центре (камень trellis),
	# без подъёма проп уходит под землю тем глубже, чем больше масштаб.
	# 10% высоты оставляем под землёй — посадка в рельеф без «парения».
	var aabb := mesh.get_aabb()
	var lift := -minf(aabb.position.y, 0.0) - aabb.size.y * 0.1

	var positions = []
	for i in count * 3:
		var x = rng.randf_range(-half, half)
		var z = rng.randf_range(-half, half)
		if abs(x) < camp_radius and abs(z) < camp_radius:
			continue
		var too_close = false
		for p in positions:
			if (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) < spacing * spacing:
				too_close = true
				break
		if too_close:
			continue
		var y = _height(x, z)
		positions.append(Vector3(x, y, z))
		if positions.size() >= count:
			break

	if positions.is_empty():
		return

	var instance_transforms: Array[Transform3D] = []
	for i in positions.size():
		var s := 1.0
		if always_scale or rng.randf() > 0.5:
			s = rng.randf_range(scale_lo, scale_hi)
		var t = Transform3D.IDENTITY
		t.origin = positions[i] + Vector3(0, lift * s, 0)
		t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(0, PI * 2))
		if s != 1.0:
			t.basis = t.basis.scaled(Vector3(s, s, s))
		instance_transforms.append(t)

	# Чанки 32×32 (ревью спеца §4): свой MultiMeshInstance3D на чанк, culling
	# отсекает чанки за спиной/за горизонтом. Коллизии не трогаем — один
	# StaticBody на группу остаётся (форма дешёвая, чанкинг выигрыша не даст).
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
		var mm = MultiMesh.new()
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
		# custom_aabb страховочно: у MultiMesh он считается из инстансов,
		# но явный AABB гарантирует корректный culling чанка.
		mm.custom_aabb = caabb.grow(2.0)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [group_name, key.x, key.y]
		mmi.multimesh = mm
		if not cast_shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# HLOD-фейд (демо 3d/visibility_ranges): чанк гаснет с дистанции,
		# дальние группы не рисуются. Деревья видимы дальше камней.
		var far := 200.0 if group_name == "Rocks" else 240.0
		mmi.visibility_range_end = far
		mmi.visibility_range_end_margin = far * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		group_root.add_child(mmi)

	print("[Scatter] %s: инстансов %d, чанков %d" % [group_name, instance_transforms.size(), chunks.size()])

	# Коллизия: MultiMesh сам по себе не коллизится (юзер ходил сквозь
	# деревья/камни). Один StaticBody на группу, у каждого инстанса —
	# цилиндр из AABB пропа (дешёвая форма, масштаб наследуется от инстанса).
	var body := StaticBody3D.new()
	body.name = group_name + "_Body"
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(maxf(aabb.size.x, aabb.size.z) * 0.45, 0.1)
	shape.height = maxf(aabb.size.y * 0.9, 0.2)
	var aabb_center := aabb.position + aabb.size * 0.5
	for t in instance_transforms:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t * Transform3D(Basis.IDENTITY, aabb_center)
		body.add_child(cs)

func _add_wfc_camp():
	var modules = WFCModuleDB.get_modules()
	var solver = WFCSolver.new(GRID_W, GRID_D, modules)

	var result = solver.collapse()
	if not result.success:
		print("WFC failed, using fallback layout")
		return

	var grid = result.grid
	var camp_root = Node3D.new()
	camp_root.name = "WFC_Camp"
	add_child(camp_root)

	var offset_x = -(GRID_W * TILE_SIZE) / 2.0
	var offset_z = -(GRID_D * TILE_SIZE) / 2.0
	var wall_h = 2.0
	var wall_d = 0.2

	for z in GRID_D:
		for x in GRID_W:
			var mod_idx = grid[z][x]
			var mod = modules[mod_idx]
			var pos_x = x * TILE_SIZE + offset_x
			var pos_z = z * TILE_SIZE + offset_z

			var tile = Node3D.new()
			tile.position = Vector3(pos_x, _height(pos_x + TILE_SIZE/2, pos_z + TILE_SIZE/2), pos_z)
			tile.name = "Tile_%d_%d_%s" % [x, z, mod.id]
			camp_root.add_child(tile)

			var floor_mi = MeshInstance3D.new()
			floor_mi.mesh = BoxMesh.new()
			floor_mi.mesh.size = Vector3(TILE_SIZE, 0.15, TILE_SIZE)
			var floor_mat = StandardMaterial3D.new()
			floor_mat.albedo_color = Color(0.30, 0.28, 0.25)
			floor_mi.mesh.material = floor_mat
			floor_mi.position.y = -0.075
			tile.add_child(floor_mi)

			var s = mod.sockets
			var half = TILE_SIZE / 2.0
			var wall_offsets = [
				{sock=s.N, pos=Vector3(0, wall_h/2, -half), sz=Vector3(TILE_SIZE - wall_d, wall_h, wall_d)},
				{sock=s.S, pos=Vector3(0, wall_h/2, half), sz=Vector3(TILE_SIZE - wall_d, wall_h, wall_d)},
				{sock=s.E, pos=Vector3(half, wall_h/2, 0), sz=Vector3(wall_d, wall_h, TILE_SIZE - wall_d)},
				{sock=s.W, pos=Vector3(-half, wall_h/2, 0), sz=Vector3(wall_d, wall_h, TILE_SIZE - wall_d)},
			]

			for wo in wall_offsets:
				if wo.sock == 1:
					var wmi = MeshInstance3D.new()
					wmi.mesh = BoxMesh.new()
					wmi.mesh.size = wo.sz
					var wmat = StandardMaterial3D.new()
					wmat.albedo_color = mod.color
					wmi.mesh.material = wmat
					wmi.position = wo.pos
					tile.add_child(wmi)

func _add_entities():
	var player_scene = load("res://Scenes/player.tscn")
	if player_scene:
		var player = player_scene.instantiate()
		player.position = Vector3(2, _height(2, 2) + 1.5, 2)
		add_child(player)
		# Диагностика телепорт-бага (Шаг 1 плана): зонд пишет скачки позиции,
		# смерть и пересоздание игрока в консоль.
		var probe := preload("res://Logic/Diagnostics/PlayerProbe.gd").new()
		player.add_child(probe)

	# Непись-телепортер у лагеря (19.11.26, верб. юзера): один и тот же на всех
	# картах — подход → значок [Z] слева снизу → окно со списком 3 карт.
	var NPC = preload("res://Logic/NPCTeleporter.gd")
	var npc := NPC.new()
	npc.name = "NPCTeleporter"
	npc.position = Vector3(20, _height(20, 8) + 0.1, 8)
	add_child(npc)

	var dummy_scene = load("res://Scenes/dummy.tscn")
	if not dummy_scene: return

	var dummy_positions = [
		Vector3(-4, _height(-4, -4) + 1.5, -4),
		Vector3(6, _height(6, -3) + 1.5, -3),
		Vector3(-3, _height(-3, 5) + 1.5, 5),
		Vector3(-6, _height(-6, -6) + 1.5, -6),
	]

	for i in dummy_positions.size():
		var d = dummy_scene.instantiate()
		d.position = dummy_positions[i]
		if i == 1:
			d.set_script(load("res://Logic/MovingDummy.gd"))
			d.set("move_type", "line")
			d.set("move_speed", 3.0)
		elif i == 2:
			d.set_script(load("res://Logic/MovingDummy.gd"))
			d.set("move_type", "complex_polygon")
			d.set("move_speed", 12.0)
		elif i == 3:
			d.set_script(load("res://Logic/FriendlyDummy.gd"))
			d.set("move_type", "triangle")
			d.set("move_speed", 8.0)
		add_child(d)