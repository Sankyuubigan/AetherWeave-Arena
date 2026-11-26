"""Бейк анимации Mixamo-FBX на скин-GLB → GLB (меш + анимация в одном файле).

Запуск (Blender 5.1 headless):
  blender --background --python res://Generators/bake_anim_glb.py -- \
      <char.glb> <anim.fbx> <out.glb> [clip_name]

Порядок: импорт скина (арматура B + меш), импорт FBX-анимации (арматура A с
экшеном), покадровое копирование pose-матриц A→B по НОРМАЛИЗОВАННЫМ именам
костей (rest-позы различаются — матрицы это учитывают), бейк в экшен B,
ПРОВЕРКА результата на T-позу, экспорт GLB.

ИСТОРИЯ БАГА №1 (26.11.26 — «в админке часть GLB в T-позе»):
  Кости сопоставлялись ПО ТОЧНОМУ имени: скин-GLB из Blender даёт
  `mixamorig:Hips`, а FBX-арматура Mixamo — `mixamorig1:Hips` → 0 совпадений,
  и скрипт МОЛЧА писал rest-позу. 4 файла в tools/candidates_models оказались
  с константной анимацией (varied=0/198 каналов). Теперь: (1) имена
  нормализуются (как в Generators/anim_retarget_lib.gd::normalize_bone),
  (2) меньше 50% совпадений = abort, (3) после бейка проверяется разброс
  ключей — константный клип = «T-ПОЗА» и EXIT≠0.

ИСТОРИЯ БАГА №2 (26.11.26, вторая итерация — «перепёк, всё равно T-поза»):
  В каждом GLB-кандидате ЛЕЖАЛИ ДВА экшена: исходный из базового скина
  (2 ключа = rest-поза) и запечённый. Экспорт шёл с export_animation_mode=
  'ACTIONS' и тащил ОБА; вьюер админки играет clips[0] → играл rest-позу,
  хотя корректный клип в файле был. Теперь: (1) анимации базы вычищаются
  ДО бейка, (2) после бейка в файле обязан остаться РОВНО ОДИН экшен,
  (3) он переименовывается в имя клипа (не «ArmatureAction»), (4) проверка
  «сколько клипов в GLB» входит в гейт.
"""
import bpy
import sys
import re

argv = sys.argv[sys.argv.index("--") + 1:]
char_glb, anim_fbx, out_glb = argv[0], argv[1], argv[2]
clip_name = argv[3] if len(argv) > 3 else ""

MIN_MATCH_RATIO = 0.5     # меньше половины костей сматчилось = имена разъехались
MIN_VARIED_CHANNELS = 20  # сколько каналов обязаны РАЗЛИЧАТЬСЯ между кадрами
# Сколько кадров минимум обязано быть в клипе. 2 кадра = «начало и конец» =
# rest-поза (ровно дефект битых GLB): настоящий клип 24 fps даёт десятки.
MIN_KEYFRAMES = 4


def norm_bone(name):
    """mixamorig1_Hips / mixamorig1:Hips / mixamorig:Hips → mixamorig_Hips.

    Зеркало Generators/anim_retarget_lib.gd::normalize_bone. Вся пунктуация
    приводится к '_', чтобы ':' из Blender-GLB и '_' из FBX считались одним.
    """
    n = (name or "").strip()
    n = n.replace(":", "_").replace(".", "_").replace("|", "_").replace(" ", "_")
    n = re.sub(r"_+", "_", n)
    if n.startswith("mixamorig1_"):
        n = "mixamorig" + n[len("mixamorig1"):]
    elif n.startswith("mixamorig1"):
        n = "mixamorig" + n[len("mixamorig1"):]
    return n


def iter_fcurves(action):
    """Все f-кривые экшена в любой версии Blender.

    Blender 5.x убрал `Action.fcurves`: экшены стали слоёными
    (layers → strips → channelbags → fcurves). Прямое обращение падало
    AttributeError и валило бейк ПОСЛЕ записи ключей — файл не писался
    (поймано 26.11.26). Обходим оба API.
    """
    layers = getattr(action, "layers", None)
    if layers is not None and len(layers) > 0:
        for layer in layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []):
                    for fc in cb.fcurves:
                        yield fc
        return
    for fc in action.fcurves:
        yield fc


