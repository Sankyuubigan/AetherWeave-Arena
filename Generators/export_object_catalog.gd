extends SceneTree

# Q41: каталог 3D-объектов (tools/object_catalog). Для каждого префаба
# Graphics/Environment/Props/<name>/:
#   1) считает ФАКТИЧЕСКИЕ трисы игровых мешей <name>_mesh_*.res
#      (surface_get_arrays → ARRAY_INDEX/3, как в check_polycount.gd);
#   2) экспортирует визуальную часть .tscn в GLTF для three.js-вьюера
#      (GLTFDocument.append_from_scene + write_to_filesystem).
# Текстуры: CompressedTexture2D (VRAM .ctex) не годятся для GLTF — подменяем
# на ImageTexture из исходного webp/png через Image.load_from_file()
# (проверенный путь build_env_prop.gd). GLTFDocument.image_format = Lossy WebP
# — текстуры пишутся рядом с .gltf (.webp, EXT_texture_webp, three r160 OK).
# ShaderMaterial (mushroom_bounce/soft_ground) не сериализуется в glTF —
# подменяем StandardMaterial3D с цветом из shader_parameter/albedo_col.
# Запуск ТОЛЬКО через PowerShell-обёртку (прямой pipe из Git Bash виснет):
#   powershell -File _tmp_probe/run_godot.ps1 res://Generators/export_object_catalog.gd

const PROPS_DIR := "res://Graphics/Environment/Props/"
const OUT_ROOT := "D:/Projects/3d_game/tools/object_catalog"

# Цветовые фолбэки для пропов с ShaderMaterial (tscn хранит null →
# применяется дефолт шейдера; сюда выписаны эти дефолты из .gdshader).
const SHADER_FALLBACK := {
	"mushroom_bounce": Color(0.72, 0.25, 0.18),
	"soft_ground": Color(0.82, 0.74, 0.58),
}
const SHADER_FALLBACK_DEFAULT := Color(0.65, 0.65, 0.65)

var failures: Array = []

func _init() -> void:
	print("=== OBJECT CATALOG EXPORT (Q41) ===")
	var props_root := DirAccess.open(PROPS_DIR)
	if not props_root:
		print("SCRIPT ERROR: не открыть ", PROPS_DIR)
		quit(1)
		return
	var entries: Array = []
	props_root.list_dir_begin()
	var dir_name := props_root.get_next()
	while dir_name != "":
		if props_root.current_is_dir() and not dir_name.begins_with("."):
			var e := _export_prop(dir_name)
			if e.is_empty():
				failures.append(dir_name)
			else:
				entries.append(e)
		dir_name = props_root.get_next()
	entries.sort_custom(func(a, b): return a.name < b.name)
	var json_path := OUT_ROOT + "/catalog.json"
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if not f:
		print("SCRIPT ERROR: не записать ", json_path)
		quit(1)
		return
	f.store_string(JSON.stringify(entries, "  "))
	f.close()
	var total_tris := 0
	for e in entries:
		total_tris += int(e.tris)
	print("=== catalog.json: ", entries.size(), " объектов, ", total_tris, " трис ===")
	if failures.size() > 0:
		print("ОШИБКИ (", failures.size(), "): ", failures)
		quit(1)
	else:
		quit(0)

