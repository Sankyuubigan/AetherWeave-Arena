extends Node

var anim_player: AnimationPlayer
var was_in_air: bool = false
var jump_playing: bool = false

func _ready():
    anim_player = get_parent().get_node("GraphicsWrapper/AnimationPlayer")
    if not anim_player:
        print("PlayerAnimationComponent: No AnimationPlayer found")
        return
        
    var lib = anim_player.get_animation_library("")
    if lib:
        for anim_name in lib.get_animation_list():
            var anim = lib.get_animation(anim_name)
            for i in range(anim.get_track_count()):
                if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
                    for k in range(anim.track_get_key_count(i)):
                        var pos = anim.track_get_key_value(i, k)
                        pos.x = 0
                        pos.z = 0
                        anim.track_set_key_value(i, k, pos)

    var anims = anim_player.get_animation_list()
    if "Idle" in anims:
        anim_player.play("Idle")
    elif anims.size() > 0:
        anim_player.play(anims[0])

func play_jump():
    if anim_player and anim_player.has_animation("Jump"):
        # ИСПРАВЛЕНИЕ ВАЙБА: Убрали anim_player.stop(), добавили блендинг (0.15 сек)
        # Это сглаживает рывки при двойном прыжке и отрыве от земли.
        anim_player.play("Jump", 0.15)
        jump_playing = true

func _process(_delta):
    if not anim_player:
        return
        
    var parent = get_parent()
    var speed = Vector2(parent.velocity.x, parent.velocity.z).length()
    var current = anim_player.current_animation
    var anims = anim_player.get_animation_list()

    if jump_playing:
        if anim_player.is_playing() and current == "Jump":
            return
        else:
            jump_playing = false

    var in_air = not parent.is_on_floor()
    if in_air:
        if not jump_playing and "Jump" in anims and current != "Jump":
            anim_player.play("Jump", 0.2)
        was_in_air = true
        return

    if was_in_air:
        was_in_air = false
        if speed < 0.001 and "Idle" in anims:
            anim_player.play("Idle", 0.15)
            return

    if speed < 0.001:
        if current != "Idle" and "Idle" in anims:
            anim_player.play("Idle", 0.2)
    else:
        if current != "Run" and "Run" in anims:
            anim_player.play("Run", 0.2)