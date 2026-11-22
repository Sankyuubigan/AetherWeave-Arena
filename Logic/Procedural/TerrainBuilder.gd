extends RefCounted
# Генератор рельефа ProceduralArena: чанки 4×4 с единой сеткой и юбками,
# фототекстура × вершинные цвета по высоте/наклону, коллизия — единый trimesh.
#
# Почему так (план «Апгрейд второй карты», Шаги 2–3 + план «Швы» 19.11.26):
# - Вершинные цвета тонируют фототекстуру: низина/равнина/склоны/вершины
#   читаются поверх детали; vertex_color_use_as_albedo (правило vfx_guidelines).
# - ЕДИНАЯ сетка чанков (статический LOD убран 19.11.26): кромки полилиний
#   res 24 и res 12 не совпадают — юбки торчали из земли тёмными «швами»
#   (верб. юзера «видно соединения швы»). При 4×4 чанках экономия LOD ничтожна.
#   Юбки (кромка дублируется вниз на SKIRT_DEPTH) остаются как страховка.
# - Нормали аналитические из height_fn: у соседей на общем ребре совпадают
#   побитово — шва освещения нет (generate_normals считал по своему чанку).
# - Коллизия НЕ наследует визуальную сетку: один trimesh по равномерной сетке
#   на всю карту. Точность коллизии не зависит от чанков.

const CHUNKS_PER_SIDE := 4
const SKIRT_DEPTH := 3.0
const COLLISION_RES := 64
const DENSE_RES := 24
## Размах шума в _height (noise * 4.0) — для нормировки цвета по высоте.
const HEIGHT_RANGE := 4.0
## Плотность текстурного тайла рельефа: UV = x/map_size * UV_TILES.
## 40 тайлов на карту 200 м = плитка 5 м (детальный план «Пол»).
const UV_TILES := 40.0
## Сила тонировки вершинными цветами там, где лежит фототекстура: 1.0 — как
## было (фото пережимается палитрой, рендер-проба 19.11.26 = плоская зелень),
## ниже — фото просвечивает, высота/наклон остаются читаемы.
const TINT_STRENGTH := 0.6
## Бесшовная фототекстура лесного пола (PolyHaven CC0, сет dl.polyhaven.org):
## альбедо+normal+roughness+AO, множится на вершинные цвета (деталь-слой
## плана «Пол»). Назначается темам, использующим лесную (default) палитру.
const GROUND_TEX := {
	"diff": "res://Graphics/Environment/Textures/forrest_ground_01/forrest_ground_01_diff_1k.jpg",
	"norm": "res://Graphics/Environment/Textures/forrest_ground_01/forrest_ground_01_nor_gl_1k.jpg",
	"rough": "res://Graphics/Environment/Textures/forrest_ground_01/forrest_ground_01_rough_1k.jpg",
	"ao": "res://Graphics/Environment/Textures/forrest_ground_01/forrest_ground_01_ao_1k.jpg",
}
## Каменный рельеф ада (PolyHaven rocky_terrain_02 CC0, сет dl.polyhaven.org,
## 19.11.26): серый камень + багровая тонировка вершинными цветами = нар-камень.
const HELL_TEX := {
	"diff": "res://Graphics/Environment/Textures/hell_rock/rocky_terrain_02_diff_1k.jpg",
	"norm": "res://Graphics/Environment/Textures/hell_rock/rocky_terrain_02_nor_gl_1k.jpg",
	"rough": "res://Graphics/Environment/Textures/hell_rock/rocky_terrain_02_rough_1k.jpg",
	"ao": "res://Graphics/Environment/Textures/hell_rock/rocky_terrain_02_ao_1k.jpg",
}

# Палитры вершинных цветов по темам: низина → равнина → вершина + скала.
const PALETTES := {
	"default": {
		"low": Color(0.16, 0.30, 0.12), "mid": Color(0.35, 0.55, 0.25),
		"high": Color(0.55, 0.58, 0.38), "rock": Color(0.42, 0.36, 0.28),
	},
	"cyberpunk": {
		"low": Color(0.05, 0.07, 0.12), "mid": Color(0.10, 0.10, 0.20),
		"high": Color(0.22, 0.18, 0.30), "rock": Color(0.14, 0.15, 0.22),
	},
	"desert": {
		"low": Color(0.62, 0.52, 0.30), "mid": Color(0.80, 0.70, 0.40),
		"high": Color(0.90, 0.85, 0.62), "rock": Color(0.55, 0.45, 0.32),
	},
	# Ад (19.11.26, верб. юзера «хаос как в аду Майнкрафта»): низины тёмная кровь,
	# равнины багровые, вершины светлеют к пепельно-красному, склоны угольные.
	"hell": {
		"low": Color(0.14, 0.04, 0.03), "mid": Color(0.28, 0.08, 0.06),
		"high": Color(0.42, 0.14, 0.10), "rock": Color(0.10, 0.06, 0.06),
	},
	# Гнилодолье (Q49, 22.11.26): гнилое болото — тёмный ил низин, оливковая
	# плесень равнин, бледный мох верхних этажей, мокрый тёмный камень склонов.
	"rotmarsh": {
		"low": Color(0.09, 0.13, 0.07), "mid": Color(0.24, 0.32, 0.14),
		"high": Color(0.44, 0.48, 0.28), "rock": Color(0.18, 0.20, 0.16),
	},
}

