extends SceneTree

## Probe раунд 3 (вердикт спеца 09, В.6.2 + В.6.1): ловля слота SkillMenu.
## «Клик → слот» → статус-приглашение; Esc отменяет ловлю, книга ЖИВА;
## N отменяет ловлю И закрывает книгу (мышь CAPTURED по ССОТ ui_input_rules);
## клик мимо слотов — отмена без закрытия; клик ПО слоту (мышь и клавиатура)
## пишет бинд через assign_stance_sub; чужая клавиша НЕ глотается (ловля
## жива); ⚙ — строгий тоггл (повторный клик закрывает панель). EXIT 0 = PASS.
## binds в памяти ActionBar (без user://) — файл-план и пресеты юзера не трогаем.

const ActionBarScript := preload("res://Graphics/ActionBar.gd")
const SkillMenuScript := preload("res://Graphics/SkillMenu.gd")

## Стаб игрока: поля для SkillMenu.buy/sell/refresh_sp (SP_MAX, update_hud).
const STUB_PLAYER := "extends CharacterBody3D\nvar unlocked_skills := {}\nvar skill_points := 10\nvar SP_MAX := 10\nfunc update_hud() -> void:\n\tpass\nfunc unlearn_cleanup(id: String) -> void:\n\tpass\n"

var _pass := 0
var _fail := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _init() -> void:
	call_deferred("_run")

func _mk_dyn(src: String):
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	return gs.new()

