extends Node

## Архитектура анимаций («всегда UB» + AnimationTree, 17.11.26):
##   ЛОКОМОЦИЯ — AnimationTree со стейт-машиной (строится КОДОМ в _ready,
##   никаких правок .tscn). AnimationPlayer остаётся ИСТОЧНИКОМ анимаций
##   (дерево берёт клипы из его библиотеки, сам он больше ничего не играет).
##   Игровой код только travel(): правила перетекания (xfade) живут в схеме.
##   AUTO+AT_END: Landing→Idle и FrontFlip→Falling доигрывают сами, без кода.
##   _state = НАМЕРЕНИЕ кода; дерево может уйти дальше само (AUTO AT_END) —
##   каждый кадр ресинк по факту, когда фейд завершён (fading_from пуст).
##   Производные клипы (тоже код, генераторы не тронуты):
##     Jump_Launch    — Jump с обрезкой приседа 0..0.33 (бывший seek-хак);
##     FrontFlip_Fast — FrontFlip, растянутый под время полёта (константа
##     физики 2·jump_velocity/GRAVITY; бывший custom_speed).
##   КАСТЫ — второй AnimationPlayer (CastPlayer) добавлен ПОСЛЕ дерева:
##   тот же root_node, пишет поверх позы дерева. UB-варианты клипов (бейк
##   build_cast_ub.gd), capture() — вход из ТЕКУЩЕЙ позы, stop() перед
##   рестартом (фикс спама раунда 14).
##   Канал (cast_time>0): Cast_Enter_UB → (сигнал) Cast_Loop_UB → end_channel:
##   Cast_Shoot_UB. Движение в канале гасит PlayerController через
##   is_channeling(); ноги при этом живут (Idle/Falling под UB-верхом).

## UAL-касты: библиотека с UB-вариантами (бейк: retarget_ual_anims.gd →
## build_heart_cast.gd → build_cast_ub.gd).
const USE_UAL_CASTS := true
const UAL_CASTS_LIB := "res://Graphics/Animations/ual_casts_test.res"
## Каст-имена игры, которых нет в UAL, → ближайший UAL-клип.
const UAL_CAST_ALIASES := {
    "Cast_Shoot_L": "Pistol_Shoot",
}

## Разметка клипов по дампам ключей (Hips Y, 17.11.26):
##   Jump:    присед 0–0.33 → взлёт 0.33–0.75 → СВОЁ падение 0.75–1.28 →
##            вставание 1.28–1.88. Физика (v=4.5, g=9.8): взлёт 0.46с, полёт 0.92с.
##   Landing: начинается с y=1.533 (высота в воздухе!) — внутри записано СВОЁ
##            падение 0–0.47 и лишь затем присед-удар и вставание 0.47–1.07.
##            На земле «своё падение» выглядит вторым падением («падает 2 раза»).
##            Поэтому: Jump_Launch = взлёт [0.33..0.75], Landing_Cut =
##            удар+вставание [0.47..1.07] — падение всегда ведёт Falling.
const JUMP_CUT_TIME := 0.33      # конец приседа
const JUMP_APEX_TIME := 0.75     # пик дуги (y=1.567)
const LANDING_CUT_TIME := 0.47   # низ приседа-удара в Landing

var anim_player: AnimationPlayer
var cast_player: AnimationPlayer
var tree: AnimationTree
var playback  # AnimationNodeStateMachinePlayback
var _state: String = ""  # намерение кода; дерево может уйти само (AUTO AT_END)
var _last_travel_frame: int = -100  # кадр последнего кодового travel (ресинк-гвард)
var was_in_air: bool = false
var air_frames: int = 0  # гистерезис против «мигания» is_on_floor на склонах
var _channel: bool = false  # длительный каст (метеор/гром): движение гасится

func is_channeling() -> bool:
    return _channel

## Текущее состояние локомоции (для тестов/диагностики)
func loco_state() -> String:
    return _state

