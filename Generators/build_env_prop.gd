extends SceneTree

var prop_name: String
var prop_dir: String
var raw_gltf: String

func _init():
	parse_args()
	if prop_name == "":
		print("Usage: godot --headless -s res://Generators/build_env_prop.gd <prop_name>")
		quit(1)

	prop_dir = "res://Graphics/Environment/Props/%s/" % prop_name

	var candidates = [
		prop_dir + prop_name + "_v2_baked.gltf",
		prop_dir + prop_name + "_baked.gltf", # выход optimize_triangles.py v2 (нейро-пропы)
		prop_dir + prop_name + "_4k_baked.gltf",
		prop_dir + prop_name + "_4k_optimized.gltf",
		prop_dir + prop_name + ".gltf",
		prop_dir + prop_name + "_4k_baked.glb",
		prop_dir + prop_name + ".glb",
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			raw_gltf = c
			break

	if raw_gltf == "":
		# Q22: проп в ЧУЖОЙ папке (ель-v2 живёт в pine_tree_01/ — кора и
		# атлас хвои рядом, изображения gltf резолвятся относительно gltf).
		# Сканируем Props/*/ на <name>.gltf и берём ту папку как prop_dir.
		var props_root := "res://Graphics/Environment/Props/"
		var da := DirAccess.open(props_root)
		if da:
			for d in da.get_directories():
				var c := props_root.path_join(d.path_join(prop_name + ".gltf"))
				if FileAccess.file_exists(c):
					prop_dir = props_root.path_join(d) + "/"
					raw_gltf = c
					break

	if raw_gltf == "":
		print("ERROR: No glTF found for '%s' in %s" % [prop_name, prop_dir])
		quit(1)

	print("Loading: %s" % raw_gltf)
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file(raw_gltf, state)
	if err != OK:
		print("ERROR: Failed to load GLTF: %s" % error_string(err))
		quit(1)

	var scene_root = doc.generate_scene(state)
	if not scene_root:
		print("ERROR: Generated scene is null")
		quit(1)

	var orm_mat := try_orm_material()
	if orm_mat:
		print("  Материал: ORMMaterial3D (v2-пайплайн, нормал+ORM)")
	else:
		replace_textures_in_state(state)
		print("  Материал: legacy-путь (замена текстур по URI)")

	_ensure_foliage_materials(state)
	build_prop_scene(scene_root)
	print("Done! Prop '%s' ready in %s" % [prop_name, prop_dir])
	quit()


func parse_args():
	var args = OS.get_cmdline_args()
	for arg in args:
		var trimmed = arg.strip_edges()
		if trimmed.is_empty() or trimmed.length() < 2:
			continue
		if trimmed.begins_with("res:") or trimmed.begins_with("-"):
			continue
		if trimmed.ends_with(".gd"):
			continue
		if trimmed.to_lower() in ["headless", "editor"]:
			continue
		prop_name = trimmed
		return


## --- v2-пайплайн (ревью спеца): ORMMaterial3D + CompressedTexture2D из .import ---
## Файлы v2-бейка лежат в папке пропа по конвенции имён:
##   <name>_baked_diffuse.webp, <name>_baked_normal.png, <name>_baked_orm.png
## ORM: R=AO, G=Roughness, B=Metal(=0). Текстуры грузятся через load() —
## если .import есть (запускали --import), это VRAM-сжатый CompressedTexture2D;
## без него — фолбэк Image.load_from_file + мипмапы (работает везде).

func _gltf_base() -> String:
	return raw_gltf.get_file().get_basename()


func _tex_prefix() -> String:
	# Текстуры бейка названы {--name}_baked_*: base «test_stone_v2_baked» →
	# префикс «test_stone_v2» (минус только _baked).
	var b := _gltf_base()
	return b.trim_suffix("_baked") if b.ends_with("_baked") else b


func try_orm_material() -> ORMMaterial3D:
	return _orm_material_for(0)


## Материал меша с индексом idx: одиночный бейк пишет {prefix}_baked_*,
## мультимеш — {prefix}_m{idx}_baked_*. Индекс = порядок MeshInstance3D
## в том же обходе, что и сохранение мешей.
func _orm_material_for(idx: int) -> ORMMaterial3D:
	for suf in ["", "_m%d" % idx]:
		var mat := _orm_from_prefix(_tex_prefix() + suf)
		if mat:
			return mat
	return null


func _orm_from_prefix(pre: String) -> ORMMaterial3D:
	var diff_p := prop_dir + pre + "_baked_diffuse.webp"
	var norm_p := prop_dir + pre + "_baked_normal.png"
	var orm_p := prop_dir + pre + "_baked_orm.png"
	if not (FileAccess.file_exists(diff_p) and FileAccess.file_exists(norm_p) and FileAccess.file_exists(orm_p)):
		return null
	var mat := ORMMaterial3D.new()
	mat.resource_name = pre + "_orm"
	mat.albedo_texture = load_tex_any(diff_p)
	mat.orm_texture = load_tex_any(orm_p)
	mat.normal_enabled = true
	mat.normal_texture = load_tex_any(norm_p)
	mat.ao_enabled = true
	return mat


func load_tex_any(p: String) -> Texture2D:
	if ResourceLoader.exists(p):
		var t := load(p) as Texture2D
		if t:
			print("    TEX: %s [%s]" % [p.get_file(), t.get_class()])
			return t
	# Фолбэк без .import: сырая картинка + генерим мипмапы (иначе рябь в 3D).
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null:
		print("    TEX FAIL: %s" % p)
		return null
	if not img.has_mipmaps():
		img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	print("    TEX: %s [ImageTexture-фолбэк]" % p.get_file())
	return tex


func replace_textures_in_state(state: GLTFState):
	var materials = state.get_materials()
	var images = state.get_images()
	if images.is_empty():
		print("  No images in GLTF — nothing to replace")
		return

	var json_text = FileAccess.get_file_as_string(raw_gltf)
	var gltf_data = JSON.parse_string(json_text)
	var gltf_images = gltf_data.get("images", [])

	var replaced = 0
	for i in range(images.size()):
		var old_tex = images[i] as Texture2D
		if not old_tex:
			continue

		var uri = ""
		if i < gltf_images.size():
			uri = gltf_images[i].get("uri", "")
		if uri.is_empty():
			# embedded image — skip
			print("  SKIP %d: no URI (embedded)" % i)
			continue

		var webp_path = prop_dir.path_join(uri)
		if not FileAccess.file_exists(webp_path):
			print("  SKIP %d: %s not found" % [i, webp_path])
			continue

		# load() при наличии .import даёт CompressedTexture2D С resource_path —
		# ResourceSaver тогда сохраняет ВНЕШНЮЮ ссылку, а не вкомпывает текстуру
		# в .res (инцидент 18.11.26: ель 25–38 МБ на меш + 576 МБ VRAM, камни
		# 12,6 МБ на меш). Фолбэк на сырую картинку живёт в load_tex_any.
		var new_tex := load_tex_any(webp_path)
		if new_tex == null:
			print("  SKIP %d: cannot load %s" % [i, webp_path])
			continue

		for mat in materials:
			if mat is BaseMaterial3D:
				replace_tex_in_material(mat, old_tex, new_tex)

		print("  TEX %d: %s -> %s [%s]" % [i, uri, webp_path, new_tex.get_class()])
		replaced += 1

	print("  Replaced %d / %d textures" % [replaced, images.size()])


func replace_tex_in_material(mat: BaseMaterial3D, old_tex: Texture2D, new_tex: Texture2D):
	var slots = ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]
	for slot in slots:
		var current = mat.get(slot) as Texture2D
		if current == old_tex:
			mat.set(slot, new_tex)


