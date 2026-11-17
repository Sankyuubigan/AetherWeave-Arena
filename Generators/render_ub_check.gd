extends SceneTree
## Кадровая проверка «всегда UB» (§13.4): UB-каст играет ВТОРЫМ плеером
## поверх продолжающегося Run — как в игре. ОДИН процесс (§11.29).
## Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File _tmp_probe/run_ub.ps1
## Кадры: _tmp_probe/ub_<клип>_fXX.png (+ лог UBCHK с позициями кистей/стоп)

const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const OUT_DIR := "res://_tmp_probe"
## Клипы и число кадров (60 fps): Heart ~1.17с, Throw/ Shoot ~1.0-1.2с
const CLIPS := [
	["Heart_Cast_UB", 78],
	["Throw_UB", 78],
	["Cast_Shoot_UB", 78],
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame

	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var skel: Skeleton3D = _find_skeleton(player)

	# CastPlayer как в игре: после loco, тот же root_node, только UB-клипы.
	var castp := AnimationPlayer.new()
	loco.get_parent().add_child(castp)
	castp.root_node = loco.root_node
	var src_lib = load(TEST_LIB)
	var clib := AnimationLibrary.new()
	for an in src_lib.get_animation_list():
		if String(an).ends_with("_UB"):
			clib.add_animation(an, src_lib.get_animation(an))
	castp.add_animation_library("", clib)

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
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.35, 3.6), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	loco.play("Run")
	for i in 20:
		await process_frame

	for spec in CLIPS:
		var clip: String = spec[0]
		var nframes: int = spec[1]
		# Как в игре: play + capture (вход из позы бега)
		castp.play(clip, 0.1)
		castp.capture(clip, 0.1)
		for i in nframes:
			await process_frame
			if i % 6 == 0:
				var idx := i / 6
				var img := root.get_texture().get_image()
				var path := "%s/ub_%s_f%02d.png" % [OUT_DIR, clip.to_lower(), idx]
				img.save_png(path)
				var lh := skel.find_bone("mixamorig_LeftHand")
				var lf := skel.find_bone("mixamorig_LeftFoot")
				print("UBCHK %s f%02d → %s | кисть %s | стопа %s" % [
					clip, idx, path,
					(skel.global_transform * skel.get_bone_global_pose(lh)).origin,
					(skel.global_transform * skel.get_bone_global_pose(lf)).origin])
		castp.stop()
		for i in 10:
			await process_frame
	print("UB RENDER DONE")
	quit(0)

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
