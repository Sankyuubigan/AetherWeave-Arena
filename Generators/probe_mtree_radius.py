# Probe: min/max/hist radius-атрибута на скелете MTree PINE.
import bpy, sys

def enable_extension():
    import addon_utils
    mods = [m.__name__ for m in addon_utils.modules()
            if "modular_tree" in m.__name__ and m.__name__.startswith("bl_ext.")]
    if mods and bpy.context.preferences.addons.get(mods[0]) is None:
        bpy.ops.preferences.addon_enable(module=mods[0])

enable_extension()
bpy.ops.wm.read_factory_settings(use_empty=True)
enable_extension()

import importlib.util as iu
spec = iu.spec_from_file_location(
    "m5", "D:/Projects/3d_game/Generators/build_mtree_spruce_cards2.py")
m5 = iu.module_from_spec(spec)
try:
    spec.loader.exec_module(m5)
except Exception:
    pass

tree = bpy.data.objects.get("Spruce_Trunk")
if tree is None:
    print("[RADIUS] no skeleton"); raise SystemExit(1)
# Скелет уже без модификаторов (main() успел их поставить?) — берём как есть
mesh = tree.data
attr = mesh.attributes.get("radius")
import numpy as np
vals = np.zeros(len(mesh.vertices), dtype=np.float32)
attr.data.foreach_get("value", vals)
print("[RADIUS] n=%d min=%.4f max=%.4f" % (len(vals), vals.min(), vals.max()))
for th in (0.01, 0.02, 0.03, 0.05, 0.1, 0.2, 0.4):
    print("[RADIUS] verts radius<%.2f: %d (%.1f%%)" % (
        th, (vals < th).sum(), 100.0 * (vals < th).sum() / len(vals)))
