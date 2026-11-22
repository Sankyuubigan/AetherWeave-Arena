extends Node3D
## Арена «Гнилодолье» (Q49, заказ юзера 22.11.26): карта «этажами» по оси Y —
## террасы/горы/ямы, как мир Minecraft. Рельеф TerrainBuilder тема rotmarsh
## (фототекстура лесного пола × гнилая палитра), этажи = квантование шума
## 0/3.5/7/10.5 м (шаг 3.5 — батут MushroomBounce добивает 4.5 м), пандусы —
## smoothstep-рампы между плато, ямы-котлованы −3.5 м, спавн-зона плоская.
## Стаи желе (тот же приказ): 3 зелёных (дружественные) на низких этажах +
## 3 красных (агрессивные) на средних/верхних, центры ≥25 м друг от друга и
## ≥26 м от спавна. Батуты на низких этажах, мини-грибы, 2 стоунхенджа +
## рунические обелиски (эмиссия). Генерация асинхронная по шагам (паттерн
## HellArena/ProceduralArena — оверлей стадии, без фриза).
## Детерминизм: все rng seed=49 (Q49) — планировка стабильна для гейтов.

const TERRAIN_SIZE := 200.0
## Чанк скаттера (ревью спеца §4): свой MultiMeshInstance3D на чанк.
const SCATTER_CHUNK := 32.0
# --- Этажи (Q49) ---
const STEP := 3.5          # перепад этажей; батут bounce_max_h 4.5 м добивает
const MAX_H := 10.5        # верхний этаж (0/3.5/7/10.5)
const PIT_DEPTH := 3.5     # глубина ям
const SEED := 49           # Q49: детерминированная планировка
# Доля рампы в полосе этажа: 60% ширины — плато, 40% — подъём (smoothstep).
const RAMP_FRAC := 0.4

const NPCTeleporter = preload("res://Logic/NPCTeleporter.gd")
const JellyScript = preload("res://Logic/JellyMonster.gd")
const BOUNCE_SCENE := "res://Graphics/Environment/Props/mushroom_bounce/mushroom_bounce.tscn"
# Скины деревьев каталога (Q22-слоты, foot-origin контракт Q47-F: низ AABB = 0).
const TREE_PREFABS := [
	"res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage_b.tscn",
	"res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn",
]
# Оффсеты членов стаи (диаметр мувера 4 м → шаг ≥4.4, иначе расталкивание).
const PACK_OFFSETS := [Vector2(0, 0), Vector2(4.6, 1.4), Vector2(-4.2, 2.6), Vector2(2.8, -4.6)]
# Состав стай (зелёные 3, красные 3) — 2-4 особи: итого ~18.
const PACK_COUNTS := [3, 2, 4, 3, 2, 4]

var _noise: FastNoiseLite
var _loading_layer: CanvasLayer
var _loading_label: Label
# Планировка (заполняется _plan_layout ДО генерации рельефа):
var _pits: Array = []     # [{c: Vector2, r: float, depth_h: float}]
var _packs: Array = []    # [{c: Vector2, red: bool, n: int}]
var _henges: Array[Vector3] = []
var _obelisks: Array[Vector3] = []
var _bounces: Array[Vector3] = []

func _ready():
	print("Runtime: Generating Rotmarsh Arena...")
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	# freq 0.009: фичи ~110 м → плато/рампы достаточно широкие для стай/руин.
	_noise.frequency = 0.009
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.5
	_plan_layout()
	_generate_async()

func _generate_async() -> void:
	_make_loading_overlay()
	await get_tree().process_frame
	await _gen_step("Планировка этажей...", _plan_ready_check)
	await _gen_step("Террасы Гнилодолья...", _add_terrain)
	await _gen_step("Деревья и камни...", _add_rocks_trees)
	await _gen_step("Руины и грибы...", _add_ruins_mushrooms)
	await _gen_step("Стаи желе и игрок...", _add_entities)

	var profiler = preload("res://Logic/Diagnostics/MapProfiler.gd").new()
	profiler.name = "MapProfiler"
	add_child(profiler)

	print("Runtime: Rotmarsh Arena generation complete!")
	_loading_layer.queue_free()

func _plan_ready_check() -> void:
	pass # планировка уже сделана в _ready; шаг — для оверлея загрузки

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

