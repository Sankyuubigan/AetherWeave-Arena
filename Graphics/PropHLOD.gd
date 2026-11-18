extends StaticBody3D

## HLOD-фейк (фишка из демо 3d/visibility_ranges): проп плавно гаснет с дистанции
## (FADE_SELF + margin), дальние пропы не рисуются. Диапазон — от диагонали
## AABB меша с учётом масштаба пропа: мелкие (фон) короче, хиро длиннее.
## Скрипт-апликатор вешается генератором сцены на одобренные префабы (после
## instantiate), т.к. pack() не сериализует настройки вложенных узлов префаба.

func _ready() -> void:
    var s := basis.get_scale().abs()
    var k: float = maxf(s.x, maxf(s.y, s.z))
    _apply(self, k)

func _apply(node: Node, scale_k: float) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh:
            var diag: float = mi.get_aabb().size.length() * scale_k
            mi.visibility_range_end = clampf(diag * 50.0, 120.0, 350.0)
            mi.visibility_range_end_margin = mi.visibility_range_end * 0.08
            mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    for c in node.get_children():
        _apply(c, scale_k)
