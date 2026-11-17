extends SceneTree
## ВИЗУАЛЬНАЯ САМОПРОВЕРКА каст-анимаций (раунд 8; урок вердикта юзера
## «ты же сказал что умеешь тестировать»): грузим player.tscn, играем клип,
## снимаем кадры камерой спереди-сбоку в PNG — агент СМОТРИТ анимацию своими
## глазами ДО передачи юзеру. Headless НЕ рендерит — запуск ОКОННЫЙ.
##
## Запуск:
##   "<godot>" -s res://Generators/visual_cast_check.gd -- <имя_анимации> [секназнач]
## Пример:
##   "<godot>" -s res://Generators/visual_cast_check.gd -- Cast_Push 0.03,0.17,0.27,0.37,0.5,0.75
## Кадры пишутся в res://_tmp_probe/cast_<имя>_kNN.png.

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT_DIR := "res://_tmp_probe"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ОКНО ЮЗЕРУ НЕ МЕШАЕТ: рендер нужен в окне (headless кадры не даёт), но окно
	# уводим за пределы экрана — захват идёт из viewport-текстуры GPU, позиции
	# на экране не требует. НЕ минимизировать: минимизированное окно чёрные кадры.
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var args := OS.get_cmdline_user_args()
	# Опциональный "lib=<путь>": подмешать анимации из внешней библиотеки
	# (например ual_casts_test.res) в дефолтную ДО поиска клипа.
	var lib_path := ""
	var clean: Array = []
	for a in args:
		if String(a).begins_with("lib="):
			lib_path = String(a).substr(4)
		else:
			clean.append(a)
	args = clean
	if args.size() < 1:
		print("VIS FAIL: нужно <имя_анимации>")
		quit(1)
		return
	var anim_name: String = args[0]
	var times: Array = [0.03, 0.17, 0.27, 0.37, 0.5, 0.75]
	if args.size() > 1:
		times.clear()
		for s in String(args[1]).split(","):
			times.append(float(s))

	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		print("VIS FAIL: нет player.tscn")
		quit(1)
		return
	var player := packed.instantiate()

	# Снять ВСЕ скрипты (логика игрока не должна перебивать анимацию и не
	# должна дёргать автолоады, которых в -s нет).
	_strip_scripts(player)

	root.add_child(player)
	await process_frame
	await process_frame

	# Аниматор: ищем после добавления в дерево.
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		print("VIS FAIL: AnimationPlayer не найден")
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]
	if lib_path != "":
		var extra = load(lib_path)
		if extra == null or not (extra is AnimationLibrary):
			print("VIS FAIL: не загрузилась библиотека " + lib_path)
			quit(1)
			return
		var def := ap.get_animation_library("")
		for an in extra.get_animation_list():
			if def.has_animation(an):
				def.remove_animation(an)
			def.add_animation(an, extra.get_animation(an))
		print("VIS: библиотека %s подмешана (%d анимаций)" % [lib_path, extra.get_animation_list().size()])

	# Своя камера (окно у -s сцены есть — рендерит, если не --headless).
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.1, 1.45, 2.4)
	cam.look_at_from_position(Vector3(1.1, 1.45, 2.4), Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.make_current()
	await process_frame

	# Как называется клип в библиотеке (ищем по подстроке без регистра).
	var target := ""
	for a in ap.get_animation_list():
		if a.to_lower().contains(anim_name.to_lower()):
			target = a
			break
	if target == "":
		print("VIS FAIL: анимация '%s' не найдена. Есть: %s" % [anim_name, ", ".join(ap.get_animation_list())])
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var base := anim_name.to_lower().replace(" ", "_")
	var idx := 0
	for t: float in times:
		ap.play(target)
		ap.seek(t, true)          # мгновенно применить позу кадра
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var path := "%s/cast_%s_%02d.png" % [OUT_DIR, base, idx]
		img.save_png(path)
		print("VIS %s t=%.2f → %s (%dx%d)" % [target, t, path, img.get_width(), img.get_height()])
		idx += 1
	quit(0)

## Снять скрипты со всех узлов (включая корень).
func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
