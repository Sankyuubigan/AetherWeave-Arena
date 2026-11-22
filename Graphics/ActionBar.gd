extends CanvasLayer

var slots = []
var key_bindings = [
    {"label": "1", "type": "key", "code": KEY_1},
    {"label": "2", "type": "key", "code": KEY_2},
    {"label": "3", "type": "key", "code": KEY_3},
    {"label": "4", "type": "key", "code": KEY_4},
    {"label": "5", "type": "key", "code": KEY_5},
    {"label": "6", "type": "key", "code": KEY_6},
    {"label": "7", "type": "key", "code": KEY_7},
    {"label": "Q", "type": "key", "code": KEY_Q},
    {"label": "E", "type": "key", "code": KEY_E},
    {"label": "R", "type": "key", "code": KEY_R},
    {"label": "F", "type": "key", "code": KEY_F},
    {"label": "Shift", "type": "key", "code": KEY_SHIFT},
    {"label": "ЛКМ", "type": "mouse", "code": MOUSE_BUTTON_LEFT},
    {"label": "ПКМ", "type": "mouse", "code": MOUSE_BUTTON_RIGHT}
]

## Переназначения под-приёмов стоек (Q16 Шаг 1; UI-редактор — Шаг 8 PRP):
## {stance_id: {sub_id: slot_label}}. Пусто = дефолты default_slot.
var stance_binds := {}

## Бинды под-приёмов конкретной стойки. Пустой словарь = дефолты.
func get_stance_binds(stance_id: String) -> Dictionary:
    return stance_binds.get(stance_id, {})

## ---------- Редактор биндов стоек (Q16 Шаг 8) ----------

var _edit_mode := false
var _edit_banner: Label
var _edit_stance_id := ""        # id стойки в режиме «Слой стойки»
var _edit_icon_backup := {}      # index слота → исходный текст иконки

## Режим «Слой стойки: <имя>»: слоты подсвечены фиолетовым, на слотах ВИДНЫ
## назначенные под-приёмы (вердикт юзера 22.11.26: бинды обязаны быть видны
## на панели, а не только в мини-панели), drag под-приёмов разрешён.
func set_stance_edit_mode(active: bool, stance_name: String = "", stance_id: String = "") -> void:
    _edit_mode = active
    if active:
        _edit_stance_id = stance_id
        if _edit_banner == null:
            _edit_banner = Label.new()
            _edit_banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
            _edit_banner.position.y = -112
            _edit_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            _edit_banner.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
            add_child(_edit_banner)
        _edit_banner.text = "Слой стойки: %s — перетащите приём на слот" % stance_name
        _edit_banner.visible = true
    elif _edit_banner != null:
        _edit_banner.visible = false
        _edit_stance_id = ""
    if active:
        _refresh_edit_preview()
    else:
        for i in _edit_icon_backup:
            slots[i].label_skill.text = _edit_icon_backup[i]
        _edit_icon_backup.clear()
        for s in slots:
            s.label_skill.modulate = Color(1, 1, 1, 1)
    for s in slots:
        s.color = Color(0.42, 0.2, 0.6, 0.85) if active else Color(0.1, 0.1, 0.1, 0.7)

## Перерисовать превью под-приёмов на слотах (режим «Слой стойки»): слот,
## куда назначен приём (явный бинд или default_slot), показывает его иконку
## на полную яркость; остальные слоты приглушены. Вызывается при открытии
## режима, после assign_stance_sub и при выходе активной стойки.
func _refresh_edit_preview() -> void:
    for i in _edit_icon_backup:
        slots[i].label_skill.text = _edit_icon_backup[i]
    _edit_icon_backup.clear()
    if not _edit_mode or _edit_stance_id == "":
        return
    var skills = preload("res://Logic/Skills/SkillDB.gd").get_skills()
    var st = skills.get(_edit_stance_id)
    if st == null:
        return
    var binds: Dictionary = stance_binds.get(_edit_stance_id, {})
    var slot_sub := {}  # метка слота → sub_id
    for sd in st.stance_sub_skills:
        var sub_id := str(sd.get("id", ""))
        var slot := str(binds.get(sub_id, sd.get("default_slot", "")))
        if slot != "":
            slot_sub[slot] = sub_id
    for i in slots.size():
        var s = slots[i]
        var label := str(s.key_info.get("label", ""))
        if s.skill_id != "" and s.skill_id == _edit_stance_id:
            label = "self"
        if slot_sub.has(label):
            var sub = skills.get(str(slot_sub[label]))
            _edit_icon_backup[i] = s.label_skill.text
            s.label_skill.text = sub.icon if sub != null else "?"
            s.label_skill.modulate = Color(1, 1, 1, 1)

