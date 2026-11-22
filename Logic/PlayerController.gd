extends CharacterBody3D

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var jump_velocity: float = 4.5
var speed_mult: float = 1.0  # буст-скиллы (Q20 крылья) ставят 1.35 на окно действия

## Полёт на крыльях (Q20 v2, вердикт юзера: «скилл активен — не летает,
## просто ускорение»): ставит true/false WingsComponent.activate/deactivate.
## Пока крылья активны: удержание Space в воздухе = тяга вверх, без Space
## падение глайдом (медленное), на земле Space = обычный прыжок.
var wings_fly: bool = false

## Тяга крыльев вверх и скорость планирования (м/с).
const WINGS_LIFT: float = 4.2
const WINGS_GLIDE: float = -2.0

const GRAVITY: float = 9.8

## Общий бюджет очков навыков (механика добора SP пока не введена).
const SP_MAX: int = 50

var camera: Camera3D
var spring_arm: Node3D
## Pitch камеры — СКАЛЯР (SSOT). Читать его обратно из базиса пивота нельзя:
## в Фазе 1 базис маппится матрицей портала (произвольный yaw/наклон) и
## эйлер YXZ такого базиса возвращает мусор (гимбал-флип) → инверсия мыши,
## живущая и после деспавна порталов (регресс Q44-R, вердикт юзера 26.11.26).
var _cam_pitch: float = 0.0
var graphics_wrapper: Node3D
var spell_caster: Node

var skill_points: int = SP_MAX
var player_hp: int = 100

var unlocked_skills = {}
var can_double_jump: bool = false
var was_space_pressed: bool = false

## Свип телепорта (TeleportEffect): пока true, позицией владеет твин —
## ввод/гравитация спят, move_and_slide гоняется только ради is_on_floor().
var input_locked: bool = false

var hud_hp: ProgressBar
var hp_label: Label
var is_dying: bool = false

## Макс HP игрока: враги ада наносят % ОТ ЭТОГО ЧИСЛА (верб. юзера 19.11.26).
const MAX_HP: int = 100

## Q44-R порталы v2 (спец, баг №3): фазовое состояние камеры-пивота.
var _arm_mask: int = 0        # штатная collision_mask SpringArm (Фаза 1 глушит)
var _shoulder := Vector3.ZERO # локальный оффсет пивота на теле
var _p2_cam_prev := 1e9       # локальный z камеры у входного портала (кадр назад)
var _p2_t0_seen := 0          # t0 последнего захода (сброс prev на новый проход)

## В.7 (вердикт 09): поза-боб в активной стойке — модель качается по синусу
## в такт биту (beat_len от /root/RhythmConductor); T3 «Потока» — плавная
## левитация +0.18 м. База позиции модели запоминается на входе в стойку,
## при выходе модель возвращается на базу.
const STANCE_BOB_AMP := 0.04
const STANCE_LEVITATE := 0.18
var _bob_base_y := INF
var _bob_lift := 0.0
var _bob_active := false

## Q48 «Эфирный захват» (ТЗ §4.2): данные инерции в воздухе и банни-хопа.
## _air_hvel — горизонталь последнего воздушного тика; при приземлении она
## уходит в _landed_hvel и прыжок в первые 0.14 с возвращает ~80% импульса.
var _air_hvel := Vector2.ZERO
var _landed_hvel := Vector2.ZERO
var _was_airborne := false
var _since_landing := 1e9

