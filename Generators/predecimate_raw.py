# Стадия A двухстадийного меш-пайплайна (18.11.26).
#
# ИНЦИДЕНТ: raw-сканы бывают по 17 млн трис (ель pine_tree_01, 948 МБ bin) —
# optimize_triangles.py на них съедает 35 ГБ РАМ и полчаса на weld+QEM-дечимацию
# (вердикт юзера: «на сраную елку столько памяти — не нормально»).
#
# Эта стадия ОДИН раз грубо режет raw до work-копии (~1.5 млн трис) воксель-ремешем
# (OpenVDB, многопоточный, минуты, память ограничена): weld/strip-UV не нужны —
# стадия B (optimize_triangles.py) всё равно пересобирает UV и перепекает текстуры
# с work-копии (детали 17М-исходника на 1024px-бейке всё равно не видны).
#
# Запуск:
# & blender.exe --background --python Generators/predecimate_raw.py -- <input.gltf> \
#     --out <work.gltf> --target 1500000
#
# Потом стадия B:
# & blender.exe --background --python Generators/optimize_triangles.py -- <work.gltf> \
#     --target 5000 --out <prop_dir> --name <prop>_v2

import bpy
import sys
import os
import math
import time

# Живой прогресс в лог (stdout блочно-буферизуется при редиректе)
sys.stdout.reconfigure(line_buffering=True)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    inp = argv[0]
    out = None
    target = 1_500_000
    i = 1
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--target":
            target = int(argv[i + 1])
            i += 2
        else:
            i += 1
    if out is None:
        base = os.path.splitext(os.path.basename(inp))[0]
        out = os.path.join(os.path.dirname(inp), base + "_pre.gltf")
    return inp, out, target


def tri_count(objs):
    n = 0
    for o in objs:
        m = o.data
        n += sum(len(p.vertices) - 2 for p in m.polygons)
    return n


def surface_area(objs):
    """Мировая площадь поверхности (для оценки вокселя). area в локале —
    умножаем на квадрат медианного скейла объекта."""
    total = 0.0
    for o in objs:
        m = o.data
        arr = [0.0] * len(m.polygons)
        m.polygons.foreach_get("area", arr)
        s = o.matrix_world.median_scale
        total += sum(arr) * s * s
    return total


def main():
    inp, out_path, target_total = parse_args()
    t0 = time.perf_counter()

    bpy.ops.import_scene.gltf(filepath=inp)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not meshes:
        print("ERROR: мешей нет")
        return False

    total = tri_count(meshes)
    area = surface_area(meshes)
    print(f"RAW: {total:,} трис | площадь поверхности ~{area:.1f} м² | цель {target_total:,}")

    if total <= target_total * 1.3:
        print("RAW уже меньше цели ×1.3 — ремеш не нужен, просто экспорт")
    else:
        # Воксельная сетка: ~2 триса на поверхностную ячейку ⇒
        # cells ≈ area / voxel², tris ≈ 2·cells ⇒ voxel = sqrt(2·area/target)
        voxel = math.sqrt(2.0 * area / target_total)
        print(f"Воксель-ремеш: размер {voxel * 100:.1f} см (оценка по площади)")
        for obj in meshes:
            t_m = time.perf_counter()
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)
            mod = obj.modifiers.new(name='Remesh', type='REMESH')
            mod.mode = 'VOXEL'
            mod.voxel_size = voxel
            mod.adaptivity = 0.0
            bpy.ops.object.modifier_apply(modifier=mod.name)
            print(f"  '{obj.name}': ремеш за {time.perf_counter() - t_m:.1f} с")

    after = tri_count(meshes)
    print(f"WORK: {after:,} трис (было {total:,}) | {time.perf_counter() - t0:.0f} с")

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLTF_SEPARATE',
        export_image_format='AUTO',   # текстуры нужны стадии B для диффуз-бейка
        export_apply=False,
    )
    print(f"EXPORT: {out_path} ({os.path.getsize(out_path) / 1024:.0f} КБ gltf) | "
          f"итого {time.perf_counter() - t0:.0f} с")
    return True


main()
