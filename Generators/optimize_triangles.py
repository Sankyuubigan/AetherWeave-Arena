# Меш-пайплайн v2 по ревью спеца (18.11.26). Заменяет версию с delimit-декимацией.
#
# Ключевые отличия от v1 (почему):
# - DECIMATE БЕЗ delimit: фотограмметрия имеет плотные UV-швы; delimit запрещал
#   коллапс рёбер поперёк швов → почти не децимировал и тянул треугольники.
#   Старые UV на LP-копии удаляются ПЕРЕД декимацией — всё равно перепекаем.
# - Re-UV: smart_project(angle_limit=РАДИАНЫ(80), island_margin=0.004) +
#   pack_islands(..., margin=0.005). v1 передавала 66 как «радианы» (на деле
#   66 рад!) и margin 0.02 — раздутые атласы.
# - Бейки LP<-HP (selected-to-active): normal + AO + roughness + diffuse(color),
#   2048 → даунскейл 1024. Нормал/ORM сохраняются ТОЛЬКО в PNG (lossy WebP на
#   нормалях = рябь). Диффуз — WebP.
# - cage_extrusion 0.05–0.08 (кламп 0.03×радиус), max_ray_distance 0.15–0.3
#   (v1: 0.0 = без лимита — в мульти-сетах лучи ловили соседние камни).
# - Пасс-спец 19.11.26: island_margin 0.003; bake margin=16 EXTEND; сэмплы
#   normal/diffuse/roughness=4, AO=64; соседние HP скрываются на бейк
#   (hide_render) — лучи не ловят соседние камни сета; orphans_purge после модели.
# - shade_smooth по углу после декимации, ПЕРЕД бейками.
# - ORM-карта: R=AO, G=Roughness, B=Metal=0 (металл в бейк = чёрнота).
# - REMESH(voxel) — только --remesh РЕМОНТ (дыры/нон-манifold), не для оптимизации.
#
# Запуск:
# & "D:\Programs\Blender Foundation\Blender 5.1\blender.exe" --background \
#   --python res://Generators/optimize_triangles.py -- <input_gltf|glb> \
#   [--target N] [--out DIR] [--name NAME] [--remesh] [--no-bake] [--no-decimate]
import bpy
import sys
import os
import math
import time
import numpy as np

# УРОК (18.11.26): stdout при редиректе блочно-буферизуется — прогресс бейка
# в логе появлялся только после выхода blender. Линейная буферизация = живой
# прогресс (юзер: «есть прогрессбар?»).
sys.stdout.reconfigure(line_buffering=True)

TARGET_TRIANGLES = 5000     # бюджет хиро-пропа с нормал-бейком (спец: 1000-5000)
# УРОК (18.11.26, вердикт юзера «25 минут неприемлемо»): бейк сразу в финальное
# 1024 — в 4 раза меньше пикселей, чем 2048→даунскейл. Качество на камнях
# проверит юзер; если не хватит — поднять точечно, не глобально.
BAKE_IMAGE_SIZE = 1024
FINAL_IMAGE_SIZE = 1024
SKIP_BAKE = False
USE_REMESH = False
REMESH_VOXEL_SIZE = 0.035


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def tri_count(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    return sum(len(o.evaluated_get(dg).data.loop_triangles) for o in objs)


def bbox_radius(objs):
    xs, ys, zs = [], [], []
    for o in objs:
        for c in o.bound_box:
            xs.append(c[0]); ys.append(c[1]); zs.append(c[2])
    if not xs:
        return 0.5
    diag = math.dist((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))
    return max(diag / 2.0, 1e-3)


def strip_uvs(obj):
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])


