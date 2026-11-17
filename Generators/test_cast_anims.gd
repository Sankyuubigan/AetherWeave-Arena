extends SceneTree
## Функциональный тест каст-анимаций: игрок видит все каст-клипы,
## play_cast_anim/play_channel/end_channel не ломают плеер.

const NAMES := ["Cast_Enter", "Cast_Loop", "Cast_Shoot", "Cast_Shoot_L",
	"Cast_Exit", "Throw", "Pistol_Shoot", "Pistol_Shoot_L"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("CAST-TEST FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	root.add_child(player)
	await process_frame
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp == null:
		print("CAST-TEST FAIL: нет PlayerAnimationComponent")
		quit(1)
		return
	var missing: Array[String] = []
	for n in NAMES:
		if not comp.has_cast_anim(n):
			missing.append(n)
	print("CAST-TEST: отсутствуют: ", missing if missing.size() > 0 else "нет — все 8 на месте")
	comp.play_cast_anim("Throw")
	for i in 5:
		await process_frame
	print("CAST-TEST: после Throw current=", comp.anim_player.current_animation,
		" playing=", comp.anim_player.is_playing())
	comp.play_channel()
	for i in 40:  # ~0.66с: Enter (0.53) должен смениться Loop
		await process_frame
	var cur: String = comp.anim_player.current_animation
	print("CAST-TEST: канал через 40 кадров current=", cur, " channeling=", comp.is_channeling())
	comp.end_channel()
	await process_frame
	print("CAST-TEST: после end_channel current=", comp.anim_player.current_animation)
	quit(0 if missing.is_empty() else 1)
