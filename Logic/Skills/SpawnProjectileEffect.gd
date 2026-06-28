# ИСПРАВЛЕНИЕ: Явное наследование по пути файла спасает от багов кэша Godot
extends "res://Logic/Skills/Effect.gd"

@export var projectile_scene: PackedScene
@export var offset_y: float = 1.2

func apply(caster: Node, context: Dictionary) -> void:
    if not projectile_scene: 
        return
        
    var proj = projectile_scene.instantiate()
    
    var tree = caster.get_tree()
    if tree and tree.current_scene:
        tree.current_scene.add_child(proj)
    else:
        caster.get_parent().add_child(proj)
        
    proj.global_position = caster.global_position + Vector3(0, offset_y, 0)
    
    var target_pos = context.get("target_pos", proj.global_position + Vector3.FORWARD)
    var direction = proj.global_position.direction_to(target_pos)
    
    if proj.has_method("set_direction"):
        proj.set_direction(direction)