def weld_verts(obj, bbox_r):
    """Сварка совпадающих вершин ДО декимации (совет из практики): GLB хранит
    по копии вершин на UV-остров + кастомные нормали — QEM считает рёбра швов
    граничными и не коллапсит их (валун: 114,778 «граничных» рёбер, декимация
    застревала на 57K). Сваривать ПОСЛЕ поздно — края уже разошлись."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:
        pass
    before = len(obj.data.vertices)
    bpy.ops.mesh.remove_doubles(threshold=max(1e-5, 0.0002 * bbox_r))
    after = len(obj.data.vertices)
    print(f"    weld '{obj.name}': {before:,} -> {after:,} вершин")
    bpy.ops.object.mode_set(mode='OBJECT')


def fill_holes(obj, max_sides=64):
    """Оставшиеся дыры после сварки (реальные пробоины скана).
    QEM не коллапсит граничные рёбра → декимация застревает."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    try:
        bpy.ops.mesh.fill_holes(sides=max_sides)
    except Exception as e:
        print(f"    fill_holes: {e}")
    bpy.ops.object.mode_set(mode='OBJECT')


def remake_uvs(obj):
    """Новые UV для перепека: smart_project + pack_islands. Углы в РАДИАНАХ."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    # Спец (19.11.26): island_margin=0.003 — 0.02 съедал атлас; 0.004/0.005 близко,
    # берём точное значение спеца.
    bpy.ops.uv.smart_project(angle_limit=math.radians(80), island_margin=0.003)
    bpy.ops.mesh.select_all(action='SELECT')
    try:
        bpy.ops.uv.pack_islands(angle_method='ANGLE', angle_limit=math.radians(80), margin=0.003)
    except TypeError:
        bpy.ops.uv.pack_islands(margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')


def recalc_normals_outside(obj):
    """QEM-декимация вертит/портит нормали части треугольников (rock_moss:
    чёрные осколки с рваными краями, мигрируют между ракурсами — диффуз и ORM
    при этом чистые). Пересчёт «наружу» чинит winding+нормали перед бейками."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')


def shade_smooth_by_angle(obj, deg=30):
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))
    except Exception:
        bpy.ops.object.shade_smooth()
    bpy.ops.object.mode_set(mode='OBJECT')


def uv_island_stats(obj):
    """Доля атласа, занятая островами (0..1), и число островов."""
    me = obj.data
    me.calc_loop_triangles()
    if not me.uv_layers:
        return 0.0, 0
    uvl = me.uv_layers[0].data
    if len(me.loop_triangles) == 0 or len(uvl) == 0:
        return 0.0, 0
    occ = 0.0
    for tri in me.loop_triangles:
        uvs = [uvl[li].uv for li in tri.loops]
        (ax, ay), (bx, by), (cx, cy) = [tuple(u) for u in uvs]
        occ += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) / 2.0
    # Число островов: связность UV-вершин (соседство через UV-рёбра).
    import bmesh
    from collections import defaultdict
    bm = bmesh.new(); bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.active
    adj = defaultdict(set)
    for f in bm.faces:
        loops = f.loops
        for i in range(len(loops)):
            a = loops[i][uv_layer].uv.copy().freeze()
            b = loops[(i + 1) % len(loops)][uv_layer].uv.copy().freeze()
            if a != b:
                adj[a].add(b)
                adj[b].add(a)
    seen, islands = set(), 0
    for f in bm.faces:
        key = f.loops[0][uv_layer].uv.copy().freeze()
        if key in seen:
            continue
        stack, islands = [key], islands + 1
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(adj[cur] - seen)
    bm.free()
    return min(occ, 1.0), islands


def hp_zero_metallic():
    """Metallic=0 на HP перед diffuse-бейком (металл в бейк = чёрнота)."""
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                for l in list(node.inputs['Metallic'].links):
                    mat.node_tree.links.remove(l)
                node.inputs['Metallic'].default_value = 0.0


def new_bake_image(name, non_color=True, init_rgb=(0.0, 0.0, 0.0)):
    img = bpy.data.images.new(name, width=BAKE_IMAGE_SIZE, height=BAKE_IMAGE_SIZE, alpha=False)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    # Фон атласа НЕ чёрный: вырожденные UV-треугольники (после smart_project
    # на узких трианглах) сэмплят фон атласа → чёрные осколки на пропе
    # (rock_moss: геометрия/нормали/карты чисты, flat-зонд белоснежный, а
    # nonormal/noorm черны — виноват сэмпл фона). Нейтральный фон = серый
    # камень вместо чёрных дыр. (19.11.26)
    if init_rgb != (0.0, 0.0, 0.0):
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        px[0::4] = init_rgb[0]
        px[1::4] = init_rgb[1]
        px[2::4] = init_rgb[2]
        px[3::4] = 1.0
        img.pixels.foreach_set(px)
    return img