func _ready():
    anim_player = get_parent().get_node("GraphicsWrapper/AnimationPlayer")
    if not anim_player:
        print("PlayerAnimationComponent: No AnimationPlayer found")
        return

    var lib = anim_player.get_animation_library("")
    if lib:
        # Нормализация позиционных треков локомоции (анти-дрифт x/z).
        for anim_name in lib.get_animation_list():
            var anim = lib.get_animation(anim_name)
            for i in range(anim.get_track_count()):
                if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
                    for k in range(anim.track_get_key_count(i)):
                        var pos = anim.track_get_key_value(i, k)
                        pos.x = 0
                        pos.z = 0
                        anim.track_set_key_value(i, k, pos)
        # Производные клипы (см. шапку)
        if lib.has_animation("Jump"):
            lib.add_animation("Jump_Launch",
                    _cut_range(lib.get_animation("Jump"), JUMP_CUT_TIME, JUMP_APEX_TIME))
        if lib.has_animation("Landing"):
            lib.add_animation("Landing_Cut",
                    _cut_from(lib.get_animation("Landing"), LANDING_CUT_TIME))
        if lib.has_animation("FrontFlip"):
            var flip: Animation = lib.get_animation("FrontFlip")
            var parent = get_parent()
            var air_time: float = 2.0 * parent.jump_velocity / parent.GRAVITY
            var spd: float = clampf(flip.length / maxf(air_time, 0.1), 1.0, 3.0)
            lib.add_animation("FrontFlip_Fast", _stretched(flip, flip.length / spd))

    # AnimationTree: стейт-машина локомоции. Сиблинг ПОСЛЕ AnimationPlayer,
    # ДО CastPlayer (порядок записи поз за кадр: loco → cast).
    tree = AnimationTree.new()
    anim_player.get_parent().add_child(tree)
    tree.anim_player = tree.get_path_to(anim_player)
    tree.root_node = anim_player.root_node
    tree.callback_mode_process = anim_player.callback_mode_process
    tree.tree_root = _build_loco_machine()
    tree.active = true

    # CastPlayer (без изменений, раунды 13–14): тот же скелет (root_node),
    # добавлен ПОСЛЕ дерева — пишет поверх. Незатронутые кости (ноги) ведёт FSM.
    cast_player = AnimationPlayer.new()
    anim_player.get_parent().add_child(cast_player)
    cast_player.root_node = anim_player.root_node
    # Канал Enter→Loop — по СИГНАЛУ: current_animation очищается сразу по
    # окончании клипа, опросное окно «клип кончился, но имя ещё то» нулевое.
    cast_player.animation_finished.connect(_on_cast_anim_finished)
    if USE_UAL_CASTS and ResourceLoader.exists(UAL_CASTS_LIB):
        var ual = load(UAL_CASTS_LIB)
        if ual is AnimationLibrary:
            var clib := AnimationLibrary.new()
            for anim_name in ual.get_animation_list():
                if String(anim_name).ends_with("_UB"):
                    clib.add_animation(anim_name, ual.get_animation(anim_name))
            for alias in UAL_CAST_ALIASES:
                var target: String = UAL_CAST_ALIASES[alias] + "_UB"
                var alias_ub: String = alias + "_UB"
                if clib.has_animation(target) and not clib.has_animation(alias_ub):
                    clib.add_animation(alias_ub, clib.get_animation(target))
            cast_player.add_animation_library("", clib)
            print("PlayerAnimationComponent: UB-касты на CastPlayer (", clib.get_animation_list().size(), "): ", ", ".join(clib.get_animation_list()))
        else:
            print("PlayerAnimationComponent: ", UAL_CASTS_LIB, " не AnimationLibrary")
    else:
        print("PlayerAnimationComponent: UB-библиотека не найдена: ", UAL_CASTS_LIB)

    # Старт локомоции через дерево (parameters/playback живёт после
    # первого прохода дерева)
    await get_tree().process_frame
    playback = tree.get("parameters/playback")
    if playback:
        playback.start("Idle")
        _state = "Idle"
    else:
        print("PlayerAnimationComponent: parameters/playback не появился")

## ── Стейт-машина локомоции (правила переходов живут здесь) ──────────────

