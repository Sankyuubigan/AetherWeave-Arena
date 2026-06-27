extends Node

var frames = 0

func _process(delta):
    if frames == 0:
        var root = get_tree().root
        var packed = load("res://Scenes/player.tscn")
        var player = packed.instantiate()
        player.name = "Player"
        player.position = Vector3(0, 1, 0)
        root.add_child(player)
    elif frames == 2:
        var player = get_tree().root.get_node("Player")
        var camera = player.get_node("SpringArm3D/Camera3D")
        print("Camera position: ", camera.global_position)
        print("Player position: ", player.global_position)
        var cam_look = -camera.global_transform.basis.z
        cam_look.y = 0
        cam_look = cam_look.normalized()
        print("Camera -basis.z (look dir): ", cam_look)
        var forward = (player.global_position - camera.global_position).normalized()
        forward.y = 0
        forward = forward.normalized()
        print("Camera-to-player XZ: ", forward)
        if forward.z > 0:
            print("PASS: W moves away from camera (+Z)")
        else:
            print("FAIL: W moves toward camera")
        get_tree().quit()
    frames += 1