extends SceneTree
## Зонд: travel против РЕАЛЬНОГО PlayerAnimationComponent (дерево строит он сам).
## В тесте #6 travel("Run") из Falling молчал — трассируем _state / current /
## fading / travel_path по кадрам, чтобы найти отличие от голого прототипа.
## Запуск: Godot --headless -s res://Generators/probe_comp_travel.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	var player = ps.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp == null:
		print("PC FAIL: нет компонента")
		quit(1)
		return
	# Ждём пока игрок упадёт и FSM уйдёт в Falling
	var w := 0
	while comp.loco_state() != "Falling" and w < 300:
		await process_frame
		w += 1
	print("PC Falling достигнут за ", w, " кадров")
	for i in 30:
		await process_frame
	print("PC до travel: state=", comp.loco_state(),
		" cur=", comp.playback.get_current_node(),
		" fading=", String(comp.playback.get_fading_from_node()))

	comp.set_process(false)
	comp._travel("Run")
	print("PC после travel(Run): state=", comp.loco_state(),
		" cur=", comp.playback.get_current_node(),
		" fading=", String(comp.playback.get_fading_from_node()),
		" path=", comp.playback.get_travel_path())
	for f in 100:
		await process_frame
		if f % 10 == 0:
			print("PC f=", f, " cur=", comp.playback.get_current_node(),
				" fading=", String(comp.playback.get_fading_from_node()),
				" path=", comp.playback.get_travel_path())
	print("PC DONE")
	quit(0)
