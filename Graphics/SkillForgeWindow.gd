extends CanvasLayer

## Кузница скиллов (Q36) — окно-конструктор пользовательских скиллов.
## Автолоад /root/SkillForgeWindow. Чек-лист ui_input_rules.md: скрыто при
## старте; is_open-флаг; открытие -> VISIBLE, закрытие -> CAPTURED
## (идиома NPCTeleporter._close_dialog); _process-гард; флаг окна в
## PlayerController._gui_blocks_capture(). Z-переключение живёт в зоне
## Logic/SkillForge.gd (вердикт: закрытие по Z работает при любом фокусе).
## Границы ползунков = константы SkillSerializer (SSOT границ, правило 10 PRP).

const SER := preload("res://Logic/Skills/SkillSerializer.gd")
const USDB := preload("res://Logic/Skills/UserSkillDB.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const ForgeList := preload("res://Graphics/SkillForgeList.gd")

const ICONS := ["🔥", "⚡", "☄️", "🔮", "💖", "🔦", "🌌", "🌪️", "💀"]
const TYPES := [
    ["spawn_projectile", "Снаряд"],
    ["homing_projectile", "Самонаводка"],
    ["homing_heal", "Лечение"],
    ["hitscan", "Луч"],
    ["aoe", "Взрыв"],
    ["teleport", "Телепорт"],
]
const ANIMS := ["", "Throw", "Cast_Shoot", "Heart_Cast"]

var is_open := false

var _edit_id := ""
var _type := "spawn_projectile"
var _icon := "🔥"

var _name: LineEdit
var _status: Label
var _params: VBoxContainer
var _list = null
var _p: Dictionary = {}  # контролы параметров текущего типа
var _type_btns: Dictionary = {}
var _icon_btns: Dictionary = {}
var _cast_time: SpinBox
var _range_v: SpinBox
var _shake: SpinBox
var _price: SpinBox
var _req_target: CheckButton
var _tt: OptionButton
var _anim: OptionButton
var _hand: OptionButton
var _alt: CheckButton
var _snd: OptionButton


func _ready() -> void:
    visible = false
    layer = 30
    _build_ui()


func open() -> void:
    is_open = true
    visible = true
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    _list.refresh()
    _status.text = ""


func close() -> void:
    is_open = false
    visible = false
    # МЫШЬ ССОТ v2: закрытие UI возвращает мышь в игру (NPCTeleporter-идиома).
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
    # Страховка ССОТ (копия SettingsMenu._process): открыто -> мышь видима.
    # Ловит только утечки будущего кода, нарушающего ССОТ.
    if is_open and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func load_from_dict(d: Dictionary) -> void:
    ## Правка существующего: форма заполняется из словаря (кнопка ✎ списка).
    _edit_id = str(d.get("id", ""))
    _name.text = str(d.get("name", ""))
    _icon = str(d.get("icon", "🔥"))
    if _icon.is_empty():
        _icon = "🔥"
    _sync_icon_buttons()
    _price.value = float(d.get("price", 1))
    _range_v.value = float(d.get("max_range", 200.0))
    _req_target.button_pressed = bool(d.get("requires_target", false))
    _tt.selected = 1 if str(d.get("target_type", "enemy")) == "ally" else 0
    _cast_time.value = float(d.get("cast_time", 0.0))
    _shake.value = float(d.get("shake", 0.0))
    _hand.selected = 1 if str(d.get("cast_hand", "Right")) == "Left" else 0
    _alt.button_pressed = bool(d.get("alternate_hands", false))
    var ca := str(d.get("cast_anim", ""))
    _anim.selected = ANIMS.find(ca) if ANIMS.has(ca) and ca != "" else 0
    var snd_idx := 0
    var effs = d.get("effects", [])
    if effs.size() > 0 and effs[0] is Dictionary:
        var t := str(effs[0].get("type", ""))
        var valid := false
        for tt in TYPES:
            if tt[0] == t:
                valid = true
        if valid:
            _set_type(t)
            _load_effect_params(effs[0])
    for e in effs:
        if e is Dictionary and str(e.get("type", "")) == "play_sound":
            snd_idx = SER.SOUNDS.find(str(e.get("stream", ""))) + 1
    _snd.selected = snd_idx
    _status.text = "Правка: %s (сохранение перезапишет)" % _edit_id


func notify_deleted(id: String) -> void:
    if _edit_id == id:
        _edit_id = ""
    _status.text = "Скилл удалён (из купленных исчезнет после перезапуска игры)"


# ---------- сборка UI ----------

func _build_ui() -> void:
    var root := Control.new()
    root.name = "ForgeRoot"
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)
    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    var panel := PanelContainer.new()
    center.add_child(panel)
    var vb := VBoxContainer.new()
    vb.add_theme_constant_override("separation", 6)
    panel.add_child(vb)

    var head := HBoxContainer.new()
    var title := Label.new()
    title.text = "🔥 Кузница скиллов"
    title.add_theme_font_size_override("font_size", 22)
    head.add_child(title)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(spacer)
    var xbtn := Button.new()
    xbtn.text = "✖ Закрыть (Z)"
    xbtn.pressed.connect(close)
    head.add_child(xbtn)
    vb.add_child(head)

    _status = Label.new()
    vb.add_child(_status)

    var cols := HBoxContainer.new()
    cols.add_theme_constant_override("separation", 10)
    vb.add_child(cols)

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(560, 520)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    cols.add_child(scroll)
    var form := VBoxContainer.new()
    form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    form.add_theme_constant_override("separation", 4)
    scroll.add_child(form)
    _build_form(form)

    _list = ForgeList.new(self)
    _list.custom_minimum_size = Vector2(300, 520)
    cols.add_child(_list)


