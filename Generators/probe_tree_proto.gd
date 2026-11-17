extends SceneTree
## Зонд 2 (AnimationTree): прототип стейт-машины КОДОМ поверх player.tscn.
## Проверяем: (1) дерево САМО применяет позу (travel Run → стопа бежит),
## (2) CastPlayer поверх дерева жив (capture из позы дерева — гладко),
## (3) AUTO+AT_END авто-переход (Landing→Idle без кода),
## (4) производный клип Jump_Launch (сдвиг 0.33) играет.
## Запуск: Godot --headless -s res://Generators/probe_tree_proto.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var methods = ClassDB.class_get_method_list("AnimationNodeStateMachinePlayback", true)
	var mnames: Array[String] = []
	for m in methods:
		mnames.append(str(m["name"]))
	print("P2 playback methods → ", ", ".join(mnames))

	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("P2 FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var skel = _find_skeleton(player)
	print("P2 loco callback=", loco.callback_mode_process)

	# Производный клип Jump_Launch (старт с отрыва, без приседа)
	var lib = loco.get_animation_library("")
	var jump: Animation = lib.get_animation("Jump")
	var jl: Animation = jump.duplicate(true)
	_shift_from(jl, 0.33)
	lib.add_animation("Jump_Launch", jl)
	print("P2 Jump_Launch: длина ", snappedf(jump.length, 0.01), " → ",
		snappedf(jl.length, 0.01), ", треков ", jl.get_track_count())

	# Дерево: sibling ПОСЛЕ loco (до castp)
	var tree := AnimationTree.new()
	loco.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(loco)
	tree.root_node = loco.root_node
	tree.callback_mode_process = loco.callback_mode_process
	var sm := AnimationNodeStateMachine.new()
	for st in ["Idle", "Run", "Jump_Launch", "Falling", "Landing", "FrontFlip"]:
		var an := AnimationNodeAnimation.new()
		an.animation = st
		sm.add_node(st, an)
	_tr(sm, "Idle", "Run", 0.15)
	_tr(sm, "Run", "Idle", 0.2)
	_tr(sm, "Idle", "Jump_Launch", 0.1)
	_tr(sm, "Run", "Jump_Launch", 0.1)
	_tr(sm, "Jump_Launch", "Falling", 0.25)
	_tr(sm, "Falling", "Landing", 0.1)
	_tr(sm, "Landing", "Idle", 0.2, true)      # AUTO+AT_END
	_tr(sm, "Landing", "Run", 0.15)
	_tr(sm, "Falling", "FrontFlip", 0.15)
	_tr(sm, "FrontFlip", "Falling", 0.25, true)  # AUTO+AT_END
	tree.tree_root = sm
	tree.active = true
	await process_frame
	await process_frame

	var pb = tree.get("parameters/playback")
	if pb == null:
		print("P2 FAIL: parameters/playback отсутствует")
		quit(1)
		return
	pb.start("Idle")
	for i in 10:
		await process_frame
	print("P2 start Idle → state=", pb.get_current_node())

	# (1) Travel Run: дерево применяет позу? (осцилляция стопы)
	pb.travel("Run")
	var last: Vector3 = _bone(skel, "mixamorig_LeftFoot")
	var moved := 0.0
	for i in 25:
		await process_frame
		var f := _bone(skel, "mixamorig_LeftFoot")
		moved += (f - last).length()
		last = f
	print("P2 Run: state=", pb.get_current_node(), " стопа прошла ",
		snappedf(moved, 0.01), " м за 25 кадров (>0.10 = дерево применяет)")

	# (2) CastPlayer поверх дерева
	var castp := AnimationPlayer.new()
	loco.get_parent().add_child(castp)
	castp.root_node = loco.root_node
	var src_lib = load("res://Graphics/Animations/ual_casts_test.res")
	var clib := AnimationLibrary.new()
	for an in src_lib.get_animation_list():
		if String(an).ends_with("_UB"):
			clib.add_animation(an, src_lib.get_animation(an))
	castp.add_animation_library("", clib)
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	var maxjump := 0.0
	var hprev := _bone(skel, "mixamorig_LeftHand")
	for i in 12:
		await process_frame
		var h := _bone(skel, "mixamorig_LeftHand")
		maxjump = maxf(maxjump, (h - hprev).length())
		hprev = h
	print("P2 UB поверх дерева: макс скачок кисти/кадр=", snappedf(maxjump, 0.03),
		" (гладко если <0.2)")

	# (2b) A/B: тот же замер поверх ПРЯМОГО AnimationPlayer (старая архитектура)
	castp.stop()
	tree.active = false
	loco.play("Run")
	for i in 10:
		await process_frame
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	var maxjump2 := 0.0
	hprev = _bone(skel, "mixamorig_LeftHand")
	for i in 12:
		await process_frame
		var h := _bone(skel, "mixamorig_LeftHand")
		maxjump2 = maxf(maxjump2, (h - hprev).length())
		hprev = h
	print("P2 A/B старая архитектура: макс скачок=", snappedf(maxjump2, 0.03),
		" (дерево эквивалентно, если числа одного порядка)")
	castp.stop()
	tree.active = true
	loco.stop()
	await process_frame

	# (3) Landing → AUTO+AT_END → Idle без кода
	pb.travel("Jump_Launch")
	for i in 3:
		await process_frame
	pb.travel("Falling")
	for i in 3:
		await process_frame
	pb.travel("Landing")
	for i in 3:
		await process_frame
	print("P2 в Landing: state=", pb.get_current_node())
	var waited := 0
	while pb.get_current_node() != "Idle" and waited < 500:
		await process_frame
		waited += 1
	print("P2 AUTO+AT_END: ", "OK — сам дошёл до Idle за " + str(waited) + " кадров"
		if pb.get_current_node() == "Idle" else "НЕ ДОШЁЛ (" + str(pb.get_current_node()) + ")")

	print("P2 DONE")
	quit(0)

func _tr(sm: AnimationNodeStateMachine, from: String, to: String,
		xfade: float, auto := false) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	if auto:
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	else:
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	sm.add_transition(from, to, t)

## Производный клип: обрезать все ключи до off (квирик 4.8: track_clear нет —
## удаляем по индексам с хвоста)
func _shift_from(a: Animation, off: float) -> void:
	for i in a.get_track_count():
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, k) < off:
				a.track_remove_key(i, k)
	a.length = maxf(a.length - off, 0.01)

func _bone(skel: Skeleton3D, bone: String) -> Vector3:
	var i: int = skel.find_bone(bone)
	return (skel.global_transform * skel.get_bone_global_pose(i)).origin

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
