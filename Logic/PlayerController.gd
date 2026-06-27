extends CharacterBody3D

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var jump_velocity: float = 4.5

const GRAVITY: float = 9.8

var camera: Camera3D
var spring_arm: Node3D
var graphics_wrapper: Node3D
var spell_caster: Node

var skill_points: int = 50
var player_hp: int = 100

var unlocked_skills = {
    "fireball": false,
    "double_jump": false,
    "teleport": false
}
var can_double_jump: bool = false
var was_space_pressed: bool = false

var hud_hp: ProgressBar
var hud_sp: Label

func _ready():
    camera = $SpringArm3D/Camera3D
    spring_arm = $SpringArm3D
    graphics_wrapper = $GraphicsWrapper
    spell_caster = $SpellCasterComponent
    
    if spring_arm:
        spring_arm.add_excluded_object(self.get_rid())
        spring_arm.position.y = 0.5
        
    if graphics_wrapper:
        graphics_wrapper.position.y = -1.0
        
    setup_hud()
        
    var skill_menu = preload("res://Graphics/SkillMenu.gd").new()
    add_child(skill_menu)
    
    var action_bar = preload("res://Graphics/ActionBar.gd").new()
    add_child(action_bar)

func setup_hud():
    var hud = CanvasLayer.new()
    hud.name = "PlayerHUD"
    
    hud_hp = ProgressBar.new()
    hud_hp.custom_minimum_size = Vector2(300, 30)
    hud_hp.position = Vector2(20, 20)
    hud_hp.max_value = 100
    hud_hp.value = player_hp
    hud_hp.show_percentage = true
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.2, 0.7, 0.2, 1.0)
    hud_hp.add_theme_stylebox_override("fill", sb)
    hud.add_child(hud_hp)
    
    hud_sp = Label.new()
    hud_sp.position = Vector2(20, 60)
    hud_sp.text = "Очки навыков (SP): " + str(skill_points)
    hud.add_child(hud_sp)
    
    add_child(hud)

func update_hud():
    if hud_sp: hud_sp.text = "Очки навыков (SP): " + str(skill_points)
    if hud_hp: hud_hp.value = player_hp

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

func _input(event):
    var menu = get_node_or_null("SkillMenu")
    if menu and menu.is_open:
        return

    # Захват мыши по ЛКМ
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
            return

    if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
        return

    if event is InputEventMouseMotion:
        rotate_y(-event.relative.x * mouse_sensitivity)
        spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
        spring_arm.rotation.x = clamp(spring_arm.rotation.x, -1.2, 1.2)

    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
    var input_dir = Vector2(
        int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
        int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
    )

    var local_dir = Vector3(input_dir.x, 0, input_dir.y)
    
    if local_dir.length() > 0.1:
        local_dir = local_dir.normalized()
        var target_angle = atan2(local_dir.x, local_dir.z)
        graphics_wrapper.rotation.y = lerp_angle(graphics_wrapper.rotation.y, target_angle, delta * 10.0)

    var global_dir = (global_transform.basis * local_dir)

    velocity.x = global_dir.x * speed
    velocity.z = global_dir.z * speed

    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    else:
        can_double_jump = unlocked_skills.get("double_jump", false)

    var space_pressed = Input.is_key_pressed(KEY_SPACE)
    if space_pressed and not was_space_pressed:
        if is_on_floor():
            velocity.y = jump_velocity
        elif can_double_jump:
            velocity.y = jump_velocity
            can_double_jump = false
            
    was_space_pressed = space_pressed
    move_and_slide()