func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _mouse_event(btn: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	return ev

func _slot_by_label(bar, label: String):
	for slot in bar.slots:
		if str(slot.key_info.get("label", "")) == label:
			return slot
	return null

func _run() -> void:
	print("=== PROBE: раунд 3 — ловля слота SkillMenu (В.6.2/В.6.1) ===")
	await process_frame

	for path in ["res://Graphics/SkillMenu.gd", "res://Graphics/ActionBar.gd",
			"res://Graphics/SkillPresetsPanel.gd", "res://Logic/Skills/SkillDB.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)

	var player = _mk_dyn(STUB_PLAYER)
	var bar := ActionBarScript.new()
	bar.name = "ActionBar"
	player.add_child(bar)
	var menu := SkillMenuScript.new()
	menu.name = "SkillMenu"
	player.add_child(menu)
	root.add_child(player)
	await process_frame
	await process_frame  # menu._ready: сетка карточек + панель пресетов

	# ── Открытие книги + ⚙-панель изученной стойки ────────────────────────
	menu._unhandled_input(_key_event(KEY_N))
	_ck(menu.is_open and menu.panel.visible, "N открывает книгу")
	player.unlocked_skills["bard_flow"] = true
	menu.refresh_grid()
	var card = null
	for c in menu.grid.get_children():
		if str(c.skill_data.get("id", "")) == "bard_flow":
			card = c
			break
	_ck(card != null and card._gear != null and card._gear.visible,
			"⚙-бейдж виден у изученной стойки")
	card._on_gear_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_ck(menu._stance_panel != null and menu._stance_panel.visible,
			"⚙ открыл мини-панель приёмов")
	_ck(str(menu._edit_stance_id) == "bard_flow", "edit_stance_id = bard_flow")
	_ck(menu._await_slot.is_empty(), "ловля не активна до «Клик → слот»")

	# ── «Клик → слот» → ловля; Esc отменяет, книга ЖИВА (В.6.2) ──────────
	menu._on_pick_slot("bard_flow", "bard_note")
	_ck(not menu._await_slot.is_empty(), "ловля слота активна после кнопки")
	_ck(menu._stance_status.text == "Нажми клавишу слота (Esc — отмена).",
			"статус «Нажми клавишу слота»")
	menu._unhandled_input(_key_event(KEY_ESCAPE))
	_ck(menu._await_slot.is_empty(), "Esc отменил ловлю")
	_ck(menu._stance_status.text == "Назначение отменено (Esc).",
			"статус «Назначение отменено (Esc).»")
	_ck(menu.is_open and menu.panel.visible, "Esc НЕ закрыл книгу (ловля — не окно)")

	# ── N во время ловли: отмена + ЗАКРЫТИЕ книги, мышь в игру ────────────
	menu._on_pick_slot("bard_flow", "bard_note")
	menu._unhandled_input(_key_event(KEY_N))
	_ck(menu._await_slot.is_empty() and not menu.is_open,
			"N при ловле: отмена + книга закрыта")
	_ck(not menu.panel.visible, "панель книги скрыта")
	# CAPTURED ставится в _close_book (ССОТ ui_input_rules); в headless-дисплее
	# set_mouse_mode — no-op, проверяем сам вызов только не-headless.
	_ck(Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			or DisplayServer.get_name() == "headless",
			"закрытие книги вернуло мышь в игру (CAPTURED, ССОТ)")

	# ── Переоткрытие: ⚙ снова открывает (состояние не залипло, фикс В.6.2) ─
	menu._unhandled_input(_key_event(KEY_N))
	card._on_gear_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_ck(menu._stance_panel.visible, "⚙ снова открыл панель после переоткрытия книги")

	# ── Клик мимо слотов → отмена ловли, книга жива ───────────────────────
	menu._on_pick_slot("bard_flow", "bard_chord")
	var miss := _mouse_event(MOUSE_BUTTON_LEFT)
	miss.position = Vector2(10000, 10000)
	menu._input(miss)  # мимо слотов ActionBar: не назначает, не глотает
	menu._unhandled_input(miss)  # → отмена ловли (клик уходит в мир)
	_ck(menu._await_slot.is_empty(), "клик мимо слотов отменил ловлю")
	_ck(menu._stance_status.text == "Назначение отменено.",
			"статус «Назначение отменено.»")
	_ck(menu.is_open, "книга жива после отмены мышью")

	# ── Позитив: клик ПО слоту 7 (мышь, _input-путь) → бинд записан ───────
	menu._on_pick_slot("bard_flow", "bard_note")
	var slot7 = _slot_by_label(bar, "7")
	_ck(slot7 != null, "слот 7 найден в ActionBar")
	var hit := _mouse_event(MOUSE_BUTTON_LEFT)
	hit.position = slot7.get_global_rect().get_center()
	menu._input(hit)
	_ck(menu._await_slot.is_empty(), "клик по слоту закрыл ловлю")
	var binds1: Dictionary = bar.get_stance_binds("bard_flow")
	_ck(str(binds1.get("bard_note", "")) == "7", "клик по слоту 7: бинд bard_note→7")
	_ck(menu._stance_status.text.length() > 0,
			"статус от assign_stance_sub («%s»)" % menu._stance_status.text)

	# ── Позитив: клавиатура KEY_7 во время ловли → тот же бинд ────────────
	menu._on_pick_slot("bard_flow", "bard_chord")
	menu._unhandled_input(_key_event(KEY_7))
	var binds2: Dictionary = bar.get_stance_binds("bard_flow")
	_ck(str(binds2.get("bard_chord", "")) == "7", "KEY_7 при ловле: бинд bard_chord→7")

	# ── Чужая клавиша НЕ глотается: ловля жива, назначения нет (В.6.2) ────
	menu._on_pick_slot("bard_flow", "bard_chord")
	menu._unhandled_input(_key_event(KEY_X))
	_ck(not menu._await_slot.is_empty(), "KEY_X не глотается — ловля жива")
	_ck(menu._stance_status.text == "Нажми клавишу слота (Esc — отмена).",
			"чужая клавиша не меняет статус")
	menu._unhandled_input(_key_event(KEY_ESCAPE))  # гасим ловлю перед тогглом

	# ── ⚙-тоггл (В.6.1): повторный клик закрыл, третий открыл ─────────────
	card._on_gear_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_ck(not menu._stance_panel.visible and str(menu._edit_stance_id) == "",
			"⚙-тоггл: повторный клик закрыл панель")
	card._on_gear_input(_mouse_event(MOUSE_BUTTON_LEFT))
	_ck(menu._stance_panel.visible, "⚙-тоггл: третий клик снова открыл")

	# Cleanup (бинды в памяти ActionBar — диск не тронут)
	menu._unhandled_input(_key_event(KEY_N))
	player.queue_free()
	await process_frame

	if _fail == 0 and _pass > 0:
		print("SKILLMENU AWAIT SLOT GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("SKILLMENU AWAIT SLOT GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
