extends SceneTree
## Кадровая проверка сердечек (§13.4): серии Heart_Cast и Heart_Cast_L.
## ОДИН процесс (§11.29 — серийные запуски мелькают окнами). Скин смотрит
## в камеру сам (проверено render_batch_ual.gd), манекен не нужен.
## Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File _tmp_probe/run_heart.ps1
## Кадры: _tmp_probe/heart_heart_cast_XX.png, heart_heart_cast_l_XX.png

const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const OUT_DIR := "res://_tmp_probe"

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
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0]
	var extra = load(TEST_LIB)
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

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

	var skel: Skeleton3D = _find_skeleton(player)
	var specs := [
		["Spell_Cast", [0.80, 0.85, 0.88, 0.92]],
		["Spell_Cast_L", [0.80, 0.85, 0.88, 0.92]],
	]
	for spec in specs:
		var clip: String = spec[0]
		var idx := 0
		for t: float in spec[1]:
			ap.play(clip)
			ap.seek(t, true)
			await process_frame
			await process_frame
			var img := root.get_texture().get_image()
			var path := "%s/heart_%s_%02d.png" % [OUT_DIR, clip.to_lower(), idx]
			img.save_png(path)
			var lh := skel.find_bone("mixamorig_LeftHand")
			var rh := skel.find_bone("mixamorig_RightHand")
			print("HEARTF %s t=%.2f → %s | L %s | R %s" % [clip, t, path,
				(skel.global_transform * skel.get_bone_global_pose(lh)).origin,
				(skel.global_transform * skel.get_bone_global_pose(rh)).origin])
			idx += 1
	print("HEART RENDER DONE")
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