## Foliage-поверхности (Q22, метод A «процедурный атлас»): gltf alphaMode
## MASK → ALPHA_SCISSOR + cull DISABLED. Godot-импортёр обычно сам мапит
## MASK/doubleSided; пасс-страховка по JSON — на случай дрейфа импортёра
## (трогает ТОЛЬКО transparency/cull/metallic — v2-ORM-флоу не ломает).
func _ensure_foliage_materials(state: GLTFState) -> void:
	var json_text = FileAccess.get_file_as_string(raw_gltf)
	var gltf_data = JSON.parse_string(json_text)
	if gltf_data == null:
		return
	var mats = gltf_data.get("materials", [])
	var state_mats = state.get_materials()
	for i in range(mini(mats.size(), state_mats.size())):
		if str(mats[i].get("alphaMode", "")) != "MASK":
			continue
		var m = state_mats[i] as BaseMaterial3D
		if m == null:
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = float(mats[i].get("alphaCutoff", 0.45))
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.metallic = 0.0
		print("  FOLIAGE: %s → scissor %.2f, cull off"
			% [m.resource_name, m.alpha_scissor_threshold])


func build_prop_scene(model_root: Node):
	# База имени выхода = имя gltf-файла без суффиксов (_v2_baked/_4k_baked):
	# пилотный test_stone_v2_baked.gltf не затирает живой test_stone.tscn.
	var gltf_base: String = raw_gltf.get_file().get_basename()
	for suffix in ["_v2_baked", "_4k_optimized", "_4k_baked", "_baked"]:
		if gltf_base.ends_with(suffix):
			gltf_base = gltf_base.trim_suffix(suffix)
			break
	var out_base: String = gltf_base if gltf_base != prop_name else prop_name
	var root = StaticBody3D.new()
	root.name = out_base.capitalize()

	var mesh_index = 0
	var todo = [model_root]
	while todo:
		var node = todo.pop_back()
		if node is MeshInstance3D:
			var mi = node as MeshInstance3D
			if mi.mesh:
				# v2: свой ORM-материал на каждый меш (до save — внешние ссылки).
				var mat := _orm_material_for(mesh_index)
				if mat:
					for s in mi.mesh.get_surface_count():
						mi.mesh.surface_set_material(s, mat)
				var mesh_path = prop_dir + out_base + "_mesh_%d.res" % mesh_index
				ResourceSaver.save(mi.mesh, mesh_path)
				mi.mesh = load(mesh_path)
				print("  MESH %d: %s -> %s" % [mesh_index, mi.name, mesh_path])
				mesh_index += 1
		for c in node.get_children():
			todo.append(c)

	var first_mi = find_first_mesh_instance(model_root)
	if first_mi and first_mi.mesh:
		var collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		# Convex-hull вместо trimesh (19.11.26, зонд probe_boulder_fps5): упор
		# CharacterBody3D в trimesh-коллизию валуна = move_and_slide 5-11мс НА
		# КАЖДЫЙ тик физики (депенетрация против 4000 граней, класс Godot
		# issue #70453) — у юзера это фризы 100-400мс у валуна. Тот же упор в
		# convex-hull (32 точки): worst 1.7мс. Рокам/камням hull визуально не
		# уступает (коллизия невидима), решает задача.
		collision.shape = first_mi.mesh.create_convex_shape(true, true)
		root.add_child(collision)

	# КОНТРАКТ ПОДОШВЫ (Q47-F, гоу юзера 21.11.26): origin сырья (trellis/Blender/
	# сканы) НЕ в подошве — свойство ДАННЫХ, чиним здесь, единственной точкой
	# сборки: низ merged AABB → y=0. Идемпотентно (низ 0 не двигается). Потребители
	# (скаттер, билдеры, PortalArchVisual, каталог) ставят проп в точку пола без
	# вычислений. Гейт контракта — check_foot_origin.gd (низ tscn == 0±1 см).
	var lowest := _merged_lowest_y(model_root)
	if absf(lowest) > 0.001:
		model_root.position.y -= lowest
		print("  FOOT: низ геометрии %.3f → y=0 (Graphics сдвинут на %.3f)" % [lowest, -lowest])
	elif absf(lowest) <= 0.001:
		print("  FOOT: низ уже в y=0 — не двигаю")

	model_root.name = "Graphics"
	if model_root.get_parent():
		model_root.get_parent().remove_child(model_root)
	root.add_child(model_root)

	_apply_visibility_ranges(model_root)
	set_owner_recursive(root, root)

	var packed = PackedScene.new()
	packed.pack(root)
	var tscn_path = prop_dir + out_base + ".tscn"
	ResourceSaver.save(packed, tscn_path)
	print("  TSCN: %s (%d meshes)" % [tscn_path, mesh_index])


