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

func _ready():
    add_to_group("player") # цель для врагов ада (HellEnemyBase)
    camera = $SpringArm3D/Camera3D
    spring_arm = $SpringArm3D
    graphics_wrapper = $GraphicsWrapper
    spell_caster = $SpellCasterComponent
    
    if spring_arm:
        spring_arm.add_excluded_object(self.get_rid())
        spring_arm.position.y = 0.5
        
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
func take_damage(amount: int):
    if is_dying:
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
        spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
        spring_arm.rotation.x = clamp(spring_arm.rotation.x, -1.2, 1.2)

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
    
    if local_dir.length() > 0.1:
        local_dir = local_dir.normalized()
        var target_angle = atan2(local_dir.x, local_dir.z)
        graphics_wrapper.rotation.y = lerp_angle(graphics_wrapper.rotation.y, target_angle, delta * 10.0)

    var global_dir = (global_transform.basis * local_dir)

    # Множитель ускорения (Q20 крылья: 1.35 на окно активности, ставит
    # WingsComponent.activate/deactivate; остальные скиллы не трогают).
    velocity.x = global_dir.x * speed * speed_mult
    velocity.z = global_dir.z * speed * speed_mult

    var space_pressed = (not locked) and Input.is_key_pressed(KEY_SPACE)

    if not is_on_floor():
        velocity.y -= GRAVITY * delta
        # Полёт на крыльях (Q20 v2): удержание Space — тяга вверх (плавный
        # разгон), отпущено — планирование (медленное падение вместо обрыва).
        if wings_fly:
            if space_pressed:
                velocity.y = move_toward(velocity.y, WINGS_LIFT, delta * 24.0)
            elif velocity.y < WINGS_GLIDE:
                velocity.y = WINGS_GLIDE
    else:
        can_double_jump = unlocked_skills.get("double_jump", false)

    if space_pressed and not was_space_pressed:
        var anim_comp = get_node_or_null("PlayerAnimationComponent")
        if is_on_floor():
            velocity.y = jump_velocity
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
        return
    move_and_slide()