def purge_animations(obj):
    """Снять ВСЕ анимации с арматуры и вычистить осиротевшие экшены.

    Зачем: базовый скин-GLB приходит со своими экшенами (rest-поза из 2
    ключей). Экспорт в режиме ACTIONS тащит их в файл, вьюер играет clips[0]
    и показывает T-позу, хотя запечённый клип лежит рядом (баг №2, 26.11.26).
    """
    if obj.animation_data is not None:
        obj.animation_data.action = None
        obj.animation_data_clear()
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)


bpy.ops.wm.read_factory_settings(use_empty=True)

# --- скин (арматура B + меш) ---
bpy.ops.import_scene.gltf(filepath=char_glb)
char_obj = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
if char_obj is None:
    raise SystemExit("no armature in character glb")
# База обязана быть БЕЗ анимаций — иначе они уедут в GLB рядом с запечённой.
purge_animations(char_obj)

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
if frames < MIN_KEYFRAMES:
    raise SystemExit(
        "ABORT: в FBX %d кадров (< %d) — это не анимация: %s"
        % (frames, MIN_KEYFRAMES, anim_fbx))

# --- карта костей по нормализованным именам (единственное место сопоставления) ---
src_by_norm = {}
for pb in anim_obj.pose.bones:
    src_by_norm[norm_bone(pb.name)] = pb

bone_map = {}
for pb in char_obj.pose.bones:
    src = src_by_norm.get(norm_bone(pb.name))
    if src is not None:
        bone_map[pb.name] = src

total = len(char_obj.pose.bones)
matched = len(bone_map)
print("BAKE names: matched %d/%d bones (%.0f%%)" % (matched, total, 100.0 * matched / max(total, 1)))
if total == 0 or matched < total * MIN_MATCH_RATIO:
    # Fail loud: раньше здесь молча пеклась rest-поза.
    raise SystemExit(
        "ABORT: сматчилось %d/%d костей (< %.0f%%) — имена FBX и скина не совпадают.\n"
        "  примеры скина: %s\n  примеры FBX: %s"
        % (matched, total, MIN_MATCH_RATIO * 100,
           [b.name for b in list(char_obj.pose.bones)[:4]],
           [b.name for b in list(anim_obj.pose.bones)[:4]]))

# --- покадровый перенос поз (матрицы в пространстве арматуры) ---
bpy.context.view_layer.objects.active = char_obj
bpy.ops.object.mode_set(mode='POSE')
for f in range(1, frames + 1):
    scene.frame_set(f)
    for dst_name, src_pb in bone_map.items():
        char_obj.pose.bones[dst_name].matrix = src_pb.matrix
    bpy.context.view_layer.update()
    for pb in char_obj.pose.bones:
        pb.keyframe_insert('location', frame=f)
        pb.keyframe_insert('rotation_quaternion', frame=f)
bpy.ops.object.mode_set(mode='OBJECT')

# --- ПРОВЕРКА РЕЗУЛЬТАТА: анимация обязана РАЗЛИЧАТЬСЯ между кадрами ---
# Константные ключи = запеклась rest-поза (ровно тот баг, что ловим).
action = char_obj.animation_data.action if char_obj.animation_data else None
if action is None:
    raise SystemExit("ABORT: после бейка у скина нет экшена — писать нечего")
varied = 0
checked = 0
for fc in iter_fcurves(action):
    vals = [kp.co[1] for kp in fc.keyframe_points]
    checked += 1
    if vals and (max(vals) - min(vals)) > 1e-4:
        varied += 1
print("BAKE check: varied %d/%d fcurves" % (varied, checked))
if varied < MIN_VARIED_CHANNELS:
    raise SystemExit(
        "ABORT: T-ПОЗА — различаются только %d из %d каналов (нужно ≥%d).\n"
        "  Бейк не перенёс позу: проверь bone_map и rest-позы." % (varied, checked, MIN_VARIED_CHANNELS))

# --- имя клипа: вьюер админки играет clips[0], имя обязано быть читаемым ---
if clip_name:
    action.name = clip_name
    action.use_fake_user = True
    print("BAKE action renamed to: %s" % clip_name)

# --- в файле обязан остаться РОВНО ОДИН экшен (баг №2: лишние давали T-позу) ---
others = [a for a in bpy.data.actions if a != action]
for a in others:
    print("BAKE drop stray action: %s" % a.name)
    bpy.data.actions.remove(a)
if len(bpy.data.actions) != 1:
    raise SystemExit("ABORT: в сцене %d экшенов, должен остаться 1" % len(bpy.data.actions))

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
print("BAKED %s -> %s (%d frames, %d/%d bones, %d varied fcurves, clip=%s)" % (
    anim_fbx, out_glb, frames, matched, total, varied, action.name))