## Назначение под-приёма на слот (drag на слот или «клик → нажми слот»).
## Swap двух под-приёмов ТОЛЬКО внутри своей стойки; слот под-приёма другой
## стойки занят — назначение отклонено. Возвращает статус-строку для UI.
func assign_stance_sub(stance_id: String, sub_id: String, slot_label: String) -> String:
    if slot_label == "self":
        return "«self» — слот самой стойки, не назначается"
    var binds: Dictionary = stance_binds.get(stance_id, {}).duplicate()
    for other_id in stance_binds:
        # Ключи словаря биндов — sub_id, слоты живут в ЗНАЧЕНИЯХ.
        if str(other_id) != stance_id and stance_binds[other_id] is Dictionary \
                and stance_binds[other_id].values().has(slot_label):
            return "Слот «%s» занят приёмом стойки «%s»" % [slot_label, other_id]
    var old := str(binds.get(sub_id, ""))
    if old == slot_label:
        return "Уже назначено на «%s»" % slot_label
    var skills = preload("res://Logic/Skills/SkillDB.gd").get_skills()
    for s2 in binds:
        if str(s2) != sub_id and str(binds[s2]) == slot_label:
            # Партнёр по стойке получает «эффективный старый» слот sub
            # (явный бинд или его default_slot из SkillDB).
            var def := ""
            if skills.has(stance_id):
                for sd in skills[stance_id].stance_sub_skills:
                    if str(sd.get("id", "")) == sub_id:
                        def = str(sd.get("default_slot", ""))
            binds[s2] = binds.get(sub_id, def)
    binds[sub_id] = slot_label
    stance_binds[stance_id] = binds
    if _edit_mode:
        _refresh_edit_preview()
    return "Назначено: «%s» → слот %s" % [sub_id, slot_label]

class ActionSlot extends ColorRect:
    var key_info = {}
    var skill_id: String = ""
    var label_key: Label
    var label_skill: Label

    func _ready():
        custom_minimum_size = Vector2(55, 55)
        color = Color(0.1, 0.1, 0.1, 0.7)
        mouse_filter = Control.MOUSE_FILTER_STOP

        label_key = Label.new()
        label_key.text = key_info["label"]
        label_key.position = Vector2(4, 2)
        label_key.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
        label_key.mouse_filter = Control.MOUSE_FILTER_IGNORE 
        add_child(label_key)

        label_skill = Label.new()
        label_skill.set_anchors_preset(Control.PRESET_CENTER)
        label_skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label_skill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(label_skill)

    func _bar():
        return get_parent().get_parent()  # hbox → ActionBar

    func _can_drop_data(at_position, data):
        # Drag под-приёма стойки (Q16 Шаг 8) — только в режиме «Слой стойки».
        if data is Dictionary and data.get("type") == "stance_sub":
            return _bar()._edit_mode
        return data is Dictionary and data.has("type") and data["type"] == "skill"

    func _drop_data(at_position, data):
        if data is Dictionary and data.get("type") == "stance_sub":
            _bar().assign_stance_sub(str(data.get("stance_id", "")),
                    str(data.get("sub_id", "")), str(key_info["label"]))
            return
        var src = data.get("source")
        if src != null and src is ColorRect and src != self:
            src.set_skill(self.skill_id)
        set_skill(data["skill_id"])

    func _get_drag_data(at_position):
        if skill_id == "": return null
        var data = {"type": "skill", "skill_id": skill_id, "source": self}
        
        var preview = ColorRect.new()
        preview.custom_minimum_size = Vector2(40, 40)
        preview.color = Color(0, 0, 0, 0.6)
        var lbl = Label.new()
        lbl.text = label_skill.text
        lbl.set_anchors_preset(Control.PRESET_CENTER)
        preview.add_child(lbl)
        set_drag_preview(preview)
        
        return data

    func _gui_input(event):
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
            set_skill("")

    func set_skill(id: String):
        skill_id = id
        if id == "": 
            label_skill.text = ""
            return
            
        # Загружаем напрямую через статическую функцию прелоада
        var sdb = preload("res://Logic/Skills/SkillDB.gd").get_skills()
        if sdb.has(id):
            label_skill.text = sdb[id].icon
        else:
            label_skill.text = "?"

func _ready():
    name = "ActionBar"
    layer = 5
    
    var hbox = HBoxContainer.new()
    hbox.alignment = BoxContainer.ALIGNMENT_CENTER
    hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hbox.position.y = -80
    hbox.add_theme_constant_override("separation", 8)
    
    hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hbox)
    
    for bind in key_bindings:
        var slot = ActionSlot.new()
        slot.key_info = bind
        hbox.add_child(slot)
        slots.append(slot)

    # Раскладка панели тоже слетала при смене карты — восстановление из
    # автолоада PlayerSession (наполнение слотов в PlayerController._ready).
    var session = get_node_or_null("/root/PlayerSession")
    if session and session.has_state:
        var bar: Array = session.bar
        for i in slots.size():
            var sid: String = bar[i] if i < bar.size() else ""
            slots[i].set_skill(str(sid))

    # Стойка (Q16 Шаг 1): StanceComponent добавляется в игрока ПОСЛЕ ActionBar —
    # подключение к сигналам отложенным вызовом.
    call_deferred("_hook_stance")