# ---------------------------------------------------------------- рельеф ---
## Терраса без ям/спавн-зоны: шум → непрерывная высота → квантование на этажи.
## 60% полосы этажа — плато, 40% — smoothstep-рампа на следующий уровень.
## РАСТЯЖКА ×2.5 с сатурацией: FBM-шум гауссово-центрирован (±0.22 в 1σ) —
## прямое отображение давало низину (h<1.2 → n<−0.77) в 0.3% карты: зелёных
## стай/батутов/хенджей 0 (первый прогон). С сатурацией хвосты n<±0.4 дают
## БОЛЬШИЕ плоские плато уровня 0 (низины) и уровня 3 (горы-столы).
func _terrace(x: float, z: float) -> float:
	var n := clampf(_noise.get_noise_2d(x, z) * 2.5, -1.0, 1.0)
	var h_cont := (n * 0.5 + 0.5) * MAX_H
	var lvl := floorf(h_cont / STEP)
	var frac := h_cont / STEP - lvl
	var t := _sm(clampf((frac - (1.0 - RAMP_FRAC)) / RAMP_FRAC, 0.0, 1.0))
	return minf((lvl + t) * STEP, MAX_H)

## Полная высота: терраса → ямы (гладкая чаша depth_h) → плоская спавн-зона.
func _height(x: float, z: float) -> float:
	var h := _terrace(x, z)
	for p in _pits:
		var pc: Vector2 = p["c"]
		var pr: float = p["r"]
		var d := Vector2(x - pc.x, z - pc.y).length()
		if d < pr:
			var w := _sm(clampf(1.0 - d / pr, 0.0, 1.0))
			h = lerpf(h, p["depth_h"], w)
	var dc := Vector2(x, z).length()
	if dc < 16.0:
		var w2 := _sm(clampf((16.0 - dc) / 6.0, 0.0, 1.0))
		h = lerpf(h, 0.0, w2)
	return h