func _ready():
    process_physics_priority = 100 # перенос портала в тике РАНЬШЕ камеры (спец)
    add_to_group("player") # цель для врагов ада (HellEnemyBase)
    camera = $SpringArm3D/Camera3D
    spring_arm = $SpringArm3D
    graphics_wrapper = $GraphicsWrapper
    spell_caster = $SpellCasterComponent
    
    if spring_arm:
        spring_arm.add_excluded_object(self.get_rid())
        spring_arm.position.y = 0.5
        # Q44-R (спец, баг №3): SpringArm — ребёнок тела, телепорт матрицей
        # утаскивал камеру вместе с телом («залезание в окно» невозможно).
        # top_level: пивот живёт в мире, каждый физ-тик ставим вручную —
        # штатный след (Фаза 0) или фазовый перенос через портал.
        _arm_mask = spring_arm.collision_mask
        _shoulder = spring_arm.position
        _cam_pitch = spring_arm.rotation.x  # стартовый наклон из сцены
        spring_arm.top_level = true

    if graphics_wrapper:
        graphics_wrapper.position.y = -1.0
        
    var all_skills = SkillDB.get_skills()
    for s_id in all_skills:
        if not unlocked_skills.has(s_id):
            unlocked_skills[s_id] = false

    # Персист скиллов между картами (19.11.26): change_scene пересоздаёт игрока,
    # купленные навыки/SP слетали в ноль. Восстановление из автолоада-сессии.
    var session = get_node_or_null("/root/PlayerSession")
    if session and session.has_state:
        session.restore(self)

    setup_hud()

    var skill_menu = preload("res://Graphics/SkillMenu.gd").new()
    add_child(skill_menu)

    # Рэгдолл-смерть игрока (QUEUE Q26, фидбэк юзера 19.11.26: «перс просто
    # исчезает, рэгдола нет»): компонент куклы как у врагов ада, activate() в
    # take_damage. Скин без PhysicalBoneSimulator3D → путь куклы-манекена.
    var rag := Node.new()
    rag.name = "Ragdoll"
    rag.set_script(load("res://Graphics/RagdollComponent.gd"))
    rag.set("tint", Color(0.85, 0.9, 1.0))
    add_child(rag)
    
    var action_bar = preload("res://Graphics/ActionBar.gd").new()
    add_child(action_bar)

    # AIM ASSIST (QUEUE Q29): отметка целей рядом с прицелом + честный перенос
    # помеченной цели в каст (SpellCasterComponent._aim_context assist-first).
    var aim_assist := Node.new()
    aim_assist.name = "AimAssist"
    aim_assist.set_script(load("res://Logic/AimAssistComponent.gd"))
    add_child(aim_assist)

    # Система стоек (Q16): Logic-компонент стоек, создаётся кодом (без
    # пересборки скинов). UI подключается к его сигналам сам (ActionBar).
    if get_node_or_null("StanceComponent") == null:
        var stance_comp := Node.new()
        stance_comp.name = "StanceComponent"
        stance_comp.set_script(load("res://Logic/StanceComponent.gd"))
        add_child(stance_comp)

    # Вход-вайб стойки «Концентрация маны» (Q16 Шаг 2): вспышка у кулаков.
    if get_node_or_null("ManaStanceVFX") == null:
        var vfx_comp := Node.new()
        vfx_comp.name = "ManaStanceVFX"
        vfx_comp.set_script(load("res://Graphics/ManaStanceVFX.gd"))
        add_child(vfx_comp)

    # «Поток Гармонии» (Q16 Шаг 6): топливо/барьер/tier/рикошет/полифония.
    if get_node_or_null("BardFlowComponent") == null:
        var bard_comp := Node.new()
        bard_comp.name = "BardFlowComponent"
        bard_comp.set_script(load("res://Logic/BardFlowComponent.gd"))
        add_child(bard_comp)

    # Визуал Потока (Q16 Шаг 7): купол-барьер + дуги вокруг прицела.
    if get_node_or_null("AcousticBarrierVFX") == null:
        var dome_vfx = preload("res://Graphics/AcousticBarrierVFX.gd").new()
        dome_vfx.name = "AcousticBarrierVFX"
        add_child(dome_vfx)
    if get_node_or_null("BardFlowUI") == null:
        var flow_ui = preload("res://Graphics/BardFlowUI.gd").new()
        flow_ui.name = "BardFlowUI"
        add_child(flow_ui)

func _exit_tree():
    # Снапшот скиллов при уходе с карты (телепорт непися / меню I / смерть).
    # Дети к этому моменту вышли из дерева, но живы — ActionBar читается.
    var session = get_node_or_null("/root/PlayerSession")
    if session:
        session.capture(self)

