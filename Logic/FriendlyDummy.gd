extends "res://Logic/MovingDummy.gd"

var time_since_last_heal: float = 0.0
var heal_cooldown: float = 10.0

func _ready():
    is_friendly = true
    super._ready()
    
    # Меняем цвет на зеленый для отличия
    var mesh = get_node_or_null("MeshInstance3D")
    if mesh:
        var mat = StandardMaterial3D.new()
        mat.albedo_color = Color(0.2, 1.0, 0.2)
        mesh.set_surface_override_material(0, mat)
        
    # Изначально 10% здоровья (ждёт отхила)
    current_health = int(max_health * 0.1)
    hp_bar.value = current_health

func _physics_process(delta):
    super._physics_process(delta) # Продолжает бегать
    if is_dead: return
    
    # Логика потери ХП, если долго не лечили
    time_since_last_heal += delta
    if time_since_last_heal >= heal_cooldown:
        current_health = int(max_health * 0.1)
        hp_bar.value = current_health
        time_since_last_heal = 0.0

func heal(amount: int):
    super.heal(amount)
    time_since_last_heal = 0.0 # Сбрасываем таймер гниения