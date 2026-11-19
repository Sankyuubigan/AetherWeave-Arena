# Q22-C v5: скелет MTree с КОНТРОЛИРУЕМЫМ мешером (radial 7, resolution явно,
# smooth 2 — оператор хардкодил 32 → 154K трис) + СВОЯ geo-nodes дистрибуция
# карточек (аддонова distribute_leaves в Blender 5.1 молча пишет ID-пропы
# вместо RNA-инпутов → density/scale/max_radius игнорируются, работают дефолты
# нод-группы 200/м² × scale 0.1 = 38.8K инстансов).
#
# Запуск из корня проекта:
#   & "D:\Programs\Blender Foundation\Blender 5.1\blender.exe" --background --python Generators/build_mtree_spruce_cards2.py -- <seed> <out_gltf> <atlas_png>

import math
import os
import sys

import bpy
import mathutils

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SEED = int(ARGS[0]) if len(ARGS) >= 1 else 42
OUT = ARGS[1] if len(ARGS) >= 2 else "tasks/261117_2355-089dca89/stock/modular_tree_560/spruce_cards.gltf"
ATLAS = ARGS[2] if len(ARGS) >= 3 else "Graphics/Environment/Props/pine_tree_01/pine_tree_01_foliage_diff_B.png"
ORM = ATLAS.replace("diff_B", "orm_B")

TILE = 0.5      # атлас 1024 = 4 тайла 512
INSET = 0.012
DENSITY = 15.0  # ель-колонна: кора ~40 м² × 15 × ~0.9 → ~540 карт × 4 триса ≈ 2160
MAX_RADIUS = 0.08  # карточки на прутьях/ветках <8см; толще — несёт ствол-меш
THICK_R = 0.08     # сплит ствола: radius > THICK_R — декимируемая труба
SCALE_MIN, SCALE_MAX = 0.8, 1.3


def enable_extension() -> None:
    import addon_utils
    mods = [m.__name__ for m in addon_utils.modules()
            if "modular_tree" in m.__name__ and m.__name__.startswith("bl_ext.")]
    if not mods:
        raise RuntimeError("modular_tree extension not found")
    if bpy.context.preferences.addons.get(mods[0]) is None:
        bpy.ops.preferences.addon_enable(module=mods[0])


def build_skeleton(seed: int) -> bpy.types.Object:
    """Реплика QuickGenerateTree._generate_tree, но с лёгким мешером и
    явным resolution на функциях ветвления."""
    from m_tree import m_tree
    from bl_ext.user_default.modular_tree.python_classes.presets import tree_presets as tp
    from bl_ext.user_default.modular_tree.python_classes.mesh_utils import create_mesh_from_cpp

    preset = tp.TREE_PRESETS["PINE"]

    # Ветвления: вложенные структуры (distribution/gravity/split/crown) —
    # только через штатный ремап аддона, голый setattr падает AttributeError.
    trunk = m_tree.TrunkFunction()
    trunk.seed = seed
    tp.apply_trunk_preset(trunk, "PINE")
    trunk.resolution = 6   # вдоль ствола (дефолт тяжелее)

    branches = m_tree.BranchFunction()
    branches.seed = seed + 1
    tp.apply_preset(branches, "PINE")
    branches.resolution = 4
    # Ель-силуэт: пресет PINE даёт горизонтальные мутовки (шар) — прижимаем
    # ветки к стволу и укорачиваем (MTREE_SHAPE=1); 0 = пресет как есть.
    if os.environ.get("MTREE_SHAPE") == "1":
        # угол/длина — PropertyWrapper-поля, gravity — nested; только через
        # штатный сеттер пресетов (голый setattr = TypeError C++-биндинга).
        tp._set_branch_param(branches, "start_angle", 45)
        tp._set_branch_param(branches, "length", 4.5)
        tp._set_branch_param(branches, "gravity_strength", 8)
        tp._set_branch_param(branches, "start", 0.12)  # крона от 12% высоты

    if preset.sub_branches:
        sub = m_tree.BranchFunction()
        sub.seed = seed + 2
        tp.apply_sub_branch_preset(sub, "PINE")
        sub.resolution = 2
        if os.environ.get("MTREE_SHAPE") == "1":
            tp._set_branch_param(sub, "start_angle", 35)
            tp._set_branch_param(sub, "length", 1.6)
        branches.add_child(sub)

    trunk.add_child(branches)
    tree = m_tree.Tree()
    tree.set_trunk_function(trunk)
    tree.execute_functions()

    mesher = m_tree.ManifoldMesher()
    mesher.radial_n_points = 7   # оператор хардкодил 32 → 154K трис
    mesher.smooth_iterations = 2
    cpp_mesh = mesher.mesh_tree(tree)

    mesh = bpy.data.meshes.new("Spruce_Trunk")
    obj = bpy.data.objects.new("Spruce_Trunk", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    create_mesh_from_cpp(mesh, cpp_mesh)
    # Швы мешера = дублированные вершины: DECIMATE collapse через них не
    # коллапсит (пол 26% при любом ratio) — сварить перед декиматом.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    attrs = [a.name for a in mesh.attributes]
    print("[MTREE] skeleton attrs:", attrs)
    if "radius" not in attrs:
        raise RuntimeError("no radius attribute on skeleton mesh")
    return obj


def build_foliage_mesh(points, name: str) -> bpy.types.Object:
    """Хвоя В PYTHON: на каждую точку дистрибуции — карточка (2 скрещённых
    квада с droop), рандом-поворот/масштаб, UV одного тайла атласа.
    Geo-nodes-инстансинг (ObjectInfo+InstanceOnPoints+Realize) в Blender 5.1
    headless даёт 0 инстансов при живой дистрибуции — сборка в python."""
    import random
    from mathutils import Euler, Matrix, Vector
    rng = random.Random(SEED * 1000 + 7)
    verts_out, faces_out, uv_out = [], [], []
    u0, v0, u1, v1 = INSET, INSET, TILE - INSET, TILE - INSET
    quad_uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for i, p in enumerate(points):
        rx, ry, rz = (rng.uniform(-math.pi, math.pi) for _ in range(3))
        s = rng.uniform(SCALE_MIN, SCALE_MAX)
        h = s / 2.0
        local = [
            (-h, 0.0, -h * 0.9), (h, 0.0, -h), (h, 0.0, h), (-h, 0.0, h * 0.9),
            (0.0, -h, -h * 0.9), (0.0, h, -h), (0.0, h, h), (0.0, -h, h * 0.9),
        ]
        rot = Euler((rx, ry, rz)).to_matrix().to_4x4()
        for vi, lv in enumerate(local):
            w = rot @ Vector(lv)
            verts_out.append(tuple(w + Vector(p)))
        base = i * 8
        faces_out.append((base + 0, base + 1, base + 2, base + 3))
        faces_out.append((base + 4, base + 5, base + 6, base + 7))
        uv_out += quad_uv + quad_uv
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts_out, [], faces_out)
    uv = mesh.uv_layers.new()
    for li, uvv in enumerate(uv_out):
        uv.data[li].uv = uvv
    mesh.update()
    mesh.validate(verbose=False)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    print("[MTREE] foliage python-built: cards=%d verts=%d polys=%d" % (
        len(points), len(verts_out), len(faces_out)))
    return ob


