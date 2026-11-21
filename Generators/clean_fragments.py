"""clean_fragments.py — удалить мелкие отсоединённые фрагменты из glTF-меша.

Прецедент: у trellis-кольца (portal_arch_b) после REMESH остались обломки
пьедестала — тонкие пластины под кольцом. Критерий: связная часть (loose part)
с числом полигонов < MIN_RATIO от самой большой части = мусор, удаляется.
Атлас/материалы не трогаем — диффуз-бейк остаётся валидным.

Запуск:
  blender.exe --background --python Generators/clean_fragments.py -- <in.gltf> <out.gltf> [min_ratio]
"""
import sys

import bpy


def main() -> None:
    argv = sys.argv
    idx = len(argv)
    for i, arg in enumerate(argv):
        if arg == "--":
            idx = i + 1
            break
    if idx >= len(argv):
        raise SystemExit("Usage: blender --background --python clean_fragments.py -- <in> <out> [min_ratio]")
    args = argv[idx:]
    in_path = args[0]
    out_path = args[1] if len(args) > 1 else in_path
    min_ratio = float(args[2]) if len(args) > 2 else 0.10

    bpy.ops.wm.read_homefile(use_factory_startup=True)
    bpy.ops.import_scene.gltf(filepath=in_path)

    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not objs:
        raise SystemExit("CLEAN: ERROR — мешей нет: " + in_path)
    before = sum(len(o.data.polygons) for o in objs)

    # Разрезать меши на связные части (штатная операция, один проход)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")

    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(parts) <= 1:
        print("CLEAN: единая часть, чистить нечего (", before, "полигонов )")
        return

    counts = [(o, len(o.data.polygons)) for o in parts]
    max_polys = max(c for _o, c in counts)
    kept = []
    for o, c in counts:
        if c < max_polys * min_ratio:
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            kept.append((o.name, c))
    after = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print("CLEAN: частей было", len(parts), "стало", len(kept), "полигоны", before, "->", after)
    for name, c in kept:
        print("CLEAN: keep", name, c)

    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLTF_SEPARATE",
        export_image_format="NONE",
    )
    print("CLEAN: exported", out_path)


main()
