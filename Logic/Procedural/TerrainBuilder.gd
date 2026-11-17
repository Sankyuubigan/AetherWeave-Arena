extends RefCounted
# Генератор рельефа ProceduralArena: чанки 4×4 со статическим LOD и юбками,
# вершинные цвета по высоте/наклону, коллизия — единый trimesh.
#
# Почему так (план «Апгрейд второй карты», Шаги 2–3):
# - Вершинные цвета вместо плоского albedo: низина/равнина/склоны/вершины
#   читаются без текстур; vertex_color_use_as_albedo (правило vfx_guidelines).
# - Статический LOD: ближние к центру чанки плотные, дальние разреженные;
#   перестроений в рантайме нет. Щели между чанками разной плотности закрыты
#   юбками (кромка чанка дублируется вниз) — стандартный приём террейн-LOD.
# - Коллизия НЕ наследует визуальный LOD: один trimesh по равномерной сетке
#   на всю карту. Физика cheaper (меньше треугольников, чем 128×128), а игрок
#   бегает по всей карте — точность коллизии не зависит от чанка.

const CHUNKS_PER_SIDE := 4
const SKIRT_DEPTH := 3.0
const COLLISION_RES := 64
const DENSE_RES := 24
const SPARSE_RES := 12
## Размах шума в _height (noise * 4.0) — для нормировки цвета по высоте.
const HEIGHT_RANGE := 4.0

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
}

static func build(arena: Node3D, height_fn: Callable, size: float, theme: String) -> void:
	var half := size / 2.0
	var pal: Dictionary = PALETTES.get(theme, PALETTES["default"])

	var body := StaticBody3D.new()
	body.name = "Terrain"
	arena.add_child(body)

	var chunk_size := size / float(CHUNKS_PER_SIDE)
	for cz in CHUNKS_PER_SIDE:
		for cx in CHUNKS_PER_SIDE:
			var origin := Vector3(cx * chunk_size - half, 0.0, cz * chunk_size - half)
			# Кольцо от центра карты: внутренние 2×2 чанка — плотная сетка.
			var ring := maxf(absf(cx - 1.5), absf(cz - 1.5))
			var res := DENSE_RES if ring < 1.0 else SPARSE_RES
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(height_fn, origin, chunk_size, res, pal, size)
			mi.material_override = _terrain_material()
			body.add_child(mi)

	body.add_child(_collision_shape(height_fn, size, half))

static func _terrain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true # цвет приходит из вершин
	mat.albedo_color = Color.WHITE
	return mat

static func _chunk_mesh(height_fn: Callable, origin: Vector3, chunk_size: float, res: int, pal: Dictionary, map_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := chunk_size / float(res)
	var base := res + 1
	for iz in base:
		for ix in base:
			var x := origin.x + ix * step
			var z := origin.z + iz * step
			var y: float = height_fn.call(x, z)
			st.set_uv(Vector2(x / map_size * 8.0, z / map_size * 8.0))
			st.set_color(_vertex_color(height_fn, x, z, y, pal))
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
		st.set_uv(Vector2(p.x / map_size * 8.0, p.z / map_size * 8.0))
		st.set_color(_vertex_color(height_fn, p.x, p.z, y, pal))
		st.add_vertex(Vector3(p.x, y - SKIRT_DEPTH, p.z))
	for i in border.size():
		var j := (i + 1) % border.size()
		var a: int = border[i]
		var b: int = border[j]
		var sa := lowered_start + i
		var sb := lowered_start + j
		st.add_index(a); st.add_index(b); st.add_index(sa)
		st.add_index(b); st.add_index(sb); st.add_index(sa)
	st.generate_normals()
	return st.commit()

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