def bake_map(lp_obj, hp_obj, bake_type, img, color_only=False, samples=4):
    # Спец (19.11.26): normal/diffuse/roughness детерминированы — 1–4 сэмплов
    # достаточно (дефолт 64 зря ×16 время); шумной только AO — ей 64–128.
    bpy.context.scene.cycles.samples = samples
    tex_node = lp_obj.data.materials[0].node_tree.nodes.new('ShaderNodeTexImage')
    tex_node.image = img
    tex_node.select = True
    lp_obj.data.materials[0].node_tree.nodes.active = tex_node

    bpy.ops.object.select_all(action='DESELECT')
    hp_obj.select_set(True)
    lp_obj.select_set(True)
    bpy.context.view_layer.objects.active = lp_obj

    b = bpy.context.scene.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = lp_obj["cage"]
    # Спец (19.11.26): max_ray_distance 0.15–0.3 (v1: 0.0 = без лимита — лучи
    # улетали через весь сет и ловили СМЕЖНЫЕ камни). Не ниже cage × 2 — луч
    # короче вылета клетки срезает бейк у швов.
    b.max_ray_distance = lp_obj.get("max_ray", 0.15)
    # use_clear=False ОБЯЗАТЕЛЕН: дефолт True стирает всю картинку (в чёрный)
    # перед бейком — нейтральная заливка new_bake_image не доживает до рендера
    # (3 ребейка подряд «фикс не сработал» именно поэтому). Незапечённые тексели
    # (вырожденные UV-островки) остаются с цветом фона вместо чёрных дыр.
    b.use_clear = False
    # Спец: margin=16 + EXTEND — краевые тексели растягиваются наружу,
    # мипмапы не тянут чёрную кайму с фона атласа.
    b.margin = 16
    try:
        b.margin_type = 'EXTEND'
    except Exception:
        pass
    if color_only:
        b.use_pass_direct = False
        b.use_pass_indirect = False
        b.use_pass_color = True
    try:
        bpy.ops.object.bake(type=bake_type)
        print(f"    {bake_type} OK")
        return True
    except Exception as e:
        print(f"    {bake_type} FAILED: {e}")
        return False


def save_img(img, path, file_format):
    img.filepath_raw = path
    img.file_format = file_format
    try:
        img.save(filepath=path, quality=95)
    except TypeError:
        img.save(filepath=path)
    img.source = 'FILE'
    img.filepath = path
    print(f"    saved {os.path.basename(path)} ({os.path.getsize(path) / 1024:.0f} KB)")


def compose_orm(ao_img, rough_img, out_path, name):
    w = h = FINAL_IMAGE_SIZE
    ao = np.empty(w * h * 4, dtype=np.float32)
    ao_img.pixels.foreach_get(ao)
    ro = np.empty(w * h * 4, dtype=np.float32)
    rough_img.pixels.foreach_get(ro)
    orm = np.zeros(w * h * 4, dtype=np.float32)
    orm[0::4] = ao[0::4]          # R = AO
    orm[1::4] = ro[1::4]          # G = Roughness
    orm[3::4] = 1.0               # A = 1
    out = bpy.data.images.new(name, width=w, height=h, alpha=False)
    out.colorspace_settings.name = 'Non-Color'
    out.pixels.foreach_set(orm)
    save_img(out, out_path, 'PNG')
    return out


