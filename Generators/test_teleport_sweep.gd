extends SceneTree
## Функциональный тест свип-телепорта (17.11.26): apply запускает корутину-
## полёт A→B, ввод заблокирован, тело прибывает в точку, лок снимается.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("SWEEP-TEST FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	root.add_child(player)
	await process_frame

	var tel = load("res://Logic/Skills/TeleportEffect.gd").new()
	var target: Vector3 = player.global_position + Vector3(12, 0, 0)
	var t0: int = Time.get_ticks_msec()
	tel.apply(player, {"target_pos": target})

	if not player.input_locked:
		print("SWEEP-TEST FAIL: input_locked не включился")
		quit(1)
		return
	print("SWEEP-TEST: лок включён, коллизии: layer=", player.collision_layer,
		" mask=", player.collision_mask)

	# В середине полёта позиция обязана быть между A и B (свип движется).
	while Time.get_ticks_msec() - t0 < 220:
		await process_frame
	var mid: Vector3 = player.global_position
	print("SWEEP-TEST: t=+0.22с поз=", mid, " старт был ", target - Vector3(12, 0, 0))
	if mid.x < 0.5:
		print("SWEEP-TEST FAIL: тело не движется")
		quit(1)
		return

	# Ждём завершения (не дольше 3с реального времени).
	while player.input_locked and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if player.input_locked:
		print("SWEEP-TEST FAIL: лок не снялся за 3с")
		quit(1)
		return
	var err: float = (player.global_position - target).length()
	print("SWEEP-TEST: финал поз=", player.global_position, " отклонение=", err)
	if err > 0.05:
		print("SWEEP-TEST FAIL: не долетели до цели")
		quit(1)
		return

	# Повторный каст сразу после свипа должен отработать (не залипнуть).
	t0 = Time.get_ticks_msec()
	var target2: Vector3 = player.global_position + Vector3(-6, 0, 0)
	tel.apply(player, {"target_pos": target2})
	if not player.input_locked:
		print("SWEEP-TEST FAIL: повторный свип не стартовал")
		quit(1)
		return
	while player.input_locked and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	var err2: float = (player.global_position - target2).length()
	print("SWEEP-TEST: повторный финал отклонение=", err2)
	if err2 > 0.05:
		print("SWEEP-TEST FAIL: повторный свип не долетел")
		quit(1)
		return

	# Ввод должен снова работать (locked=false), коллизии восстановлены
	# (layer/mask игрока по умолчанию ненулевые).
	print("SWEEP-TEST: коллизии после: layer=", player.collision_layer,
		" mask=", player.collision_mask, " locked=", player.input_locked)
	if player.collision_layer == 0 or player.collision_mask == 0:
		print("SWEEP-TEST FAIL: коллизии не восстановлены")
		quit(1)
		return
	print("SWEEP-TEST: ALL PASS")
	quit(0)
