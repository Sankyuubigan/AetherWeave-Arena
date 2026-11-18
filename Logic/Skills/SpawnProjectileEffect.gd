# ИСПРАВЛЕНИЕ: Явное наследование по пути файла спасает от багов кэша Godot
extends "res://Logic/Skills/Effect.gd"

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

@export var projectile_scene: PackedScene
@export var offset_y: float = 1.2
## Звук удара снаряда о цель/землю (data-driven через meta). Ставится/стирается
## КАЖДЫЙ каст: fireball.tscn шарится скиллами (огненный шар и метеор) через
## пул — без стирания звук метеора «прилип» бы к огненному шару.
@export var impact_sound: AudioStream
## Тряска камеры при УДАРЕ снаряда (метеорит: падение после 2-с канала —
## шейк в момент каста не нужен, верб. юзера 19.11.26). Паттерн impact_sound:
## пул-безопасно, set/erase каждый каст (fireball.tscn шарится скиллами).
@export var impact_shake: float = 0.0
## Множитель размера следа-декали при ударе (метеор: крупная подпалина + лужа
## лавы, QUEUE Q5). Тот же пул-безопасный паттерн impact_*: set/erase каждый
## каст — fireball.tscn шарится скиллами.
@export var decal_scale: float = 1.0
## Оставить ЭМИССИВНУЮ лужу лавы в точке удара (метеор: «лужи лавы,
## оставляющие след» — заказ юзера 19.11.26).
@export var lava_pool: bool = false
## Спавн от ПРАВОЙ кисти (план 17.11.26 Шаг 3): источник — context.cast_origin
## (кладёт SpellCasterComponent из BoneAttachment3D RightHand/CastPoint).
## false — старое поведение от тела+offset_y (метеор летит с неба).
@export var spawn_from_hand: bool = false
## Задержка спавна от нажатия (с), 0 = инстант. Для инста-кастов, чей клип
## начинает выброс позже t=0 (Throw: замах → хлыст ~0.3 с): снаряд рождается
## в момент хлыста из ЖИВОЙ позиции кисти, а не из позы нажатия.
@export var spawn_delay: float = 0.0

func apply(caster: Node, context: Dictionary) -> void:
    if not projectile_scene:
        return

    var tree = caster.get_tree()
    if spawn_delay > 0.0:
        var side: String = context.get("hand", "Right")
        await tree.create_timer(spawn_delay).timeout
        # За время задержки сцена/кастер могли умереть.
        if not is_instance_valid(caster) or not caster.is_inside_tree():
            return
        if spawn_from_hand:
            context["cast_origin"] = hand_pos(caster, side)

    var parent = tree.current_scene if tree and tree.current_scene else caster.get_parent()
    if not parent:
        return

    var proj = ProjectilePool.acquire(projectile_scene, parent)

    var origin: Vector3 = caster.global_position + Vector3(0, offset_y, 0)
    if spawn_from_hand and context.has("cast_origin"):
        origin = context["cast_origin"]
    proj.global_position = origin
    # Телепорт снаряда из пула: сброс физ-интерполяции (иначе полёт «дотягивает»
    # от старой позиции прошлой жизни узла).
    proj.reset_physics_interpolation()

    var target_pos = context.get("target_pos", proj.global_position + Vector3.FORWARD)
    var direction = proj.global_position.direction_to(target_pos)

    if proj.has_method("set_direction"):
        proj.set_direction(direction)

    if impact_sound:
        proj.set_meta("impact_sfx", impact_sound)
    else:
        proj.remove_meta("impact_sfx")

    if impact_shake > 0.0:
        proj.set_meta("impact_shake", impact_shake)
    else:
        proj.remove_meta("impact_shake")

    if decal_scale > 1.001:
        proj.set_meta("decal_scale", decal_scale)
    else:
        proj.remove_meta("decal_scale")

    if lava_pool:
        proj.set_meta("lava_pool", true)
    else:
        proj.remove_meta("lava_pool")