def heal_bake_image(img, init_rgb, max_iters=512):
    """Дозаливка незапечённого фона соседними запечёнными цветами.

    Бейк не попадает по части LP-текселей (глубокие щели между камнями сета:
    рейки из LP вдоль нормалей летят мимо HP), и эти тексели остаются с цветом
    инициализации new_bake_image — на пропе выглядят серыми/чёрными пятнами
    («осколки» rock_moss, 19.11.26). Нейтральный фон меняет цвет пятна, но не
    убирает его; лечит только растяжка запечённых цветов в дыры кольцами 3x3
    (усреднение известных соседей), пока дыры не кончатся.

    Допуск 1.5/255, а не 1e-6: sRGB-картинки (diffuse) Blender прогоняет через
    колор-менеджмент — 0.5 превращается в ~0.503, точное сравнение дыры не видит
    (ребейк 4: «дыр нет» при сером фоне на рендере). Non-Color карты проходят
    точно, но единый допуск покрывает оба случая; ложно-дырные запечённые
    тексели (AO=1, нейтральные нормали) дозаливаются соседями ≈ без изменений.
    """
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    buf = px.reshape(h, w, 4)
    rgb = buf[..., :3].copy()
    init = np.array(init_rgb, dtype=np.float32)
    known = ~np.all(np.abs(rgb - init) < (1.5 / 255.0), axis=-1)
    if known.all():
        print(f"    heal {img.name}: дыр нет")
        return
    holes0 = int((~known).sum())
    filled = known.copy()
    it_used = 0
    for it in range(max_iters):
        if filled.all():
            break
        it_used = it + 1
        ksum = np.zeros((h, w, 3), dtype=np.float32)
        kcnt = np.zeros((h, w), dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                mk = np.roll(np.roll(filled.astype(np.float32), dy, axis=0), dx, axis=1)
                sv = np.roll(np.roll(rgb, dy, axis=0), dx, axis=1)
                ksum += sv * mk[..., None]
                kcnt += mk
        newk = (kcnt > 0) & ~filled
        rgb[newk] = ksum[newk] / kcnt[newk][..., None]
        filled |= newk
    buf[..., :3] = rgb
    img.pixels.foreach_set(px)
    print(f"    heal {img.name}: дыр {holes0}, итераций {it_used}")


def scale_down(img):
    if img.size[0] > FINAL_IMAGE_SIZE or img.size[1] > FINAL_IMAGE_SIZE:
        img.scale(FINAL_IMAGE_SIZE, FINAL_IMAGE_SIZE)


def wire_lp_material(lp_obj, diff_img, norm_img, orm_img):
    mat = bpy.data.materials.new(name=f"{lp_obj.name}_v2mat")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial'); out.location = (500, 0)
    bsdf = nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location = (0, 0)
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    n_diff = nodes.new('ShaderNodeTexImage'); n_diff.image = diff_img
    n_diff.location = (-400, 200)
    links.new(n_diff.outputs['Color'], bsdf.inputs['Base Color'])

    n_norm = nodes.new('ShaderNodeTexImage'); n_norm.image = norm_img
    n_norm.image.colorspace_settings.name = 'Non-Color'
    n_norm.location = (-400, -100)
    n_nm = nodes.new('ShaderNodeNormalMap'); n_nm.location = (-200, -100)
    links.new(n_norm.outputs['Color'], n_nm.inputs['Color'])
    links.new(n_nm.outputs['Normal'], bsdf.inputs['Normal'])

    n_orm = nodes.new('ShaderNodeTexImage'); n_orm.image = orm_img
    n_orm.image.colorspace_settings.name = 'Non-Color'
    n_orm.location = (-400, -400)
    sep = nodes.new('ShaderNodeSeparateColor'); sep.location = (-200, -400)
    links.new(n_orm.outputs['Color'], sep.inputs['Color'])
    links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
    node_metal = bsdf.inputs['Metallic']
    node_metal.default_value = 0.0

    if lp_obj.data.materials:
        lp_obj.data.materials[0] = mat
    else:
        lp_obj.data.materials.append(mat)


def export_gltf(lowpoly_objects, out_dir, base_name):
    os.makedirs(out_dir, exist_ok=True)
    out_gltf = os.path.join(out_dir, base_name + "_baked.gltf")
    bpy.ops.object.select_all(action='DESELECT')
    for obj in lowpoly_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = lowpoly_objects[0]
    kw = dict(
        filepath=out_gltf,
        export_format='GLTF_SEPARATE',
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials='EXPORT',
        use_selection=True,
    )
    try:
        bpy.ops.export_scene.gltf(export_image_format='NONE', **kw)
        print("  textures: НЕ экспортированы (NONE) — берём наши файлы из папки")
    except Exception:
        bpy.ops.export_scene.gltf(export_image_format='AUTO', **kw)
    return out_gltf


def process_model(filepath, output_dir, skip_decimate, out_name):
    base_name = out_name or os.path.splitext(os.path.basename(filepath))[0]
    print(f"\n{'='*60}\nV2 PIPELINE: {filepath}\n{'='*60}")

    clear_scene()
    if filepath.lower().endswith(".glb"):
        bpy.ops.import_scene.gltf(filepath=filepath)
    else:
        bpy.ops.import_scene.gltf(filepath=filepath)

    highpoly_objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not highpoly_objects:
        print("ERROR: No mesh objects found!")
        return False
    total_before = tri_count(highpoly_objects)
    # Спец (19.11.26): cage_extrusion 0.05–0.08 для камней 1–3 м (v1: 0.03×radius
    # = 0.015–0.045 — клетка тоньше рельефа скана, лучи срезали рельеф).
    cage = min(0.08, max(0.05, 0.03 * bbox_radius(highpoly_objects)))
    max_ray = min(0.3, max(0.15, cage * 3.0))
    print(f"HP tris: {total_before:,} | bbox radius: {bbox_radius(highpoly_objects):.3f} м | cage: {cage:.3f} | max_ray: {max_ray:.3f}")

    hp_coll = bpy.data.collections.new("HighPoly")
    bpy.context.scene.collection.children.link(hp_coll)
    for obj in highpoly_objects:
        for coll in obj.users_collection:
            coll.objects.unlink(obj)
        hp_coll.objects.link(obj)

    # LP-копии
    lowpoly_objects = []
    for obj in highpoly_objects:
        new_obj = obj.copy()
        new_obj.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(new_obj)
        lowpoly_objects.append(new_obj)
    lp_coll = bpy.data.collections.new("LowPoly")
    bpy.context.scene.collection.children.link(lp_coll)
    for obj in lowpoly_objects:
        for coll in obj.users_collection:
            coll.objects.unlink(obj)
        lp_coll.objects.link(obj)

    # РЕДУКЦИЯ: UV на LP-копиях удаляем ДО декимации (перепекаем всё равно),
    # затем сварка швов и затыкание оставшихся дыр.
    for obj in lowpoly_objects:
        strip_uvs(obj)
        weld_verts(obj, bbox_radius(highpoly_objects))
        fill_holes(obj)

    if not skip_decimate:
        total_lp = tri_count(lowpoly_objects)
        print(f"\nSTEP 2: {'REMESH (VOXEL)' if USE_REMESH else 'DECIMATE (no delimit)'} | {total_lp:,} -> target {TARGET_TRIANGLES:,}")
        for obj in lowpoly_objects:
            dg = bpy.context.evaluated_depsgraph_get()
            current = len(obj.evaluated_get(dg).data.loop_triangles)
            if total_lp <= TARGET_TRIANGLES or current == 0:
                continue
            target_for_mesh = max(4, round(TARGET_TRIANGLES * current / total_lp))
            if current <= target_for_mesh:
                continue
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)

            def decimate_to(t_cur, t_target):
                ratio = t_target / t_cur
                mod = obj.modifiers.new(name='Decimate', type='DECIMATE')
                mod.ratio = ratio
                mod.use_collapse_triangulate = False
                mod.delimit = set()  # ГЛАВНОЕ: коллапс везде, UV перепекаем
                bpy.ops.object.modifier_apply(modifier=mod.name)

            if USE_REMESH:
                # РЕМОНТ рваных сканов: воксельная перестройка даёт чистую
                # замкнутую топологию (QEM не коллапсит рёбра нон-манifold —
                # валун 98K застревал на 57K). Затем decimate до бюджета.
                mod = obj.modifiers.new(name='Remesh', type='REMESH')
                mod.mode = 'VOXEL'
                mod.voxel_size = REMESH_VOXEL_SIZE
                mod.adaptivity = 0.0
                bpy.ops.object.modifier_apply(modifier=mod.name)
                cur2 = len(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.loop_triangles)
                print(f"  '{obj.name}': remesh {current:,} -> {cur2:,}")
                if cur2 > target_for_mesh:
                    decimate_to(cur2, target_for_mesh)
            else:
                decimate_to(current, target_for_mesh)
            new_tris = len(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.loop_triangles)
            print(f"  '{obj.name}': {current:,} -> {new_tris:,}")

    # POST: re-UV + smooth + метал-ноль
    for obj in lowpoly_objects:
        remake_uvs(obj)
        recalc_normals_outside(obj)
        shade_smooth_by_angle(obj)
        obj["cage"] = cage
        obj["max_ray"] = max_ray
    if not SKIP_BAKE:
        hp_zero_metallic()

    occ_avg, islands_avg = 0.0, 0
    for obj in lowpoly_objects:
        occ, isl = uv_island_stats(obj)
        occ_avg += occ; islands_avg += isl
        print(f"  UV '{obj.name}': островов ~{isl}, атлас занят {occ * 100:.0f}%")
    occ_avg /= max(len(lowpoly_objects), 1)

    diff_img = norm_img = orm_img = None
    if not SKIP_BAKE:
        print(f"\nSTEP 3: BAKE {BAKE_IMAGE_SIZE}x{BAKE_IMAGE_SIZE} LP<-HP (normal/AO/rough/diffuse)")
        bpy.context.scene.render.engine = 'CYCLES'
        # УРОК (18.11.26, ель 30+ мин): cycles.device='GPU' молча падает на CPU в
        # headless-фабрике — без preferencescompute_device_type='OPTIX'/'CUDA'.
        # И дефолтные сэмплы Cycles (4096) на плотной хвое = десятки минут на бейк.
        gpu_found = False
        try:
            prefs = bpy.context.preferences.addons['cycles'].preferences
            for dev_type in ('OPTIX', 'CUDA'):
                prefs.compute_device_type = dev_type
                prefs.get_devices()
                gpus = [d for d in prefs.devices if d.type == dev_type]
                if gpus:
                    for d in prefs.devices:
                        d.use = (d.type == dev_type)
                    gpu_found = True
                    print(f"  Cycles: GPU {dev_type} — {gpus[0].name}")
                    break
        except Exception as e:
            print(f"  Cycles GPU-настройка не удалась ({e}) — рендер на CPU")
        if not gpu_found:
            print("  ВНИМАНИЕ: GPU не найден — бейк пойдёт на CPU (медленно!)")
        bpy.context.scene.cycles.device = 'GPU' if gpu_found else 'CPU'
        bpy.context.scene.cycles.samples = 64
        bpy.context.scene.cycles.use_adaptive_sampling = False
        hp_list, lp_list = list(hp_coll.objects), list(lp_coll.objects)
        for idx, lp_obj in enumerate(lp_list):
            hp_obj = hp_list[idx] if idx < len(hp_list) else None
            if not hp_obj:
                print(f"  нет HP для '{lp_obj.name}' — пропуск бейка")
                continue
            print(f"  Baking: '{lp_obj.name}' <- '{hp_obj.name}'")
            if not lp_obj.data.materials:
                lp_obj.data.materials.append(bpy.data.materials.new(f"{lp_obj.name}_tmp"))
            lp_obj.data.materials[0].use_nodes = True
            if not any(n.type == 'BSDF_PRINCIPLED' for n in lp_obj.data.materials[0].node_tree.nodes):
                lp_obj.data.materials[0].node_tree.nodes.new('ShaderNodeBsdfPrincipled')

            # Мультимеш: у каждого меша СВОЙ набор карт (суффикс _m{idx}).
            suf = f"_m{idx}" if len(lp_list) > 1 else ""
            img_n = new_bake_image(f"{base_name}{suf}_baked_normal", init_rgb=(0.5, 0.5, 1.0))
            img_a = new_bake_image(f"{base_name}{suf}_baked_ao", init_rgb=(1.0, 1.0, 1.0))
            img_r = new_bake_image(f"{base_name}{suf}_baked_rough", init_rgb=(1.0, 1.0, 1.0))
            img_d = new_bake_image(f"{base_name}{suf}_baked_diffuse", non_color=False, init_rgb=(0.5, 0.5, 0.5))
            t_mesh = time.perf_counter()
            # Спец (19.11.26): соседние HP СКРЫВАТЬ на время бейка — лучи из LP
            # камня A долетали до HP камня B (мульти-сет), атлас заливался
            # соседом (hide_render альтернатива раздвиганию объектов на +10м X).
            for other in hp_list:
                if other is not hp_obj:
                    other.hide_render = True
            ok_n = bake_map(lp_obj, hp_obj, 'NORMAL', img_n)
            bake_map(lp_obj, hp_obj, 'AO', img_a, samples=64)
            bake_map(lp_obj, hp_obj, 'ROUGHNESS', img_r)
            bake_map(lp_obj, hp_obj, 'DIFFUSE', img_d, color_only=True, samples=4)
            for other in hp_list:
                if other is not hp_obj:
                    other.hide_render = False
            print(f"  БЕЙК '{lp_obj.name}': 4 карты за {time.perf_counter() - t_mesh:.1f} с "
                  f"(сэмплы {bpy.context.scene.cycles.samples}, устройство {bpy.context.scene.cycles.device})")
            # heal ДО scale_down: дыры лечим в разрешении бейка, даунскейл сгладит
            heal_bake_image(img_n, (0.5, 0.5, 1.0))
            heal_bake_image(img_a, (1.0, 1.0, 1.0))
            heal_bake_image(img_r, (1.0, 1.0, 1.0))
            heal_bake_image(img_d, (0.5, 0.5, 0.5))
            for im in (img_n, img_a, img_r, img_d):
                scale_down(im)

            p = os.path.join(output_dir, "")
            save_img(img_n, p + f"{base_name}{suf}_baked_normal.png", 'PNG')
            orm_img = compose_orm(img_a, img_r, p + f"{base_name}{suf}_baked_orm.png", f"{base_name}{suf}_baked_orm")
            save_img(img_d, p + f"{base_name}{suf}_baked_diffuse.webp", 'WEBP')

            if ok_n:
                diff_img, norm_img = img_d, img_n
                wire_lp_material(lp_obj, img_d, img_n, orm_img)

    print(f"\nSTEP 4: EXPORT")
    hp_coll.hide_viewport = True
    hp_coll.hide_render = True
    out_gltf = export_gltf(lowpoly_objects, output_dir, base_name)

    total_after = tri_count(lowpoly_objects)
    print(f"\n{'='*60}\nSUMMARY v2 {base_name}\n{'='*60}")
    print(f"  Tris: {total_before:,} -> {total_after:,} ({(1 - total_after / max(total_before, 1)) * 100:.1f}%)")
    print(f"  UV атлас занят (среднее): {occ_avg * 100:.0f}%")
    print(f"  Output: {out_gltf}")
    out_size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(output_dir) for f in fs
                   if base_name in f)
    print(f"  Size (v2 files): {out_size / (1024 * 1024):.2f} MB")
    # Спец (19.11.26): RAM-гигиена между моделями (пайплайн гоняет сканы по
    # очереди) — рекурсивная чистка data-blockов без юзеров.
    try:
        bpy.data.orphans_purge(do_recursive=True)
    except Exception:
        pass
    return True


if __name__ == "__main__":
    argv = sys.argv
    idx = len(argv) - 1
    for i, arg in enumerate(argv):
        if arg == "--":
            idx = i + 1
            break
    if idx >= len(argv):
        print("Usage: blender --background --python optimize_triangles.py -- <input> "
              "[--target N] [--out DIR] [--name NAME] [--remesh] [--no-bake] [--no-decimate]")
        sys.exit(1)

    args = argv[idx:]
    input_path = args[0]

    def opt(flag, cast=str, default=None):
        if flag in args:
            return cast(args[args.index(flag) + 1])
        return default

    TARGET_TRIANGLES = opt('--target', int, TARGET_TRIANGLES)
    out_dir = opt('--out', str, None) or os.path.dirname(os.path.abspath(input_path))
    out_name = opt('--name', str, None)
    SKIP_BAKE = '--no-bake' in args
    USE_REMESH = '--remesh' in args
    skip_decimate = '--no-decimate' in args

    output_dir = os.path.abspath(out_dir)
    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    success = process_model(input_path, output_dir, skip_decimate, out_name)
    sys.exit(0 if success else 1)
