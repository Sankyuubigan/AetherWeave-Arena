extends SceneTree
## Зонд: почему travel("Run") из Falling не двигает дерево (упало в тесте #6).
## Смотрим get_travel_path() (появился в дампе методов playback) и трассируем
## состояние по кадрам. Машина идентична компонент PlayerAnimationComponent.
## Запуск: Godot --headless -s res://Generators/probe_travel_path.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	var player = ps.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")

	# Машина как в компоненте (16 переходов)
	var sm := AnimationNodeStateMachine.new()
	for st in ["Idle", "Run", "Jump_Launch", "Falling", "Landing", "FrontFlip"]:
		var an := AnimationNodeAnimation.new()
		an.animation = st
		sm.add_node(st, an)
	_tr(sm, "Idle", "Run", 0.15)
	_tr(sm, "Run", "Idle", 0.2)
	_tr(sm, "Idle", "Jump_Launch", 0.1)
	_tr(sm, "Run", "Jump_Launch", 0.1)
	_tr(sm, "Jump_Launch", "Falling", 0.2)
	_tr(sm, "Jump_Launch", "Landing", 0.1)
	_tr(sm, "Idle", "Falling", 0.25)
	_tr(sm, "Run", "Falling", 0.25)
	_tr(sm, "Landing", "Falling", 0.25)
	_tr(sm, "Falling", "Landing", 0.1)
	_tr(sm, "Falling", "FrontFlip", 0.15)
	_tr(sm, "Jump_Launch", "FrontFlip", 0.15)
	_tr(sm, "FrontFlip", "Falling", 0.2, true)
	_tr(sm, "Landing", "Idle", 0.2, true)
	_tr(sm, "Landing", "Run", 0.1)

	var tree := AnimationTree.new()
	loco.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(loco)
	tree.root_node = loco.root_node
	tree.callback_mode_process = loco.callback_mode_process
	tree.tree_root = sm
	tree.active = true
	await process_frame
	await process_frame

	var pb = tree.get("parameters/playback")
	if pb == null:
		print("PT FAIL: parameters/playback отсутствует")
		quit(1)
		return
	pb.start("Idle")
	for i in 10:
		await process_frame
	print("PT start → ", pb.get_current_node())

	# Пусть игрок «падает» без физики: стартуем сразу в Falling (как в тесте #6:
	# comp был в Falling когда travel("Run") молчал)
	pb.travel("Falling")
	for i in 20:
		await process_frame
	print("PT до travel: state=", pb.get_current_node(),
		" fading=", String(pb.get_fading_from_node()))

	# ГЛАВНЫЙ замер: travel Run из Falling (путь Falling→Landing→Run)
	pb.travel("Run")
	print("PT после travel(Run): travel_path=", pb.get_travel_path())
	for f in 120:
		await process_frame
		if f % 10 == 0:
			print("PT f=", f, " cur=", pb.get_current_node(),
				" fading=", String(pb.get_fading_from_node()),
				" path=", pb.get_travel_path())

	# Контроль: travel в СОСЕДНЕЕ состояние из того же места (Falling→Landing)
	pb.travel("Landing")
	for i in 5:
		await process_frame
	print("PT travel(Landing) из Run: cur=", pb.get_current_node())
	pb.travel("Falling")
	for i in 20:
		await process_frame
	print("PT travel(Falling) из Landing: cur=", pb.get_current_node())
	# И снова Run — но уже из Landing (прямая ветка Landing→Run)
	pb.travel("Run")
	for i in 5:
		await process_frame
	print("PT travel(Run) из Landing (прямая): cur=", pb.get_current_node())

	print("PT DONE")
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

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
