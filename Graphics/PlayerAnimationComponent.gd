extends Node

## Архитектура анимаций («всегда UB» + AnimationTree, 17.11.26):
##   ЛОКОМОЦИЯ — AnimationTree со стейт-машиной (строится КОДОМ в _ready,
##   никаких правок .tscn). AnimationPlayer остаётся ИСТОЧНИКОМ анимаций
##   (дерево берёт клипы из его библиотеки, сам он больше ничего не играет).
##   Игровой код только travel(): правила перетекания (xfade) живут в схеме.
##   AUTO+AT_END: Landing→Idle и FrontFlip→Falling доигрывают сами, без кода.
##   _state = НАМЕРЕНИЕ кода; дерево может уйти дальше само (AUTO AT_END) —
##   каждый кадр ресинк по факту, когда фейд завершён (fading_from пуст).
##   23.11.26 вердикт спеца (гибрид): Run_Start/Run_Stop ДРОПНУТЫ — Idle↔Run
##   крестфейд 0.14 с, темп Run тянется за фактической скоростью тела
##   (TimeScale clamp 0.7..1.8), «разгон/торможение» докручивает процедурный
##   lean/dip/bank (SkeletonLeanModifier поверх позы). Физика НЕ тронута.
##   F4 A/B нейро-бег удалён (директива юзера 23.11.26) — остался Mixamo Run.
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
var _cast_layer: Node = null   # CastAnimationLayer (фасад кастов, Ф2.1/2.2)
## Совместимость: гейты (test_cast_anims, render_tree_check) обращаются к плееру
## кастов напрямую. Сам плеер теперь живёт в слое CastAnimationLayer.
var cast_player: AnimationPlayer:
    get:
        return _cast_layer.cast_player if _cast_layer != null else null
var tree: AnimationTree
var playback  # AnimationNodeStateMachinePlayback
var _state: String = ""  # намерение кода; дерево может уйти само (AUTO AT_END)
var _last_travel_frame: int = -100  # кадр последнего кодового travel (ресинк-гвард)
var was_in_air: bool = false
var air_frames: int = 0  # гистерезис против «мигания» is_on_floor на склонах
var _channel: bool = false  # длительный каст (метеор/гром): движение гасится

