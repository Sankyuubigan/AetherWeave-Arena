# ИСПРАВЛЕНИЕ: Явное наследование по пути файла спасает от багов кэша Godot
extends "res://Logic/Skills/Effect.gd"

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

@export var projectile_scene: PackedScene
@export var offset_y: float = 1.2
## Звук удара снаряда о цель/землю (data-driven через meta). Ставится/стирается
## КАЖДЫЙ каст: fireball.tscn шарится скиллами (огненный шар и метеор) через
## пул — без стирания звук метеора «прилип» бы к огненному шару.
@export var impact_sound: AudioStream
## Спавн от ПРАВОЙ кисти (план 17.11.26 Шаг 3): источник — context.cast_origin
## (кладёт SpellCasterComponent из BoneAttachment3D RightHand/CastPoint).
## false — старое поведение от тела+offset_y (метеор летит с неба).
@export var spawn_from_hand: bool = false

func apply(caster: Node, context: Dictionary) -> void:
    if not projectile_scene:
        return

    var tree = caster.get_tree()
    var parent = tree.current_scene if tree and tree.current_scene else caster.get_parent()
    if not parent:
        return

    var proj = ProjectilePool.acquire(projectile_scene, parent)

    var origin: Vector3 = caster.global_position + Vector3(0, offset_y, 0)
    if spawn_from_hand and context.has("cast_origin"):
        origin = context["cast_origin"]
    proj.global_position = origin

    var target_pos = context.get("target_pos", proj.global_position + Vector3.FORWARD)
    var direction = proj.global_position.direction_to(target_pos)

    if proj.has_method("set_direction"):
        proj.set_direction(direction)

    if impact_sound:
        proj.set_meta("impact_sfx", impact_sound)
    else:
        proj.remove_meta("impact_sfx")