static func _sm(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

## Плоская площадка (max перепад высоты на ±2 м) — стаям/батутам/руинам.
func _flat(x: float, z: float) -> bool:
	var h0 := _height(x, z)
	for d in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		if absf(_height(x + d.x, z + d.y) - h0) > 0.7:
			return false
	return true

## Не в яме (с запасом wall).
func _out_of_pits(c: Vector2, wall: float) -> bool:
	for p in _pits:
		var pc: Vector2 = p["c"]
		var pr: float = p["r"]
		if c.distance_to(pc) < pr + wall:
			return false
	return true

# ------------------------------------------------------------- планировка ---
## Детерминированная (seed 49): ямы → стаи → руины → батуты. Все центры
## разводятся: стаи ≥25 между собой и ≥26 от спавна, руины ≥30 от занятых.
func _plan_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# 1) Ямы-котлованы (5 шт, r 5-8, не у спавна и не на краю).
	_pits.clear()
	var tries := 0
	while _pits.size() < 5 and tries < 300:
		tries += 1
		var c := Vector2(rng.randf_range(-72, 72), rng.randf_range(-72, 72))
		if c.length() < 20.0 or c.length() > 82.0:
			continue
		var r := rng.randf_range(5.0, 8.0)
		var depth := maxf(_terrace(c.x, c.y) - PIT_DEPTH, -PIT_DEPTH)
		_pits.append({"c": c, "r": r, "depth_h": depth})
	# 2) Стаи: зелёные на низких (h<1.2), красные на средних/верхних (h>4.0).
	_packs.clear()
	var reserved: Array[Vector2] = []
	var greens := 0
	var reds := 0
	for ri: float in [35.0, 50.0, 65.0, 80.0]:
		for k in 12:
			var ang := TAU * k / 12.0 + ri * 0.13
			var c := Vector2(cos(ang), sin(ang)) * ri
			if not _pack_spot_ok(c, reserved):
				continue
			var h := _height(c.x, c.y)
			var red := false
			if greens < 3 and h < 1.2:
				greens += 1
			elif reds < 3 and h > 4.0:
				reds += 1
				red = true
			else:
				continue
			_packs.append({"c": c, "red": red, "n": PACK_COUNTS[reds + greens - 1]})
			reserved.append(c)
	if greens < 3 or reds < 3:
		print("Runtime: РОТМАРШ планировка стай неполная (зел=%d, крас=%d)" % [greens, reds])
	# 3) Стоунхенджи ×2 (низкие этажи) + обелиски ×4 (средние/верхние).
	_henges.clear()
	_obelisks.clear()
	for ri: float in [45.0, 60.0, 75.0, 82.0]:
		for k in 8:
			var ang := TAU * k / 8.0 + ri * 0.07 + 0.19
			var c := Vector2(cos(ang), sin(ang)) * ri
			if c.length() < 26.0 or not _pack_spot_ok(c, reserved, 24.0):
				continue
			var h := _height(c.x, c.y)
			if _henges.size() < 2 and h < 1.2:
				_henges.append(Vector3(c.x, h, c.y))
				reserved.append(c)
			elif _obelisks.size() < 4 and h > 2.5:
				_obelisks.append(Vector3(c.x, h, c.y))
				reserved.append(c)
	# 4) Батуты ×5 на низких этажах (гладко, не в яме, не на занятом).
	_bounces.clear()
	for ri: float in [28.0, 40.0, 52.0, 64.0, 76.0]:
		for k in 10:
			var ang := TAU * k / 10.0 + ri * 0.11 + 0.41
			var c := Vector2(cos(ang), sin(ang)) * ri
			if c.length() < 15.0:
				continue
			var h := _height(c.x, c.y)
			if h > 1.2 or not _out_of_pits(c, 2.0) or not _flat(c.x, c.y):
				continue
			var ok := true
			for r2 in reserved:
				if c.distance_to(r2) < 10.0:
					ok = false
					break
			if not ok:
				continue
			_bounces.append(Vector3(c.x, h, c.y))
			reserved.append(c)
	print("Runtime: план Гнилодолья: ям=%d стай=%d хенджей=%d обелисков=%d батутов=%d"
			% [_pits.size(), _packs.size(), _henges.size(), _obelisks.size(), _bounces.size()])

## Общая проверка точки стаи: от спавна, от занятых (sep), от ям, гладкость.
func _pack_spot_ok(c: Vector2, reserved: Array[Vector2], sep: float = 25.0) -> bool:
	if c.length() < 26.0 or not _out_of_pits(c, 3.0) or not _flat(c.x, c.y):
		return false
	for r in reserved:
		if c.distance_to(r) < sep:
			return false
	return true

# ------------------------------------------------------------- контент ---
func _add_terrain():
	var TerrainBuilder = preload("res://Logic/Procedural/TerrainBuilder.gd")
	TerrainBuilder.build(self, _height, TERRAIN_SIZE, "rotmarsh")

## Деревья каталога (инстансы префабов — коллизия внутри префаба) + камни
## (MultiMesh-скаттер с цилиндрами коллизии, паттерн HellArena).
func _add_rocks_trees():
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var half := TERRAIN_SIZE / 2.0 - 10.0
	for i in TREE_PREFABS.size():
		var scene: PackedScene = load(TREE_PREFABS[i])
		if scene == null:
			continue
		var planted := 0
		for t in 60:
			if planted >= 16:
				break
			var x := rng.randf_range(-half, half)
			var z := rng.randf_range(-half, half)
			if Vector2(x, z).length() < 14.0:
				continue
			var tree = scene.instantiate()
			tree.position = Vector3(x, _height(x, z), z)
			tree.rotation_degrees.y = rng.randf_range(0, 360)
			var s := rng.randf_range(0.8, 1.4)
			tree.scale = Vector3(s, s, s)
			tree.set_script(load("res://Graphics/PropHLOD.gd"))
			add_child(tree)
			planted += 1
	var stone_mesh: Mesh = load("res://Graphics/Environment/Props/test_stone/test_stone_mesh_0.res")
	if stone_mesh != null:
		_scatter_stones("Rocks", stone_mesh, 70, rng, half)

## Сокращённый скаттер из HellArena: чанки MultiMesh + коллизия-цилиндры.
func _scatter_stones(group_name: String, mesh: Mesh, count: int, rng: RandomNumberGenerator, half: float) -> void:
	var aabb := mesh.get_aabb()
	var lift := -minf(aabb.position.y, 0.0) - aabb.size.y * 0.1
	var aabb_center := aabb.position + aabb.size * 0.5
	var positions := []
	for i in count * 3:
		var x = rng.randf_range(-half, half)
		var z = rng.randf_range(-half, half)
		if abs(x) < 12.0 and abs(z) < 12.0:
			continue
		if Vector2(x, z).length() < 12.0:
			continue
		var too_close := false
		for p in positions:
			if (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) < 64.0: # шаг 8 м
				too_close = true
				break
		if too_close:
			continue
		positions.append(Vector3(x, _height(x, z), z))
		if positions.size() >= count:
			break
	if positions.is_empty():
		return
	var transforms: Array[Transform3D] = []
	for i in positions.size():
		var s: float = rng.randf_range(0.6, 2.2)
		var t := Transform3D.IDENTITY
		t.origin = positions[i] + Vector3(0, lift * s, 0)
		t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(0, TAU))
		t.basis = t.basis.scaled(Vector3(s, s, s))
		transforms.append(t)
	var chunks := {}
	for t in transforms:
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
	var body := StaticBody3D.new()
	body.name = group_name + "_Body"
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(maxf(aabb.size.x, aabb.size.z) * 0.45, 0.1)
	shape.height = maxf(aabb.size.y * 0.9, 0.2)
	for t in transforms:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t * Transform3D(Basis.IDENTITY, aabb_center)
		body.add_child(cs)

