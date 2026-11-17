extends SceneTree

var skin_name: String
var skin_dir: String
var raw_fbx: String
var godot_exe: String
var tex_count: int = 0

func _init():
	parse_args()

	skin_dir = "res://Graphics/PlayerModel/%s/" % skin_name
	raw_fbx = "res://Graphics/PlayerModel/raw/%s.fbx" % skin_name
	godot_exe = OS.get_executable_path()

	ensure_skin_dir()

	print("Loading FBX via FBXDocument...")
	var model_root = load_fbx_direct(raw_fbx)
	if not model_root:
		print("ERROR: cannot load %s" % raw_fbx)
		quit(1)

	if tex_count > 0 and not webps_are_imported():
		print("WebP not yet imported. Running Editor --import...")
		run_editor_import()
		print("Re-checking WebP import after --import...")
		if not webps_are_imported():
			print("WARNING: WebP still not importable. Building with embedded textures (large .tscn).")
			print("  Open project in Godot Editor once to fix, then re-run.")
		else:
			print("WebP imported! Reloading FBX to build compact scene...")
			model_root.queue_free()
			model_root = load_fbx_direct(raw_fbx)
			if not model_root:
				print("ERROR: cannot reload %s" % raw_fbx)
				quit(1)

	build_player_scene(model_root)
	clean_old_png()
	print("Done! Skin '%s' ready." % [skin_name])
	quit()


func parse_args():
	skin_name = "Ch24_nonPBR"
	var args = OS.get_cmdline_args()
	for arg in args:
		var trimmed = arg.trim_suffix(".fbx").strip_edges()
		if trimmed.is_empty() or trimmed.length() < 2:
			continue
		if trimmed.begins_with("res:") or trimmed.begins_with("-"):
			continue
		if trimmed.ends_with(".gd"):
			continue
		if trimmed.to_lower() in ["headless", "editor"]:
			continue
		skin_name = trimmed
		return


func ensure_skin_dir():
	var parent = DirAccess.open("res://Graphics/PlayerModel/")
	if parent and not parent.dir_exists(skin_name):
		parent.make_dir(skin_name)
		print("Created: %s" % skin_dir)


func webps_are_imported() -> bool:
	var dir = DirAccess.open(skin_dir)
	if not dir:
		return false
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".webp"):
			var full = skin_dir + file
			var tex = load(full)
			if tex:
				return true
		file = dir.get_next()
	dir.list_dir_end()
	return false


func run_editor_import():
	var project_path = ProjectSettings.globalize_path("res://")
	var err = OS.execute(godot_exe, ["--path", project_path, "--import"], [], true)
	if err != OK:
		print("WARNING: OS.execute for --import returned error code %d" % err)


# ─── FBXDocument ────────────────────────────────────────────────────

func load_fbx_direct(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	if not fbx_doc:
		print("FBXDocument not available in this Godot build")
		return null

	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())

	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null

	# Извлекаем встроенные изображения, сохраняем как WebP, заменяем в материалах
	self.tex_count = extract_images_and_replace(state)

	var scene_root = fbx_doc.generate_scene(state)
	if not scene_root:
		print("FBXDocument generated null scene")
		return null

	print("FBX loaded: %s" % scene_root.name)
	dump_node_tree(scene_root, "")
	return scene_root


func extract_images_and_replace(state: FBXState) -> int:
	var images = state.get_images()
	if images.is_empty():
		return 0

	var materials = state.get_materials()
	var count = 0

	for i in images.size():
		var tex = images[i] as Texture2D
		if not tex:
			continue

		var img = tex.get_image()
		if not img:
			continue

		var webp_name = "%s_tex_%d.webp" % [skin_name, i]
		var webp_path = skin_dir + webp_name
		img.save_webp(webp_path, 0.95)
		count += 1
		print("  IMG: %s -> %s" % [tex.resource_path.get_file(), webp_name])

		var new_tex = ResourceLoader.load(webp_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE)
		if not new_tex:
			new_tex = ImageTexture.create_from_image(img)

		for mat in materials:
			if not (mat is BaseMaterial3D):
				continue
			replace_in_mat(mat, tex, new_tex)

	return count


func replace_in_mat(mat: BaseMaterial3D, old_tex: Texture2D, new_tex: Texture2D):
	var slots = ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]
	for slot in slots:
		var current = mat.get(slot) as Texture2D
		if current == old_tex:
			mat.set(slot, new_tex)
			print("    SET %s" % slot)


func dump_node_tree(node: Node, indent: String):
	var info = node.name
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		info += " [MeshInstance3D]"
		if mi.mesh:
			info += " mesh=%s surfaces=%d" % [mi.mesh.resource_name, mi.mesh.get_surface_count()]
			for si in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(si)
				if m:
					info += " mat%d=%s" % [si, m.resource_name]
	print(indent + info)
	for child in node.get_children():
		dump_node_tree(child, indent + "  ")


# ─── Очистка ────────────────────────────────────────────────────────

