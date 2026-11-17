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
        
        update_visuals()

    func _gui_input(event):
        if event is InputEventMouseButton and event.pressed:
            if event.button_index == MOUSE_BUTTON_LEFT:
                menu.buy_skill(skill_data["id"], skill_data["price"])
                update_visuals()
            elif event.button_index == MOUSE_BUTTON_RIGHT:
                menu.sell_skill(skill_data["id"], skill_data["price"])
                update_visuals()

    func update_visuals():
        var is_unlocked = menu.player.unlocked_skills.get(skill_data["id"], false)
        if is_unlocked:
            color = Color(0.2, 0.6, 0.2, 1.0)
        else:
            color = Color(0.2, 0.2, 0.2, 1.0)
            
        var status = "ИЗУЧЕНО" if is_unlocked else "Не изучено (Цена: " + str(skill_data["price"]) + " SP)"
        
        # Собираем всплывающую подсказку с описанием
        tooltip_text = skill_data["name"] + "\n"
        var desc = skill_data.get("description", "")
        if desc != "":
            tooltip_text += desc + "\n"
        tooltip_text += "\n" + status + "\n\n[ЛКМ] Купить | [ПКМ] Продать"
        
        if skill_data["id"] != "double_jump":
            tooltip_text += "\nПеретащите на нижнюю панель"

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
    
    var all_skills = SkillDB.get_skills()
    for s_id in all_skills:
        var skill_obj = all_skills[s_id]
        var slot = SkillSlot.new()
        slot.skill_data = {
            "id": skill_obj.id,
            "price": skill_obj.price,
            "name": skill_obj.skill_name,
            "icon": skill_obj.icon,
            "description": skill_obj.description
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
## в поле, а не закрывает окно.
func _unhandled_input(event):
    if event is InputEventKey and event.pressed and event.keycode == KEY_N:
        is_open = !is_open

        if is_open:
            panel.show()
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
            refresh_grid()
            refresh_sp()
            presets_panel.refresh()
        else:
            panel.hide()
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)