## Стоунхенджи + обелиски (рунические места — идея юзера) + грибы.
func _add_ruins_mushrooms():
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.20, 0.22, 0.19) # мокрый серо-зелёный камень
	stone_mat.roughness = 0.9
	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = Color(0.05, 0.10, 0.08)
	rune_mat.emission_enabled = true
	rune_mat.emission = Color(0.35, 0.95, 0.65) # болотно-бирюзовое свечение
	rune_mat.emission_energy_multiplier = 1.6
	for hpos in _henges:
		_build_stonehenge(hpos, stone_mat, rune_mat)
	for opos in _obelisks:
		_build_obelisk(opos, stone_mat, rune_mat)
	_add_bounce_mushrooms()
	_add_mini_mushrooms()

## Кольцо из 9 плит + перемычки + рунные таблички изнутри (группа rune_ruins).
func _build_stonehenge(center: Vector3, stone_mat: StandardMaterial3D, rune_mat: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.name = "Stonehenge"
	root.add_to_group("rune_ruins")
	add_child(root)
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(1.6, 4.2, 0.8)
	slab_mesh.material = stone_mat
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(3.6, 0.7, 1.0)
	lintel_mesh.material = stone_mat
	var rune_mesh := PlaneMesh.new()
	rune_mesh.size = Vector2(0.6, 2.4)
	rune_mesh.material = rune_mat
	var n := 9
	for i in n:
		var ang := TAU * i / n
		var dir := Vector3(cos(ang), 0, sin(ang))
		var p := center + dir * 7.0
		# Ось X бокса — по касательной к кольцу (yaw = −ang − 90°).
		var yaw := -ang - PI / 2.0
		# Плита
		var slab := MeshInstance3D.new()
		slab.name = "Slab_%d" % i
		slab.mesh = slab_mesh
		slab.position = p + Vector3(0, 2.1, 0)
		slab.rotation.y = yaw
		root.add_child(slab)
		var body := StaticBody3D.new()
		body.name = "SlabBody_%d" % i
		root.add_child(body)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 4.2, 0.8)
		cs.shape = box
		body.position = slab.position
		body.rotation.y = yaw
		body.add_child(cs)
		# Рунная планка на внутренней грани (вертикальная, смотрит в центр:
		# PlaneMesh нормаль +Y → X+90° = +Z → yaw разворачивает на −dir).
		var rune := MeshInstance3D.new()
		rune.name = "Rune_%d" % i
		rune.mesh = rune_mesh
		rune.position = center + dir * 6.5 + Vector3(0, 2.2, 0)
		rune.rotation = Vector3(PI / 2.0, yaw, 0)
		root.add_child(rune)
		# Перемычка поверх соседних плит
		var ang2 := TAU * ((i + 1) % n) / n
		var dir2 := Vector3(cos(ang2), 0, sin(ang2))
		var mid := center + (dir + dir2).normalized() * 7.0 * cos(PI / n)
		var lintel := MeshInstance3D.new()
		lintel.name = "Lintel_%d" % i
		lintel.mesh = lintel_mesh
		lintel.position = mid + Vector3(0, 4.55, 0)
		lintel.rotation.y = yaw # длинная сторона вдоль хорды
		root.add_child(lintel)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.95, 0.7)
	light.light_energy = 1.2
	light.omni_range = 16.0
	light.position = center + Vector3(0, 3.0, 0)
	root.add_child(light)