static func find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if not node:
		return null
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r = find_first_mesh_instance(c)
		if r:
			return r
	return null


func set_owner_recursive(node: Node, owner_node: Node):
	if node == owner_node:
		for child in node.get_children():
			set_owner_recursive(child, owner_node)
		return
	node.owner = owner_node
	for child in node.get_children():
		set_owner_recursive(child, owner_node)


## HLOD-фейк из демо 3d/visibility_ranges: проп плавно гаснет с дистанции.
## Диапазон от диагонали AABB меша: мелкие (фон) короче, хиро длиннее.
func _apply_visibility_ranges(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var diag := mi.get_aabb().size.length()
			mi.visibility_range_end = clampf(diag * 50.0, 120.0, 350.0)
			mi.visibility_range_end_margin = mi.visibility_range_end * 0.08
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in node.get_children():
		_apply_visibility_ranges(c)


## Сырой низ merged AABB геометрии (детached-иерархия: трансформы НАКОПЛЕНИЕМ,
## global_transform не работает; узловой get_aabb() пуст — только РЕСУРСНЫЕ
## mesh.get_aabb()/multimesh.get_aabb(); паттерн _geometry_lowest_y из
## build_main_arena.gd). Для контракта подошвы Q47-F.
func _merged_lowest_y(n: Node3D) -> float:
	var lo := 1e9
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var nd: Node = e[0]
		var xf: Transform3D = e[1]
		var next_xf := xf
		if nd is Node3D:
			next_xf = xf * (nd as Node3D).transform
		var ab: AABB
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			ab = (nd as MeshInstance3D).mesh.get_aabb()
		elif nd is MultiMeshInstance3D and (nd as MultiMeshInstance3D).multimesh != null:
			ab = (nd as MultiMeshInstance3D).multimesh.get_aabb()
		else:
			ab = AABB()
		if ab.size != Vector3.ZERO or ab.position != Vector3.ZERO:
			for i in 8:
				var cy := ab.position.y if i < 4 else ab.position.y + ab.size.y
				var cx := ab.position.x if i % 2 == 0 else ab.position.x + ab.size.x
				var cz := ab.position.z if (i % 4) < 2 else ab.position.z + ab.size.z
				lo = minf(lo, (next_xf * Vector3(cx, cy, cz)).y)
		for c in nd.get_children():
			stack.append([c, next_xf])
	if lo >= 1e9:
		return 0.0
	return lo
