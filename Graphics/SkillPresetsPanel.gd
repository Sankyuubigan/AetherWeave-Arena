extends VBoxContainer

## Боковая панель «Пресеты» внутри книги навыков.
## Снапшот состояния навыков (по skill id — названия могут меняться):
## купленные id + остаток SP + расстановка по 14 слотам ActionBar.
## Хранение: user://skill_presets.json (переживает перезапуск игры).

const SAVE_PATH := "user://skill_presets.json"
const BAR_SLOTS := 14

var menu: CanvasLayer          # SkillMenu (владелец)
var player: CharacterBody3D
var _name_input: LineEdit
var _rows_box: VBoxContainer
var _confirm: ConfirmationDialog  # Q42: подтверждение пересохранения пресета
var _pending_save := -1           # индекс пресета, ожидающего «да»

func _init(owner_menu: CanvasLayer) -> void:
	menu = owner_menu

func _ready() -> void:
	# Панель создаётся в SkillMenu._ready ПОСЛЕ того, как тот заполнил
	# menu.player (строка player = get_parent()) — ссылка уже готова.
	player = menu.player
	# Высота ОБЯЗАТЕЛЬНА: VBox без минимальной высоты сжимается до суммы
	# детей, ScrollContainer внутри получает 0px → список пресетов невидим
	# (регресс 17.11: строки строились, но не отображались).
	custom_minimum_size = Vector2(330, 430)
	add_theme_constant_override("separation", 8)
	_build_ui()
	refresh()

func _build_ui() -> void:
	var title := Label.new()
	title.text = "Пресеты"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	add_child(add_row)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Название пресета"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_submitted.connect(func(_t): _on_add())
	add_row.add_child(_name_input)

	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(36, 0)
	add_btn.pressed.connect(_on_add)
	add_row.add_child(add_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 290)  # страховка видимой высоты
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows_box)

	var hint := Label.new()
	hint.text = "Сохраняет купленные навыки, остаток SP\nи раскладку панели. 💾 — перезаписать\nпресет текущим состоянием (с подтверждением)."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	add_child(hint)

## Пересобирает список строк из файла.
func refresh() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	var presets: Array = _load_file()
	for i in presets.size():
		_rows_box.add_child(_make_row(presets[i], i))

func _make_row(preset: Dictionary, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = str(preset.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	var skills_label := Label.new()
	skills_label.text = "(" + str(preset.get("skills", []).size()) + ")"
	skills_label.modulate = Color(1, 1, 1, 0.5)
	row.add_child(skills_label)

	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.pressed.connect(_on_load.bind(index))
	row.add_child(load_btn)

	# Q42 (заказ юзера 20.11.26): иконка сохранения на каждом созданном
	# пресете — пересохраняет ТЕКУЩЕЕ состояние (скиллы, SP, раскладка,
	# купленное) в файл этого пресета. Не сразу: сначала подтверждение.
	var save_btn := Button.new()
	save_btn.text = "💾"
	save_btn.custom_minimum_size = Vector2(36, 0)
	save_btn.tooltip_text = "Пересохранить пресет текущим состоянием"
	save_btn.pressed.connect(_on_save.bind(index))
	row.add_child(save_btn)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(32, 0)
	del_btn.pressed.connect(_on_delete.bind(index))
	row.add_child(del_btn)
	return row

## Текущее состояние игрока — общий снапшот для «+» и для 💾 (Q42).
func _state_snapshot() -> Dictionary:
	var bar: Array = []
	var action_bar = player.get_node_or_null("ActionBar")
	if action_bar:
		for slot in action_bar.slots:
			bar.append(slot.skill_id)
	bar.resize(BAR_SLOTS)
	var skills: Array = []
	for sid in player.unlocked_skills:
		if player.unlocked_skills[sid]:
			skills.append(sid)
	# Q16 Шаг 8: бинды под-приёмов стоек едут в пресете (round-trip JSON).
	var binds := {}
	if action_bar:
		for sid in action_bar.stance_binds:
			binds[sid] = (action_bar.stance_binds[sid] as Dictionary).duplicate()
	return {
		"skills": skills,
		"sp": int(player.skill_points),
		"bar": bar,
		"stance_binds": binds,
	}

## «+»: снапшот купленных навыков + SP + расстановка ActionBar.
func _on_add() -> void:
	var preset_name := _name_input.text.strip_edges()
	if preset_name == "":
		preset_name = "Пресет " + str(_load_file().size() + 1)
	var preset := _state_snapshot()
	preset["name"] = preset_name
	var presets := _load_file()
	presets.append(preset)
	_save_file(presets)
	_name_input.text = ""
	refresh()

## 💾 на строке пресета: НЕ пересохраняет сразу — сначала подтверждение
## «уверены, что хотите пересохранить?» (заказ юзера).
func _on_save(index: int) -> void:
	var presets := _load_file()
	if index < 0 or index >= presets.size():
		return
	_pending_save = index
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.ok_button_text = "Да, пересохранить"
		_confirm.cancel_button_text = "Отмена"
		_confirm.confirmed.connect(_on_confirm_save)
		menu.add_child(_confirm)
	_confirm.dialog_text = "Уверены, что хотите пересохранить пресет «%s»?\nТекущие навыки, SP и раскладка панели перезапишут его." % str(presets[index].get("name", "?"))
	_confirm.popup_centered()

## «Да» в подтверждении: полная перезапись записи пресета текущим состоянием.
func _on_confirm_save() -> void:
	if _pending_save < 0:
		return
	if _confirm != null:
		_confirm.hide()  # клик «Да» окно гасит сам, прямой вызов хендлера — нет
	var presets := _load_file()
	if _pending_save >= presets.size():
		_pending_save = -1
		return
	var preset := _state_snapshot()
	preset["name"] = str(presets[_pending_save].get("name", "?"))
	presets[_pending_save] = preset
	_save_file(presets)
	_pending_save = -1
	refresh()

## Загрузка: полная перезапись состояния снапшотом — навыки «покупаются»,
## SP и нижняя панель становятся как при сохранении.
func _on_load(index: int) -> void:
	var presets: Array = _load_file()
	if index < 0 or index >= presets.size():
		return
	var preset: Dictionary = presets[index]
	var skills: Array = preset.get("skills", [])
	for sid in skills:
		player.unlocked_skills[str(sid)] = true
	player.skill_points = int(preset.get("sp", player.skill_points))
	var bar: Array = preset.get("bar", [])
	var action_bar = player.get_node_or_null("ActionBar")
	if action_bar:
		for i in action_bar.slots.size():
			var sid: String = bar[i] if i < bar.size() else ""
			action_bar.slots[i].set_skill(str(sid))
	# Q16 Шаг 8: восстановление биндов под-приёмов стоек.
	var binds = preset.get("stance_binds", {})
	if action_bar != null and binds is Dictionary:
		var restored := {}
		for sid in binds:
			restored[sid] = (binds[sid] as Dictionary).duplicate()
		action_bar.stance_binds = restored
	player.update_hud()
	menu.refresh_sp()
	menu.refresh_grid()
	refresh()

func _on_delete(index: int) -> void:
	var presets: Array = _load_file()
	if index < 0 or index >= presets.size():
		return
	presets.remove_at(index)
	_save_file(presets)
	refresh()

## --- Персист (JSON-файл сохранения) ---

func _load_file() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return []
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("presets")) != TYPE_ARRAY:
		return []
	return parsed["presets"]

func _save_file(presets: Array) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SkillPresetsPanel: не открыть " + SAVE_PATH)
		return
	f.store_string(JSON.stringify({"presets": presets}, "  "))