func remove_skill(id: String):
    for slot in slots:
        if slot.skill_id == id:
            slot.set_skill("")

# ---------- Система стоек (Q16) ----------

var _icon_backup := {}  # index слота → {text, color} для возврата после стойки

## Подключение к StanceComponent (создаётся позже ActionBar в _ready игрока).
func _hook_stance() -> void:
    var stance = get_parent().get_node_or_null("StanceComponent")
    if stance == null:
        return
    if not stance.stance_entered.is_connected(_on_stance_entered):
        stance.stance_entered.connect(_on_stance_entered)
    if not stance.stance_exited.is_connected(_on_stance_exited):
        stance.stance_exited.connect(_on_stance_exited)

## Вход стойки: key-слоты — подмена иконки на иконку под-приёма; mouse-слоты
## (М1/М2) — только фиолетовая подсветка без иконки (вердикт спеца).
func _on_stance_entered(overrides: Dictionary, stance_skill_id: String) -> void:
    _icon_backup.clear()
    var sdb = preload("res://Logic/Skills/SkillDB.gd").get_skills()
    for i in slots.size():
        var slot = slots[i]
        var label := str(slot.key_info.get("label", ""))
        if slot.skill_id != "" and slot.skill_id == stance_skill_id:
            label = "self"
        if not overrides.has(label):
            continue
        _icon_backup[i] = {"text": slot.label_skill.text, "color": slot.color}
        if slot.key_info["type"] == "key":
            var sub_id := str(overrides[label])
            slot.label_skill.text = sdb[sub_id].icon if sdb.has(sub_id) else "?"
        slot.color = Color(0.55, 0.25, 0.8, 0.85)

## Выход стойки: возврат иконок/цвета всех подменённых слотов.
func _on_stance_exited(_reason: String) -> void:
    for i in _icon_backup:
        var slot = slots[i]
        slot.label_skill.text = _icon_backup[i]["text"]
        slot.color = _icon_backup[i]["color"]
    _icon_backup.clear()
    if _edit_mode:
        _refresh_edit_preview()  # превью слоя могло перезаписаться подменой

## Точка перехвата стойки (Q16): активная стойка подменяет слот → под-приём.
## true = нажатие перехвачено, обычный скилл слота НЕ кастовать.
func _try_stance(slot) -> bool:
    var stance = get_parent().get_node_or_null("StanceComponent")
    if stance == null or not stance.is_active:
        return false
    var label := str(slot.key_info.get("label", ""))
    if slot.skill_id != "" and slot.skill_id == stance.stance_skill_id:
        label = "self"
    return stance.try_handle_slot(label)

## Текст клавиши, куда забинжен скилл (AIM ASSIST Q29: подпись на отметке
## цели). key-слоты: key_info["label"] = "1".."5"; мышиные — М1/М2.
func key_label_for_skill(id: String) -> String:
    for slot in slots:
        if slot.skill_id == id:
            return str(slot.key_info.get("label", ""))
    return ""

## КЛАВИШИ — _unhandled_input: LineEdit с фокусом (печать имени пресета)
## поглощает клавиши раньше нас — хоткеи не срабатывают во время печати.
func _unhandled_input(event):
    if not (event is InputEventKey):
        return
    var menu = get_parent().get_node_or_null("SkillMenu")
    if menu and menu.is_open:
        return

    for slot in slots:
        if slot.key_info["type"] != "key": continue

        if event.pressed and not event.echo and (event.keycode == slot.key_info["code"] or event.physical_keycode == slot.key_info["code"]):
            # Стойка (Q16): подменённый слот исполняет под-приём.
            if not _try_stance(slot) and slot.skill_id != "":
                get_parent().use_skill(slot.skill_id)

## КНОПКИ МЫШИ — _input (сырой ввод): STOP-слоты под виртуальным курсором
## поглощают клик до _unhandled_input — касты ЛКМ/ПКМ «пропадали» при
## наведении на панель. Меню открыто → гвард (drag&drop слотов не трогаем).
func _input(event):
    if not (event is InputEventMouseButton and event.pressed):
        return
    var menu = get_parent().get_node_or_null("SkillMenu")
    if menu and menu.is_open:
        return

    for slot in slots:
        if slot.key_info["type"] != "mouse": continue

        if event.button_index == slot.key_info["code"]:
            # Стойка (Q16): перехват работает и на пустых mouse-слотах.
            if not _try_stance(slot) and slot.skill_id != "":
                get_parent().use_skill(slot.skill_id)