extends CanvasLayer

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")
const SkillPresetsPanel = preload("res://Graphics/SkillPresetsPanel.gd")

var panel: Panel
var is_open: bool = false
var player: CharacterBody3D
var grid: GridContainer
var sp_label: Label
var presets_panel

class SkillSlot extends ColorRect:
    var skill_data: Dictionary
    var menu: CanvasLayer
    var icon_label: Label
    var _gear: Label = null
    
    func _ready():
        custom_minimum_size = Vector2(70, 70)
        mouse_filter = Control.MOUSE_FILTER_STOP
        
        icon_label = Label.new()
        icon_label.set_anchors_preset(Control.PRESET_CENTER)
        icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        icon_label.text = skill_data["icon"]
        icon_label.add_theme_font_size_override("font_size", 32)
        add_child(icon_label)

        # ⚙-кнопка стойки (Q16 Шаг 8; вердикт юзера 22.11.26: панель приёмов
        # открывает ШЕСТЕРЁНКА у изученной стойки, клик по карте = магазин).
        if skill_data.get("stance", false):
            var gear := Label.new()
            gear.text = "⚙"
            gear.position = Vector2(48, 2)
            gear.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
            gear.mouse_filter = Control.MOUSE_FILTER_STOP
            gear.gui_input.connect(_on_gear_input)
            gear.visible = false
            add_child(gear)
            _gear = gear

        update_visuals()

    func _gui_input(event):
        if event is InputEventMouseButton and event.pressed:
            if event.button_index == MOUSE_BUTTON_LEFT:
                # Вердикт юзера 22.11.26: карта = магазинные семантики (у
                # изученной — no-op), панель приёмов открывает только ⚙.
                menu.buy_skill(skill_data["id"], skill_data["price"])
                update_visuals()
            elif event.button_index == MOUSE_BUTTON_RIGHT:
                menu.sell_skill(skill_data["id"], skill_data["price"])
                update_visuals()

    func _on_gear_input(event):
        # ⚙ = кнопка «Приёмы стойки» (видна только у изученной — update_visuals).
        # В.6.1 (вердикт спеца): СТРОГИЙ ТУГЛ — повторный клик закрывает панель.
        if event is InputEventMouseButton and event.pressed \
                and event.button_index == MOUSE_BUTTON_LEFT \
                and menu.player.unlocked_skills.get(skill_data["id"], false):
            if menu._edit_stance_id == skill_data["id"] \
                    and menu._stance_panel != null and menu._stance_panel.visible:
                menu.close_stance_panel()
            else:
                menu.open_stance_panel(skill_data["id"])
            accept_event()

    func update_visuals():
        var is_unlocked = menu.player.unlocked_skills.get(skill_data["id"], false)
        if is_unlocked:
            color = Color(0.2, 0.6, 0.2, 1.0)
        else:
            color = Color(0.2, 0.2, 0.2, 1.0)
            
        var status = "ИЗУЧЕНО" if is_unlocked else "Не изучено (Цена: " + str(skill_data["price"]) + " SP)"
        if _gear != null:
            _gear.visible = is_unlocked
        
        # Собираем всплывающую подсказку с описанием
        tooltip_text = skill_data["name"] + "\n"
        var desc = skill_data.get("description", "")
        if desc != "":
            tooltip_text += desc + "\n"
        tooltip_text += "\n" + status + "\n\n[ЛКМ] Купить | [ПКМ] Продать"
        
        if skill_data["id"] != "double_jump":
            tooltip_text += "\nПеретащите на нижнюю панель"
        if skill_data.get("stance", false):
            tooltip_text += "\n⚙ (в углу карточки) — приёмы стойки (слоты под-приёмов)"

    func _get_drag_data(at_position):
        var sid = skill_data["id"]
        if sid == "double_jump" or not menu.player.unlocked_skills.get(sid, false):
            return null
            
        var data = {"type": "skill", "skill_id": sid, "source": null}
        
        var preview = ColorRect.new()
        preview.custom_minimum_size = Vector2(50, 50)
        preview.color = Color(0, 0, 0, 0.5)
        var lbl = Label.new()
        lbl.text = skill_data["icon"]
        lbl.add_theme_font_size_override("font_size", 24)
        lbl.set_anchors_preset(Control.PRESET_CENTER)
        preview.add_child(lbl)
        set_drag_preview(preview)
        
        return data