static func build(arena: Node3D, height_fn: Callable, size: float, theme: String) -> void:
	var half := size / 2.0
	var pal: Dictionary = PALETTES.get(theme, PALETTES["default"])

	var body := StaticBody3D.new()
	body.name = "Terrain"
	arena.add_child(body)

	var chunk_size := size / float(CHUNKS_PER_SIDE)
	var textured := (not PALETTES.has(theme)) or theme == "hell" or theme == "rotmarsh"
	# Ад мрачнее лесной карты: палитра доминирует над фототекстурой сильнее.
	var strength := 0.75 if theme == "hell" else TINT_STRENGTH
	var tint := 0.0 if not textured else 1.0 - strength
	for cz in CHUNKS_PER_SIDE:
		for cx in CHUNKS_PER_SIDE:
			var origin := Vector3(cx * chunk_size - half, 0.0, cz * chunk_size - half)
			# Единая сетка на всех чанках (19.11.26, швы у юзера): LOD-расщепление
			# плотный/разреженный рвало кромки на стыке (полилинии res 24 и 12 не
			# совпадают — юбки торчат из земли тёмными полосами). При 4×4 чанках
			# экономия LOD ничтожна, а швы заметны; юбки остаются как страховка.
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(height_fn, origin, chunk_size, DENSE_RES, pal, size, tint)
			mi.material_override = _terrain_material(theme)
			body.add_child(mi)

	body.add_child(_collision_shape(height_fn, size, half))

