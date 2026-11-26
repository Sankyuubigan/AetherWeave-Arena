extends Resource

# Базовый класс для всех эффектов
func apply(_caster: Node, _context: Dictionary) -> void:
    pass

## Хук РЕЖИМА (26.11.26): эффект может выбрать клип каста по СВОЕМУ состоянию —
## у скилла одно поле cast_anim, а режимов бывает два (энергоклинок:
## материализация Throw / взмах A-B). "" = не выбирает, действует
## Skill.cast_anim. Очередь A/B при этом остаётся у каст-слоя: хук только
## подменяет имя клипа, продвижение очереди — в SpellCasterComponent.
## ВАЖНО: хук обязан быть ЧИСТЫМ (только чтение состояния), иначе повторный
## вызов (в т.ч. буфером ввода) съест режим.
func pick_cast_anim(_caster: Node, _skill) -> String:
    return ""

## Позиция кости кисти кастера (для спавна снарядов из руки). Живая позиция
## на момент вызова — при отложенном спавне (spawn_delay) даёт точку выброса
## из анимации, а не из позы нажатия.
static func hand_pos(caster: Node, side: String) -> Vector3:
    if caster == null:
        return Vector3.ZERO
    var skel := find_skeleton(caster.get_node_or_null("GraphicsWrapper/PlayerModel"))
    if not skel:
        # Враги/FFA-боты: скин не под GraphicsWrapper/PlayerModel (латент Q10,
        # вскрыт смоуком MainArena 19.11.26) — ищем скелет по всему поддереву.
        skel = find_skeleton(caster)
    if skel:
        var bi := skel.find_bone("mixamorig_%sHand" % side)
        if bi >= 0:
            return (skel.global_transform * skel.get_bone_global_pose(bi)).origin
    return caster.global_position + Vector3(0, 1.2, 0)  # фолбэк — центр тела

static func find_skeleton(node: Node) -> Skeleton3D:
    if node == null:
        return null
    if node is Skeleton3D:
        return node
    for c in node.get_children():
        var r := find_skeleton(c)
        if r:
            return r
    return null