func _build_loco_machine() -> AnimationNodeStateMachine:
    var sm := AnimationNodeStateMachine.new()
    _add_anim_node(sm, "Idle", "Idle")
    _add_anim_node(sm, "Run", "Run")
    _add_anim_node(sm, "Jump", "Jump_Launch")
    _add_anim_node(sm, "Falling", "Falling")
    _add_anim_node(sm, "Landing", "Landing_Cut")
    _add_anim_node(sm, "FrontFlip", "FrontFlip_Fast")
    # [из, в, xfade, auto_at_end]: ENABLED = переключаем travel()'ом,
    # AUTO+AT_END = дерево доигрывает клип и уходит само.
    var tr := [
        ["Idle", "Run", 0.15, false],
        ["Run", "Idle", 0.2, false],
        ["Idle", "Jump", 0.1, false],
        ["Run", "Jump", 0.1, false],
        ["Landing", "Jump", 0.1, false],
        ["Jump", "Falling", 0.2, false],
        ["Jump", "Landing", 0.1, false],
        ["Idle", "Falling", 0.25, false],
        ["Run", "Falling", 0.25, false],
        ["Landing", "Falling", 0.25, false],
        ["Falling", "Landing", 0.1, false],
        ["Falling", "FrontFlip", 0.15, false],
        ["Jump", "FrontFlip", 0.15, false],
        ["FrontFlip", "Falling", 0.2, true],
        ["Landing", "Idle", 0.2, true],
        ["Landing", "Run", 0.1, false],
    ]
    for t in tr:
        var trans := AnimationNodeStateMachineTransition.new()
        trans.xfade_time = t[2]
        if t[3]:
            trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
            trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
        else:
            trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
        sm.add_transition(t[0], t[1], trans)
    return sm

func _add_anim_node(sm: AnimationNodeStateMachine, node_name: String, anim: String) -> void:
    var an := AnimationNodeAnimation.new()
    an.animation = anim
    sm.add_node(node_name, an)

func _travel(to: String) -> void:
    if _state == to:
        return
    _state = to
    # travel() ОТЛОЖЕН: фейд материализуется на следующем проходе дерева.
    # Ресинк в _process не должен затереть намерение этим же кадром.
    _last_travel_frame = Engine.get_process_frames()
    playback.travel(to)

## ── Прыжок (вызов из PlayerController) ──────────────────────────────────

func play_jump(double: bool = false) -> void:
    if playback == null:
        return
    # Двойной прыжок — сальто (верdict 17.11.26): FrontFlip_Fast растянут под
    # время полёта (скорость зашита в производный клип); AT_END сам уведёт в
    # Falling, если ещё в воздухе. Одиночный — Jump_Launch (старт с отрыва,
    # без приседа в воздухе).
    _travel("FrontFlip" if double else "Jump")

## ── Каст-анимации: верх тела на CastPlayer (всегда UB) ──────────────────

func has_cast_anim(anim_name: String) -> bool:
    return cast_player != null and anim_name != "" \
            and cast_player.has_animation(anim_name + "_UB")

## Инста-каст: UB-вариант поверх текущего состояния локомоции. capture()
## блендит из ТЕКУЩЕЙ позы (бег/падение) — без него рывок через rest.
## Спам/перебивание: play() на уже играющем (даже том же) клипе НЕ рестартует
## его, а прежний capture-оверлей продолжает писать позу — «прошлая анимация
## не отменяется» (зонд probe_cast_cancel.gd S1: pos 0.302→0.323). Фикс:
## чистый stop() → рестарт с нуля, вход из ТЕКУЩЕЙ позы (S3: гладко).
func play_cast_anim(anim_name: String) -> void:
    var ub := anim_name + "_UB"
    if cast_player == null or not cast_player.has_animation(ub):
        return
    cast_player.stop()
    cast_player.play(ub, 0.1)
    cast_player.capture(ub, 0.1)

## Старт канала: Enter (0.53с) → сигнал сам подхватит Loop. stop() — та же
## отмена предыдущего каста, что и в play_cast_anim.
func play_channel() -> void:
    if not cast_player:
        return
    _channel = true
    for ub in ["Cast_Enter_UB", "Cast_Loop_UB"]:
        if cast_player.has_animation(ub):
            cast_player.stop()
            cast_player.play(ub, 0.1)
            cast_player.capture(ub, 0.1)
            break

## Конец канала: выброс (Cast_Shoot_UB). Локомоция не трогается — ноги жили
## всё время канала.
func end_channel() -> void:
    if not _channel:
        return
    _channel = false
    if cast_player and cast_player.has_animation("Cast_Shoot_UB"):
        cast_player.stop()
        cast_player.play("Cast_Shoot_UB", 0.1)
        cast_player.capture("Cast_Shoot_UB", 0.1)

## Естественное окончание клипа на CastPlayer (loop-клипы сигнал не дают).
func _on_cast_anim_finished(anim_name: StringName) -> void:
    # Канал: Enter доиграл → Loop (capture — вход из позы конца Enter,
    # иначе 0.1с бленд проваливается через rest). Локомоция НЕ замирает.
    if _channel and String(anim_name) == "Cast_Enter_UB" \
            and cast_player and cast_player.has_animation("Cast_Loop_UB"):
        cast_player.play("Cast_Loop_UB", 0.1)
        cast_player.capture("Cast_Loop_UB", 0.1)

