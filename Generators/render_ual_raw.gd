extends SceneTree
## Рендер СЫРЫХ UAL-клипов на манекене пака (ДО ретаргета) — вердикт о
## качестве исходного движения своими глазами. Окно заэкранное (правило
## юзера: моё окно теста не должно мешать).
##
## Запуск (ОКОННЫЙ, не headless — headless не рендерит):
##   "<godot>" -s res://Generators/render_ual_raw.gd -- <1|2> <Клип> [времена]
## Пример:
##   "<godot>" -s res://Generators/render_ual_raw.gd -- 1 Pistol_Shoot 0.05,0.2,0.35,0.5
## Кадры: res://_tmp_probe/ualraw_<клип>_NN.png

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const UAL2 := "res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx"
const OUT_DIR := "res://_tmp_probe"

var skel: Skeleton3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("RAW FAIL: нужно <1|2> <Клип> [времена]")
		quit(1)
		return
	var path := UAL1 if String(args[0]) == "1" else UAL2
	var clip: String = args[1]
	var times: Array = []
	if args.size() > 2:
		for s in String(args[2]).split(","):
			times.append(float(s))

	var scene = load_fbx_scene(path)
	if scene == null:
		print("RAW FAIL: нет сцены")
		quit(1)
		return
	root.add_child(scene)
	await process_frame
	var ap = find_animation_player(scene)
	skel = find_skeleton(scene)
	if ap == null or skel == null:
		print("RAW FAIL: нет аниматора/скелета")
		quit(1)
		return
	var lib = ap.get_animation_library("")
	var target := ""
	for n in lib.get_animation_list():
		if String(n).ends_with("|" + clip) or n == clip:
			target = n
			break
	if target == "":
		print("RAW FAIL: нет клипа %s. Есть: %s..." % [clip, ", ".join(lib.get_animation_list().slice(0, 8))])
		quit(1)
		return

	# Автокадрирование: AABB по костям в текущей позе.
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in skel.get_bone_count():
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var center := (lo + hi) * 0.5 + Vector3(0, 0.1, 0)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(center + Vector3(1.2, 0.35, 2.3), center, Vector3.UP)
	cam.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(light)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var base := clip.to_lower()
	var idx := 0
	for t: float in times:
		ap.play(target)
		ap.seek(t, true)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var p := "%s/ualraw_%s_%02d.png" % [OUT_DIR, base, idx]
		img.save_png(p)
		print("RAW %s t=%.2f -> %s" % [clip, t, p])
		idx += 1
	quit(0)

func load_fbx_scene(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null
	return fbx_doc.generate_scene(state)

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skeleton(c)
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
