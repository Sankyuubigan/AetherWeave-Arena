extends SceneTree
## БАТЧ-РЕНДЕР верификации UAL-ретаргета: ВСЕ кадры за ОДИН запуск Godot.
## Урок (раунд 10): последовательные windowed-запуски мелькают окнами даже с
## --position — console-exe под detached-шеллом создаёт НОВУЮ консоль на каждый
## запуск. Один процесс = максимум одна отрисовка; консоль прячем через
## PowerShell Start-Process -WindowStyle Hidden (рецепт §11.29 доки).
## Манекен развёрнут лицом к камере (rotation.y = PI), иначе его рук не видно.
##
## Запуск (см. §11.29 docs/animation_generation.md):
##   powershell -NoProfile -ExecutionPolicy Bypass -File _tmp_probe/run_renders.ps1
## Кадры: _tmp_probe/v4cmp_*.png (источник|скин бок о бок) и
##        _tmp_probe/v4cast_*.png (только скин, серия времён).

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const OUT_DIR := "res://_tmp_probe"

# [подстрока исходного клипа, имя скин-клипа, время]
const CMP_SPECS := [
	["Spell_Simple_Idle_Loop", "Cast_Loop", 0.0],
	["Spell_Simple_Shoot", "Cast_Shoot", 0.25],
	["Push_Loop", "Beam_Push", 0.4],
	["OverhandThrow", "Throw", 0.6],
]
# [скин-клип, [времена]]
const SKIN_SPECS := [
	["Cast_Enter", [0.03, 0.17, 0.3, 0.45]],
	["Cast_Loop", [0.03, 0.8, 1.6]],
	["Cast_Shoot", [0.03, 0.15, 0.25, 0.35, 0.45]],
	["Cast_Exit", [0.03, 0.15, 0.28, 0.4]],
	["Throw", [0.03, 0.3, 0.6, 0.9, 1.2]],
	["Beam_Push", [0.03, 0.5, 1.0, 1.5, 2.0]],
]

var man: Node
var mskel  # Skeleton3D источника; untyped — find_bone недоступен на Node
var map: Node
var player: Node
var skin: Skeleton3D
var ap: AnimationPlayer
var cam: Camera3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Страховка; главный механизм скрытия — --position в командной строке.
	DisplayServer.window_set_position(Vector2i(-2400, -2400))

	# ── Манекен UAL (источник) ──
	man = load_fbx_scene(UAL1)
	if man == null:
		print("BATCH FAIL: манекен не загрузился")
		quit(1)
		return
	mskel = find_skeleton(man)
	map = find_animation_player(man)
	root.add_child(man)
	man.position = Vector3(-1.2, 0, 0)
	man.rotation.y = PI  # источник смотрит −Z — разворачиваем к камере

	# ── Скин + тестовая библиотека ──
	var packed: PackedScene = load(PLAYER_SCENE)
	player = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	player.position = Vector3(1.2, 0, 0)
	await process_frame
	await process_frame
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	ap = aps[0]
	var extra = load(TEST_LIB)
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

	# ── Сцена: пол, свет, камера спереди ──
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
	cam = Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.35, 3.6), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# ── Сравнения источник|скин ──
	for spec in CMP_SPECS:
		await _render_cmp(spec[0], spec[1], spec[2])

	# ── Серии скина (манекен скрыт) ──
	man.visible = false
	for spec in SKIN_SPECS:
		await _render_skin(spec[0], spec[1])

	print("BATCH DONE")
	quit(0)

func _render_cmp(src_sub: String, skin_clip: String, t: float) -> void:
	var mclip := ""
	for n in map.get_animation_list():
		if String(n).ends_with(src_sub):
			mclip = n
			break
	if mclip == "":
		print("BATCH WARN: нет исходного клипа ", src_sub)
		return
	man.visible = true
	map.play(mclip)
	map.seek(t, true)
	ap.play(skin_clip)
	ap.seek(t, true)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/v4cmp_%s_%02d.png" % [OUT_DIR, src_sub.to_lower(), int(t * 100)]
	img.save_png(path)
	var mk_r: int = mskel.find_bone("hand_r")
	var mk_l: int = mskel.find_bone("hand_l")
	var ir: int = skin.find_bone("mixamorig_RightHand")
	var il: int = skin.find_bone("mixamorig_LeftHand")
	print("CMP %s t=%.2f → %s" % [src_sub, t, path])
	print("  SRC hand_r %s hand_l %s" % [
		mskel.global_transform * mskel.get_bone_global_pose(mk_r).origin,
		mskel.global_transform * mskel.get_bone_global_pose(mk_l).origin])
	print("  SKIN RightHand %s LeftHand %s" % [
		skin.global_transform * skin.get_bone_global_pose(ir).origin,
		skin.global_transform * skin.get_bone_global_pose(il).origin])

func _render_skin(clip: String, times: Array) -> void:
	man.visible = false
	var target := ""
	for a in ap.get_animation_list():
		if a.to_lower().contains(clip.to_lower()):
			target = a
			break
	if target == "":
		print("BATCH WARN: нет скин-клипа ", clip)
		return
	var idx := 0
	for t: float in times:
		ap.play(target)
		ap.seek(t, true)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var path := "%s/v4cast_%s_%02d.png" % [OUT_DIR, clip.to_lower(), idx]
		img.save_png(path)
		print("SKIN %s t=%.2f → %s" % [clip, t, path])
		idx += 1

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
