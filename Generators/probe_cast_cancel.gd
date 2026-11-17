extends SceneTree
## Зонд «отмена каст-анимации при спаме» (17.11.26): воспроизводит быстрые
## нажатия скиллов на CastPlayer и меряет, рестартует ли клип и переезжает ли
## поза на новый каст. Headless, без рендера.
## Запуск: Godot --headless -s res://Generators/probe_cast_cancel.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("CANCEL FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var skel = _find_skeleton(player)
	# CastPlayer как в игре: после loco в дереве, тот же root_node, UB-клипы.
	var castp := AnimationPlayer.new()
	loco.get_parent().add_child(castp)
	castp.root_node = loco.root_node
	var src_lib = load("res://Graphics/Animations/ual_casts_test.res")
	var clib := AnimationLibrary.new()
	for an in src_lib.get_animation_list():
		if String(an).ends_with("_UB"):
			clib.add_animation(an, src_lib.get_animation(an))
	castp.add_animation_library("", clib)
	loco.play("Run")
	for i in 20:
		await process_frame

	# ── С1: спам ОДНОГО скилла (повторный play+capture на том же клипе) ──
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	var waited := 0
	while castp.current_animation_position < 0.30 and waited < 600:
		await process_frame
		waited += 1
	var pos_before := castp.current_animation_position
	print("S1 до повтора:      pos=%.3f (кадров=%d)" % [pos_before, waited])
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	for i in 3:
		await process_frame
	print("S1 после повтора:   pos=%.3f → %s" % [
		castp.current_animation_position,
		"РЕСТАРТ (ок)" if castp.current_animation_position < pos_before * 0.5 else "ПРОДОЛЖАЕТСЯ (БАГ)"])

	# ── С2: другой скилл посреди каста (перебивание) ──
	waited = 0
	while castp.current_animation_position < 0.30 and waited < 600:
		await process_frame
		waited += 1
	var hp_before := _hand(skel)
	castp.play("Throw_UB", 0.1)
	castp.capture("Throw_UB", 0.1)
	for i in 3:
		await process_frame
	print("S2 другой клип:     current=%s pos=%.3f прыжок_позы=%.3f м → %s" % [
		castp.current_animation, castp.current_animation_position,
		(hp_before as Vector3).distance_to(_hand(skel)),
		"ПЕРЕКЛЮЧИЛСЯ" if castp.current_animation == "Throw_UB" else "НЕ ПЕРЕКЛЮЧИЛСЯ (БАГ)"])

	# ── С3: вариант фикса — stop() перед play+capture (чистый рестарт) ──
	waited = 0
	while castp.current_animation_position < 0.30 and waited < 600:
		await process_frame
		waited += 1
	hp_before = _hand(skel)
	castp.stop()
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	for i in 3:
		await process_frame
	print("S3 stop()+play+capture: pos=%.3f прыжок_позы=%.3f м/3 кадра → %s" % [
		castp.current_animation_position,
		(hp_before as Vector3).distance_to(_hand(skel)),
		"РЕСТАРТ" if castp.current_animation_position < 0.1 else "?"])
	for i in 12:
		await process_frame
	print("S3 вход сглаживается: прыжок_позы за след. 12 кадров=%.3f м" % [
		(hp_before as Vector3).distance_to(_hand(skel))])

	# ── С4: каноничный API play_with_capture (одним вызовом) ──
	waited = 0
	while castp.current_animation_position < 0.30 and waited < 600:
		await process_frame
		waited += 1
	hp_before = _hand(skel)
	castp.stop()
	castp.play_with_capture("Throw_UB", 0.1)
	for i in 3:
		await process_frame
	print("S4 play_with_capture: current=%s pos=%.3f прыжок=%.3f м → %s" % [
		castp.current_animation, castp.current_animation_position,
		(hp_before as Vector3).distance_to(_hand(skel)),
		"OK" if castp.current_animation == "Throw_UB" else "?"])

	print("CANCEL PROBE DONE")
	quit(0)

func _hand(skel) -> Vector3:
	var i: int = skel.find_bone("mixamorig_LeftHand")
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