func _build_form(form: VBoxContainer) -> void:
    _name = LineEdit.new()
    _name.max_length = 24
    _name.placeholder_text = "Имя скилла"
    form.add_child(_name)

    var ic_box := HBoxContainer.new()
    var icg := ButtonGroup.new()
    for i in ICONS.size():
        var b := Button.new()
        b.text = ICONS[i]
        b.toggle_mode = true
        b.button_group = icg
        b.pressed.connect(_set_icon.bind(ICONS[i], b))
        ic_box.add_child(b)
        _icon_btns[ICONS[i]] = b
        if i == 0:
            b.button_pressed = true
    form.add_child(ic_box)

    form.add_child(_mk_label("Тип скилла"))
    var tg := ButtonGroup.new()
    var tgrid := GridContainer.new()
    tgrid.columns = 3
    for t in TYPES:
        var b := Button.new()
        b.text = t[1]
        b.toggle_mode = true
        b.button_group = tg
        b.pressed.connect(_set_type.bind(t[0]))
        tgrid.add_child(b)
        _type_btns[t[0]] = b
        if t[0] == _type:
            b.button_pressed = true
    form.add_child(tgrid)

    form.add_child(_mk_label("Параметры"))
    _params = VBoxContainer.new()
    form.add_child(_params)

    _cast_time = _spin(form, "Канал, сек (0 = инста)", SER.CLAMP_CAST_TIME.x, SER.CLAMP_CAST_TIME.y, 0.1, 0.0)
    _range_v = _spin(form, "Дальность, м", SER.CLAMP_RANGE.x, SER.CLAMP_RANGE.y, 1.0, 200.0)
    _shake = _spin(form, "Тряска экрана", SER.CLAMP_SHAKE.x, SER.CLAMP_SHAKE.y, 0.05, 0.0)
    var anim_items := ["нет"]
    for a in ANIMS:
        if a != "":
            anim_items.append(a)
    _anim = _opt(form, "Каст-анимация", anim_items)
    _hand = _opt(form, "Рука", ["Right", "Left"])
    _alt = _check(form, "Поочерёдно обеими руками")
    var snd_items := ["нет"]
    for s in SER.SOUNDS:
        snd_items.append(s.get_file().get_basename())
    _snd = _opt(form, "Звук каста", snd_items)
    _req_target = _check(form, "Требует прицеливания")
    _tt = _opt(form, "Цель", ["enemy", "ally"])
    _price = _spin(form, "Цена, SP", SER.CLAMP_PRICE.x, SER.CLAMP_PRICE.y, 1, 1)

    var cr := Button.new()
    cr.text = "⚒ Создать скилл"
    cr.pressed.connect(_on_create)
    form.add_child(cr)

    _rebuild_params()