func setup_hud():
    var hud = CanvasLayer.new()
    hud.name = "PlayerHUD"

    # 19.11.26 (верб. юзера): панель HP по центру снизу, НАД панелью скиллов,
    # цифры «20/100» вместо процентов. Оффсеты явные (паттерн TeleportMenu):
    # низ экрана, 300×28, зазор над ActionBar (слоты 55 px при y=-80).
    hud_hp = ProgressBar.new()
    hud_hp.custom_minimum_size = Vector2(300, 28)
    hud_hp.anchor_left = 0.5
    hud_hp.anchor_right = 0.5
    hud_hp.anchor_top = 1.0
    hud_hp.anchor_bottom = 1.0
    hud_hp.offset_left = -150
    hud_hp.offset_right = 150
    hud_hp.offset_top = -116
    hud_hp.offset_bottom = -88
    hud_hp.max_value = MAX_HP
    hud_hp.value = player_hp
    hud_hp.show_percentage = false
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.2, 0.7, 0.2, 1.0)
    hud_hp.add_theme_stylebox_override("fill", sb)
    hud.add_child(hud_hp)

    hp_label = Label.new()
    hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
    hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hp_label.text = "%d/%d" % [player_hp, MAX_HP]
    hud_hp.add_child(hp_label)

    add_child(hud)

func update_hud():
    if hud_hp: hud_hp.value = player_hp
    if hp_label: hp_label.text = "%d/%d" % [player_hp, MAX_HP]

## Q35 (юзер 19.11.26): игрок — дружественная цель сердечек, лечится и
## инициатор каста. Без heal() сердечко игрока пролетало насквозь.
var is_friendly: bool = true

func heal(amount: int):
    player_hp = mini(MAX_HP, player_hp + amount)
    update_hud()

## Урон игроку (ад, 19.11.26): враги наносят % от MAX_HP (5% ближники, 2% дальники).
## Смерть в аду → респавн на обычной арене, где манекены (верб. юзера).
func take_damage(amount: int, attacker: Node = null):
    if is_dying:
        return
    # Q16 Шаг 6: купол «Потока Гармонии» перехватывает урон в Потоке
    # (полное поглощение + Нота-Рикошет). Вне Потока — урон как обычно.
    var bf = get_node_or_null("BardFlowComponent")
    if bf != null and bf.has_method("player_damage_hook") \
            and bool(bf.player_damage_hook(amount, attacker)):
        return
    player_hp = max(0, player_hp - amount)
    update_hud()
    var md = get_node_or_null("/root/MusicDirector")
    if md:
        md.note_combat()
    if player_hp <= 0:
        is_dying = true
        # Рэгдолл-смерть (QUEUE Q26, фидбэк юзера: «перс просто исчезает,
        # мгновенный респавн на новую локу»): кукла-труп на месте смерти,
        # респавн через 2.5 с — труп успевает упасть и полежать.
        var rag = get_node_or_null("Ragdoll")
        if rag:
            rag.activate(MAX_HP, Vector3(0, 1, 0))
        if graphics_wrapper:
            graphics_wrapper.hide()
        var col = get_node_or_null("CollisionShape3D")
        if col:
            col.set_deferred("disabled", true)
        await get_tree().create_timer(2.5).timeout
        get_tree().change_scene_to_file("res://Scenes/MainArena.tscn")

func use_skill(skill_id: String):
    if not unlocked_skills.get(skill_id, false):
        # В.6.3 (вердикт спеца): никаких тихих отказов — тост в HUD.
        var ab = get_node_or_null("ActionBar")
        if ab != null and ab.has_method("show_toast"):
            ab.show_toast("Навык не изучен")
        return
    if skill_id == "double_jump":
        return 
        
    if spell_caster and spell_caster.has_method("cast_skill"):
        spell_caster.cast_skill(skill_id)

func unlearn_cleanup(skill_id: String):
    var action_bar = get_node_or_null("ActionBar")
    if action_bar and action_bar.has_method("remove_skill"):
        action_bar.remove_skill(skill_id)