## ТAPERed-обелиск с эмиссивным рунным поясом (группа rune_ruins).
func _build_obelisk(center: Vector3, stone_mat: StandardMaterial3D, rune_mat: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.name = "Obelisk"
	root.add_to_group("rune_ruins")
	add_child(root)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.6
	mesh.height = 5.5
	mesh.radial_segments = 4 # квадратная усечённая колонна
	mesh.material = stone_mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center + Vector3(0, 2.75, 0)
	mi.rotation.y = PI / 4.0
	root.add_child(mi)
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.62
	band_mesh.bottom_radius = 0.66
	band_mesh.height = 0.5
	band_mesh.radial_segments = 12
	band_mesh.material = rune_mat
	var band := MeshInstance3D.new()
	band.mesh = band_mesh
	band.position = center + Vector3(0, 2.4, 0)
	root.add_child(band)
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = 5.5
	cs.shape = shape
	body.position = center + Vector3(0, 2.75, 0)
	body.add_child(cs)

## Грибы-батуты (Q31) на низких этажах — «лифты» на этаж выше.
func _add_bounce_mushrooms():
	var scene: PackedScene = load(BOUNCE_SCENE)
	if scene == null:
		print("Runtime: mushroom_bounce.tscn не найден — батуты пропущены")
		return
	for p in _bounces:
		var m = scene.instantiate()
		m.name = "BounceMushroom"
		m.position = Vector3(p.x, p.y, p.z)
		add_child(m)

## Мини-грибы (заказ юзера «обычные грибы поменьше»): декор без коллизии,
## 2 MultiMesh-группы (ножка + шляпка), гнило-красные.
func _add_mini_mushrooms():
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var half := TERRAIN_SIZE / 2.0 - 8.0
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.14
	stem_mesh.bottom_radius = 0.2
	stem_mesh.height = 1.0
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.72, 0.66, 0.55)
	stem_mesh.material = stem_mat
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.55
	cap_mesh.height = 0.8
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.52, 0.16, 0.13) # гнило-красная шляпка
	cap_mat.roughness = 0.6
	cap_mesh.material = cap_mat
	var stem_t: Array[Transform3D] = []
	var cap_t: Array[Transform3D] = []
	var placed := 0
	for i in 160:
		if placed >= 40:
			break
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if Vector2(x, z).length() < 12.0:
			continue
		var h := _height(x, z)
		if h > 9.0: # не на самом верхнем этаже (редкий гриб на вершине — норм)
			continue
		var s := rng.randf_range(0.35, 0.7)
		stem_t.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(x, h + 0.5 * s, z)))
		cap_t.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.6, s)),
				Vector3(x, h + 1.0 * s, z)))
		placed += 1
	_scatter_deco("MiniMushroomStems", stem_mesh, stem_t)
	_scatter_deco("MiniMushroomCaps", cap_mesh, cap_t)

## Декор-скаттер без коллизии (чанки MultiMesh, паттерн без body).
func _scatter_deco(group_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var chunks := {}
	for t in transforms:
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

# ------------------------------------------------------------- сущности ---
func _add_entities():
	# Игрок в центре (смерть → респавн на MainArena, логика PlayerController).
	var player_scene = load("res://Scenes/player.tscn")
	if player_scene:
		var player = player_scene.instantiate()
		player.position = Vector3(0, _height(0, 0) + 1.5, 0)
		add_child(player)
	# Непись-телепортер — тот же на всех картах (в списке появится Гнилодолье).
	var npc := NPCTeleporter.new()
	npc.name = "NPCTeleporter"
	npc.position = Vector3(6, _height(6, 6) + 0.1, 6)
	add_child(npc)
	# Стаи желе (Q49): зелёные низкие, красные средние/верхние.
	var spawned_g := 0
	var spawned_r := 0
	for p in _packs:
		var red: bool = p["red"]
		var c: Vector2 = p["c"]
		var n: int = p["n"]
		var col: Color = JellyScript.COLOR_AGGRESSIVE if red else JellyScript.COLOR_FRIENDLY
		for k in n:
			var off: Vector2 = PACK_OFFSETS[k % PACK_OFFSETS.size()]
			var x := c.x + off.x
			var z := c.y + off.y
			var j = JellyScript.new()
			j.aggressive = red
			j.body_color = col
			# Меш ДО add_child (грабля 4.8: меш узлу в дереве сбрасывает
			# трансформ) и по цвету вида.
			j.mesh = JellyScript.build_blob_mesh(j.radius, 0.04, col)
			j.position = Vector3(x, _height(x, z) + 0.75, z)
			add_child(j)
			if red:
				spawned_r += 1
			else:
				spawned_g += 1
	print("Runtime: стаи Гнилодолья: зелёных=%d красных=%d" % [spawned_g, spawned_r])
