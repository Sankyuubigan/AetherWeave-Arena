extends "res://Logic/Skills/Effect.gd"

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

## Стремительный свип A→B (вердикт 17.11.26: не мгновенно, а очень быстро
## и плавно; подпрыг в начале, «падение» в конце). Камера летит сама — она
## на SpringArm3D, ребёнке тела. На полёте глушим коллизии тела (позицию
## ведёт твин, препятствия не вносят рывков), гравитация спит (velocity
## обнуляется в контроллере при input_locked). Приземление подхватывает
## автомат: Jump → Falling (в полёте) → Landing (на прибытии).
const SWEEP_TIME := 0.45   # сам пролёт A→B
const DROP_TIME := 0.15    # повторное снижение на целевую точку
const ARRIVE_LIFT := 0.5   # подлёт над целевой точкой → падение на неё
const HOP_HEIGHT := 0.4    # подпрыг в первые 30% пролёта
## Клип ПРИБЫТИЯ (26.11.26, решение юзера «магическое исчезновение +
## обратное появление»): тот же Dismissing_Gesture, но РЕВЕРСОМ (манифест
## reverse:true) — руки раскрываются из позы исчезновения. Играет ЭФФЕКТ, а
## не скилл: только он знает момент приземления (свип 0.45 + дроп 0.15 с).
const ARRIVE_ANIM := "Teleport_Appear"

@export var vfx_scene: PackedScene

func apply(caster: Node, context: Dictionary) -> void:
    var start_pos = caster.global_position
    var target_pos: Vector3 = context.get("target_pos", start_pos)

    # Свип только для тела с локомцией (PlayerController.input_locked);
    # повторный каст в полёте уже в свипе — игнор. Прочие кастеры —
    # мгновенный телепорт как раньше.
    if "input_locked" in caster:
        if caster.input_locked:
            return
        _sweep(caster, target_pos)
    else:
        caster.global_position = target_pos
        if "velocity" in caster:
            caster.set("velocity", Vector3.ZERO)
        # Физ-интерполяция включена проектно: вне-физический телепорт без
        # сброса дал бы рывок-дотягивание от старой позиции.
        if caster is Node3D:
            caster.reset_physics_interpolation()

    if vfx_scene:
        var tree = caster.get_tree()
        var world = tree.current_scene if (tree and tree.current_scene) else caster.get_parent()

        var burst_out = vfx_scene.instantiate()
        world.add_child(burst_out)
        burst_out.global_position = start_pos + Vector3(0, 1, 0)

        var burst_in = vfx_scene.instantiate()
        world.add_child(burst_in)
        burst_in.global_position = target_pos + Vector3(0, 1, 0)

    # Круги варпа на полу: уход — кольцо сжимается, приход — расширяется
    # (аним. декаль 4.8). Нет пола под точкой — декаль не спавним.
    var world: World3D = caster.get_world_3d()
    var scene = caster.get_tree().current_scene if caster.get_tree() else null
    if not scene:
        return
    var ground_out := AnimatedDecalComponent.ground_hit_below(world, start_pos)
    if not ground_out.is_empty():
        var frames_out := DecalFrames.warp_ring(Color(0.55, 0.35, 1.0), true)
        var decal_out := AnimatedDecalComponent.new()
        decal_out.configure(frames_out, 10.0, 1.2, 1.6)
        scene.add_child(decal_out)
        decal_out.place(ground_out.position, ground_out.normal)
    var ground_in := AnimatedDecalComponent.ground_hit_below(world, target_pos)
    if not ground_in.is_empty():
        var frames_in := DecalFrames.warp_ring(Color(0.55, 0.35, 1.0), false)
        var decal_in := AnimatedDecalComponent.new()
        decal_in.configure(frames_in, 10.0, 1.2, 1.6)
        scene.add_child(decal_in)
        decal_in.place(ground_in.position, ground_in.normal)

## Свип-полёт (корутина): запускается без await — VFX/звук каста играют сразу.
func _sweep(player: Node3D, target: Vector3) -> void:
    player.input_locked = true
    if "velocity" in player:
        player.set("velocity", Vector3.ZERO)
    var layer_keep: int = player.collision_layer
    var mask_keep: int = player.collision_mask
    player.collision_layer = 0
    player.collision_mask = 0

    # Поза полёта: Jump от отрыва (гард в автомате держит его первый кадр);
    # дальше is_on_floor() = false → Falling, на прибытии → Landing.
    var anim_comp = player.get_node_or_null("PlayerAnimationComponent")
    if anim_comp and anim_comp.has_method("play_jump"):
        anim_comp.play_jump(false)

    var start: Vector3 = player.global_position
    var end_up: Vector3 = target + Vector3(0, ARRIVE_LIFT, 0)
    var tw = player.create_tween()
    tw.tween_method(_sweep_pose.bind(player, start, end_up), 0.0, 1.0, SWEEP_TIME)
    await tw.finished
    if not is_instance_valid(player):
        return
    # Падение на точку: разгоняющийся дроп (EASE_IN) с ARRIVE_LIFT.
    var tw2 = player.create_tween()
    tw2.tween_property(player, "global_position:y", target.y, DROP_TIME) \
            .set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
    await tw2.finished
    if not is_instance_valid(player):
        return
    player.global_position = target
    player.reset_physics_interpolation()
    player.collision_layer = layer_keep
    player.collision_mask = mask_keep
    if "velocity" in player:
        player.set("velocity", Vector3.ZERO)
    player.input_locked = false
    # Клип ПРИБЫТИЯ (26.11.26): реверс-жест исчезновения — руки раскрываются
    # в точке выхода. Играем ПОСЛЕ разблокировки ввода: каст-слой поверх
    # локомотики, игрок уже управляет.
    var anim_comp2 = player.get_node_or_null("PlayerAnimationComponent")
    if anim_comp2 and anim_comp2.has_method("play_cast_anim") \
            and anim_comp2.has_method("has_cast_anim") \
            and anim_comp2.has_cast_anim(ARRIVE_ANIM):
        anim_comp2.play_cast_anim(ARRIVE_ANIM)

## Траектория: горизонталь — smoothstep (разгон и торможение), вертикаль —
## базовая дуга к точке над целью + хоп-синус в первые 30% пролёта.
func _sweep_pose(u: float, player: Node3D, start: Vector3, end_up: Vector3) -> void:
    if not is_instance_valid(player):
        return
    var e := u * u * (3.0 - 2.0 * u)
    var hop := HOP_HEIGHT * sin(PI * minf(u / 0.3, 1.0))
    player.global_position = Vector3(
            lerpf(start.x, end_up.x, e),
            lerpf(start.y, end_up.y, e) + hop,
            lerpf(start.z, end_up.z, e))
