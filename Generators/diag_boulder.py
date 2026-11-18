# Диагностика: почему DECIMATE не дожимает валун и UV-статистика 0%.
import bpy
import sys

src = None
for i, a in enumerate(sys.argv):
    if a == "--":
        src = sys.argv[i + 1]
        break

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
print("DIAG объектов:", len(objs))
for o in objs:
    me = o.data
    print(f"DIAG '{o.name}': polys={len(me.polygons):,} verts={len(me.vertices):,}")
    print("DIAG  uv_layers:", [l.name for l in me.uv_layers])
    print("DIAG  customdata layers:", [l.name for l in me.attributes])
    print("DIAG  shape_keys:", me.shape_keys is not None)
    print("DIAG  materials:", len(me.materials))

o = objs[0]
me = o.data

# нон-манifold и граничные рёбра
import bmesh
bm = bmesh.new()
bm.from_mesh(me)
non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
boundary = sum(1 for e in bm.edges if e.is_boundary)
loose = sum(1 for v in bm.verts if not v.link_edges)
print(f"DIAG рёбер нон-манifold: {non_manifold:,} | граничных: {boundary:,} | висячих вершин: {loose:,}")
bm.free()

# копия, strip, fill, decimate
new_o = o.copy()
new_o.data = o.data.copy()
bpy.context.scene.collection.objects.link(new_obj := new_o)
while new_obj.data.uv_layers:
    new_obj.data.uv_layers.remove(new_obj.data.uv_layers[0])
print("DIAG после strip: uv_layers =", len(new_obj.data.uv_layers))

bpy.context.view_layer.objects.active = new_obj
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.fill_holes(sides=64)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
me2 = new_obj.data
print(f"DIAG после fill_holes: polys={len(me2.polygons):,}")

bm = bmesh.new()
bm.from_mesh(me2)
non_manifold2 = sum(1 for e in bm.edges if not e.is_manifold)
boundary2 = sum(1 for e in bm.edges if e.is_boundary)
bm.free()
print(f"DIAG после fill: нон-манifold={non_manifold2:,} | граничных={boundary2:,}")

mod = new_obj.modifiers.new(name='Decimate', type='DECIMATE')
mod.ratio = 4000.0 / len(me2.polygons)
mod.use_collapse_triangulate = False
mod.delimit = set()
print("DIAG decimate ratio =", mod.ratio)
bpy.ops.object.modifier_apply(modifier=mod.name)
print(f"DIAG после decimate: polys={len(new_obj.data.polygons):,}")

# UV
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.396, island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
me3 = new_obj.data
print("DIAG uv_layers после smart_project:", [l.name for l in me3.uv_layers])
if me3.uv_layers:
    uvs = me3.uv_layers[0].data
    us = [u.uv[0] for u in uvs]
    vs = [u.uv[1] for u in uvs]
    print(f"DIAG UV min=({min(us):.4f},{min(vs):.4f}) max=({max(us):.4f},{max(vs):.4f}) n={len(uvs):,}")
print("DIAG конец")
