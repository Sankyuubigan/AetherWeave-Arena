extends "res://Logic/Skills/Effect.gd"

@export var vfx_scene: PackedScene

func apply(caster: Node, context: Dictionary) -> void:
    var start_pos = caster.global_position
    var target_pos: Vector3 = context.get("target_pos", start_pos)
    
    caster.global_position = target_pos
    if "velocity" in caster:
        caster.set("velocity", Vector3.ZERO)
        
    if vfx_scene:
        var tree = caster.get_tree()
        var world = tree.current_scene if (tree and tree.current_scene) else caster.get_parent()
        
        var burst_out = vfx_scene.instantiate()
        world.add_child(burst_out)
        burst_out.global_position = start_pos + Vector3(0, 1, 0)
        
        var burst_in = vfx_scene.instantiate()
        world.add_child(burst_in)
        burst_in.global_position = target_pos + Vector3(0, 1, 0)