# Q22-C: генерация ели аддоном MTree (GoodPie fork 5.6.0, GPL-3.0 — инструмент,
# выходной меш наш; журнал ассетов docs/asset_sources.md). Headless-скрипт для
# Blender 5.1: quick_generate(PINE) → дубликат с применённым leaves-модификатором
# (хвоя реальной геометрией) → оригинал без модификатора (ствол) → материалы
# → экспорт GLTF_SEPARATE.
#
# Запуск из корня проекта:
#   & "D:\Programs\Blender Foundation\Blender 5.1\blender.exe" --background --python Generators/build_mtree_spruce.py -- <seed> <out_gltf>

import bpy
import sys

SEED = int(sys.argv[-2]) if len(sys.argv) >= 3 else 42
OUT = sys.argv[-1] if len(sys.argv) >= 3 else "tasks/261117_2355-089dca89/stock/modular_tree_560/spruce_raw.gltf"

EXT_MODULE = "bl_ext.user_default.modular_tree"


def enable_extension() -> None:
    import addon_utils
    mods = [m.__name__ for m in addon_utils.modules()
            if "modular_tree" in m.__name__]
    print("[MTREE] found modules:", mods)
    target = None
    for m in mods:
        if m.startswith("bl_ext."):
            target = m
            break
    if target is None:
        raise RuntimeError("modular_tree extension not found")
    prefs = bpy.context.preferences
    addon_prefs = prefs.addons.get(target)
    if addon_prefs is None:
        bpy.ops.preferences.addon_enable(module=target)
    print("[MTREE] enabled:", target)


def run_quick_generate() -> bpy.types.Object:
    res = bpy.ops.mtree.quick_generate(
        'EXEC_DEFAULT', preset="PINE", seed=SEED, add_leaves=True)
    print("[MTREE] quick_generate:", res)
    obj = bpy.context.active_object
    if obj is None or not obj.name.startswith("Tree_"):
        raise RuntimeError("quick_generate failed: active=%s" %
                           (obj.name if obj else None))
    print("[MTREE] tree object:", obj.name,
          "| polys:", len(obj.data.polygons),
          "| modifiers:", [m.name for m in obj.modifiers])
    return obj


def split_trunk_and_foliage(tree: bpy.types.Object):
    """Дубликат → применить leaves-модификатор (хвоя реальной геометрией);
    оригинал — снять модификатор (голый ствол). Возвращает (ствол, хвоя)."""
    mod_name = None
    for m in tree.modifiers:
        if m.type == 'NODES':
            mod_name = m.name
            break
    if mod_name is None:
        raise RuntimeError("no leaves modifier on tree")

    bpy.ops.object.select_all(action='DESELECT')
    tree.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.object.duplicate()
    foliage = bpy.context.active_object
    foliage.name = "Spruce_Foliage"

    bpy.context.view_layer.objects.active = foliage
    bpy.ops.object.modifier_apply(modifier=mod_name)
    # Удалить лист-исходник (инстанс-исходник больше не нужен после apply).
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Leaf_"):
            bpy.data.objects.remove(ob, do_unlink=True)

    bpy.context.view_layer.objects.active = tree
    bpy.ops.object.modifier_remove(modifier=mod_name)
    tree.name = "Spruce_Trunk"
    return tree, foliage


def assign_material(ob: bpy.types.Object, name: str, color) -> None:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.9
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.material_index = 0
    print("[MTREE] material %s -> %s (polys=%d)" %
          (name, ob.name, len(ob.data.polygons)))


def export(objects, path: str) -> None:
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLTF_SEPARATE',
        export_apply=False, use_selection=True,
        export_yup=True)
    print("[MTREE] exported:", path)


def main() -> None:
    enable_extension()
    # Чистая сцена: аддон-пресеты ожидают дефолтный контекст.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    enable_extension()  # после сброса сцены включаем заново

    tree = run_quick_generate()
    trunk, foliage = split_trunk_and_foliage(tree)

    # Статистика ДО экспорта (гейт полигонажа — смотреть честные числа).
    for ob in (trunk, foliage):
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print("[MTREE] STATS %s: verts=%d polys=%d tris=%d uvs=%d mats=%d" % (
            ob.name, len(ob.data.vertices), len(ob.data.polygons), tris,
            len(ob.data.uv_layers) if hasattr(ob.data, 'uv_layers') else 0,
            len(ob.data.materials)))

    assign_material(trunk, "MTree_Bark", (0.28, 0.20, 0.14, 1.0))
    assign_material(foliage, "MTree_Needles", (0.10, 0.22, 0.10, 1.0))

    export([trunk, foliage], OUT)
    print("[MTREE] DONE seed=%d out=%s" % (SEED, OUT))


main()
