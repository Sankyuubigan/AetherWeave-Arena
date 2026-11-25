"""Бейк анимации Mixamo-FBX на скин-GLB → GLB (меш + анимация в одном файле).

Запуск (Blender 5.1 headless):
  blender --background --python res://Generators/bake_anim_glb.py -- \
      <char.glb> <anim.fbx> <out.glb>

Порядок: импорт скина (арматура B + меш), импорт FBX-анимации (арматура A с
экшеном), покадровое копирование pose-матриц A→B по именам костей (rest-позы
различаются — матрицы это учитывают), бейк в экшен B, экспорт GLB.
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
char_glb, anim_fbx, out_glb = argv[0], argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- скин (арматура B + меш) ---
bpy.ops.import_scene.gltf(filepath=char_glb)
char_obj = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
if char_obj is None:
    raise SystemExit("no armature in character glb")

# --- анимация (арматура A + экшен) ---
bpy.ops.import_scene.fbx(filepath=anim_fbx)
anim_obj = next((o for o in bpy.data.objects if o.type == 'ARMATURE' and o != char_obj), None)
if anim_obj is None:
    raise SystemExit("no armature in anim fbx")
act = anim_obj.animation_data.action if anim_obj.animation_data else None
frames = int(act.frame_range[1]) if act else 2
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = frames

# --- покадровый перенос поз (матрицы в пространстве арматуры) ---
bpy.context.view_layer.objects.active = char_obj
bpy.ops.object.mode_set(mode='POSE')
for f in range(1, frames + 1):
    scene.frame_set(f)
    for pb in char_obj.pose.bones:
        src = anim_obj.pose.bones.get(pb.name)
        if src is not None:
            pb.matrix = src.matrix
    bpy.context.view_layer.update()
    for pb in char_obj.pose.bones:
        pb.keyframe_insert('location', frame=f)
        pb.keyframe_insert('rotation_quaternion', frame=f)
bpy.ops.object.mode_set(mode='OBJECT')

# --- убираем арматуру-источник, экспортируем GLB ---
bpy.data.objects.remove(anim_obj, do_unlink=True)
bpy.ops.export_scene.gltf(
    filepath=out_glb,
    export_format='GLB',
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_frame_range=True,
    export_yup=True,
)
print("BAKED %s -> %s (%d frames)" % (anim_fbx, out_glb, frames))