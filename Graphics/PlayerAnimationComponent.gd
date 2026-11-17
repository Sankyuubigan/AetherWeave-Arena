extends Node

## Анимации локомоции — конечный автомат: GROUND (Idle/Run) / JUMP / FALL / LAND.
## Починка 17.11.26: в воздухе после Jump — Falling (луп), а не рестарт Jump
## («накачивание»); сход с уступа без прыжка — тоже Falling; приземление
## проигрывает одноразовый Landing, бег перебивает его мгновенно.

var anim_player: AnimationPlayer
var was_in_air: bool = false
var air_state: String = ""  # "", "jump", "flip", "fall"
var air_frames: int = 0     # гистерезис против «мигания» is_on_floor на склонах
var _channel: bool = false  # длительный каст (метеор/гром): автомат заморожен
## Защита инста-каста: клип доигрывает поверх локомоции (иначе Run/Falling
## сжирают бросок за кадр — поймал test_cast_anims).
var _cast_hold_until_ms: int = 0

## Одноразовые каст-клипы (защита от перебоя локомоцией).
const CAST_ANIMS := ["Throw", "Cast_Shoot", "Cast_Shoot_L", "Pistol_Shoot", "Pistol_Shoot_L"]

func is_channeling() -> bool:
    return _channel

## Точка отрыва в клипе Jump (дамп ключей hips Y 17.11.26): 0–0.33 с — присед
## (Y 0.93→0.56), отрыв с ~0.33. Стартуем с отрыва: физика взлетает сразу, а
## проигрывание приседа в воздухе читалось как «тормозит».
const JUMP_LAUNCH_TIME := 0.33

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

func play_jump(double: bool = false) -> void:
    if not anim_player:
        return
    # Двойной прыжок — сальто (вердикт 17.11.26: «сальто вообще нету»):
    # доигрываем целиком, автомат не режет его на вершине дуги (state "flip").
    if double and anim_player.has_animation("FrontFlip"):
        var parent = get_parent()
        var flip: Animation = anim_player.get_animation("FrontFlip")
        # Скорость под физику: полное время полёта = 2*v/g. Клип 1.667 с без
        # разгона не успевает за ~0.92 с полёта («медленно, не заканчивается»).
        var air_time: float = 2.0 * parent.jump_velocity / parent.GRAVITY
        var spd: float = clampf(flip.length / maxf(air_time, 0.1), 1.0, 3.0)
        anim_player.play("FrontFlip", 0.15, spd)
        air_state = "flip"
        return
    if anim_player.has_animation("Jump"):
        # Старт новой дуги: блендинг покороче, затем прыжок сразу к ОТРЫВУ
        # (JUMP_LAUNCH_TIME) — без приседа в воздухе. Рестарт намеренный —
        # «накачивания» нет: в FALL автомат уводит по velocity.
        anim_player.play("Jump", 0.1)
        anim_player.seek(JUMP_LAUNCH_TIME, true)
        air_state = "jump"

## ── Каст-анимации (план 17.11.26, Шаги 3–4) ─────────────────────────────

func has_cast_anim(anim_name: String) -> bool:
    return anim_player != null and anim_name != "" and anim_player.has_animation(anim_name)

## Инста-каст: один клип поверх текущего состояния (выброс/бросок).
func play_cast_anim(anim_name: String) -> void:
    if not has_cast_anim(anim_name):
        return
    anim_player.play(anim_name, 0.1)
    _cast_hold_until_ms = Time.get_ticks_msec() \
            + int(anim_player.get_animation(anim_name).length * 1000.0)

## Старт канала: Enter (0.53с) → _process сам подхватит Loop.
func play_channel() -> void:
    if not anim_player:
        return
    _channel = true
    if anim_player.has_animation("Cast_Enter"):
        anim_player.play("Cast_Enter", 0.1)
    elif anim_player.has_animation("Cast_Loop"):
        anim_player.play("Cast_Loop", 0.1)

## Конец канала: выброс (Cast_Shoot), автомат разморожен.
func end_channel() -> void:
    if not _channel:
        return
    _channel = false
    if anim_player and anim_player.has_animation("Cast_Shoot"):
        anim_player.play("Cast_Shoot", 0.1)
        _cast_hold_until_ms = Time.get_ticks_msec() \
                + int(anim_player.get_animation("Cast_Shoot").length * 1000.0)

## Активен защищённый каст-клип (идёт и не истёк холд).
func _cast_anim_active() -> bool:
    if anim_player == null or not anim_player.is_playing():
        return false
    var n: String = anim_player.current_animation
    if not (n in CAST_ANIMS):
        return false
    return Time.get_ticks_msec() < _cast_hold_until_ms

func _process(_delta):
    if not anim_player:
        return

    # Канал каста (план 17.11.26 Шаг 4): автомат спит, Enter доигрывает → Loop.
    if _channel:
        var chan_now := anim_player.current_animation
        if chan_now == "Cast_Enter" and not anim_player.is_playing() \
                and anim_player.has_animation("Cast_Loop"):
            anim_player.play("Cast_Loop", 0.1)
        return

    # Инста-каст доигрывает поверх локомоции (и в воздухе, и в беге).
    if _cast_anim_active():
        return

    var parent = get_parent()
    var speed = Vector2(parent.velocity.x, parent.velocity.z).length()
    var anims = anim_player.get_animation_list()

    var in_air = not parent.is_on_floor()

    if in_air:
        air_frames += 1
        was_in_air = true
        # Сальто двойного прыжка доигрываем целиком — оно и есть визуал полёта;
        # кончилось, а мы всё ещё в воздухе → обычное Falling.
        if air_state == "flip":
            if anim_player.current_animation == "FrontFlip" and anim_player.is_playing():
                return
            air_state = "fall"
            if "Falling" in anims:
                anim_player.play("Falling", 0.25)
            return
        # FALL: сорвался с уступа без прыжка (несколько кадров в воздухе)
        # ИЛИ пройдена вершина дуги прыжка (velocity.y < 0).
        var start_fall := false
        if air_state == "" and air_frames > 3:
            start_fall = true
        elif air_state == "jump" and parent.velocity.y < 0.0:
            start_fall = true
        if start_fall and "Falling" in anims:
            air_state = "fall"
            anim_player.play("Falling", 0.25)
        return

    air_frames = 0

    # На земле
    if was_in_air:
        was_in_air = false
        air_state = ""
        if "Landing" in anims:
            anim_player.play("Landing", 0.1)

    # Читаем ПОСЛЕ возможного старта Landing — иначе устаревшее имя
    # заставит Idle-ветку тут же перебить приземление.
    var now = anim_player.current_animation

    if (now == "Landing" or now == "Cast_Shoot") and anim_player.is_playing() and speed < 0.001:
        return  # доигрываем приземление/выброс стоя (бег ниже перебьёт)

    # Свежий Jump при ещё «земном» is_on_floor (кадр стейла до первого
    # move_and_slide после старта свипа телепорта) — не съедаем в Idle.
    if now == "Jump" and air_state == "jump" and anim_player.is_playing():
        return

    if speed < 0.001:
        if now != "Idle" and "Idle" in anims:
            anim_player.play("Idle", 0.2)
    else:
        if now != "Run" and "Run" in anims:
            anim_player.play("Run", 0.15)