func _export_prop(prop: String) -> Dictionary:
	var dir_path := PROPS_DIR + prop
	var dd := DirAccess.open(dir_path)
	if not dd:
		print("ОШИБКА: не открыть ", dir_path)
		return {}

	# --- 1) трисы по игровым _mesh_*.res ---
	var mesh_files: Array = []
	dd.list_dir_begin()
	var fn := dd.get_next()
	while fn != "":
		if not dd.current_is_dir() and fn.begins_with(prop + "_mesh_") and fn.ends_with(".res"):
			mesh_files.append(fn)
		fn = dd.get_next()
	mesh_files.sort()
	var files_info: Array = []
	var tris_total := 0
	for mf in mesh_files:
		var mesh := load(dir_path + "/" + mf) as Mesh
		if not mesh:
			print("ОШИБКА: не загрузить меш ", dir_path + "/", mf)
			return {}
		var t := count_mesh_tris(mesh)
		files_info.append({"file": mf, "tris": t})
		tris_total += t

	# --- 2) сцена → визуальное дерево → GLTF ---
	var scene_res := load(dir_path + "/" + prop + ".tscn")
	if not scene_res:
		print("ОШИБКА: нет tscn у ", prop)
		return {}
	var instant_root: Node = (scene_res as PackedScene).instantiate()
	if not instant_root:
		print("ОШИБКА: instantiate вернул null у ", prop)
		return {}

	var vis_root := Node3D.new()
	vis_root.name = prop
	var used_shader_fallback := false
	var scene_tris := 0
	for mi in _collect_mesh_instances(instant_root):
		# накопленный трансформ от корня инстанса до меш-инстанса
		var acc := (mi as MeshInstance3D).transform
		var n: Node = mi.get_parent()
		while n != null and n != instant_root:
			if n is Node3D:
				acc = (n as Node3D).transform * acc
			n = n.get_parent()
		var dup := (mi as MeshInstance3D).duplicate() as MeshInstance3D
		dup.transform = acc
		scene_tris += count_mesh_tris(dup.mesh)
		if _fixup_materials(dup, prop):
			used_shader_fallback = true
		vis_root.add_child(dup)
	instant_root.free()

	# sanity: сцена должна совпасть с суммой игровых мешей (если они есть)
	if mesh_files.size() > 0 and scene_tris != tris_total:
		print("! ", prop, ": tscn рендерит ", scene_tris, " трис, а _mesh_*.res дают ", tris_total)

	var out_dir := OUT_ROOT + "/models/" + prop
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		print("ОШИБКА: mkdir ", out_dir, " err=", err)
		return {}
	var doc := GLTFDocument.new()
	doc.image_format = "Lossy WebP"
	doc.lossy_quality = 0.8
	var state := GLTFState.new()
	err = doc.append_from_scene(vis_root, state)
	if err != OK:
		print("ОШИБКА: append_from_scene ", prop, " err=", err)
		return {}
	err = doc.write_to_filesystem(state, out_dir + "/" + prop + ".gltf")
	if err != OK:
		print("ОШИБКА: write_to_filesystem ", prop, " err=", err)
		return {}

	var entry := {
		"name": prop,
		"tris": tris_total if mesh_files.size() > 0 else scene_tris,
		"files": files_info,
		"gltf": "models/" + prop + "/" + prop + ".gltf",
	}
	if used_shader_fallback:
		entry["note"] = "ShaderMaterial заменён цветом (в glTF шейдеры не сериализуются)"
	print("OK: ", prop, " tris=", entry.tris, " (", mesh_files.size(), " mesh-файлов)")
	return entry

# Все MeshInstance3D поддерева (рекурсивно).
func _collect_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_mesh_instances(c))
	return out

# Подменяет материалы у дубля: CompressedTexture2D → ImageTexture из исходника,
# ShaderMaterial → StandardMaterial3D цвет-фолбэк. Возвращает true, если был шейдер.
func _fixup_materials(mi: MeshInstance3D, prop: String) -> bool:
	var had_shader := false
	if mi.material_override is ShaderMaterial:
		mi.material_override = _fallback_from_shader(mi.material_override, prop)
		had_shader = true
	elif mi.material_override:
		_swap_textures(mi.material_override)
	for s in range(mi.mesh.get_surface_count()):
		var ov := mi.get_surface_override_material(s)
		if ov is ShaderMaterial:
			mi.set_surface_override_material(s, _fallback_from_shader(ov, prop))
			had_shader = true
		elif ov:
			_swap_textures(ov)
	for s in range(mi.mesh.get_surface_count()):
		var m := mi.mesh.surface_get_material(s)
		if m is ShaderMaterial:
			mi.mesh.surface_set_material(s, _fallback_from_shader(m, prop))
			had_shader = true
		elif m:
			_swap_textures(m)
	return had_shader

func _fallback_from_shader(sm: ShaderMaterial, prop: String) -> StandardMaterial3D:
	var col: Color = SHADER_FALLBACK.get(prop, SHADER_FALLBACK_DEFAULT)
	var c = sm.get_shader_parameter("albedo_col")
	if c is Color:
		col = c
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	return m

# Все *_texture-свойства BaseMaterial3D: CompressedTexture2D (с путём к
# исходному webp/png) → ImageTexture из декодированного файла.
func _swap_textures(mat: Material) -> void:
	if not (mat is BaseMaterial3D):
		return
	var bm := mat as BaseMaterial3D
	for p in bm.get_property_list():
		var pname: String = p.name
		if not pname.ends_with("_texture"):
			continue
		var v = bm.get(pname)
		if not (v is Texture2D) or v is ImageTexture:
			continue
		var tex: Texture2D = v
		var rp := tex.resource_path
		if rp.is_empty():
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(rp))
		if img == null:
			print("  ! текстура не декодировалась: ", rp)
			continue
		bm.set(pname, ImageTexture.create_from_image(img))

# Формула трис как в check_polycount.gd: индексы/3 (или вершины/3), по ВСЕМ
# поверхностям меша.
func count_mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var tris := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		# as-каст на null в GDScript 4.8 кидает рантайм-ошибку — проверяем через is
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and idx.size() > 0:
			tris += idx.size() / 3
		else:
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts is PackedVector3Array:
				tris += verts.size() / 3
	return tris
