extends SceneTree
## РАЗРЕШАЮЩИЙ зонд: какие стороны скина реально видны в мире при игре
## Cast_Loop (ual_casts_test.res). Печатает нод-трансформ Skeleton3D и мировые
## позиции плеч/кистей в позе. Ответ на вопрос «зеркалит ли ретаргет».
## Запуск: --headless -s res://Generators/probe_skin_sides.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player := packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var sks := player.find_children("*", "Skeleton3D", true, false)
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	var skin: Skeleton3D = sks[0]
	var ap: AnimationPlayer = aps[0]

	print("player.global_transform: ", player.global_transform)
	print("skeleton.transform: ", skin.transform)
	print("skeleton.global_transform.basis: ", skin.global_transform.basis)

	var extra = load(TEST_LIB)
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

	ap.play("Cast_Loop")
	ap.seek(0.03, true)
	await process_frame
	await process_frame

	for nm in ["mixamorig_RightShoulder", "mixamorig_LeftShoulder",
			"mixamorig_RightHand", "mixamorig_LeftHand",
			"mixamorig_Hips"]:
		var i := skin.find_bone(nm)
		if i < 0:
			var i1 := skin.find_bone(nm.replace("mixamorig_", "mixamorig1_"))
			i = i1
		if i < 0:
			print("нет кости ", nm)
			continue
		var w: Vector3 = skin.global_transform * skin.get_bone_global_pose(i).origin
		print("%-26s world %s" % [nm, w])

	# фасинг скина в ПОЗЕ: fwd = up × (правое плечо − левое), up=+Y
	var ri := skin.find_bone("mixamorig_RightShoulder")
	var li := skin.find_bone("mixamorig_LeftShoulder")
	if ri >= 0 and li >= 0:
		var pr: Vector3 = skin.global_transform * skin.get_bone_global_pose(ri).origin
		var pl: Vector3 = skin.global_transform * skin.get_bone_global_pose(li).origin
		print("SKIN поза Cast_Loop: fwd = %s (up=+Y)" % [Vector3.UP.cross(pr - pl).normalized()])

	# НОСКИ (фасинг без привязки к именам/формуле): toe − foot
	for nm in ["mixamorig_RightFoot", "mixamorig_RightToeBase",
			"mixamorig_LeftFoot", "mixamorig_LeftToeBase"]:
		var i := skin.find_bone(nm)
		if i < 0:
			i = skin.find_bone(nm.replace("mixamorig_", "mixamorig1_"))
		if i >= 0:
			var w: Vector3 = skin.global_transform * skin.get_bone_global_pose(i).origin
			var wr: Vector3 = skin.get_bone_global_rest(i).origin
			print("%-24s rest %s  pose %s" % [nm, wr, w])

	# OVERLAY T-ПОЗ: rest-глобали всей цепи рук (для сравнения с S·gT(A_TPose))
	print("=== SKIN REST руки (глобальные rest-позиции) ===")
	for nm in ["mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
			"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
			"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]:
		var i2 := skin.find_bone(nm)
		if i2 < 0:
			i2 = skin.find_bone(nm.replace("mixamorig_", "mixamorig1_"))
		if i2 >= 0:
			print("%-26s rest %s" % [nm, skin.get_bone_global_rest(i2).origin])
	quit(0)

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