def count_points(tree: bpy.types.Object, use_filter: bool):
    """Счётчик дистрибуции: dist→[filter]→points-to-verts→mesh. Считаем
    ВЕРШИНЫ (p2v отдаёт вершины без полигонов — polygons всегда 0)."""
    tag = "Filtered" if use_filter else "Raw"
    ng = bpy.data.node_groups.new("CountPoints_" + tag, 'GeometryNodeTree')
    ng.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n_in = ng.nodes.new("NodeGroupInput")
    n_out = ng.nodes.new("NodeGroupOutput")
    n_dist = ng.nodes.new("GeometryNodeDistributePointsOnFaces")
    n_dist.inputs["Density"].default_value = DENSITY
    n_dist.inputs["Seed"].default_value = SEED
    n_dist.distribute_method = 'RANDOM'
    L = ng.links
    L.new(n_in.outputs["Geometry"], n_dist.inputs["Mesh"])
    dst = n_dist.outputs["Points"]
    if use_filter:
        n_radius = ng.nodes.new("GeometryNodeInputNamedAttribute")
        n_radius.data_type = 'FLOAT'
        n_radius.inputs["Name"].default_value = "radius"
        n_sample = ng.nodes.new("GeometryNodeSampleNearestSurface")
        n_sample.data_type = 'FLOAT'
        n_gt = ng.nodes.new("ShaderNodeMath")
        n_gt.operation = 'GREATER_THAN'
        n_gt.inputs[1].default_value = MAX_RADIUS
        n_del = ng.nodes.new("GeometryNodeDeleteGeometry")
        n_del.domain = 'POINT'
        n_del.mode = 'ALL'
        L.new(n_dist.outputs["Points"], n_sample.inputs["Sample Position"])
        L.new(n_in.outputs["Geometry"], n_sample.inputs["Mesh"])
        L.new(n_radius.outputs["Attribute"], n_sample.inputs["Value"])
        L.new(n_sample.outputs["Value"], n_gt.inputs[0])
        L.new(dst, n_del.inputs["Geometry"])
        L.new(n_gt.outputs["Value"], n_del.inputs["Selection"])
        dst = n_del.outputs["Geometry"]
    n_p2v = ng.nodes.new("GeometryNodePointsToVertices")
    L.new(dst, n_p2v.inputs["Points"])
    L.new(n_p2v.outputs["Mesh"], n_out.inputs["Geometry"])
    mod = tree.modifiers.new("Count_" + tag, 'NODES')
    mod.node_group = ng
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = tree.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)  # p2v = только вершины!
    pts = [tuple(v.co) for v in me.vertices]
    ev.to_mesh_clear()
    print("[MTREE] points %s: %d" % (tag, n))
    tree.modifiers.remove(mod)
    bpy.data.node_groups.remove(ng)
    return n, pts