static func _terrain_material(theme: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true # цвет приходит из вершин
	mat.albedo_color = Color.WHITE
	# Фототекстура рельефа (19.11.26, план «Пол»): тайл 5 м, вершинный цвет
	# мультипликативно тонирует альбедо (низина темнее, склоны — скала).
	# hell — каменный сет PolyHaven (rocky_terrain_02) под багровой палитрой;
	# лесной сет — темы вне PALETTES (fantasy); cyberpunk/desert — чистые
	# вершинные цвета (фото им не подходит).
	if theme == "hell":
		var hdiff := load(HELL_TEX["diff"]) as Texture2D
		if hdiff: # после --import это CompressedTexture2D; без него — грязный фолбэк
			mat.albedo_texture = hdiff
			mat.normal_enabled = true
			mat.normal_texture = load(HELL_TEX["norm"])
			mat.roughness_texture = load(HELL_TEX["rough"])
			mat.ao_enabled = true
			mat.ao_texture = load(HELL_TEX["ao"])
	elif theme == "rotmarsh" or not PALETTES.has(theme):
		var diff := load(GROUND_TEX["diff"]) as Texture2D
		if diff: # после --import это CompressedTexture2D; без него — грязный фолбэк
			mat.albedo_texture = diff
			mat.normal_enabled = true
			mat.normal_texture = load(GROUND_TEX["norm"])
			mat.roughness_texture = load(GROUND_TEX["rough"])
			mat.ao_enabled = true
			mat.ao_texture = load(GROUND_TEX["ao"])
	return mat

static func _chunk_mesh(height_fn: Callable, origin: Vector3, chunk_size: float, res: int, pal: Dictionary, map_size: float, tint: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := chunk_size / float(res)
	var base := res + 1
	for iz in base:
		for ix in base:
			var x := origin.x + ix * step
			var z := origin.z + iz * step
			var y: float = height_fn.call(x, z)
			st.set_uv(Vector2(x / map_size * UV_TILES, z / map_size * UV_TILES))
			st.set_color(_vertex_color(height_fn, x, z, y, pal).lerp(Color.WHITE, tint))
			# Аналитическая нормаль из height_fn (19.11.26, швы): generate_normals()
			# считает по треугольникам СВОЕГО чанка — на кромках соседи расходились
			# и давали полосу освещения. Центральные разности дают у соседей
			# ПОБИТОВО одинаковые нормали на общем ребре.
			st.set_normal(_height_normal(height_fn, x, z))
			st.add_vertex(Vector3(x, y, z))
	for iz in res:
		for ix in res:
			var tl := iz * base + ix
			var tr := tl + 1
			var bl := (iz + 1) * base + ix
			var br := bl + 1
			st.add_index(tl); st.add_index(tr); st.add_index(bl)
			st.add_index(tr); st.add_index(br); st.add_index(bl)

	# Юбка: кромка по периметру дублируется опущенной на SKIRT_DEPTH,
	# щели между чанками разной плотности становятся невидимыми стенками.
	var border := _border_indices(res)
	var lowered_start := base * base
	for i in border.size():
		var p := _border_position(origin, chunk_size, res, step, i)
		var y: float = height_fn.call(p.x, p.z)
		st.set_uv(Vector2(p.x / map_size * UV_TILES, p.z / map_size * UV_TILES))
		st.set_color(_vertex_color(height_fn, p.x, p.z, y, pal).lerp(Color.WHITE, tint))
		# Юбка наследует нормаль кромки (стенка затеняется как земля, а не как
		# вертикаль; стена скрыта в грунте при совпадающих кромках).
		st.set_normal(_height_normal(height_fn, p.x, p.z))
		st.add_vertex(Vector3(p.x, y - SKIRT_DEPTH, p.z))
	for i in border.size():
		var j := (i + 1) % border.size()
		var a: int = border[i]
		var b: int = border[j]
		var sa := lowered_start + i
		var sb := lowered_start + j
		st.add_index(a); st.add_index(b); st.add_index(sa)
		st.add_index(b); st.add_index(sb); st.add_index(sa)
	return st.commit()

## Нормаль хайтфилда центральными разностями (шаг 1 м — тот же, что в _vertex_color):
## n = normalize(-dh/dx, 1, -dh/dz).
static func _height_normal(height_fn: Callable, x: float, z: float) -> Vector3:
	var e := 1.0
	var hx: float = (height_fn.call(x + e, z) - height_fn.call(x - e, z)) / (2.0 * e)
	var hz: float = (height_fn.call(x, z + e) - height_fn.call(x, z - e)) / (2.0 * e)
	return Vector3(-hx, 1.0, -hz).normalized()

# Индексы кромочных вершин сетки по периметру, по часовой, замкнуто.
static func _border_indices(res: int) -> PackedInt32Array:
	var b := PackedInt32Array()
	var base := res + 1
	for ix in res:
		b.append(ix)                          # верх, слева направо
	for iz in res:
		b.append(iz * base + res)             # право, сверху вниз
	for ix in res:
		b.append(res * base + (res - ix))     # низ, справа налево
	for iz in res:
		b.append((res - iz) * base)           # лево, снизу вверх
	return b

static func _border_position(origin: Vector3, chunk_size: float, res: int, step: float, i: int) -> Vector3:
	# Тот же порядок обхода, что в _border_indices — позиция i-й кромочной вершины.
	var seg := 4 * res
	var k := i % seg
	var p := Vector3.ZERO
	if k < res: # верх
		p = Vector3(k * step, 0, 0)
	elif k < 2 * res: # право
		p = Vector3(chunk_size, 0, (k - res) * step)
	elif k < 3 * res: # низ
		p = Vector3((3 * res - k) * step, 0, chunk_size)
	else: # лево
		p = Vector3(0, 0, (4 * res - 1 - k) * step)
	p = origin + p
	p.y = 0.0
	return p

static func _vertex_color(height_fn: Callable, x: float, z: float, y: float, pal: Dictionary) -> Color:
	# Наклон конечными разностями: круто — скала; выше — светлее.
	var e := 1.0
	var hx: float = (height_fn.call(x + e, z) - height_fn.call(x - e, z)) / (2.0 * e)
	var hz: float = (height_fn.call(x, z + e) - height_fn.call(x, z - e)) / (2.0 * e)
	var slope := sqrt(hx * hx + hz * hz)
	var t := clampf((y + HEIGHT_RANGE) / (2.0 * HEIGHT_RANGE), 0.0, 1.0)
	var col: Color
	if t < 0.5:
		col = pal["low"].lerp(pal["mid"], t * 2.0)
	else:
		col = pal["mid"].lerp(pal["high"], (t - 0.5) * 2.0)
	return col.lerp(pal["rock"], clampf(slope * 1.2, 0.0, 1.0))

static func _collision_shape(height_fn: Callable, size: float, half: float) -> CollisionShape3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := COLLISION_RES
	var step := size / float(n)
	for iz in n + 1:
		for ix in n + 1:
			var x := ix * step - half
			var z := iz * step - half
			st.add_vertex(Vector3(x, height_fn.call(x, z), z))
	for iz in n:
		for ix in n:
			var tl := iz * (n + 1) + ix
			var tr := tl + 1
			var bl := (iz + 1) * (n + 1) + ix
			var br := bl + 1
			st.add_index(tl); st.add_index(tr); st.add_index(bl)
			st.add_index(tr); st.add_index(br); st.add_index(bl)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = st.commit().create_trimesh_shape()
	return cs
