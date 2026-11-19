extends SceneTree

## Q31 гриб-батут: процедурная шляпка (равномерная топология — критично для
## soft body симуляции) + префаб. PRP: tasks/261117_2355-089dca89/20.11.26 Q31.
## Запуск: --headless -s res://Generators/build_mushroom_prop.gd

const OUT_DIR := "res://Graphics/Environment/Props/mushroom_bounce/"
const CAP_R := 2.2        # радиус шляпки (м)
const CAP_FLAT := 0.6     # сплюснутость купола (высота = CAP_R*CAP_FLAT)
const RINGS := 9          # колец от полюса до кромки (без полюса)
const SEGS := 24          # радиальных сегментов
const STEM_H := 1.0       # высота ножки

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var cap := _build_cap_mesh()
	var err := ResourceSaver.save(cap, OUT_DIR + "mushroom_cap.tres")
	print("[MUSH] cap saved: ", error_string(err), " verts=", (cap.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	_build_prefab(cap)
	print("[MUSH] DONE")
	quit()

## Купол-шляпка: полюс + RINGS колец x SEGS сегментов, кромка в y=0,
## полюс в y=CAP_R*CAP_FLAT. Равномерная сетка (soft body любит равномерно).
func _build_cap_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.append(Vector3(0, CAP_R * CAP_FLAT, 0))  # 0 — полюс
	uvs.append(Vector2(0.5, 0.5))
	for j in range(1, RINGS + 1):
		var th := PI * 0.5 * float(j) / float(RINGS)
		for s in range(SEGS):
			var ph := TAU * float(s) / float(SEGS)
			verts.append(Vector3(
				CAP_R * sin(th) * cos(ph),
				CAP_R * CAP_FLAT * cos(th),
				CAP_R * sin(th) * sin(ph)))
			uvs.append(Vector2(0.5 + 0.5 * sin(th) * cos(ph),
				0.5 + 0.5 * sin(th) * sin(ph)))
	var idx := PackedInt32Array()
	for j in range(RINGS):
		for s in range(SEGS):
			var s2 := (s + 1) % SEGS
			if j == 0:
				# полюс (0) + кольцо 1
				var a := 1 + s
				var b := 1 + s2
				idx.append_array([0, a, b])
			else:
				var top := 1 + (j - 1) * SEGS
				var bot := 1 + j * SEGS
				idx.append_array([top + s, bot + s, bot + s2])
				idx.append_array([top + s, bot + s2, top + s2])
	# Аналитические нормали эллипсоида (x/a², y/c², z/a²) — геометрия
	# ИНДЕКСИРОВАННАЯ (217 уникальных вершин): дубли вершин = отдельные
	# soft-частицы = рваная сетка. generate_normals(true) расширяет до
	# покромочных копий — НЕ использовать.
	var normals := PackedVector3Array()
	var a := CAP_R
	var c := CAP_R * CAP_FLAT
	for v in verts:
		normals.append(Vector3(v.x / (a * a), v.y / (c * c), v.z / (a * a)).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.25, 0.18)  # красная шляпка (врем. цвет)
	mat.roughness = 0.8
	mesh.surface_set_material(0, mat)
	return mesh

## Префаб: ножка-статика + статичная коллизия купола (игрок) + CapVisual
## (шейдерный промин, PRP-фолбэк — рантайм-точки SoftBody3D сломаны в 4.x,
## issues #93847/#108090) + Area3D зона посадки. Компонент батута на корне.
func _build_prefab(cap: ArrayMesh) -> void:
	var root := Node3D.new()
	root.name = "MushroomBounce"
	# Компонент батута (шаг 2 PRP) — на корне префаба
	root.set_script(load("res://Logic/Props/MushroomBounce.gd"))

	# Ножка: статика + меш
	var stem := StaticBody3D.new()
	stem.name = "Stem"
	root.add_child(stem)
	var stem_cs := CollisionShape3D.new()
	var stem_shape := CylinderShape3D.new()
	stem_shape.radius = 0.4
	stem_shape.height = STEM_H
	stem_cs.shape = stem_shape
	stem_cs.position = Vector3(0, STEM_H * 0.5, 0)
	stem.add_child(stem_cs)
	var stem_mesh := MeshInstance3D.new()
	var stem_cyl := CylinderMesh.new()
	stem_cyl.top_radius = 0.36
	stem_cyl.bottom_radius = 0.45
	stem_cyl.height = STEM_H
	stem_mesh.mesh = stem_cyl
	stem_mesh.position = Vector3(0, STEM_H * 0.5, 0)
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.85, 0.8, 0.7)
	stem_cyl.material = stem_mat
	stem.add_child(stem_mesh)

	# Визуальная шляпка: промин двигает шейдер (mushroom_cap.gdshader) через
	# униформы dent_center/dent_depth — компонент пишет их при посадке.
	var vis := MeshInstance3D.new()
	vis.name = "CapVisual"
	vis.position = Vector3(0, STEM_H, 0)
	vis.mesh = cap
	var smat := ShaderMaterial.new()
	smat.shader = load("res://Graphics/Environment/Props/mushroom_bounce/mushroom_cap.gdshader")
	vis.material_override = smat
	root.add_child(vis)

	# Статичная коллизия купола — игрок стоит на шляпке (convex, §6.5)
	var cap_static := StaticBody3D.new()
	cap_static.name = "CapStatic"
	cap_static.position = Vector3(0, STEM_H, 0)
	root.add_child(cap_static)
	var cs := CollisionShape3D.new()
	cs.shape = cap.create_convex_shape(true, true)
	cap_static.add_child(cs)

	# Зона посадки (компонент детектит посадку). Convex ×1.3: при быстром
	# падении (13 м/с = 0.22 м/тик) зона вровень с коллизией давала вход
	# ТЕМ ЖЕ тиком, что контакт (vy уже обнулён) — margin ≥0.4 м гарантирует
	# вход в зону заранее, пока vy ещё падающий (поймано probe: entry vy=0).
	var area := Area3D.new()
	area.name = "BounceArea"
	area.position = Vector3(0, STEM_H, 0)
	root.add_child(area)
	var acs := CollisionShape3D.new()
	var aconv: ConvexPolygonShape3D = cap.create_convex_shape(true, true)
	var apts: PackedVector3Array = aconv.points
	for i in range(apts.size()):
		apts[i] = apts[i] * 1.3
	aconv.points = apts
	acs.shape = aconv
	area.add_child(acs)

	# owner — все дочерние сохраняются в tscn (AGENTS §2)
	for child in root.get_children():
		_set_owner_deep(child, root)
	var packed := PackedScene.new()
	var perr := packed.pack(root)
	print("[MUSH] pack: ", error_string(perr))
	var serr := ResourceSaver.save(packed, OUT_DIR + "mushroom_bounce.tscn")
	print("[MUSH] prefab saved: ", error_string(serr))

func _set_owner_deep(node: Node, owner: Node) -> void:
	node.owner = owner
	for c in node.get_children():
		_set_owner_deep(c, owner)
