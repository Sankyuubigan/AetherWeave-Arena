extends SceneTree
## РЕШАЮЩИЙ сравнительный кадр: манекен UAL (сырой клип) и скин (ретаргет v3)
## В ОДНОМ кадре бок о бок, одна камера. Если поднятая рука на одной стороне
## изображения — зеркала нет; на противоположных — зеркало есть.
## Запуск (ОКОННЫЙ, окно за экраном):
##   "<godot>" --position -2400,-2400 -s res://Generators/probe_compare_side.gd -- <УалКлип> <Время>

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var args := OS.get_cmdline_user_args()
	var src_clip: String = args[0] if args.size() > 0 else "Spell_Simple_Idle_Loop"
	var t_src: float = float(args[1]) if args.size() > 1 else 0.0

	# ── 1) Манекен UAL ──
	var man = load_fbx_scene(UAL1)
	var mskel = find_skeleton(man)
	var map = find_animation_player(man)
	var mlib = map.get_animation_library("")
	var mclip := ""
	for n in mlib.get_animation_list():
		if String(n).ends_with(src_clip):
			mclip = n
			break
	if mclip == "":
		print("CMP2 FAIL: нет клипа ", src_clip)
		quit(1)
		return
	man.get_node(map.get_parent().get_path_to(map)).remove_child(map) if false else null
	root.add_child(man)

	# ── 2) Скин + тестовая библиотека ──
	var packed: PackedScene = load(PLAYER_SCENE)
	var player := packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0]
	var extra = load(TEST_LIB)
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

	# Позиционирование: манекен слева (−1.2), скин справа (+1.2).
	# Манекен UAL смотрит −Z (от камеры) — разворачиваем лицом к камере.
	man.position = Vector3(-1.2, 0, 0)
	man.rotation.y = PI
	player.position = Vector3(1.2, 0, 0)

	# Стол + свет
	var floor_node := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_node.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.35, 0.4)
	floor_node.material_override = fmat
	root.add_child(floor_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-40, 150, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)

	# Камера спереди (обе фигуры смотрят +Z)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.35, 3.6)
	cam.look_at_from_position(Vector3(0, 1.35, 3.6), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	# Проиграть: манекен — сырой клип, скин — ретаргет
	map.play(mclip)
	map.seek(t_src, true)
	ap.play("Cast_Loop")
	ap.seek(t_src, true)
	await process_frame
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe")
	var img := root.get_texture().get_image()
	var path := "res://_tmp_probe/cmp_%s_%02d.png" % [src_clip.to_lower(), int(t_src * 100)]
	img.save_png(path)
	print("CMP2: %s t=%.2f → %s" % [src_clip, t_src, path])

	# Числа: мировые позиции кистей обеих фигур
	var mk_r = mskel.find_bone("hand_r")
	var mk_l = mskel.find_bone("hand_l")
	var sks := player.find_children("*", "Skeleton3D", true, false)
	var ssk: Skeleton3D = sks[0]
	var ir := ssk.find_bone("mixamorig_RightHand")
	var il := ssk.find_bone("mixamorig_LeftHand")
	print("SRC hand_r %s  hand_l %s" % [
		mskel.global_transform * mskel.get_bone_global_pose(mk_r).origin,
		mskel.global_transform * mskel.get_bone_global_pose(mk_l).origin])
	print("SKIN RightHand %s  LeftHand %s" % [
		ssk.global_transform * ssk.get_bone_global_pose(ir).origin,
		ssk.global_transform * ssk.get_bone_global_pose(il).origin])
	quit(0)

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

func load_fbx_scene(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null
	return fbx_doc.generate_scene(state)

static func find_skeleton(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skeleton(c)
		if r:
			return r
	return null

static func find_animation_player(node: Node) -> Node:
	if not node:
		return null
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_animation_player(c)
		if r:
			return r
	return null
