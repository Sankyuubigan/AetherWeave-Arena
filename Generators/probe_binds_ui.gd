extends SceneTree

## Гейт Шага 8 (Q16): бинды под-приёмов. Оба способа переназначения (drag на
## слот и «клик → нажми слот») меняют реальное поведение перехвата StanceComponent
## (Шаг 1), swap внутри своей стойки, гард слота ДРУГОЙ стойки, пресеты
## сохраняют/восстанавливают stance_binds (файл на диске, round-trip JSON).
## Файл юзера user://skill_presets.json бэкапится и восстанавливается.
## Запуск: ...console.exe --headless -s res://Generators/probe_binds_ui.gd

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")

var _pass := 0
var _fail := 0

func _ck(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("PASS: " + label)
	else:
		_fail += 1
		print("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== BINDS UI PROBE ===")
	# 1) Парс скриптов.
	for p in ["res://Graphics/ActionBar.gd", "res://Graphics/SkillMenu.gd",
			"res://Graphics/SkillPresetsPanel.gd", "res://Logic/StanceComponent.gd"]:
		_ck(load(p) != null, "парс " + p)
	# 2) Бэкап файла пресетов юзера (не трогаем его данные).
	const SAVE_PATH := "user://skill_presets.json"
	var user_backup := ""
	var had_user_file := FileAccess.file_exists(SAVE_PATH)
	if had_user_file:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		user_backup = rf.get_as_text()
		rf.close()
	# 3) Стаб игрока + реальные ActionBar/SkillMenu/StanceComponent.
	var stub := GDScript.new()
	stub.source_code = """
extends CharacterBody3D
var unlocked_skills := {}
var skill_points := 12
var SP_MAX := 20
func update_hud():
	pass
"""
	stub.reload()
	var pl := CharacterBody3D.new()
	pl.set_script(stub)
	root.add_child(pl)
	for sid in ["bard_flow", "mana_concentration", "bard_note", "bard_chord",
			"bard_drop", "mana_crush", "mana_bolt", "mana_crescent"]:
		pl.unlocked_skills[sid] = true
	var bar = load("res://Graphics/ActionBar.gd").new()
	bar.name = "ActionBar"
	pl.add_child(bar)
	var stance = load("res://Logic/StanceComponent.gd").new()
	stance.name = "StanceComponent"
	pl.add_child(stance)
	var menu = load("res://Graphics/SkillMenu.gd").new()
	menu.name = "SkillMenu"
	pl.add_child(menu)
	await process_frame
	# 4) Базлайн.
	_ck(bar.stance_binds.is_empty(), "baseline: биндов нет")
	_ck(bar.get_stance_binds("bard_flow").is_empty(), "get_stance_binds пустой словарь")
	# 5) Мини-панель: открытие + режим «Слой стойки».
	menu.open_stance_panel("bard_flow")
	await process_frame
	_ck(menu._stance_panel != null and menu._stance_panel.visible, "мини-панель открыта")
	_ck(bar._edit_mode, "ActionBar в режиме «Слой стойки»")
	_ck(bar._edit_banner != null and "Поток Гармонии" in bar._edit_banner.text,
			"баннер «Слой стойки: Поток Гармонии»")
	_ck(menu._stance_rows.get_child_count() == 3, "3 строки приёмов в панели")
	# 6) Способ (а) drag под-приёма на слот «E» (индекс 8).
	var slot_e = bar.slots[8]
	_ck(str(slot_e.key_info["label"]) == "E", "слот 8 — это «E»")
	var ddata := {"type": "stance_sub", "stance_id": "bard_flow", "sub_id": "bard_note"}
	_ck(slot_e._can_drop_data(Vector2(), ddata), "drag-приём принимается в режиме слоя")
	slot_e._drop_data(Vector2(), ddata)
	_ck(str(bar.stance_binds.get("bard_flow", {}).get("bard_note", "")) == "E",
			"drag: bard_note → E записан в stance_binds")
	# 7) Способ (б) «клик → нажми слот»: «E» занят bard_note → SWAP в своей
	#    стойке (chord получает E, note уезжает на дефолт chord «ПКМ»).
	menu._on_pick_slot("bard_flow", "bard_chord")
	_ck(menu._await_slot.get("sub_id", "") == "bard_chord", "режим ловли слота включён")
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.physical_keycode = KEY_E
	ev.pressed = true
	_ck(menu._slot_label_from_event(ev) == "E", "_slot_label_from_event(E) == «E»")
	menu._unhandled_input(ev)
	_ck(str(bar.stance_binds.get("bard_flow", {}).get("bard_chord", "")) == "E",
			"клик→слот: bard_chord → E")
	_ck(str(bar.stance_binds.get("bard_flow", {}).get("bard_note", "")) == "ПКМ",
			"swap: bard_note уехал на «ПКМ» (эффективный старый слот chord)")
	# 8) Гард: слот под-приёма ДРУГОЙ стойки занят — назначение отклонено.
	bar.stance_binds["mana_concentration"] = {"mana_crush": "ЛКМ"}
	var st8: String = bar.assign_stance_sub("bard_flow", "bard_drop", "ЛКМ")
	_ck("занят" in st8, "гард другой стойки: «%s»" % st8)
	_ck(not bar.stance_binds["bard_flow"].has("bard_drop"), "bard_drop не записан")
	# 9) Реальное поведение перехвата (Шаг 1): overrides из биндов.
	var db_skills = SkillDB.get_skills()
	var cfg := {
		"stance_id": "bard_flow", "stance_skill_id": "bard_flow",
		"duration": 9.0, "sub_skills": db_skills["bard_flow"].stance_sub_skills,
	}
	_ck(stance.enter_stance(cfg), "стойка вошла")
	_ck(str(stance.overrides.get("ПКМ", "")) == "bard_note", "перехват: ПКМ → bard_note")
	_ck(str(stance.overrides.get("E", "")) == "bard_chord", "перехват: E → bard_chord")
	_ck(str(stance.overrides.get("self", "")) == "bard_drop", "перехват: self → bard_drop")
	stance.exit_stance("probe")
	# 10) Закрытие панели — обычный режим.
	menu.close_stance_panel()
	await process_frame
	_ck(not bar._edit_mode, "после закрытия режим слоя выключен")
	_ck(str(slot_e.color) == str(Color(0.1, 0.1, 0.1, 0.7)), "цвет слота восстановлен")
	# 10b) ⚙-кнопка открывает панель; карта = магазинные семантики (вердикт
	# юзера 22.11.26); слоты показывают превью назначенных приёмов.
	var stance_slot = null
	# Q50 Шаг 2: карточки теперь в секциях веток (заголовок + грядка) — поиск рекурсивный.
	var stack := [menu.grid]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
			if c.get("skill_data") != null and c.skill_data.get("id", "") == "bard_flow":
				stance_slot = c
	_ck(stance_slot != null, "карточка bard_flow найдена в сетке")
	if stance_slot != null:
		var cev := InputEventMouseButton.new()
		cev.button_index = MOUSE_BUTTON_LEFT
		cev.pressed = true
		var sp_before: int = pl.skill_points
		stance_slot._gui_input(cev)
		await process_frame
		_ck(pl.skill_points == sp_before, "клик по изученной карте — покупка no-op (SP не тронут)")
		_ck(menu._edit_stance_id == "" and (menu._stance_panel == null or not menu._stance_panel.visible),
				"клик по КАРТЕ стойки не открывает панель приёмов")
		stance_slot._on_gear_input(cev)
		await process_frame
		_ck(menu._edit_stance_id == "bard_flow" and menu._stance_panel.visible,
				"⚙-кнопка открывает панель приёмов")
		_ck(str(bar.slots[13].label_skill.text) == "🎼", "превью: слот ПКМ показывает bard_note")
		_ck(str(slot_e.label_skill.text) == "🔊", "превью: слот E показывает bard_chord")
		menu.close_stance_panel()
		await process_frame
		_ck(str(slot_e.label_skill.text) == "", "превью снято после закрытия (слот E пуст)")
	# 11) Пресеты: snapshot содержит бинды, файл на диске, round-trip.
	var snap: Dictionary = menu.presets_panel._state_snapshot()
	_ck(snap.has("stance_binds") and snap["stance_binds"].get("bard_flow", {}).get("bard_note", "") == "ПКМ",
			"snapshot содержит stance_binds")
	menu.presets_panel._name_input.text = "probe_q16"
	menu.presets_panel._on_add()
	_ck(FileAccess.file_exists(SAVE_PATH), "пресет записан на диск")
	var presets: Array = menu.presets_panel._load_file()
	_ck(presets.size() >= 1, "файл читается назад (%d пресетов)" % presets.size())
	# Меняем бинды и загружаем пресет — восстановление.
	bar.stance_binds["bard_flow"] = {"bard_note": "7"}
	var probe_idx := presets.size() - 1
	menu.presets_panel._on_load(probe_idx)
	await process_frame
	_ck(str(bar.stance_binds.get("bard_flow", {}).get("bard_note", "")) == "ПКМ",
			"загрузка пресета восстановила bard_note → ПКМ")
	var loaded: Array = menu.presets_panel._load_file()
	_ck(loaded[probe_idx].get("stance_binds", {}).get("bard_flow", {}).get("bard_chord", "") == "E",
			"round-trip JSON: chord → E в файле")
	# 12) Восстановление файла юзера.
	if had_user_file:
		var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		wf.store_string(user_backup)
		wf.close()
	else:
		DirAccess.remove_absolute(SAVE_PATH)
	print("PASS_COUNT=%d FAIL_COUNT=%d" % [_pass, _fail])
	if _fail == 0:
		print("BINDS UI GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BINDS UI GATE FAILED")
		quit(1)
