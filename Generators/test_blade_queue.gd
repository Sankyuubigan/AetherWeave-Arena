extends SceneTree
## ГЕЙТ ОЧЕРЕДИ КЛИПОВ (26.11.26) — энергоклинок A→B→A.
## PRP: tasks/261126_0838-99d99d09/PRP_импортёр_и_скиллы.md, шаг 5.4.
##
## ПОЧЕМУ ГЕЙТ СУЩЕСТВУЕТ: вердикт юзера «не отменять удары, а ставить их в
## очередь» — Blade_Swing_A игрался ОДИН раз и обрывался спамом (эффект сам
## звал play_cast_anim и рестартил клип). Теперь очередь живёт в каст-слое,
## и без гейта её снова тихо сломает любая правка порядка вызовов.
##
## Что проверяется (на РЕАЛЬНОМ игроке и реальном SpellCasterComponent):
##  1) первый каст материализации — Throw (клинка нет);
##  2) второй каст — Blade_Swing_A (начало очереди, НЕ B);
##  3) третий — Blade_Swing_B;
##  4) четвёртый — снова A (круг замкнулся);
##  5) очередь НЕ проскакивает клипы при спаме;
##  6) смена скилла сбрасывает очередь.
## Запуск: --headless -s res://Generators/test_blade_queue.gd  (EXIT=0=PASS)
##
## СКРИПТЫ НЕ СНИМАЕМ (урок: _strip снимал и SpellCasterComponent — тест
## зависал, вызывать было нечего). Сторож на 25 с гарантирует выход.

const PLAYER_SCENE := "res://Scenes/player.tscn"
## СТОЯ каст-слой играет FULL-BODY клип (без суффикса _UB), в бегу — UB.
## Сравниваем имена БЕЗ суффикса: иначе тест ловил бы «Throw != Throw_UB» и
## падал на здоровом коде (ловил 26.11.26).
const UPPER := 0.70
## Сколько ждать открытия окна отмены: клип Throw 1.33 с × cancel_at 0.6 = 0.80 с,
## фиксированные 0.42 с уводили касты в буфер и тест читал прошлый клип.
const WINDOW_WAIT_MAX_MS := 3000

var player: Node
var caster: Node
var anim_comp: Node
var fails: Array[String] = []
var _done := false

func _init() -> void:
	_watchdog()
	call_deferred("_run")

## Сторож: любой подвис (нет камеры/скелета/каст отклонён) → внятный FAIL,
## а не висящий процесс. Раньше тест молча висел 180+ с и был убит вручную.
func _watchdog() -> void:
	await create_timer(25.0).timeout
	if not _done:
		print("QUEUE FAIL: сторож 25 с — тест не дошёл до конца")
		quit(1)

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 20:
		await process_frame
	caster = player.get_node_or_null("SpellCasterComponent")
	anim_comp = player.get_node_or_null("PlayerAnimationComponent")
	if caster == null or anim_comp == null:
		_finish("нет SpellCasterComponent/PlayerAnimationComponent")
		return
	if player.get_node_or_null("SpringArm3D/Camera3D") == null:
		_finish("нет SpringArm3D/Camera3D — _aim_context вернёт пусто, касты отменятся")
		return

	# --- 1) материализация: клинка нет → Throw
	var clip: String = await _cast_and_read("energy_blade")
	_ck(_base(clip) == "Throw", "каст 1 (нет клинка) = материализация Throw, получено: " + clip)

	# --- 2..4) очередь A → B → A
	var expect := ["Blade_Swing_A", "Blade_Swing_B", "Blade_Swing_A"]
	for i in expect.size():
		await _wait_cancel_window()
		var c: String = await _cast_and_read("energy_blade")
		_ck(_base(c) == expect[i], "каст %d = %s, получено: %s" % [i + 2, expect[i], c])

	# --- 5) спам: 5 вызовов подряд без ожидания окна → клипы не проскакивают
	# Все пять попадают в ОДИН окно-буфер и по факту играет не больше одного
	# нового клипа (очередь двигается только при фактическом play_cast_anim).
	var queue_before: String = str(caster.get("_queue_next"))
	for i in 5:
		caster.call("cast_skill", "energy_blade")
		await process_frame
	var queue_after: String = str(caster.get("_queue_next"))
	_ck(queue_before == queue_after,
			"спам не сдвигает очередь авансом (было '%s', стало '%s')" % [queue_before, queue_after])

	# --- 6) смена скилла сбрасывает очередь
	await _wait_cancel_window()
	caster.call("cast_skill", "fireball")
	for i in 5:
		await process_frame
	_ck(str(caster.get("_queue_next")) == "",
			"чужой скилл сбросил очередь (queue_next='%s')" % str(caster.get("_queue_next")))
	await _wait_cancel_window()
	var after: String = await _cast_and_read("energy_blade")
	_ck(_base(after) == "Blade_Swing_A",
			"после чужого скилла очередь начата с A, получено: " + after)

	if fails.is_empty():
		print("")
		print("QUEUE: ALL PASS")
		_finish()
	else:
		print("")
		print("QUEUE: FAIL (%d)" % fails.size())
		_finish("", 1)

## Имя клипа без служебного суффикса _UB (стоя — full-body, в бегу — UB).
func _base(clip: String) -> String:
	return clip.trim_suffix("_UB")

## Дождаться ОТКРЫТИЯ окна отмены текущего инста-клипа (прогресс ≥ UPPER) —
## только тогда повторный каст играет сразу, а не уходит в буфер ввода.
func _wait_cancel_window() -> void:
	var deadline := Time.get_ticks_msec() + WINDOW_WAIT_MAX_MS
	while Time.get_ticks_msec() < deadline:
		if not bool(caster.call("_insta_running")):
			return   # клип доиграл — окно давно открыто
		if float(caster.call("_insta_progress")) >= UPPER:
			return
		await process_frame

## Каст + чтение фактически играющего клипа каст-слоя (корутина: ждёт кадры).
func _cast_and_read(skill_id: String) -> String:
	caster.call("cast_skill", skill_id)
	for i in 6:
		await process_frame
	return str(anim_comp.cast_player.current_animation)

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)

func _ck(ok: bool, msg: String) -> void:
	if ok:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
		fails.append(msg)

func _finish(why: String = "", code: int = -1) -> void:
	_done = true
	if why != "":
		print("QUEUE FAIL: ", why)
		quit(1)
		return
	quit(code if code >= 0 else 0)
