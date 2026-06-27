extends Node

var fireball_scene: PackedScene

func _ready():
    fireball_scene = load("res://Scenes/fireball.tscn")
    if fireball_scene == null:
        push_error("SpellCasterComponent: Failed to load fireball scene!")

func cast():
    if fireball_scene == null:
        return

    var player = get_parent()
    var camera = player.get_node("Camera3D")
    if not camera:
        return

    var forward = -camera.global_transform.basis.z
    var fireball = fireball_scene.instantiate()

    get_tree().current_scene.add_child(fireball)
    fireball.global_position = camera.global_position + forward * 2.0

    if fireball.has_method("set_direction"):
        fireball.set_direction(forward)