## МЫШЬ: вращение камеры — сырой ввод в _input (при захвате GUI не должен
## глотать motion: STOP-контрол под виртуальным курсором съедает события до
## _unhandled_input — камера «умирала»). ЗАХВАТ же мыши — в _unhandled_input:
## он срабатывает ТОЛЬКО когда клик не съеден GUI (клик по карточке телепорта/
## ползунку F2 до капчура не дойдёт — Q24). Вариант Q24 v1 (гейт по
## gui_get_hovered_control в _input) вечно блокировал захват — фидбэк юзера
## 19.11.26 «мышь не фокусится в игру больше никак».
func _input(event):
    if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
        return

    if event is InputEventMouseMotion:
        rotate_y(-event.relative.x * mouse_sensitivity)
        # Pitch — только в скаляр: rotate_x по узлу в Фазе 1 работал по
        # маппнутому базису, и эйлер от него инвертировал управление.
        _cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_sensitivity,
            -1.2, 1.2)

    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Клик по пустому месту (GUI его не съел) = захват мыши. Клик по живому
## GUI-контролу (F2, карточки телепорта, HUD-слоты) до сюда не доходит.
func _unhandled_input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
            and event.pressed:
        if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not _gui_blocks_capture():
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## true, если клик должен уйти в UI, а не в захват мыши: открыто меню
## (скилл-меню игрока, F2-настройки) или диалог непися-телепортера
## (группа npc_dialog_open). Hovered-эвристики не нужны: клик по живому
## контролу сам не дойдёт до _unhandled_input.
## Меню-I больше нет (убрано 19.11.26: перемещение — только через неписей).
func _gui_blocks_capture() -> bool:
    var menu = get_node_or_null("SkillMenu")
    if menu and menu.is_open:
        return true
    var ui = get_node_or_null("/root/SettingsMenu")
    if ui and ui.get("is_open"):
        return true
    var forge = get_node_or_null("/root/SkillForgeWindow")
    if forge and forge.get("is_open"):
        return true
    # Окно телепортера-непися (NPCTeleporter живёт в сцене, не autoload):
    # группа-флаг ставится/снимается в _open_dialog/_close_dialog.
    if get_tree().get_first_node_in_group("npc_dialog_open"):
        return true
    return false

## В.7: поза-боб стойки — визуал, каждый кадр (не физика). Пока стойка
## активна, модель = база + плавная левитация (T3 Потока) + покачивание
## в такт биту sin(beat_phase·TAU)·0.04; при выходе — возврат на базу.
func _process(delta: float) -> void:
    if graphics_wrapper == null:
        return
    var model = graphics_wrapper.get_node_or_null("PlayerModel")
    if model == null:
        return
    var stance = get_node_or_null("StanceComponent")
    var active: bool = stance != null and bool(stance.is_active)
    if active != _bob_active:
        _bob_active = active
        if not active:
            model.position.y = _bob_base_y
            _bob_lift = 0.0
            return
        _bob_base_y = model.position.y
    if not active:
        return
    # T3 «Потока»: цель левитации +0.18, лерп к цели — без рывка.
    var bf = get_node_or_null("BardFlowComponent")
    var target_lift := 0.0
    if bf != null and bool(bf.is_flowing) and int(bf.tier) >= 3:
        target_lift = STANCE_LEVITATE
    _bob_lift = lerpf(_bob_lift, target_lift, minf(delta * 6.0, 1.0))
    # Покачивание в такт биту: фаза = song_time / beat_len (120 BPM → 0.5 с).
    var phase := 0.0
    var cond = get_node_or_null("/root/RhythmConductor")
    if cond != null and float(cond.beat_len) > 0.0:
        phase = float(cond.song_time) / float(cond.beat_len)
    model.position.y = _bob_base_y + _bob_lift + sin(phase * TAU) * STANCE_BOB_AMP

