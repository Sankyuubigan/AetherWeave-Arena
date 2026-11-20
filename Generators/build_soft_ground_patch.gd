extends SceneTree

## Q32 мягкий грунт: дюна-патч 12×12. Базовая высота ВШИТА в меш (холм 0.32 м
## с краевым фейдом) — следы (displacement вниз по depth_tex) не уходят под
## пол террейна; convex-коллизия от базового меша — заход по пологому склону
## (~12°), физика деформации НЕ пишется (следы чисто визуал, урок Q31).
## Запуск: --headless -s res://Generators/build_soft_ground_patch.gd

const OUT_DIR := "res://Graphics/Environment/Props/soft_ground/"
const SIZE := 12.0      # размер патча (м)
const SEG := 96         # сегментов на сторону
const BASE_H := 0.32    # высота дюны в центре (м)
const FADE_IN := 0.75   # доля половины размера, внутри которой полная высота

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var mesh := _build_mesh()
	print("[SG] mesh saved: ", error_string(ResourceSaver.save(mesh, OUT_DIR + "soft_ground.tres")))
	_build_prefab(mesh)
	print("[SG] DONE")
	quit()

## Высота дюны: smoothstep с инвертированными краями = 1 внутри r<FADE_IN,
## 0 на границе патча (пологий склон, заход без прыжка).
func _h(x: float, z: float) -> float:
	var r := maxf(absf(x), absf(z)) / (SIZE * 0.5)
	return BASE_H * smoothstep(1.0, FADE_IN, r)

## Квад 2 треугольника; winding (A,B,C)/(A,C,D) — тот же ротационный порядок,
## что у работающей шляпки гриба (кольцо cosφ/sinφ, Godot CW=front).
## Нормали аналитические (центральная разность) — гладкий холм без фасетов.
func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := SIZE * 0.5
	for j in range(SEG):
		for i in range(SEG):
			var x0 := -half + SIZE * float(i) / float(SEG)
			var x1 := -half + SIZE * float(i + 1) / float(SEG)
			var z0 := -half + SIZE * float(j) / float(SEG)
			var z1 := -half + SIZE * float(j + 1) / float(SEG)
			_vtx(st, x0, z0)
			_vtx(st, x1, z0)
			_vtx(st, x1, z1)
			_vtx(st, x0, z0)
			_vtx(st, x1, z1)
			_vtx(st, x0, z1)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.74, 0.58)
	mesh.surface_set_material(0, mat)
	return mesh

func _vtx(st: SurfaceTool, x: float, z: float) -> void:
	var u := x / SIZE + 0.5
	var v := z / SIZE + 0.5
	st.set_uv(Vector2(u, v))
	st.add_vertex(Vector3(x, _h(x, z), z))

## Префаб: корень с компонентом + меш с шейдером + convex-коллизия.
func _build_prefab(mesh: ArrayMesh) -> void:
	var root := Node3D.new()
	root.name = "SoftGround"
	root.set_script(load("res://Logic/Props/SoftGround.gd"))

	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	mi.mesh = mesh
	var smat := ShaderMaterial.new()
	smat.shader = load("res://Graphics/Environment/Props/soft_ground/soft_ground.gdshader")
	mi.material_override = smat
	root.add_child(mi)

	# Convex от базового меша (§6.5): trimesh+CharacterBody = депенетрация,
	# convex дёшев; холм выпуклый, низ плоский — hull честен.
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	root.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape(true, true)
	body.add_child(cs)

	for child in root.get_children():
		_set_owner_deep(child, root)
	var packed := PackedScene.new()
	print("[SG] pack: ", error_string(packed.pack(root)))
	print("[SG] prefab saved: ", error_string(ResourceSaver.save(packed, OUT_DIR + "soft_ground.tscn")))

func _set_owner_deep(node: Node, owner: Node) -> void:
	node.owner = owner
	for c in node.get_children():
		_set_owner_deep(c, owner)
