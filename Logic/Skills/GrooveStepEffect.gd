extends "res://Logic/Skills/Effect.gd"

## «Ритм-выпад» (groove_step, дефолт ПКМ стойки «Пульс Битвы»): атомарный
## рывок-импульс ~3.5 м по направлению WASD (или вперёд) — мини-уворот-танец.
## В бит длиннее (4.5 м) и со шлейфом-декалью на полу (старт + финиш),
## мимо бита — базовая длина без шлейфа. КД 0.45 с в SkillDB. Вердикт бита —
## context["groove_verdict"]; заряд Грува (+18/+10) даёт судья стойки.

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var dash_dist: float = 3.5
@export var dash_dist_onbeat: float = 4.5

func apply(caster: Node, context: Dictionary) -> void:
    if not (caster is Node3D):
        return
    var body := caster as Node3D
    var verdict := str(context.get("groove_verdict", ""))
    var on_beat := verdict == "perfect" or verdict == "good"
    var dir := _wish_dir(body, context)
    var dist := dash_dist_onbeat if on_beat else dash_dist
    # Стена по пути — не втыкаться в депенетрацию: укорачиваем до точки удара.
    var from: Vector3 = body.global_position + Vector3(0, 1.0, 0)
    var q := PhysicsRayQueryParameters3D.create(
            from, from + dir * (dist + 0.4), 1, [body.get_rid()])
    var hit = body.get_world_3d().direct_space_state.intersect_ray(q)
    if not hit.is_empty():
        dist = minf(dist, maxf(0.5, body.global_position.distance_to(hit["position"]) - 0.6))
    var start := body.global_position
    body.global_position = start + dir * dist
    body.reset_physics_interpolation()
    _trail(body, start, on_beat)

## WASD в мировых координатах (basis тела); нет нажатий — вперёд от камеры.
func _wish_dir(body: Node3D, context: Dictionary) -> Vector3:
    var fwd := -body.global_transform.basis.z
    fwd.y = 0.0
    if fwd.length_squared() < 0.0001:
        fwd = Vector3.FORWARD
    var right := body.global_transform.basis.x
    right.y = 0.0
    var d := fwd * (int(Input.is_key_pressed(KEY_W)) - int(Input.is_key_pressed(KEY_S))) \
            + right * (int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A)))
    if d.length_squared() < 0.0001:
        var fd: Vector3 = context.get("forward_dir", fwd)
        fd.y = 0.0
        if fd.length_squared() > 0.0001:
            return fd.normalized()
        return fwd.normalized()
    return d.normalized()

## Шлейф: warp-декаль на полу в точке старта; в бит — ещё и в точке финиша
## (Блок 3 ТЗ: «в бит длиннее + шлейф»), золотая. Нет пола — декали нет.
func _trail(body: Node3D, start: Vector3, on_beat: bool) -> void:
    var scene = body.get_tree().current_scene if body.get_tree() else null
    if not scene:
        return
    var world: World3D = body.get_world_3d()
    var color := Color(1.0, 0.85, 0.3) if on_beat else Color(0.55, 0.35, 1.0)
    var g0 = AnimatedDecalComponent.ground_hit_below(world, start)
    if not g0.is_empty():
        var d0 := AnimatedDecalComponent.new()
        d0.configure(DecalFrames.warp_ring(color, true), 10.0, 1.2, 1.6)
        scene.add_child(d0)
        d0.place(g0["position"], g0["normal"])
    if not on_beat:
        return
    var g1 = AnimatedDecalComponent.ground_hit_below(world, body.global_position)
    if not g1.is_empty():
        var d1 := AnimatedDecalComponent.new()
        d1.configure(DecalFrames.warp_ring(color, false), 10.0, 1.2, 1.6)
        scene.add_child(d1)
        d1.place(g1["position"], g1["normal"])
