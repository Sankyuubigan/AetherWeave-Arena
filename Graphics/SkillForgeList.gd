extends VBoxContainer

## «Мои скиллы» (Q36) — список пользовательских скиллов Кузницы.
## Паттерн SkillPresetsPanel: JSON через UserSkillDB; ряд = [иконка имя SP]
## [✎ загрузить в форму] [✖ удалить]. Удаление = delete_skill + unregister.

const USDB := preload("res://Logic/Skills/UserSkillDB.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")

var _win = null
var _rows: VBoxContainer


func _init(win) -> void:
    _win = win
    var title := Label.new()
    title.text = "Мои скиллы"
    title.add_theme_font_size_override("font_size", 18)
    add_child(title)
    var hint := Label.new()
    hint.text = "✎ — загрузить в форму, ✖ — удалить"
    hint.add_theme_font_size_override("font_size", 11)
    add_child(hint)
    _rows = VBoxContainer.new()
    _rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_rows)
    refresh()


func refresh() -> void:
    for c in _rows.get_children():
        c.queue_free()
    for d in USDB.list():
        _add_row(d)


func _add_row(d: Dictionary) -> void:
    var row := HBoxContainer.new()
    var lbl := Label.new()
    lbl.text = "%s %s (%d SP)" % [
        str(d.get("icon", "✨")),
        str(d.get("name", "?")),
        int(d.get("price", 1)),
    ]
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    row.add_child(lbl)
    var edit := Button.new()
    edit.text = "✎"
    edit.tooltip_text = "Загрузить в форму (правка)"
    edit.pressed.connect(func(): _win.load_from_dict(d))
    row.add_child(edit)
    var del := Button.new()
    del.text = "✖"
    del.tooltip_text = "Удалить"
    del.pressed.connect(func(): _delete(d))
    row.add_child(del)
    _rows.add_child(row)


func _delete(d: Dictionary) -> void:
    var id := str(d.get("id", ""))
    if USDB.delete_skill(id):
        SDB.unregister(id)
        _win.notify_deleted(id)
    refresh()
