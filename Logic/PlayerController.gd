extends CharacterBody3D

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.002

var camera: Camera3D
var spell_caster: Node

func _ready():
    camera = $Camera3D
    spell_caster = $SpellCasterComponent
    print("PlayerController._ready() — camera=", camera != null, " spell_caster=", spell_caster != null)

func _input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
            return

    if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
        return

    if event is InputEventMouseMotion:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera.rotate_x(-event.relative.y * mouse_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, -1.5, 1.5)

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if spell_caster and spell_caster.has_method("cast"):
            spell_caster.cast()

    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
    var input_dir = Vector2(
        int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
        int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
    )

    var cam_basis = camera.global_transform.basis
    var forward = -cam_basis.z
    var right = cam_basis.x
    forward.y = 0
    right.y = 0
    forward = forward.normalized()
    right = right.normalized()

    var direction = forward * (-input_dir.y) + right * input_dir.x
    if direction.length() > 0.1:
        direction = direction.normalized()

    velocity = direction * speed
    move_and_slide()