func _ready():
    name = "SkillMenu"
    layer = 10
    player = get_parent()
    
    panel = Panel.new()
    panel.custom_minimum_size = Vector2(900, 480)
    panel.anchor_left = 0.5
    panel.anchor_top = 0.5
    panel.anchor_right = 0.5
    panel.anchor_bottom = 0.5
    panel.offset_left = -450
    panel.offset_top = -240
    panel.offset_right = 450
    panel.offset_bottom = 240
    add_child(panel)

    var title = Label.new()
    title.text = "Книга Навыков (Закрыть - 'N')\nНаведите мышь на навык для инфо"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.set_anchors_preset(Control.PRESET_TOP_WIDE)
    title.position.y = 10
    panel.add_child(title)

    # Очки навыков перенесены сюда из HUD (формат «осталось/всего»).
    sp_label = Label.new()
    sp_label.position = Vector2(40, 56)
    sp_label.add_theme_font_size_override("font_size", 16)
    sp_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
    panel.add_child(sp_label)

    grid = GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 15)
    grid.add_theme_constant_override("v_separation", 15)
    grid.position = Vector2(40, 90)
    panel.add_child(grid)
    
    var all_skills = SkillDB.get_shop_skills()
    for s_id in all_skills:
        var skill_obj = all_skills[s_id]
        var slot = SkillSlot.new()
        slot.skill_data = {
            "id": skill_obj.id,
            "price": skill_obj.price,
            "name": skill_obj.skill_name,
            "icon": skill_obj.icon,
            "description": skill_obj.description,
            "stance": not skill_obj.stance_sub_skills.is_empty(),
        }
        slot.menu = self
        grid.add_child(slot)

    # Боковая панель пресетов (снапшоты по skill id, JSON user://).
    presets_panel = SkillPresetsPanel.new(self)
    presets_panel.position = Vector2(520, 30)
    presets_panel.custom_minimum_size = Vector2(350, 430)
    panel.add_child(presets_panel)

    panel.hide()

func refresh_sp() -> void:
    if sp_label:
        sp_label.text = "Очки навыков: %d/%d" % [player.skill_points, player.SP_MAX]

func refresh_grid() -> void:
    for child in grid.get_children():
        if child.has_method("update_visuals"):
            child.update_visuals()

func buy_skill(id: String, price: int):
    if not player.unlocked_skills.get(id, false) and player.skill_points >= price:
        player.skill_points -= price
        player.unlocked_skills[id] = true
        player.update_hud()
        refresh_sp()

func sell_skill(id: String, price: int):
    if player.unlocked_skills.get(id, false):
        player.skill_points += price
        player.unlocked_skills[id] = false
        player.update_hud()
        refresh_sp()
        player.unlearn_cleanup(id)

## _unhandled_input: пока LineEdit пресетов держит фокус, «N» печатается
## в поле, а не закрывает окно. Ловля слота (В.6.2, вердикт спеца): ввод
## НЕ глотается до проверки — Esc отменяет ловлю (книга жива), N отменяет
## ловлю И закрывает книгу, прочие клавиши проходят дальше; мышь — в _input.
func _unhandled_input(event):
    # «Клик → нажми слот» (Q16 Шаг 8): клавиатурная часть ловли.
    if _await_slot.size() > 0 and event is InputEventKey \
            and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            get_viewport().set_input_as_handled()
            _await_slot = {}
            _stance_status.text = "Назначение отменено (Esc)."
            return
        if event.keycode == KEY_N:
            get_viewport().set_input_as_handled()
            _await_slot = {}
            _close_book()
            return
        var lbl := _slot_label_from_event(event)
        if lbl != "":
            get_viewport().set_input_as_handled()
            _assign_awaited_slot(lbl)
            return
        # Прочие клавиши НЕ глотаются (вердикт В.6.2) — уходят дальше.
        return
    # Дошедшая сюда мышь = клик мимо мини-панели и мимо ActionBar (STOP-контролы
    # съели бы раньше) → отмена ловли; клик НЕ глотается (уходит в мир).
    if _await_slot.size() > 0 and event is InputEventMouseButton and event.pressed:
        _await_slot = {}
        _stance_status.text = "Назначение отменено."
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_N:
        if is_open:
            _close_book()
        else:
            is_open = true
            panel.show()
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
            refresh_grid()
            refresh_sp()
            presets_panel.refresh()

