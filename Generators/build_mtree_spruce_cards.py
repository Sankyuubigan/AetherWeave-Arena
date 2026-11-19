# Q22-C v2: MTree как ССОТ-скелет + дистрибуция точек, инстанс = НАША карточка
# (2 скрещённых квада, UV одного тайла атласа B) — спец-спека: иголки-геометрия
# НЕ декимируется (14.7M трис в v1), смена представления = карточки.
# Скелет: DECIMATE с delimit (AGENTS §6.5) 154K → ~1.5K.
#
# Запуск из корня проекта:
#   & "D:\Programs\Blender Foundation\Blender 5.1\blender.exe" --background --python Generators/build_mtree_spruce_cards.py -- <seed> <out_gltf> [atlas_png]

import bpy
import sys

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SEED = int(ARGS[0]) if len(ARGS) >= 1 else 42
OUT = ARGS[1] if len(ARGS) >= 2 else "tasks/261117_2355-089dca89/stock/modular_tree_560/spruce_cards.gltf"
ATLAS = ARGS[2] if len(ARGS) >= 3 else "Graphics/Environment/Props/pine_tree_01/pine_tree_01_foliage_diff_B.png"
ORM = ATLAS.replace("diff_B", "orm_B")  # рядом с диффузом, тот же каталог

EXT_MODULE = "bl_ext.user_default.modular_tree"
# Тайл 512 атласа 1024 (v4: все тайлы зелёные) + inset против каймы соседей.
TILE = 0.5
INSET = 0.012


def enable_extension() -> None:
    import addon_utils
    mods = [m.__name__ for m in addon_utils.modules()
            if "modular_tree" in m.__name__ and m.__name__.startswith("bl_ext.")]
    if not mods:
        raise RuntimeError("modular_tree extension not found")
    if bpy.context.preferences.addons.get(mods[0]) is None:
        bpy.ops.preferences.addon_enable(module=mods[0])
    print("[MTREE] enabled:", mods[0])