func _rebuild_params() -> void:
    for c in _params.get_children():
        c.queue_free()
    _p.clear()
    match _type:
        "spawn_projectile":
            _p["scene"] = _opt(_params, "Внешность снаряда", _basenames(SER.PROJECTILE_SCENES))
            _p["from_hand"] = _check(_params, "Спавн из руки", true)
            _p["delay"] = _spin(_params, "Задержка спавна, сек", SER.CLAMP_SPAWN_DELAY.x, SER.CLAMP_SPAWN_DELAY.y, 0.05, 0.0)
            _p["impact_shake"] = _spin(_params, "Тряска при ударе", SER.CLAMP_SHAKE.x, SER.CLAMP_SHAKE.y, 0.05, 0.0)
            _p["impact_sound"] = _opt(_params, "Звук удара", ["нет"] + _basenames(SER.SOUNDS))
            _p["lava"] = _check(_params, "Лужа лавы")
        "homing_projectile", "homing_heal":
            _p["scene"] = _opt(_params, "Внешность снаряда", _basenames(SER.PROJECTILE_SCENES))
            _p["from_hand"] = _check(_params, "Спавн из руки", true)
            _p["delay"] = _spin(_params, "Задержка спавна, сек", SER.CLAMP_SPAWN_DELAY.x, SER.CLAMP_SPAWN_DELAY.y, 0.05, 0.0)
        "hitscan":
            _p["damage"] = _spin(_params, "Урон", SER.CLAMP_DAMAGE.x, SER.CLAMP_DAMAGE.y, 1, 30)
            _p["from_hand"] = _check(_params, "Из руки", true)
            _p["delay"] = _spin(_params, "Задержка, сек", SER.CLAMP_SPAWN_DELAY.x, SER.CLAMP_SPAWN_DELAY.y, 0.05, 0.0)
        "aoe":
            _p["radius"] = _spin(_params, "Радиус, м", SER.CLAMP_RADIUS.x, SER.CLAMP_RADIUS.y, 0.5, 5.0)
            _p["damage"] = _spin(_params, "Урон", SER.CLAMP_DAMAGE.x, SER.CLAMP_DAMAGE.y, 1, 30)
            _p["vfx"] = _opt(_params, "VFX взрыва", ["нет"] + _basenames(SER.VFX_SCENES))
        "teleport":
            _p["vfx"] = _opt(_params, "VFX телепорта", ["нет"] + _basenames(SER.VFX_SCENES))


func _set_type(t: String) -> void:
    _type = t
    if _type_btns.has(t):
        _type_btns[t].set_pressed_no_signal(true)
    _rebuild_params()


func _set_icon(ic: String, _b: Button) -> void:
    _icon = ic


func _sync_icon_buttons() -> void:
    if _icon_btns.has(_icon):
        for ic in _icon_btns:
            _icon_btns[ic].set_pressed_no_signal(ic == _icon)


# ---------- сборка словаря и сохранение ----------

func _on_create() -> void:
    var d := _build_dict()
    if not USDB.save_skill(d):
        _status.text = "Ошибка сохранения (см. лог)"
        return
    var s = SER.skill_from_dict(d)
    var id := str(d["id"])
    if SDB.get_skills().has(id):
        SDB.replace(id, s)
    else:
        SDB.register(id, s)
    _edit_id = id
    _status.text = "Готово: «%s» (%d SP). Открой магазин скиллов и купи его." % [
        str(d["name"]), int(d["price"])
    ]
    _list.refresh()


func _build_dict() -> Dictionary:
    var nm := _name.text.strip_edges()
    if nm.is_empty():
        nm = "Мой скилл"
    var id := _edit_id if _edit_id != "" else USDB.generate_id(nm)
    var effs: Array = []
    match _type:
        "spawn_projectile":
            effs.append({
                "type": "spawn_projectile",
                "scene": SER.PROJECTILE_SCENES[maxi(0, _p["scene"].selected)],
                "spawn_from_hand": _p["from_hand"].button_pressed,
                "spawn_delay": _p["delay"].value,
                "impact_shake": _p["impact_shake"].value,
                "impact_sound": _sound_path(_p["impact_sound"].selected),
                "lava_pool": _p["lava"].button_pressed,
            })
        "homing_projectile", "homing_heal":
            effs.append({
                "type": _type,
                "scene": SER.PROJECTILE_SCENES[maxi(0, _p["scene"].selected)],
                "spawn_from_hand": _p["from_hand"].button_pressed,
                "spawn_delay": _p["delay"].value,
            })
        "hitscan":
            effs.append({
                "type": "hitscan",
                "damage": int(_p["damage"].value),
                "spawn_from_hand": _p["from_hand"].button_pressed,
                "spawn_delay": _p["delay"].value,
            })
        "aoe":
            effs.append({
                "type": "aoe",
                "radius": _p["radius"].value,
                "damage": int(_p["damage"].value),
                "vfx": _vfx_path(_p["vfx"].selected),
            })
        "teleport":
            effs.append({
                "type": "teleport",
                "vfx": _vfx_path(_p["vfx"].selected),
            })
    if _snd.selected > 0:
        effs.append({"type": "play_sound", "stream": SER.SOUNDS[_snd.selected - 1], "volume_db": 0.0})
    var anim := ""
    if _anim.selected > 0:
        anim = ANIMS[_anim.selected]
    return {
        "id": id,
        "name": nm,
        "icon": _icon,
        "price": int(_price.value),
        "max_range": _range_v.value,
        "requires_target": _req_target.button_pressed,
        "target_type": ["enemy", "ally"][_tt.selected],
        "cast_anim": anim,
        "cast_time": _cast_time.value,
        "cast_hand": ["Right", "Left"][_hand.selected],
        "alternate_hands": _alt.button_pressed,
        "shake": _shake.value,
        "effects": effs,
    }


