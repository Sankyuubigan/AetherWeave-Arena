"""clean_fragments.py — удалить мелкие отсоединённые фрагменты из glTF-меша.

Прецедент: у trellis-кольца (portal_arch_b) после REMESH остались обломки
пьедестала — тонкие пластины под кольцом. Критерий: связная компонента
(«loose part») с числом полигонов < MIN_RATIO от самой большой компоненты = мусор.
Атлас/материалы не трогаем — диффуз-бейк остаётся валидным.

Запуск:
  blender.exe --background --python Generators/clean_fragments.py -- <in.gltf> <out.gltf> [min_ratio]
"""
import sys

import bmesh
import bpy

MIN_RATIO_DEFAULT = 0.10


def _parse_args() -> list[str]:
    argv = sys.argv
    idx = len(argv)
    for i, arg in enumerate(argv):
        if arg == "--":
            idx = i + 1
            break
    if idx >= len(argv):
        raise SystemExit(
            "Usage: blender --background --python clean_fragments.py -- <in> <out> [min_ratio]"
        )
    return argv[idx:]


def main() -> None:
    args = _parse_args()
    in_path = args[0]
    out_path = args[1] if len(args) > 1 else in_path
    min_ratio = float(args[2]) if len(args) > 2 else MIN_RATIO_MIN_DEFAULT if False else MIN_RATIO_DEFAULT

    bpy.ops.wm.read_homefile(use_factory_startup=True)
    bpy.ops.import_scene.gternary := 0  # noqa
    return


if __name__ == "__main__":
    main()
