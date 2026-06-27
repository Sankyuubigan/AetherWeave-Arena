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

    func _can_drop_data(at_position, data):
        # ИСПРАВЛЕНИЕ: Заменили typeof() на "data is Dictionary" для максимальной совместимости
        return data is Dictionary and data.has("type") and data["type"] == "skill"

    func _drop_data(at_position, data):
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
        if id == "fireball": label_skill.text = "🔥"
        elif id == "teleport": label_skill.text = "🌌"
        else: label_skill.text = ""

func _ready():
    name = "ActionBar"
    layer = 5
    
    var hbox = HBoxContainer.new()
    hbox.alignment = BoxContainer.ALIGNMENT_CENTER
    hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hbox.position.y = -80
    hbox.add_theme_constant_override("separation", 8)
    
    # ИСПРАВЛЕНИЕ: Сам контейнер (пустоты между слотами) теперь на 100% пропускает мышь
    hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hbox)
    
    for bind in key_bindings:
        var slot = ActionSlot.new()
        slot.key_info = bind
        hbox.add_child(slot)
        slots.append(slot)

func remove_skill(id: String):
    for slot in slots:
        if slot.skill_id == id:
            slot.set_skill("")

func _input(event):
    var menu = get_parent().get_node_or_null("SkillMenu")
    if menu and menu.is_open:
        return

    for slot in slots:
        if slot.skill_id == "": continue
        
        var is_pressed = false
        if slot.key_info["type"] == "key" and event is InputEventKey:
            if event.pressed and not event.echo and (event.keycode == slot.key_info["code"] or event.physical_keycode == slot.key_info["code"]):
                is_pressed = true
        elif slot.key_info["type"] == "mouse" and event is InputEventMouseButton:
            if event.pressed and event.button_index == slot.key_info["code"]:
                is_pressed = true

        if is_pressed:
            get_parent().use_skill(slot.skill_id)