## Процедурный lean/dip/bank (вердикт спеца 23.11.26): физика стартует
## мгновенно, корпус «догоняет» — старт бега: наклон вперёд до 14° (пружина
## ~0.25 с), стоп: откид назад ~6.5° + микро-присед таза 4.5 см (возврат
## ~0.2 с), поворот: крен по скорости рыскания ±6°.
## Значения читает SkeletonLeanModifier (ребёнок скелета, применяется ПОСЛЕ
## всей анимации — порядок пайплайна модификаторов).
var lean_amount: float = 0.0   # радианы, + = наклон вперёд
var dip_amount: float = 0.0    # метры, + = присед таза вниз
var bank_amount: float = 0.0   # радианы, + = крен влево (в сторону поворота)
var _lean_target: float = 0.0
var _dip_target: float = 0.0
var _lean_vel: float = 0.0
var _dip_vel: float = 0.0
var _bank_target: float = 0.0
var _prev_yaw: float = 0.0
var _hand_mod: SkeletonModifier3D = null       # позы пальцев (вес 0 = no-op)
var _aim_mod: SkeletonModifier3D = null        # прицел позвоночником (спец)
var aim_point: Vector3 = Vector3.ZERO          # глобальная точка прицела
var aim_weight: float = 0.0                    # 0..1 (вход 0.08 / выход 0.20)
var recoil_amount: float = 0.0                 # отдача Spine2 (пружина 0.15с)
var _aim_timer: float = 0.0
var _recoil_vel: float = 0.0
const LEAN_START_RAD := 0.244  # 14° — старт бега (спец 10–15°)
const LEAN_STOP_RAD := 0.113   # 6.5° — откид при стопе (спец 5–8°)
const DIP_STOP_M := 0.045      # микро-присед таза (спец 4–5 см)
const BANK_MAX_RAD := 0.105    # ±6°
const BANK_RATE := 0.025       # рад крена на рад/с рыскания
const RUN_TS_MIN := 0.7        # клампы темпа Run (спец)
const RUN_TS_MAX := 1.8

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

    # Процедурный lean/dip/bank (спец 23.11.26): модификатор поверх позы.
    # preload, НЕ class_name: глобальный кэш классов в headless-запусках без
    # --import не содержит новый класс.
    var skel := _find_skeleton(anim_player.get_parent())
    if skel:
        var lean_mod: SkeletonModifier3D = preload("res://Graphics/SkeletonLeanModifier.gd").new()
        skel.add_child(lean_mod)
        lean_mod.anim_comp = self
        # Позы пальцев (вердикт спеца): вес 0 = no-op (Mixamo-клипы с родными
        # пальцами); нейро/UAL-касты ставят вес через set_hand_pose.
        _hand_mod = preload("res://Graphics/HandPoseModifier3D.gd").new()
        skel.add_child(_hand_mod)
        _hand_mod.anim_comp = self
        # Прицел позвоночником (спец): мягкий pitch/yaw к цели вместо IK.
        _aim_mod = preload("res://Graphics/AimSpineModifier.gd").new()
        skel.add_child(_aim_mod)
        _aim_mod.anim_comp = self
    else:
        print("PlayerAnimationComponent: скелет не найден — lean-модификатор не поставлен")

    # Каст-слой (Ф2.1/2.2): фасад CastAnimationLayer над CastPlayer (тот же
    # скелет, пишет поверх дерева; ноги ведёт FSM). Enter→Loop внутри слоя.
    _cast_layer = preload("res://Graphics/CastAnimationLayer.gd").new()
    add_child(_cast_layer)
    _cast_layer.setup(anim_player, Callable())

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
    # Run = вложенный BlendTree с обычным AnimationNodeAnimation (лупится).
    # ВАЖНО (23.11.26): AnimationNodeTimeScale в 4.8-beta3 — ПУСТОЙ класс;
    # замена через use_custom_timeline+stretch_time_scale ЛОМАЕТ ЛУП (клип
    # играет 1 раз и замирает на последнем кадре — баг «замирает через 1с»).
    # Поэтому Run играет с постоянной скоростью; темп-скейл отложен.
    var run_bt := AnimationNodeBlendTree.new()
    var run_anim := AnimationNodeAnimation.new()
    run_anim.animation = "Run"
    run_bt.add_node("run", run_anim, Vector2(0, 100))
    run_bt.connect_node("output", 0, "run")
    sm.add_node("Run", run_bt)
    _add_anim_node(sm, "Jump", "Jump_Launch")
    _add_anim_node(sm, "Falling", "Falling")
    _add_anim_node(sm, "Landing", "Landing_Cut")
    _add_anim_node(sm, "FrontFlip", "FrontFlip_Fast")
    # [из, в, xfade, auto_at_end]: ENABLED = переключаем travel()'ом,
    # AUTO+AT_END = дерево доигрывает клип и уходит само.
    # Гибрид спеца: Run_Start/Run_Stop дропнуты — Idle↔Run крестфейд 0.14 с,
    # «разгон/торможение» докручивает lean-модификатор, а не клипы.
    var tr := [
        ["Idle", "Run", 0.14, false],
        ["Run", "Idle", 0.14, false],
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

## Позы пальцев для нейро/UAL-каста (SkillDB.hand_pose): preset + вес.
## weight 0 → возврат к родным пальцам клипа (Mixamo).
func set_hand_pose(preset: String, w: float) -> void:
    if _hand_mod:
        _hand_mod.preset = preset
        _hand_mod.weight = w

## Прицел позвоночником (спец): точка + окно. Вес вход 0.08/выход 0.20,
## отдача Spine2 (пружина 0.15с).
func set_aim(p: Vector3, duration: float) -> void:
    aim_point = p
    _aim_timer = maxf(_aim_timer, duration)
    recoil_amount = 1.0
    _recoil_vel = 0.0

func _travel(to: String) -> void:
    if _state == to:
        return
    _state = to
    # travel() ОТЛОЖЕН: фейд материализуется на следующем проходе дерева.
    # Ресинк в _process не должен затереть намерение этим же кадром.
    _last_travel_frame = Engine.get_process_frames()
    playback.travel(to)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for c in node.get_children():
        var r = _find_skeleton(c)
        if r:
            return r
    return null

## ── Прыжок (вызов из PlayerController) ──────────────────────────────────

func play_jump(double: bool = false) -> void:
    if playback == null:
        return
    # Двойной прыжок — сальто (верdict 17.11.26): FrontFlip_Fast растянут под
    # время полёта (скорость зашита в производный клип); AT_END сам уведёт в
    # Falling, если ещё в воздухе. Одиночный — Jump_Launch (старт с отрыва,
    # без приседа в воздухе).
    _travel("FrontFlip" if double else "Jump")

## ── Каст-анимации: делегация фасаду CastAnimationLayer (Ф2.1/2.2) ────────

func has_cast_anim(anim_name: String) -> bool:
    return _cast_layer != null and _cast_layer.has_cast_anim(anim_name)

func play_cast_anim(anim_name: String, speed: float = 1.0) -> void:
    if _cast_layer == null:
        return
    # СТОЯ (speed<0.2, на полу) → Full-Body (Hips+ноги: шаг/присед, ступни
    # на полу — ноги не «забетонированы»). БЕГ → UB (только верх тела).
    var parent = get_parent()
    var hs := 0.0
    if parent is CharacterBody3D:
        hs = Vector2(parent.velocity.x, parent.velocity.z).length()
        if hs < 0.2 and parent.is_on_floor():
            _cast_layer.play_full_body(anim_name, speed)
            return
    _cast_layer.play_cast_anim(anim_name, speed)

func cast_clip_length(anim_name: String) -> float:
    if _cast_layer == null:
        return 0.0
    return _cast_layer.cast_clip_length(anim_name)

## Длина РЕАЛЬНО играющего каст-клипа (стоя — full-body, в бегу — UB: короче/
## длиннее на хвост 0.2 с). Окно отмены инста-каста считает прогресс по этому
## значению (SpellCasterComponent), а не по длине UB.
func cast_last_len() -> float:
    return _cast_layer.last_len if _cast_layer != null else 0.0

func play_channel(clip: String = "", fit_speed: float = 1.0) -> void:
    if _cast_layer:
        _channel = true
        _cast_layer.play_channel(clip, fit_speed)

func end_channel() -> void:
    if _cast_layer:
        _channel = false
        _cast_layer.end_channel()

## Клип-состояние (крылья, гитара барда): loop-клип, владелец гасит сам.
func play_cast_loop(anim_name: String) -> void:
    if _cast_layer != null:
        _cast_layer.play_cast_loop(anim_name)

func stop_cast_loop(anim_name: String = "") -> void:
    if _cast_layer != null:
        _cast_layer.stop_cast_loop(anim_name)

func has_loop_state() -> bool:
    return _cast_layer != null and _cast_layer.has_loop_state()

## Темп, с которым надо играть клип, чтобы он ровно уложился в окно window_s
## (канал со своим клипом: метеор 2.97 с в окно 2.0 с → 1.49).
## Берём ДЛИНУ КАК ЗАПИСАНА (cast_raw_length), иначе деление на темп прошлого
## каста давало бы разный результат от каста к касту.
func cast_fit_speed(anim_name: String, window_s: float) -> float:
    if _cast_layer == null or window_s <= 0.0:
        return 1.0
    var raw: float = _cast_layer.cast_raw_length(anim_name)
    if raw <= 0.0:
        return 1.0
    return clampf(raw / window_s, 0.25, 4.0)
## ── FSM локомоции: только решение «какое состояние», перетекания — в дереве

func _process(delta):
    if playback == null:
        return

    var parent = get_parent()
    var speed = Vector2(parent.velocity.x, parent.velocity.z).length()
    var in_air = not parent.is_on_floor()
    var was_state := _state

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

    # Гибрид (спец 23.11.26): порогов и клипов разгона нет — Idle↔Run
    # крестфейд 0.14 с; «разгон/торможение» докручивает lean-модификатор.
    if speed < 0.001:
        if _state != "Idle":
            _travel("Idle")
    else:
        if _state != "Run":
            _travel("Run")

    _update_proc_deltas(delta, parent, speed, was_state)

## ── Процедурные дельты: пружины lean/dip, крен, темп Run (спец 23.11.26) ──

func _update_proc_deltas(delta: float, parent: Node, speed: float, was_state: String) -> void:
    # События старта/стопа: фактическая смена состояния Run↔Idle на земле
    # (в т.ч. Landing→Run — приземлился в бег).
    if was_state != _state:
        if _state == "Run" and (was_state == "Idle" or was_state == "Landing"):
            _lean_target = LEAN_START_RAD
            _dip_target = 0.0
        elif _state == "Idle" and was_state == "Run":
            _lean_target = -LEAN_STOP_RAD
            _dip_target = DIP_STOP_M
    # Цели затухают к нулю, пружины ведут позу (критическое демпфирование).
    _lean_target = lerpf(_lean_target, 0.0, 1.0 - exp(-delta / 0.3))
    _dip_target = lerpf(_dip_target, 0.0, 1.0 - exp(-delta / 0.25))
    var k_l := pow(TAU / 0.25, 2.0)   # lean: период 0.25 с
    _lean_vel += (k_l * (_lean_target - lean_amount) - 2.0 * sqrt(k_l) * _lean_vel) * delta
    lean_amount += _lean_vel * delta
    var k_d := pow(TAU / 0.2, 2.0)    # dip: период 0.2 с
    _dip_vel += (k_d * (_dip_target - dip_amount) - 2.0 * sqrt(k_d) * _dip_vel) * delta
    dip_amount += _dip_vel * delta
    # Крен по скорости рыскания (сглаженная); + = в сторону поворота.
    var yaw: float = parent.graphics_wrapper.rotation.y
    var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
    _prev_yaw = yaw
    _bank_target = clampf(yaw_rate * BANK_RATE, -BANK_MAX_RAD, BANK_MAX_RAD)
    bank_amount = lerpf(bank_amount, _bank_target, 1.0 - exp(-delta / 0.1))
    # Прицел позвоночником (спец): вес вход 0.08 / выход 0.20; отдача Spine2
    # — пружина 0.15с к 0.
    if _aim_timer > 0.0:
        _aim_timer -= delta
        aim_weight = minf(1.0, aim_weight + delta / 0.08)
    else:
        aim_weight = maxf(0.0, aim_weight - delta / 0.20)
    var k_r := pow(TAU / 0.15, 2.0)
    _recoil_vel += (k_r * (0.0 - recoil_amount) - 2.0 * sqrt(k_r) * _recoil_vel) * delta
    recoil_amount = maxf(0.0, recoil_amount + _recoil_vel * delta)
    # Темп Run: постоянная скорость (stretch_time_scale ломал луп — заморозка
    # на 1с; AnimationNodeTimeScale пуст в 4.8-beta3). Скейл отложен.

## ── Производные клипы ────────────────────────────────────────────────────

## Копия клипа без отрезка [0, off): ключи ДО off удаляются, ОСТАЛЬНЫЕ
## сдвигаются назад на off. НЕ сдвигать ключи на месте: track_set_key_time
## пересортировывает трек, и цикл по индексам сбивается — ключи сдвигаются
## дважды/теряются (Jump_Launch схлопывался в 6 ключей с временами
## 0.32–0.41 и обрывом позы вниз = «не прыгает, сразу падает», 18.11.26;
## зонд probe_cut_range.gd: старый алгоритм 6 ключей, безопасный 26).
## Безопасно: собрать (время, значение, transition) ДО правок, очистить
## трек, вставить заново по возрастанию. Квирик 4.8: track_clear нет.
func _cut_from(src: Animation, off: float) -> Animation:
    var a: Animation = src.duplicate(true)
    for i in a.get_track_count():
        var times: Array = []
        var payloads: Array = []
        for k in a.track_get_key_count(i):
            var t: float = a.track_get_key_time(i, k)
            if t < off:
                continue
            times.append(t - off)
            payloads.append([a.track_get_key_value(i, k), a.track_get_key_transition(i, k)])
        for k in range(a.track_get_key_count(i) - 1, -1, -1):
            a.track_remove_key(i, k)
        for j in times.size():
            a.track_insert_key(i, times[j], payloads[j][0], payloads[j][1])
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
