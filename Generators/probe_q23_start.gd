extends SceneTree
## Q23 (20.11.26) диагностическая проба: почему «перс стартует сразу резко бежит».
## Гипотезы:
##  H1: add_node("Start") падает — «Start» ЗАРЕЗЕРВИРОВАНО (встроенные Start/End
##      узлы входа/выхода AnimationNodeStateMachine) → узел Run_Start не попал
##      в машинку, travel("Start") попадает во встроенный Start (нулевая длина)
##      → AT_END Start→Run мгновенно = «сразу резко бежит».
##  H2: клипа Run_Start нет в библиотеке игрока (узел ссылается в пустоту →
##      мгновенный AT_END → тот же симптом).
## Сценарий: instantiate player.tscn → стойка 0.5 с → KEY_W 2.5 с → лог узла
## стейт-машины (get_current_node) по кадрам. Ожидание после фикса: Idle →
## «Accel» (Run_Start ~2 с) → Run.
## Запуск: timeout 60 godot --headless -s res://Generators/probe_q23_start.gd

const PLAYER := "res://Scenes/player.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps: PackedScene = load(PLAYER)
	if ps == null:
		print("Q23 FAIL: player.tscn не грузится")
		quit(1)
		return
	var player: CharacterBody3D = ps.instantiate()
	# Пол в пробном мире: без него игрок вечно Falling (is_on_floor=false)
	var floor := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	fshape.shape = box
	floor.add_child(fshape)
	floor.position = Vector3(0, -0.5, 0)
	root.add_child(floor)
	root.add_child(player)
	for i in range(10):
		await process_frame

	var comp: Node = null
	for c in player.get_children():
		var s = c.get_script() as Script
		if s != null and s.resource_path.ends_with("PlayerAnimationComponent.gd"):
			comp = c
			break
	if comp == null:
		print("Q23 FAIL: PlayerAnimationComponent не найден в ", player.get_children())
		quit(1)
		return

	# H2: клип в библиотеке?
	var lib = comp.anim_player.get_animation_library("")
	if lib.has_animation("Run_Start"):
		print("[Q23] Run_Start В библиотеке, len=%.3f с" % lib.get_animation("Run_Start").length)
	else:
		print("[Q23] Run_Start ОТСУТСТВУЕТ в библиотеке! узлы либы: ", lib.get_animation_list())

	# H1 уже доказан еррорами add_node/add_transition (Start занят) —
	# get_node_names в 4.8 нет, узлы не печатаем.
	var pb = comp.playback
	print("[Q23] старт: узел=%s _state=%s" % [pb.get_current_node(), comp._state])

	# Стойка 0.5 с
	for i in range(30):
		await physics_frame
	print("[Q23] до движения: узел=%s _state=%s" % [pb.get_current_node(), comp._state])

	# Движение 2.5 с (KEY_W — PlayerController читает is_key_pressed)
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	var accel_frames := -1
	var run_frames := -1
	for f in range(150):
		await physics_frame
		var node := String(pb.get_current_node())
		if node == "Accel" and accel_frames < 0:
			accel_frames = f
		if node == "Run" and run_frames < 0:
			run_frames = f
		if f % 15 == 0:
			var spd := Vector2(player.velocity.x, player.velocity.z).length()
			print("[Q23] кадр %3d: узел=%-6s _state=%-6s speed=%.2f" % [f, node, comp._state, spd])
	Input.parse_input_event(_key(false))
	print("[Q23] ИТОГ: Accel на кадре %s, Run на кадре %s (60 fps → 2 с = кадр 120)" \
			% [accel_frames, run_frames])
	if accel_frames >= 0 and run_frames > accel_frames + 60:
		print("Q23 PROBE: PASS — разгон играется, Run приходит после клипа")
		quit(0)
	else:
		print("Q23 PROBE: FAIL — мгновенный Run (или Accel не стартовал)")
		quit(1)

func _key(pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = pressed
	return ev
