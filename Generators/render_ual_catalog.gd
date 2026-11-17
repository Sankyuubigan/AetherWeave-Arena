extends SceneTree
## Каталог UAL-анимаций: рендер ВСЕХ клипов UAL1+UAL2 в PNG-кадры ОДНИМ
## процессом (§11.29: серийные windowed-запуски мелькают окнами).
## Дальше ffmpeg собирает per-clip GIF, bash строит index.html — таблица
## «имя клипа (копируется кликом) | гифка».
##
## Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File _tmp_probe/run_catalog.ps1
## Выход:  _tmp_probe/ual_catalog/<LIB>/<Clip>/f%03d.png

const LIBS := [
	["UAL1", "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"],
	["UAL2", "res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx"],
]
const OUT := "res://_tmp_probe/ual_catalog"
const FPS := 10.0   # сэмплируем 10 кадров/с клипа
const MIN_F := 8    # минимум кадров на клип (GIF-луп читаемее)
const MAX_F := 36   # длинные (4 с) не раздуваем

var cam: Camera3D
var lib_label := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	_ensure_stage()
	for lib in LIBS:
		lib_label = lib[0]
		var scene = _load_fbx(lib[1])
		if scene == null:
			print("CATALOG FAIL: не загрузился ", lib[0])
			continue
		var ap: AnimationPlayer = _find_ap(scene)
		if ap == null:
			print("CATALOG FAIL: нет AnimationPlayer в ", lib[0])
			scene.free()
			continue
		root.add_child(scene)
		await process_frame
		await process_frame
		var names := Array(ap.get_animation_list())
		names.sort()
		for n in names:
			await _render_clip(ap, String(n))
		scene.queue_free()
		await process_frame
		await process_frame
	print("CATALOG DONE")
	quit(0)

func _render_clip(ap: AnimationPlayer, full_name: String) -> void:
	var name := String(full_name).replace("Armature|", "")
	var anim := ap.get_animation(full_name)
	var dur: float = maxf(anim.length, 0.1)
	var n := clampi(int(dur * FPS), MIN_F, MAX_F)
	var dir := "%s/%s/%s" % [OUT, lib_label, name]
	DirAccess.make_dir_recursive_absolute(dir)
	ap.play(full_name)
	for i in range(n):
		var t: float = dur * float(i) / float(n)
		ap.seek(t, true)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/f%03d.png" % [dir, i])
	print("CAT %s %s dur=%.2f frames=%d" % [lib_label, name, dur, n])

func _ensure_stage() -> void:
	if cam:
		return
	var floor_node := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_node.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.32, 0.38)
	floor_node.material_override = fmat
	root.add_child(floor_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-40, 150, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.4, 4.4), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

func _load_fbx(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBX ERR ", path, " ", err)
		return null
	return fbx_doc.generate_scene(state)

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = _find_ap(c)
		if r:
			return r
	return null
