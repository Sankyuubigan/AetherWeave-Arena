extends SceneTree

func _init():
    var bad = load("res://Graphics/Animations/Idle.fbx").instantiate()
    var ap = find_animation_player(bad)
    var lib = ap.get_animation_library("")
    var anim = lib.get_animation(lib.get_animation_list()[0])
    print("=== Before remap ===")
    for i in min(anim.get_track_count(), 5):
        print("  Track " + str(i) + ": " + str(anim.track_get_path(i)))

    for i in anim.get_track_count():
        var path_str = str(anim.track_get_path(i))
        if "mixamorig1_" in path_str:
            var new_path_str = path_str.replace("mixamorig1_", "mixamorig_")
            anim.track_set_path(i, NodePath(new_path_str))

    print("=== After remap ===")
    for i in min(anim.get_track_count(), 5):
        print("  Track " + str(i) + ": " + str(anim.track_get_path(i)))

    bad.queue_free()

    var model = load("res://Graphics/PlayerModel/Ch24_nonPBR.fbx").instantiate()
    var model_ap = find_animation_player(model)
    var model_lib = model_ap.get_animation_library("")
    var model_anim = model_lib.get_animation("Take 001")
    print("\n=== Model animation paths ===")
    for i in min(model_anim.get_track_count(), 5):
        print("  Track " + str(i) + ": " + str(model_anim.track_get_path(i)))

    model.queue_free()
    quit()

func find_animation_player(node):
    if not node: return null
    if node is AnimationPlayer: return node
    for c in node.get_children():
        var r = find_animation_player(c)
        if r: return r
    return null
