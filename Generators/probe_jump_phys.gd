extends SceneTree
## Зонд прыжка (18.11.26): юзер — «не прыгает, а сразу падает».
## Фазы: (1) дамп библиотеки клипов, (2) прыжок прямым вызовом
## velocity+play_jump (физика+FSM), (3) синтетический KEY_SPACE (путь юзера).
## Headless: timeout 60 Godot --headless -s res://Generators/probe_jump_phys.gd

var player: CharacterBody3D
var comp: Node
var f := 0

func _init() -> void:
	call_deferred("_run")

func _log(s: String) -> void:
	print(s)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 0)
	world.add_child(player)
	for i in 100:
		await process_frame
	comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp == null:
		_log("JUMP FAIL: нет PlayerAnimationComponent")
		quit(1)
		return
	if comp.playback == null:
		_log("JUMP FAIL: playback не создался")
		quit(1)
		return
	_dump_lib()

	# ── Фаза 1: прямой вызов (физика + FSM) ──
	_log("── P1: velocity.y=jump_velocity + play_jump ──")
	player.velocity.y = player.jump_velocity
	comp.play_jump(false)
	f = 0
	while f < 130:
		await physics_frame
		_frame_log("P1")

	# ── Фаза 2: путь юзера — синтетический Space ──
	for i in 40:
		await physics_frame
	_log("── P2: KEY_SPACE через parse_input_event ──")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	f = 0
	while f < 70:
		await physics_frame
		_frame_log("P2")
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_SPACE
	ev2.physical_keycode = KEY_SPACE
	ev2.pressed = false
	Input.parse_input_event(ev2)
	for i in 30:
		await physics_frame
		_frame_log("P3")
	_log("JUMP DONE state=%s" % comp.loco_state())
	quit(0)

func _frame_log(tag: String) -> void:
	f += 1
	if f > 6 and f % 3 != 0:
		return  # прореживание хвоста, первые кадры — каждый
	var node := ""
	var fading := ""
	node = String(comp.playback.get_current_node())
	fading = String(comp.playback.get_fading_from_node())
	_log("%s f=%03d y=%.3f vy=%+.2f floor=%s state=%s node=%s fade=%s" % [
		tag, f, player.global_position.y, player.velocity.y,
		str(player.is_on_floor()), comp.loco_state(), node, fading])

func _dump_lib() -> void:
	var lib = comp.anim_player.get_animation_library("")
	for n in ["Idle", "Run", "Jump", "Jump_Launch", "Falling", "Landing", "Landing_Cut", "FrontFlip", "FrontFlip_Fast"]:
		if lib.has_animation(n):
			var a: Animation = lib.get_animation(n)
			var fk := -1.0
			if a.get_track_count() > 0 and a.track_get_key_count(0) > 0:
				fk = a.track_get_key_time(0, 0)
			_log("LIB %-14s len=%.2f tracks=%d first_key=%.2f" % [n, a.length, a.get_track_count(), fk])
		else:
			_log("LIB %-14s ОТСУТСТВУЕТ" % n)
	# Треки Hips в Jump и Jump_Launch: ключи по времени (вершина/сдвиг)
	for n in ["Jump", "Jump_Launch", "Landing", "Landing_Cut"]:
		if not lib.has_animation(n):
			continue
		var a: Animation = lib.get_animation(n)
		for i in a.get_track_count():
			var path := String(a.track_get_path(i))
			if path.contains("Hips") and a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				var times := PackedStringArray()
				for k in mini(a.track_get_key_count(i), 12):
					var v: Vector3 = a.track_get_key_value(i, k)
					times.append("%.2f:%.3f" % [a.track_get_key_time(i, k), v.y])
				_log("HIPS %s (%d keys): %s" % [n, a.track_get_key_count(i), " ".join(times)])
				# Raw Jump: ВСЕ ключи в окне взлёта [0.30..0.80]
				if n == "Jump":
					var win := PackedStringArray()
					for k in a.track_get_key_count(i):
						var t := a.track_get_key_time(i, k)
						if t >= 0.30 and t <= 0.80:
							var v2: Vector3 = a.track_get_key_value(i, k)
							win.append("%.2f:%.2f" % [t, v2.y])
					_log("HIPS Jump окно 0.30-0.80 (%d): %s" % [win.size(), " ".join(win)])
				break
	_log("START state=%s node=%s" % [comp.loco_state(), String(comp.playback.get_current_node())])