func clean_old_png():
	var dir = DirAccess.open("res://Graphics/PlayerModel/")
	if not dir:
		return
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".png") or file.ends_with(".png.import"):
			dir.remove(file)
			print("  CLEAN: removed " + file)
		file = dir.get_next()
	dir.list_dir_end()


# ─── Сборка player.tscn ────────────────────────────────────────────

func build_player_scene(model_root: Node):
	# ── Externalize mesh and skin ─────────────────────────────────
	var mesh_instance = find_first_mesh_instance(model_root)
	var mesh_path = skin_dir + skin_name + "_mesh.res"
	var skin_path = skin_dir + skin_name + "_skin.res"

	if mesh_instance and mesh_instance.mesh:
		ResourceSaver.save(mesh_instance.mesh, mesh_path)
		mesh_instance.mesh = load(mesh_path)
		print("  MESH -> " + mesh_path)

	if mesh_instance and mesh_instance.skin:
		ResourceSaver.save(mesh_instance.skin, skin_path)
		mesh_instance.skin = load(skin_path)
		print("  SKIN -> " + skin_path)

	# ── Load shared animation library ──────────────────────────────
	var lib = load("res://Graphics/Animations/shared_animations.res")
	if not lib:
		print("  ERROR: shared_animations.res not found! Run build_animations.gd first.")
		quit(1)
	print("  ANIM: shared_animations.res loaded")

	# Remove any FBX-generated AnimationPlayer from model
	var fbx_ap = find_animation_player(model_root)
	if fbx_ap and fbx_ap.get_parent():
		fbx_ap.get_parent().remove_child(fbx_ap)
		fbx_ap.queue_free()

	# ── Build scene tree ──────────────────────────────────────────
	var root = CharacterBody3D.new()
	root.name = "Player"
	root.set_script(load("res://Logic/PlayerController.gd"))

	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape = CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 2.0
	collision.shape = shape
	root.add_child(collision)

	var wrapper = Node3D.new()
	wrapper.name = "GraphicsWrapper"
	root.add_child(wrapper)

	model_root.name = "PlayerModel"
	if model_root.get_parent():
		model_root.get_parent().remove_child(model_root)
	wrapper.add_child(model_root)

	# ── Якоря кистей (план каст-анимаций, Шаг 2) ────────────────────
	# BoneAttachment3D — ребёнок Skeleton3D: точки спавна снарядов (инста-каст)
	# и крепления будущего оружия (лазер). CastPoint — маркер для спавна.
	var hand_skel = find_skeleton_node(model_root)
	if hand_skel:
		for hand_info in [["RightHandAnchor", "mixamorig_RightHand"], ["LeftHandAnchor", "mixamorig_LeftHand"]]:
			var anchor = BoneAttachment3D.new()
			anchor.name = hand_info[0]
			anchor.bone_name = hand_info[1]
			hand_skel.add_child(anchor)
			var cast_point = Marker3D.new()
			cast_point.name = "CastPoint"
			anchor.add_child(cast_point)
		print("  ANCHORS: RightHand/LeftHand -> " + str(hand_skel.name))
	else:
		print("  WARN: Skeleton3D не найден — якоря кистей не созданы")

	var ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	wrapper.add_child(ap)
	ap.root_node = NodePath("../PlayerModel")
	ap.add_animation_library("", lib)

	var anim_comp = Node.new()
	anim_comp.name = "PlayerAnimationComponent"
	anim_comp.set_script(load("res://Graphics/PlayerAnimationComponent.gd"))
	root.add_child(anim_comp)

	var spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.position = Vector3(0.7, 1.5, 0)
	spring_arm.spring_length = 3.0
	spring_arm.margin = 0.2
	root.add_child(spring_arm)

	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3.ZERO
	spring_arm.add_child(camera)

	var spell_caster = Node.new()
	spell_caster.name = "SpellCasterComponent"
	spell_caster.set_script(load("res://Logic/SpellCasterComponent.gd"))
	root.add_child(spell_caster)

	var canvas = CanvasLayer.new()
	canvas.name = "CrosshairUI"
	root.add_child(canvas)

	var container = CenterContainer.new()
	container.name = "CrosshairContainer"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)

	var cross = ColorRect.new()
	cross.name = "Crosshair"
	cross.custom_minimum_size = Vector2(4, 4)
	cross.color = Color(0.0, 1.0, 0.0)
	container.add_child(cross)

	set_owner_recursive(root, root)

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/player.tscn")
	print("Player scene saved!")


func set_owner_recursive(node: Node, owner_node: Node):
	if node == owner_node:
		for child in node.get_children():
			set_owner_recursive(child, owner_node)
		return
	node.owner = owner_node
	for child in node.get_children():
		set_owner_recursive(child, owner_node)


static func find_skeleton_node(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skeleton_node(c)
		if r:
			return r
	return null

static func find_animation_player(node: Node) -> AnimationPlayer:
	if not node:
		return null
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_animation_player(c)
		if r:
			return r
	return null

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
