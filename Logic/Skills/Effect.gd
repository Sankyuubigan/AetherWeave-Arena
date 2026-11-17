extends Resource

# Базовый класс для всех эффектов
func apply(_caster: Node, _context: Dictionary) -> void:
    pass

## Позиция кости кисти кастера (для спавна снарядов из руки). Живая позиция
## на момент вызова — при отложенном спавне (spawn_delay) даёт точку выброса
## из анимации, а не из позы нажатия.
static func hand_pos(caster: Node, side: String) -> Vector3:
    var skel := find_skeleton(caster.get_node_or_null("GraphicsWrapper/PlayerModel"))
    if skel:
        var bi := skel.find_bone("mixamorig_%sHand" % side)
        if bi >= 0:
            return (skel.global_transform * skel.get_bone_global_pose(bi)).origin
    return caster.global_position + Vector3(0, 1.2, 0)  # фолбэк — центр тела

static func find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for c in node.get_children():
        var r := find_skeleton(c)
        if r:
            return r
    return null