def make_foliage_material(name: str) -> bpy.types.Material:
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

    tree = build_skeleton(SEED)
    n_raw, _ = count_points(tree, use_filter=False)
    n_pts, pts = count_points(tree, use_filter=True)
    print("[MTREE] dist: raw=%d filtered=%d (density=%.1f max_radius=%.2f)" % (
        n_raw, n_pts, DENSITY, MAX_RADIUS))
    foliage = build_foliage_mesh(pts, "Spruce_Foliage")

    # СТВОЛ: сплит по radius-атрибуту. Тонкие прутья (<THICK_R) выбрасываем —
    # их закрывают карточки (MAX_RADIUS == THICK_R). Толстая труба декимируется
    # свободно (диаметры >> рёбер, инверсий нет). DECIMATE на тонких трубах
    # даёт растянутые шипы (§6.5) — потому сплит ДО декимата.
    import bmesh

    def _fill_holes(mesh, max_sides=12):
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bnd = [e for e in bm.edges if e.is_boundary]
        n = len(bnd)
        bmesh.ops.holes_fill(bm, edges=bnd, sides=max_sides)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        return n

    def _split_thick(src, name, th):
        bm = bmesh.new()
        bm.from_mesh(src.data)
        rad = bm.verts.layers.float.get("radius")
        if rad is None:
            raise RuntimeError("no radius layer in bmesh")
        keep = [f for f in bm.faces if all(v[rad] > th for v in f.verts)]
        vmap = {}
        bm2 = bmesh.new()
        for f in keep:
            vs = []
            for v in f.verts:
                nv = vmap.get(v)
                if nv is None:
                    nv = bm2.verts.new(v.co)
                    vmap[v] = nv
                vs.append(nv)
            try:
                bm2.faces.new(vs)
            except ValueError:
                pass  # дубль-грань на шве
        me2 = bpy.data.meshes.new(name)
        bm2.to_mesh(me2)
        bm2.free()
        bm.free()
        ob = bpy.data.objects.new(name, me2)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def _tris(ob):
        return sum(len(pp.vertices) - 2 for pp in ob.data.polygons)

    trunk = _split_thick(tree, "Spruce_Trunk_Thick", THICK_R)
    n_bnd = _fill_holes(trunk.data, max_sides=12)
    print("[MTREE] thick trunk: tris=%d boundary-filled(%d)" % (_tris(trunk), n_bnd))
    bpy.data.objects.remove(tree, do_unlink=True)  # тонкая часть — выброс

    # Мульти-проход fill+decimate до ≤3.5K (хиро-норма): collapse оставляет
    # новые boundary — каждый проход снимает пин.
    for it in range(6):
        if _tris(trunk) <= 3500:
            break
        dec = trunk.modifiers.new("Decimate%d" % it, 'DECIMATE')
        dec.delimit = set()
        dec.use_collapse_triangulate = False
        dec.ratio = 0.5 if it == 0 else 0.3
        dg = bpy.context.evaluated_depsgraph_get()
        ev = trunk.evaluated_get(dg)
        trunk.data = bpy.data.meshes.new_from_object(
            ev, preserve_all_data_layers=True, depsgraph=dg)
        trunk.modifiers.clear()
        n_bnd = _fill_holes(trunk.data, max_sides=12)
        print("[MTREE] trunk pass %d: tris=%d boundary=%d" % (
            it, _tris(trunk), n_bnd))
    trunk.name = "Spruce_Trunk"

    bark = bpy.data.materials.new("MTree_Bark")
    bark.use_nodes = True
    bsdf = bark.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.28, 0.20, 0.14, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    trunk.data.materials.clear()
    trunk.data.materials.append(bark)
    foliage.data.materials.clear()
    foliage.data.materials.append(make_foliage_material("MTree_Cards"))

    for ob in (trunk, foliage):
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print("[MTREE] STATS %s: verts=%d polys=%d tris=%d uvs=%d" % (
            ob.name, len(ob.data.vertices), len(ob.data.polygons), tris,
            len(ob.data.uv_layers)))

    bpy.ops.object.select_all(action='DESELECT')
    for ob in (trunk, foliage):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLTF_SEPARATE',
                              export_apply=False, use_selection=True,
                              export_yup=True)
    print("[MTREE] exported:", OUT)

    # Blender 5.1 glTF exporter НЕ пишет alphaMode (проверено мини-тестом:
    # blend_method='CLIP' + surface_render_method='DITHERED' + явный Alpha-линк
    # → gltf без alphaMode). Пост-патч JSON по имени материала — как uri-правки §9.
    import json as _json
    with open(OUT, "r", encoding="utf-8") as f:
        g = _json.load(f)
    patched = 0
    for m in g.get("materials", []):
        if m.get("name") == "MTree_Cards":
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.45
            patched += 1
    with open(OUT, "w", encoding="utf-8") as f:
        _json.dump(g, f, separators=(",", ":"))
    print("[MTREE] alphaMode MASK patched on %d materials" % patched)

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