func _physics_process(delta):
    # Смерть (Q30, фидбэк юзера «перс падает сквозь пол»): тело заморожено —
    # коллизия отключена, гравитация не тянет капсулу под пол, камера не ныряет.
    if is_dying:
        velocity = Vector3.ZERO
        return
    # Поллинг идёт мимо системы событий: пока фокус у GUI (печать имени
    # пресета) — сырой ввод игры (WASD/Space) игнорируем.
    var typing: bool = get_viewport().gui_get_focus_owner() != null
    # Канал каста (метеор/гром): движение и прыжок заблокированы.
    var casting: bool = spell_caster != null and spell_caster.has_method("is_channeling") \
            and spell_caster.is_channeling()
    var locked: bool = typing or casting or input_locked
    var input_dir = Vector2.ZERO if locked else Vector2(
        int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
        int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
    )

    var local_dir = Vector3(input_dir.x, 0, input_dir.y)

    var space_pressed = (not locked) and Input.is_key_pressed(KEY_SPACE)

    # Эфирный захват (Q48): пока нить активна, физика тела — у TetherSwingComponent
    # (перезапись velocity ходьбой убила бы маятник/зип, ТЗ §4.1). Мышь свободна —
    # пивот камеры top_level, обновляем его вручную и выходим. Свип телепорта
    # (input_locked) владеет телом — нить тихо рвём.
    var tether = get_node_or_null("TetherSwing")
    if tether != null and tether.is_active():
        if input_locked:
            tether.release(false)
        else:
            tether.physics_step(delta, input_dir, space_pressed)
            # Приземление может случиться и внутри троса (низкий зип скользит
            # по полу) — окно банни-хопа открываем здесь же, как в штатной ветке.
            if not is_on_floor():
                _air_hvel = Vector2(velocity.x, velocity.z)
                _was_airborne = true
            elif _was_airborne:
                _since_landing = 0.0
                _landed_hvel = _air_hvel
                _was_airborne = false
            was_space_pressed = space_pressed
            _update_camera_pivot()
            return

    if local_dir.length() > 0.1:
        local_dir = local_dir.normalized()
        var target_angle = atan2(local_dir.x, local_dir.z)
        graphics_wrapper.rotation.y = lerp_angle(graphics_wrapper.rotation.y, target_angle, delta * 10.0)

    var global_dir = (global_transform.basis * local_dir)

    # Множитель ускорения (Q20 крылья: 1.35 на окно активности, ставит
    # WingsComponent.activate/deactivate; остальные скиллы не трогают).
    # Стойка барда (вердикт юзера 22.11.26): «Поток Гармонии» режет скорость
    # передвижения на 50% — концерт требует стоять в ритме.
    var stance_mult := 1.0
    var stance_c = get_node_or_null("StanceComponent")
    if stance_c != null and stance_c.is_active \
            and str(stance_c.stance_skill_id) == "bard_flow":
        stance_mult = 0.5
    var run_speed := speed * speed_mult * stance_mult

    # Q48 Momentum Preservation (ТЗ §4.2): в воздухе быструю горизонталь
    # (после отрыва троса/бустов) НЕ клампим до run_speed — излишек над
    # run_speed гасится лёгким air drag (exp 0.5/с), WASD мягко подруливают
    # направление (slerp 3/с), не сжигая модуль. На полу / крылья / медленный
    # полёт — штатная жёсткая запись (без троса поведение не меняется).
    var hvel := Vector2(velocity.x, velocity.z)
    if not is_on_floor() and not wings_fly and hvel.length() > run_speed * 1.05:
        var sp: float = hvel.length()
        var new_sp: float = run_speed + (sp - run_speed) * exp(-0.5 * delta)
        var wish2 := Vector2(global_dir.x, global_dir.z)
        if local_dir.length() > 0.1 and wish2.length() > 0.1:
            hvel = hvel.normalized().slerp(wish2.normalized(), minf(delta * 3.0, 1.0)).normalized() * new_sp
        else:
            hvel = hvel.normalized() * new_sp
            # без ввода модель смотрит по полёту
            graphics_wrapper.rotation.y = lerp_angle(graphics_wrapper.rotation.y, atan2(hvel.x, hvel.y), delta * 8.0)
    else:
        hvel = Vector2(global_dir.x, global_dir.z) * run_speed
    velocity.x = hvel.x
    velocity.z = hvel.y

    if not is_on_floor():
        velocity.y -= GRAVITY * delta
        # Полёт на крыльях (Q20 v2): удержание Space — тяга вверх (плавный
        # разгон), отпущено — планирование (медленное падение вместо обрыва).
        if wings_fly:
            if space_pressed:
                velocity.y = move_toward(velocity.y, WINGS_LIFT, delta * 24.0)
            elif velocity.y < WINGS_GLIDE:
                velocity.y = WINGS_GLIDE
        _air_hvel = hvel
    else:
        can_double_jump = unlocked_skills.get("double_jump", false)
        if _was_airborne:
            # Приземление (Q48): открываем окно банни-хопа, запоминаем
            # горизонталь последнего воздушного тика.
            _since_landing = 0.0
            _landed_hvel = _air_hvel
        else:
            _since_landing += delta
    _was_airborne = not is_on_floor()

    if space_pressed and not was_space_pressed:
        var anim_comp = get_node_or_null("PlayerAnimationComponent")
        if is_on_floor():
            velocity.y = jump_velocity
            # Bunny-hop (Q48, ТЗ §4.2): прыжок в первые 0.14 с после приземления
            # на высокой скорости сохраняет ~80% воздушной горизонтальной скорости
            # (без банни-хопа земля мгновенно съела бы импульс штатной записью).
            if _since_landing < 0.14 and _landed_hvel.length() > run_speed:
                velocity.x = _landed_hvel.x * 0.8
                velocity.z = _landed_hvel.y * 0.8
            if anim_comp and anim_comp.has_method("play_jump"):
                anim_comp.play_jump()
        elif can_double_jump:
            velocity.y = jump_velocity
            can_double_jump = false
            if anim_comp and anim_comp.has_method("play_jump"):
                anim_comp.play_jump(true)  # сальто на двойном прыжке
            
    was_space_pressed = space_pressed
    if input_locked:
        # Свип телепорта: твин двигает тело сам, гравитацию не трогаем.
        # move_and_slide нужен, чтобы is_on_floor() обновился (коллизии
        # заглушены → автомат видит «в воздухе» → Jump/Falling → Landing).
        velocity = Vector3.ZERO
        move_and_slide()
        _update_camera_pivot()
        return
    move_and_slide()
    _update_camera_pivot()

