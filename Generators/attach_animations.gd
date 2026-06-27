extends SceneTree

func _init():
    var packed = load("res://Scenes/player.tscn")
    var root = packed.instantiate()
    root.name = "Player"

    var anim_player = find_animation_player(root)
    if not anim_player:
        print("ERROR: No AnimationPlayer found in player scene")
        quit()
        return

    var lib = anim_player.get_animation_library("")
    if not lib:
        print("ERROR: No default animation library")
        quit()
        return

    var existing = lib.get_animation_list()
    for anim in existing:
        lib.remove_animation(anim)

    var anim_sources = {
        "Idle": "res://Graphics/Animations/Idle.fbx",
        "Run": "res://Graphics/Animations/Running.fbx",
        "Jump": "res://Graphics/Animations/Jumping.fbx"
    }

    for anim_name in anim_sources:
        var fbx_path = anim_sources[anim_name]
        var fbx_scene = load(fbx_path)
        if not fbx_scene:
            print("ERROR: Cannot load " + fbx_path)
            continue
        var fbx_root = fbx_scene.instantiate()
        var fbx_anim_player = find_animation_player(fbx_root)
        if not fbx_anim_player:
            print("ERROR: No AnimationPlayer in " + fbx_path)
            fbx_root.queue_free()
            continue
        var source_lib = fbx_anim_player.get_animation_library("")
        if not source_lib:
            print("ERROR: No animation library in " + fbx_path)
            fbx_root.queue_free()
            continue
        var source_anims = source_lib.get_animation_list()
        if source_anims.is_empty():
            print("ERROR: No animations in " + fbx_path)
            fbx_root.queue_free()
            continue
        var anim = source_lib.get_animation(source_anims[0])
        if anim:
            lib.add_animation(anim_name, anim)
            print("Added animation: " + anim_name)
        fbx_root.queue_free()

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, "res://Scenes/player.tscn")
    print("Player scene saved with animations!")
    quit()

func find_animation_player(node: Node) -> AnimationPlayer:
    if not node:
        return null
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var result = find_animation_player(child)
        if result:
            return result
    return null
