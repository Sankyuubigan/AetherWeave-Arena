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
		print("ERROR: No glTF found for '%s' in %s" % [prop_name, prop_dir])
		quit(1)

	print("Loading: %s" % raw_gltf)
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file(raw_gltf, state)
	if err != OK:
		print("ERROR: Failed to load GLTF: %s" % error_string(err))
		quit(1)

	replace_textures_in_state(state)

	var scene_root = doc.generate_scene(state)
	if not scene_root:
		print("ERROR: Generated scene is null")
		quit(1)

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

		# Godot 4.8: ResourceLoader.load() для webp без .import даёт «No loader
		# found» — грузим через Image.load_from_file (ест webp/png/jpg).
		# Сырая картинка идёт БЕЗ мипмапов — в 3D это пиксельная рябь, генерим.
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(webp_path))
		if img == null:
			print("  SKIP %d: cannot load %s" % [i, webp_path])
			continue
		if not img.has_mipmaps():
			img.generate_mipmaps()
		var new_tex: ImageTexture = ImageTexture.create_from_image(img)

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


func build_prop_scene(model_root: Node):
	var root = StaticBody3D.new()
	root.name = prop_name.capitalize()

	var mesh_index = 0
	var todo = [model_root]
	while todo:
		var node = todo.pop_back()
		if node is MeshInstance3D:
			var mi = node as MeshInstance3D
			if mi.mesh:
				var mesh_path = prop_dir + prop_name + "_mesh_%d.res" % mesh_index
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
		collision.shape = first_mi.mesh.create_trimesh_shape()
		root.add_child(collision)

	model_root.name = "Graphics"
	if model_root.get_parent():
		model_root.get_parent().remove_child(model_root)
	root.add_child(model_root)

	set_owner_recursive(root, root)

	var packed = PackedScene.new()
	packed.pack(root)
	var tscn_path = prop_dir + prop_name + ".tscn"
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
