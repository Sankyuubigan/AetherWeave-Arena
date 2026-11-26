extends SceneTree
## ПРОВЕРКА (26.11.26): работает ли speed_scale на CastPlayer — путь к ускорению
## каст-анимаций без пересэмплинга клипа (фаербол «долго кастует», просьба юзера
## ускорить в 2 раза).
## В дереве ЛОКОМОЦИИ AnimationNodeTimeScale в 4.8-beta3 — ПУСТОЙ класс (известный
## баг), поэтому проверяем именно AnimationPlayer.speed_scale напрямую.
## Запуск: --headless -s res://Generators/probe_cast_speed.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player: Node = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	for i in 20:
		await physics_frame
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp == null:
		print("SPEED FAIL: нет PlayerAnimationComponent")
		quit(1)
		return
	var layer = comp._cast_layer
	var cp: AnimationPlayer = layer.cast_player
	var clip := "Cast_1H_Magic_01"
	var ub := clip + "_UB"
	if not cp.has_animation(ub):
		print("SPEED FAIL: нет клипа ", ub)
		quit(1)
		return
	var full_len: float = cp.get_animation(ub).length
	print("SPEED: клип %s длина %.3fс" % [ub, full_len])

	# 1) speed_scale = 2 → позиция воспроизведения должна идти вдвое быстрее.
	# ВАЖНО: НЕ сверять с 60 fps — в headless частота кадров не 60, а «за 10
	# кадров» даёт произвольный dt (первый прогон гейта ложно упал из-за этого).
	# Авторитетный замер — РЕАЛЬНАЯ длительность проигрывания (пункт 3).
	cp.speed_scale = 2.0
	layer.play_cast_anim(clip)
	var p0: float = cp.current_animation_position
	for i in 10:
		await process_frame
	var p1: float = cp.current_animation_position
	print("SPEED: speed_scale=2 → позиция выросла на %.3fс (контроль ниже)" % (p1 - p0))

	# 2) speed_scale = 1 → контроль
	cp.speed_scale = 1.0
	layer.play_cast_anim(clip)
	var q0: float = cp.current_animation_position
	for i in 10:
		await process_frame
	var q1: float = cp.current_animation_position
	print("SPEED: speed_scale=1 → позиция выросла на %.3fс" % (q1 - q0))
	var fast_ok := (p1 - p0) > (q1 - q0) * 1.5

	# 3) Реальная длина окна: при speed_scale=2 клип должен доиграть вдвое быстрее.
	cp.speed_scale = 2.0
	layer.play_cast_anim(clip)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while cp.is_playing() and frames < 600:
		await process_frame
		frames += 1
	var real := float(Time.get_ticks_msec() - t0) / 1000.0
	print("SPEED: при speed_scale=2 клип доиграл за %.3fс (при 1.0 было бы ~%.3f) → %s" % [
		real, full_len, "УСКОРЕНИЕ РАБОТАЕТ" if real < full_len * 0.75 else "НЕ РАБОТАЕТ"])
	cp.speed_scale = 1.0
	if fast_ok and real < full_len * 0.75:
		print("SPEED: ALL PASS — speed_scale на CastPlayer годится для cast_speed")
		quit(0)
	else:
		print("SPEED FAIL: speed_scale не даёт ускорения — нужен _stretched-клип")
		quit(1)