## ── FSM локомоции: только решение «какое состояние», перетекания — в дереве

func _process(_delta):
    if playback == null:
        return

    var parent = get_parent()
    var speed = Vector2(parent.velocity.x, parent.velocity.z).length()
    var in_air = not parent.is_on_floor()

    # Ресинк намерения: AUTO+AT_END уводит узел дерева без кода. Пока фейд
    # идёт, get_current_node отдаёт ИСТОЧНИК (проверено зондом) — не трогаем;
    # и 2 кадра после кодового travel (фейд ещё не материализовался).
    if Engine.get_process_frames() - _last_travel_frame > 1 \
            and playback.get_fading_from_node() == StringName():
        var actual := String(playback.get_current_node())
        if actual != "" and actual != _state:
            _state = actual

    if in_air:
        air_frames += 1
        was_in_air = true
        if _state == "Jump":
            # FALL: пройдена вершина дуги прыжка.
            if parent.velocity.y < 0.0:
                _travel("Falling")
            return
        # Сальто и падение доигрывает дерево (AT_END уведёт в Falling);
        if _state == "FrontFlip" or _state == "Falling":
            return
        # FALL: сорвался с уступа без прыжка (несколько кадров в воздухе —
        # гистерезис против мигания is_on_floor на склонах).
        if air_frames > 3:
            _travel("Falling")
        return

    air_frames = 0

    # Приземление: бег перебивает тем же кадром, стоя — доигрываем Landing,
    # AT_END сам уведёт в Idle (ресинк вернёт _state).
    if was_in_air:
        was_in_air = false
        _travel("Run" if speed >= 0.001 else "Landing")
        return

    # Свежий Jump при ещё «земном» is_on_floor (кадр стейла до первого
    # move_and_slide после старта прыжка) — не съедаем в Idle/Landing.
    # Лимит 6 кадров: если физика так и не подбросила (потолок), отдаём
    # состояние обычной земле-ветке — иначе Jump залипает навсегда.
    if _state == "Jump" and Engine.get_process_frames() - _last_travel_frame <= 6:
        return

    if speed < 0.001:
        if _state != "Idle":
            _travel("Idle")
    else:
        if _state != "Run":
            _travel("Run")

## ── Производные клипы ────────────────────────────────────────────────────

## Копия клипа без отрезка [0, off): ключи ДО off удаляются, ОСТАЛЬНЫЕ
## сдвигаются назад на off (иначе первый оставшийся ключ стоит на off и
## сэмплинг до него держит замороженную позу 0.33с — регресс прыжка 17.11.26).
## Квирик 4.8: track_clear нет — удаляем по индексам с хвоста.
func _cut_from(src: Animation, off: float) -> Animation:
    var a: Animation = src.duplicate(true)
    for i in a.get_track_count():
        for k in range(a.track_get_key_count(i) - 1, -1, -1):
            if a.track_get_key_time(i, k) < off:
                a.track_remove_key(i, k)
            else:
                a.track_set_key_time(i, k, a.track_get_key_time(i, k) - off)
    a.length = maxf(a.length - off, 0.01)
    return a

## Копия клипа в диапазоне [start..end): голова срезается как в _cut_from,
## хвост — ключи позже длины сегмента удаляются. Границы — по дампам ключей
## (Hips Y): Jump 0.75 = пик дуги, Landing 0.47 = низ приседа-удара.
func _cut_range(src: Animation, start: float, end: float) -> Animation:
    var a := _cut_from(src, start)
    var seg := minf(end, src.length) - start
    for i in a.get_track_count():
        for k in range(a.track_get_key_count(i) - 1, -1, -1):
            if a.track_get_key_time(i, k) > seg:
                a.track_remove_key(i, k)
    a.length = maxf(seg, 0.01)
    return a

## Копия клипа, растянутая/сжатая до target_len (бывший custom_speed сальто)
func _stretched(src: Animation, target_len: float) -> Animation:
    var a: Animation = src.duplicate(true)
    var k: float = target_len / a.length
    for i in a.get_track_count():
        var times: Array = []
        var vals: Array = []
        for j in a.track_get_key_count(i):
            times.append(a.track_get_key_time(i, j) * k)
            vals.append(a.track_get_key_value(i, j))
        for j in range(a.track_get_key_count(i) - 1, -1, -1):
            a.track_remove_key(i, j)
        for j in times.size():
            a.track_insert_key(i, times[j], vals[j])
    a.length = target_len
    return a