## Q44-R (спец, баг №3 + чек-лист п.4): пивот камеры больше НЕ ребёнок тела —
## top_level, позиция ставится вручную каждый физ-тик. Три фазы:
## 0 — штатный след за телом; 1 — тело перенесено матрицей портала, камера
## продолжает жить на входной стороне: rigid-формула m⁻¹·(тело·офсет) =
## «поза, как будто тело не телепортировалось» (точная при любом yaw/pitch —
## M·(T·L) = (M·T)·L), аватар виден через окно; 2 — камера пересекла
## плоскость входа (cam_z + → −): pivot = m·pivot — ТОЧНО совпадает с обычным
## следом (ассоциативность умножения трансформов), дальше Фаза 0. Откат тела
## через выходной портал (мета p2_entry == partner) чистит меты — Фаза 0.
## Страховка спеца: Фаза 1 дольше 2 с — форс-резолв в штатный след.
func _update_camera_pivot() -> void:
    if spring_arm == null:
        return
    var entry = null
    if has_meta("p2_entry"):
        entry = get_meta("p2_entry")
        if entry == null or not (entry is Node3D) or not is_instance_valid(entry):
            entry = null
            remove_meta("p2_entry")
    var phase1: bool = entry != null
    var t0 := 0
    if phase1:
        t0 = int(get_meta("p2_t0"))
        if t0 != _p2_t0_seen:
            _p2_t0_seen = t0
            _p2_cam_prev = 1e9
    # В Фазе 1 пивот на входной стороне — пружина не должна ловить геометрию
    # портальной зоны; штатная маска возвращается в Фазе 0.
    spring_arm.collision_mask = 0 if phase1 else _arm_mask
    var local := Transform3D(Basis(Vector3(1, 0, 0), _cam_pitch), _shoulder)
    if not phase1:
        spring_arm.global_transform = global_transform * local
        return
    var m: Transform3D = entry.call("portal_matrix")
    spring_arm.global_transform = m.affine_inverse() * (global_transform * local)
    spring_arm.reset_physics_interpolation()
    if Time.get_ticks_msec() - t0 > 2000:
        remove_meta("p2_entry")
        remove_meta("p2_t0")
        spring_arm.global_transform = global_transform * local
        return
    var cam_z: float = entry.to_local(camera.global_position).z
    if _p2_cam_prev > 0.0 and cam_z <= 0.0:
        spring_arm.global_transform = m * spring_arm.global_transform
        spring_arm.reset_physics_interpolation()
        remove_meta("p2_entry")
        remove_meta("p2_t0")
    else:
        _p2_cam_prev = cam_z
