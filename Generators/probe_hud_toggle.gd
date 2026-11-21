extends SceneTree

## Q40 гейт: HudToggle — логика снапшота/возврата CanvasLayer'ов. Обработчик
## клавиши вызывается ПРЯМО (ht._unhandled_input(ev)) — глобальный пайплайн
## ввода (parse_input_event) в -s-пробах дублирует доставку и недетерминирован;
## сам маршрут клавиши — тот же паттерн, что у работающего F2 SettingsMenu.
## L2 скрыт «по дизайну» до нажатия — после второго F1 должен вернуться СКРЫТЫМ.
## Запуск: powershell -File _tmp_probe/run_godot.ps1 res://Generators/probe_hud_toggle.gd

const HT := preload("res://Graphics/HudToggle.gd")

func _init() -> void:
	var wd := create_timer(30.0)
	wd.timeout.connect(func() -> void:
		printerr("[HUDT] TIMEOUT")
		quit(1))
	_run()

func _run() -> void:
	# фейковые HUD-слои
	var l1 := CanvasLayer.new()
	l1.name = "FakeHUD_Visible"
	root.add_child(l1)
	var l2 := CanvasLayer.new()
	l2.name = "FakeHidden_ByDesign"
	l2.visible = false
	root.add_child(l2)
	# тумблер как autoload (в -s-пробе autoloads не грузятся — вешаем вручную)
	var ht := Node.new()
	ht.set_script(HT)
	root.add_child(ht)
	await process_frame
	await process_frame

	var ev := InputEventKey.new()
	ev.keycode = KEY_F1
	ev.pressed = true

	# 1-е нажатие → скрыть всё
	ht._unhandled_input(ev)
	await process_frame
	var hidden_ok: bool = (not l1.visible) and (not l2.visible)
	print("[HUDT] после F1: L1.visible=%s L2.visible=%s (ждём false/false)" % [l1.visible, l2.visible])

	# 2-е нажатие → вернуть по снапшоту (L2 — скрытым, как было).
	# Пауза > дебаунса 250 мс — против даблтапа.
	await create_timer(0.3).timeout
	ht._unhandled_input(ev)
	await process_frame
	var restored_ok: bool = l1.visible and (not l2.visible)
	print("[HUDT] после 2-го F1: L1.visible=%s L2.visible=%s (ждём true/false)" % [l1.visible, l2.visible])

	# 3-е нажатие → снова скрыть (идемпотентность цикла)
	await create_timer(0.3).timeout
	ht._unhandled_input(ev)
	await process_frame
	var cycle_ok2: bool = (not l1.visible) and (not l2.visible)

	if hidden_ok and restored_ok and cycle_ok2:
		print("[HUDT] GATE PASS")
		quit(0)
	else:
		printerr("[HUDT] GATE FAIL hidden=%s restored=%s cycle=%s" % [hidden_ok, restored_ok, cycle_ok2])
		quit(1)
