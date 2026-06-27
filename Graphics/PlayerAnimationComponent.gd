extends Node

var anim_player: AnimationPlayer
var was_in_air: bool = false

func _ready():
    anim_player = get_parent().get_node("GraphicsWrapper/AnimationPlayer")
    if not anim_player:
        print("PlayerAnimationComponent: No AnimationPlayer found")
        return
        
    # ИСПРАВЛЕНИЕ БАГА "ДЕРГАНЬЯ И СКОРОСТИ" (Root Motion):
    # Обнуляем смещение корневой кости по X и Z во всех анимациях, 
    # чтобы моделька физически не убегала из капсулы.
    var lib = anim_player.get_animation_library("")
    if lib:
        for anim_name in lib.get_animation_list():
            var anim = lib.get_animation(anim_name)
            for i in range(anim.get_track_count()):
                # Ищем треки изменения позиций костей
                if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
                    # Проходим по всем кадрам анимации и обнуляем оси X и Z
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

func _process(_delta):
    if not anim_player:
        return
    var parent = get_parent()
    var speed = Vector2(parent.velocity.x, parent.velocity.z).length()
    var current = anim_player.current_animation
    var anims = anim_player.get_animation_list()

    var in_air = not parent.is_on_floor()
    if in_air:
        if "Jump" in anims and current != "Jump":
            anim_player.play("Jump")
        was_in_air = true
        return

    if was_in_air:
        was_in_air = false
        if speed < 0.001 and "Idle" in anims:
            anim_player.play("Idle")
            return

    if speed < 0.001:
        if current != "Idle" and "Idle" in anims:
            anim_player.play("Idle")
    else:
        if current != "Run" and "Run" in anims:
            anim_player.play("Run")