func _load_effect_params(e: Dictionary) -> void:
    var t := str(e.get("type", ""))
    match t:
        "spawn_projectile":
            _p["scene"].selected = maxi(0, SER.PROJECTILE_SCENES.find(str(e.get("scene", ""))))
            _p["from_hand"].button_pressed = bool(e.get("spawn_from_hand", false))
            _p["delay"].value = float(e.get("spawn_delay", 0.0))
            _p["impact_shake"].value = float(e.get("impact_shake", 0.0))
            _p["impact_sound"].selected = SER.SOUNDS.find(str(e.get("impact_sound", ""))) + 1
            _p["lava"].button_pressed = bool(e.get("lava_pool", false))
        "homing_projectile", "homing_heal":
            _p["scene"].selected = maxi(0, SER.PROJECTILE_SCENES.find(str(e.get("scene", ""))))
            _p["from_hand"].button_pressed = bool(e.get("spawn_from_hand", false))
            _p["delay"].value = float(e.get("spawn_delay", 0.0))
        "hitscan":
            _p["damage"].value = float(e.get("damage", 30))
            _p["from_hand"].button_pressed = bool(e.get("spawn_from_hand", false))
            _p["delay"].value = float(e.get("spawn_delay", 0.0))
        "aoe":
            _p["radius"].value = float(e.get("radius", 5.0))
            _p["damage"].value = float(e.get("damage", 30))
            _p["vfx"].selected = SER.VFX_SCENES.find(str(e.get("vfx", ""))) + 1
        "teleport":
            _p["vfx"].selected = SER.VFX_SCENES.find(str(e.get("vfx", ""))) + 1


# ---------- мелкие хелперы ----------

func _mk_label(t: String) -> Label:
    var l := Label.new()
    l.text = t
    return l


func _spin(parent: Node, label_text: String, lo: float, hi: float, step: float, val: float) -> SpinBox:
    var row := HBoxContainer.new()
    var l := Label.new()
    l.text = label_text
    l.custom_minimum_size = Vector2(200, 0)
    row.add_child(l)
    var sb := SpinBox.new()
    sb.min_value = lo
    sb.max_value = hi
    sb.step = step
    sb.value = val
    row.add_child(sb)
    parent.add_child(row)
    return sb


func _opt(parent: Node, label_text: String, items: Array) -> OptionButton:
    var row := HBoxContainer.new()
    var l := Label.new()
    l.text = label_text
    l.custom_minimum_size = Vector2(200, 0)
    row.add_child(l)
    var ob := OptionButton.new()
    for it in items:
        ob.add_item(str(it))
    row.add_child(ob)
    parent.add_child(row)
    return ob


func _check(parent: Node, label_text: String, pressed := false) -> CheckButton:
    var cb := CheckButton.new()
    cb.text = label_text
    cb.button_pressed = pressed
    parent.add_child(cb)
    return cb


func _basenames(paths: Array) -> Array:
    var out: Array = []
    for p in paths:
        out.append(str(p).get_file().get_basename())
    return out


func _sound_path(sel: int) -> String:
    return SER.SOUNDS[sel - 1] if sel > 0 else ""


func _vfx_path(sel: int) -> String:
    return SER.VFX_SCENES[sel - 1] if sel > 0 else ""