## Закрытие книги (N): режим «Слой стойки» гасим вместе с окном; мышь
## возвращается в игру (ССОТ ui_input_rules, вердикт юзера 19.11.26).
func _close_book() -> void:
    is_open = false
    panel.hide()
    close_stance_panel()
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Ловля слота — мышь в _input (сырой ввод): STOP-слоты ActionBar съедают
## клик до _unhandled_input, а клик ПО слоту панели должен назначать именно
## этот слот (В.6.2); клик мимо панели и ActionBar — отмена (не глотается).
func _input(event):
    if _await_slot.size() == 0 \
            or not (event is InputEventMouseButton and event.pressed):
        return
    var lbl := _slot_label_at(event.position)
    if lbl == "":
        return  # не над слотом: GUI/мир обработает, отмена — в _unhandled_input
    get_viewport().set_input_as_handled()  # не даём слоту съесть/очиститься
    _assign_awaited_slot(lbl)

func _assign_awaited_slot(lbl: String) -> void:
    var bar = player.get_node_or_null("ActionBar")
    if bar != null and bar.has_method("assign_stance_sub"):
        _stance_status.text = bar.assign_stance_sub(
                str(_await_slot["stance_id"]),
                str(_await_slot["sub_id"]), lbl)
    _await_slot = {}
    var st = SkillDB.get_skills().get(_edit_stance_id)
    if st != null:
        _rebuild_stance_rows(st)

## Метка слота ActionBar ПОД ПОЗИЦИЕЙ клика (клик → слот: назначается
## именно тот слот, по которому кликнули).
func _slot_label_at(pos: Vector2) -> String:
    var bar = player.get_node_or_null("ActionBar")
    if bar == null:
        return ""
    for slot in bar.slots:
        if slot is Control and slot.get_global_rect().has_point(pos):
            return str(slot.key_info.get("label", ""))
    return ""

func _process(_delta):
    # Гард симметричен SettingsMenu: пока книга открыта, мышь видима, даже
    # если другое окно закрылось и закапчурило курсор «мимо нас».
    if is_open and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## ---------- Мини-панель приёмов стойки (Q16 Шаг 8) ----------

var _stance_panel: Panel = null
var _stance_title: Label
var _stance_rows: VBoxContainer
var _stance_status: Label
var _await_slot := {}    # {stance_id, sub_id}: ловим следующее нажатие слота
var _edit_stance_id := ""

## Перетаскиваемая иконка под-приёма (drag-источник в мини-панели).
class SubDrag extends ColorRect:
    var stance_id: String
    var sub_id: String
    var sub_icon: String
    var menu: CanvasLayer

    func _ready():
        custom_minimum_size = Vector2(28, 28)
        color = Color(0.25, 0.35, 0.55, 0.9)
        mouse_filter = Control.MOUSE_FILTER_STOP
        var lbl := Label.new()
        lbl.text = sub_icon
        lbl.set_anchors_preset(Control.PRESET_CENTER)
        lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(lbl)

    func _get_drag_data(_at_position):
        # Тащить приёмы можно только изученной стойки.
        if not menu.player.unlocked_skills.get(menu._edit_stance_id, false):
            return null
        var preview := ColorRect.new()
        preview.custom_minimum_size = Vector2(40, 40)
        preview.color = Color(0.4, 0.2, 0.6, 0.7)
        var lbl := Label.new()
        lbl.text = sub_icon
        lbl.set_anchors_preset(Control.PRESET_CENTER)
        preview.add_child(lbl)
        set_drag_preview(preview)
        return {"type": "stance_sub", "stance_id": stance_id, "sub_id": sub_id}

