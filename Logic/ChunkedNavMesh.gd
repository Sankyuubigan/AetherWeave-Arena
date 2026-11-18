class_name ChunkedNavMesh
extends RefCounted
## Чанковый навмеш (QUEUE.md Q7, одобрено юзером 19.11.26): базовый модуль под
## большие карты (>200×200, «у нас будут карты побольше потом»). Навмеш печётся
## ПО ЧАНКАМ из поддерева чанка — это даёт частичный ребейк при перестройке
## куска мира без бейка всей карты.
##
## Как: parse_source_geometry_data(nm, data, chunk_root) парсит ТОЛЬКО поддерево
## чанка (root_node = узел чанка: TerrainBuilder-чанки — StaticBody+trimesh,
## скаттер — StaticBody+цилиндры), затем синхронный bake (паттерн
## HellArena._add_navmesh, проверен в 4.8-beta). Параметры агента — единый
## профиль мобов. Все функции static (GDScript-статика не зовёт нестатическое —
## урок TerrainBuilder).

## Единый профиль навмеша мобов: капсула r=0.45 + запас; agent_height кратен
## cell_height (2.1 при 0.3 — иначе recast-варнинг точности); slope под рельеф
## 5 м амплитуды.
static func make_nav_mesh() -> NavigationMesh:
    var nm := NavigationMesh.new()
    nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS # 4.8-beta: префикс geometry_*
    nm.agent_radius = 0.6
    nm.agent_height = 2.1
    nm.agent_max_climb = 0.6
    nm.agent_max_slope = 46.0
    nm.cell_size = 0.3
    nm.cell_height = 0.3
    return nm

## Запечь чанк: chunk_root — поддерево со статическими коллайдерами чанка,
## region_parent — куда положить NavigationRegion3D (обычно сам чанк).
## Возвращает регион; navigation_mesh региона — готовый навмеш чанка.
static func bake_chunk(chunk_root: Node3D, region_parent: Node) -> NavigationRegion3D:
    var nm := make_nav_mesh()
    var data := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_data(nm, data, chunk_root)
    NavigationServer3D.bake_from_source_geometry_data(nm, data)
    var region := NavigationRegion3D.new()
    region.name = "NavRegion_%s" % chunk_root.name
    region.navigation_mesh = nm
    region_parent.add_child(region)
    return region

## Частичный ребейк при перестройке чанка: удалить/добавить коллайдеры в
## поддереве чанка и вызвать. Возвращает число полигонов нового навмеша.
## (get_edge_count в 4.8 НЕ существует — только get_polygon_count.)
static func rebake_chunk(region: NavigationRegion3D, chunk_root: Node3D) -> int:
    var nm := make_nav_mesh()
    var data := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_data(nm, data, chunk_root)
    NavigationServer3D.bake_from_source_geometry_data(nm, data)
    region.navigation_mesh = nm
    return nm.get_polygon_count()
