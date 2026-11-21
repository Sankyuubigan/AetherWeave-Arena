extends Node
## Q40 тумблер скрытия ВСЕГО экранного UI по F1 — скриншоты без интерфейса
## (заказ юзера 20.11.26). Паттерн клавиши — как SettingsMenu (event.keycode,
## _unhandled_input, docs/ui_input_rules.md). Первый F1: снапшот видимости
## каждого CanvasLayer и скрытие; второй F1 возвращает ровно как было
## (слои, появившиеся ПОКА скрыто, не трогаются — окно, открытое при скрытом
## HUD, остаётся видимым). Мышь не трогает (CCOT ui_input_rules: скрытие UI
## — не открытие/закрытие окна).

var _hidden := false
var _snapshot := {}  # CanvasLayer -> visible до скрытия
var _last_us := 0
var _armed := false  # дебаунс не глотает первое в сессии нажатие

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		# Дебаунс 250 мс: parse_input_event в пробах может задвоить доставку
		# (двойной тугл = «нажал — и ничего не изменилось»); человек-даблтап
		# всегда > 250 мс.
		var now := Time.get_ticks_usec()
		if _armed and now - _last_us < 250_000:
			return
		_armed = true
		_last_us = now
		_toggle()

func _toggle() -> void:
	_hidden = not _hidden
	if _hidden:
		_snapshot.clear()
		for layer in _layers():
			_snapshot[layer] = layer.visible
			layer.visible = false
		print("[HUD] интерфейс скрыт (F1 — вернуть)")
	else:
		for layer in _snapshot:
			if is_instance_valid(layer):
				layer.visible = _snapshot[layer]
		_snapshot.clear()
		print("[HUD] интерфейс возвращён")

func _layers() -> Array:
	return get_tree().root.find_children("*", "CanvasLayer", true, false)