## Клик по изученной стойке (⚙-бейдж): мини-панель приёмов под сеткой +
## ActionBar в режиме «Слой стойки» (drag-цель).
func open_stance_panel(stance_id: String) -> void:
    var st = SkillDB.get_skills().get(stance_id)
    if st == null:
        return
    _edit_stance_id = stance_id
    if _stance_panel == null:
        _build_stance_panel()
    _stance_title.text = "Приёмы внутри «%s»" % st.skill_name
    _rebuild_stance_rows(st)
    _stance_status.text = "Перетащите приём на слот или «Клик → слот»."
    _stance_panel.visible = true
    var bar = player.get_node_or_null("ActionBar")
    if bar != null and bar.has_method("set_stance_edit_mode"):
        bar.set_stance_edit_mode(true, st.skill_name, stance_id)

func close_stance_panel() -> void:
    if _stance_panel != null:
        _stance_panel.visible = false
    _await_slot = {}
    _edit_stance_id = ""
    var bar = player.get_node_or_null("ActionBar")
    if bar != null and bar.has_method("set_stance_edit_mode"):
        bar.set_stance_edit_mode(false)

func _build_stance_panel() -> void:
    _stance_panel = Panel.new()
    _stance_panel.position = Vector2(40, 348)
    _stance_panel.custom_minimum_size = Vector2(462, 118)
    panel.add_child(_stance_panel)
    var vb := VBoxContainer.new()
    vb.set_anchors_preset(Control.PRESET_FULL_RECT)
    vb.offset_left = 8
    vb.offset_top = 6
    vb.offset_right = -8
    vb.offset_bottom = -6
    vb.add_theme_constant_override("separation", 4)
    _stance_panel.add_child(vb)
    _stance_title = Label.new()
    _stance_title.add_theme_font_size_override("font_size", 14)
    _stance_title.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
    vb.add_child(_stance_title)
    _stance_rows = VBoxContainer.new()
    _stance_rows.add_theme_constant_override("separation", 3)
    vb.add_child(_stance_rows)
    _stance_status = Label.new()
    _stance_status.add_theme_font_size_override("font_size", 12)
    _stance_status.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
    vb.add_child(_stance_status)

func _rebuild_stance_rows(st) -> void:
    for c in _stance_rows.get_children():
        c.queue_free()
    var bar = player.get_node_or_null("ActionBar")
    var binds: Dictionary = {}
    if bar != null and bar.has_method("get_stance_binds"):
        binds = bar.get_stance_binds(_edit_stance_id)
    var skills = SkillDB.get_skills()
    for sd in st.stance_sub_skills:
        var sub_id := str(sd.get("id", ""))
        if sub_id == "":
            continue
        var sub = skills.get(sub_id)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        var drag := SubDrag.new()
        drag.stance_id = _edit_stance_id
        drag.sub_id = sub_id
        drag.sub_icon = sub.icon if sub != null else "?"
        drag.menu = self
        row.add_child(drag)
        var nm := Label.new()
        nm.text = str(sd.get("label", sub_id))
        nm.custom_minimum_size = Vector2(140, 0)
        row.add_child(nm)
        var cur := Label.new()
        var eff := str(binds.get(sub_id, sd.get("default_slot", "")))
        cur.text = "слот: %s" % ("дефолт" if eff == "" else eff)
        cur.custom_minimum_size = Vector2(110, 0)
        cur.modulate = Color(1, 1, 1, 0.8)
        row.add_child(cur)
        var btn := Button.new()
        btn.text = "Клик → слот"
        btn.pressed.connect(_on_pick_slot.bind(_edit_stance_id, sub_id))
        row.add_child(btn)
        _stance_rows.add_child(row)

func _on_pick_slot(stance_id: String, sub_id: String) -> void:
    _await_slot = {"stance_id": stance_id, "sub_id": sub_id}
    _stance_status.text = "Нажми клавишу слота (Esc — отмена)."

## Лейбл слота по событию (та же таблица, что у ActionBar — keycode ИЛИ
## physical_keycode, как в его обработчике).
func _slot_label_from_event(event) -> String:
    var bar = player.get_node_or_null("ActionBar")
    if bar == null:
        return ""
    for b in bar.key_bindings:
        if b["type"] == "key" and event is InputEventKey \
                and event.pressed and not event.echo \
                and (event.keycode == b["code"] or event.physical_keycode == b["code"]):
            return str(b["label"])
        if b["type"] == "mouse" and event is InputEventMouseButton \
                and event.pressed and event.button_index == b["code"]:
            return str(b["label"])
    return ""