def make_card(name: str, size_min: float, size_max: float) -> bpy.types.Object:
    """Одна карточка = 2 скрещённых квада, droop 0.35, UV = тайл атласа."""
    import random
    rng = random.Random(SEED)
    s = rng.uniform(size_min, size_max)
    h = s / 2.0
    u0, v0 = INSET, INSET
    u1, v1 = TILE - INSET, TILE - INSET
    # Квад в плоскости XY, вершины: (±h, 0, z) — вертикальная карточка
    # вдоль Z с лёгким droop (нижние края расходятся).
    verts = [
        (-h, 0.0, -h * 0.9), (h, 0.0, -h), (h, 0.0, h), (-h, 0.0, h * 0.9),
        (0.0, -h, -h * 0.9), (0.0, h, -h), (0.0, h, h), (0.0, -h, h * 0.9),
    ]
    faces = [(0, 1, 2, 3), (4, 5, 6, 7)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    uv = mesh.uv_layers.new()
    quad_uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for li in range(8):
        uv.data[li].uv = quad_uv[li % 4]
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def make_foliage_material(name: str) -> bpy.types.Material:
    """Хвоя: атлас B в Base Color, Roughness из ORM.G (наш ORM: R=AO/G=rough/B=metal).
    Alpha CLIP 0.45, cull off — как наш build_env_prop (scissor 0.45, cull DISABLED)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ATLAS, check_existing=True)
    tex.extension = 'EXTEND'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.image = bpy.data.images.load(ORM, check_existing=True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.9
    mat.blend_method = 'CLIP'
    mat.alpha_threshold = 0.45
    mat.use_backface_culling = False
    return mat


def main() -> None:
    enable_extension()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    enable_extension()

    # 1. Скелет БЕЗ листьев (operator сам лист не создаёт при add_leaves=False).
    res = bpy.ops.mtree.quick_generate(
        'EXEC_DEFAULT', preset="PINE", seed=SEED, add_leaves=False)
    tree = bpy.context.active_object
    if tree is None or not tree.name.startswith("Tree_"):
        raise RuntimeError("quick_generate failed: %s" % res)
    print("[MTREE] skeleton:", tree.name, "polys:", len(tree.data.polygons))

    # 2. Наша карточка вместо иголки + дистрибуция из аддона (radius/direction
    #    атрибуты скелета уже на меше).
    card = make_card("FoliageCard", 0.8, 1.3)
    from bl_ext.user_default.modular_tree.python_classes.resources import node_groups as mt_ng
    # max_radius=0.03 как в пресете PINE (листья ТОЛЬКО на прутьях <3см; без
    # него дефолт раскидывает по всем веткам → 70K инстансов / 282K трис).
    mt_ng.distribute_leaves(tree, leaf_object=card, density=4.0, scale=1.0,
                            distribution_mode=0, enable_normal_transfer=True,
                            max_radius=0.03)
    # density — НА МЕТР ветки: ветки PINE ~140 м → density 4 ≈ 550 инстансов
    # × 4 триса ≈ 2200 (как у A/B).
    mod = tree.modifiers.get(mt_ng.LEAVES_MODIFIER_NAME)
    print("[MTREE] leaves modifier:", mod.name if mod else None)

    # 3. Хвоя: применить модификатор на дубликате (реальная геометрия).
    bpy.ops.object.select_all(action='DESELECT')
    tree.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.object.duplicate()
    foliage = bpy.context.active_object
    foliage.name = "Spruce_Foliage"
    bpy.context.view_layer.objects.active = foliage
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(card, do_unlink=True)

    # 4. Ствол: DECIMATE collapse c delimit (AGENTS §6.5) 154K → ~1.5K.
    #    БЕЗ UV/SEAM: у коры плоский цвет (атлас-UV переупакует optimize на
    #    bake-стадии), а UV-делimiter сковал коллапс (154K → всего 32.8K).
    bpy.context.view_layer.objects.active = tree
    tree.name = "Spruce_Trunk"
    dec = tree.modifiers.new("Decimate", 'DECIMATE')
    dec.delimit = set()  # кора плоскоцветная, UV переупакует optimize (§6.5-делimit
    # для фотосканов с текстурой; здесь UV C++-меша выбрасывается)
    dec.use_collapse_triangulate = False
    dec.ratio = 0.008
    bpy.ops.object.modifier_apply(modifier="Decimate")

    # 5. Материалы: ствол — коричневый (в baked-конвейере перекроем бейком),
    #    хвоя — атлас B (текстура уедет в glTF напрямую).
    bark = bpy.data.materials.new("MTree_Bark")
    bark.use_nodes = True
    bsdf = bark.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.28, 0.20, 0.14, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    tree.data.materials.clear()
    tree.data.materials.append(bark)
    foliage.data.materials.clear()
    foliage.data.materials.append(make_foliage_material("MTree_Cards"))

    # 6. Статистика (гейт полигонажа).
    for ob in (tree, foliage):
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print("[MTREE] STATS %s: verts=%d polys=%d tris=%d uvs=%d" % (
            ob.name, len(ob.data.vertices), len(ob.data.polygons), tris,
            len(ob.data.uv_layers)))

    # 7. Экспорт выбранных.
    bpy.ops.object.select_all(action='DESELECT')
    for ob in (tree, foliage):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLTF_SEPARATE',
                              export_apply=False, use_selection=True,
                              export_yup=True)
    print("[MTREE] exported:", OUT)

    # 8. Воркбенч-пробы вида (TEXTURE — показывает атлас на карточках):
    #    far целиком + close крона. Workbench рендерит в background без GPU.
    import os
    render_dir = os.path.dirname(OUT)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 960
    cam = bpy.data.cameras.new("ProbeCam")
    cam_ob = bpy.data.objects.new("ProbeCam", cam)
    scene.collection.objects.link(cam_ob)
    scene.camera = cam_ob
    import mathutils
    height = 16.0  # trunk length 14 + крона
    for tag, pos, look in [
        ("far", (28.0, -28.0, 10.0), (0.0, 0.0, 8.0)),
        ("close", (7.0, -7.0, 9.0), (0.0, 0.0, 10.0)),
    ]:
        cam_ob.location = pos
        d = mathutils.Vector(look) - mathutils.Vector(pos)
        cam_ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(render_dir, "spruce_cards_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("[MTREE] render:", scene.render.filepath)

    print("[MTREE] DONE seed=%d out=%s" % (SEED, OUT))


main()
