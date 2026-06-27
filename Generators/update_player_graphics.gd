extends SceneTree

func _init():
    var packed = load("res://Scenes/player.tscn")
    var root = packed.instantiate()
    root.name = "Player"

    var wrapper = root.get_node("GraphicsWrapper")

    var old_mesh = wrapper.get_node("MeshInstance3D")
    if old_mesh:
        wrapper.remove_child(old_mesh)
        old_mesh.queue_free()

    var old_model = wrapper.get_node("PlayerModel")
    if old_model:
        wrapper.remove_child(old_model)
        old_model.queue_free()

    var old_anim_player = wrapper.get_node("AnimationPlayer")
    if old_anim_player:
        wrapper.remove_child(old_anim_player)
        old_anim_player.queue_free()

    var model_scene = load("res://Graphics/PlayerModel/Ch24_nonPBR.fbx")
    var model_root = model_scene.instantiate()
    model_root.name = "PlayerModel"
    wrapper.add_child(model_root)
    set_owner_recursive(model_root, root)

    var new_ap = AnimationPlayer.new()
    new_ap.name = "AnimationPlayer"
    wrapper.add_child(new_ap)
    new_ap.owner = root
    new_ap.root_node = NodePath("../PlayerModel")

    var lib = AnimationLibrary.new()
    new_ap.add_animation_library("", lib)

    var sources = {
        "Idle": "res://Graphics/Animations/Idle.fbx",
        "Run": "res://Graphics/Animations/Running.fbx",
        "Jump": "res://Graphics/Animations/Jumping.fbx"
    }

    for anim_name in sources:
        var fbx_scene = load(sources[anim_name])
        if not fbx_scene:
            print("Cannot load " + sources[anim_name])
            continue
        var fbx_root = fbx_scene.instantiate()
        var fbx_ap = find_animation_player(fbx_root)
        if not fbx_ap:
            fbx_root.queue_free()
            continue
        var fbx_lib = fbx_ap.get_animation_library("")
        if not fbx_lib:
            fbx_root.queue_free()
            continue
        var fbx_anims = fbx_lib.get_animation_list()
        if fbx_anims.is_empty():
            fbx_root.queue_free()
            continue
        var anim = fbx_lib.get_animation(fbx_anims[0])
        if anim:
            var dup = anim.duplicate(true)
            for i in dup.get_track_count():
                var path_str = str(dup.track_get_path(i))
                if "mixamorig1_" in path_str:
                    path_str = path_str.replace("mixamorig1_", "mixamorig_")
                    dup.track_set_path(i, NodePath(path_str))
            lib.add_animation(anim_name, dup)
            print("Added " + anim_name)
        fbx_root.queue_free()

    var anim_script = load("res://Graphics/PlayerAnimationComponent.gd")
    var anim_component = root.get_node("PlayerAnimationComponent")
    if not anim_component:
        anim_component = Node.new()
        anim_component.name = "PlayerAnimationComponent"
        anim_component.set_script(anim_script)
        root.add_child(anim_component)
    anim_component.owner = root

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, "res://Scenes/player.tscn")
    print("Player scene saved!")
    quit()

func find_animation_player(node: Node) -> AnimationPlayer:
    if not node: return null
    if node is AnimationPlayer: return node
    for c in node.get_children():
        var r = find_animation_player(c)
        if r: return r
    return null

func set_owner_recursive(node: Node, owner: Node):
    node.owner = owner
    for child in node.get_children():
        set_owner_recursive(child, owner)
