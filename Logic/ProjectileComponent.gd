extends Area3D

@export var speed: float = 20.0
var direction: Vector3 = Vector3.FORWARD

func set_direction(dir: Vector3):
    direction = dir.normalized()

func _ready():
    body_entered.connect(_on_body_entered)

func _physics_process(delta):
    global_position += direction * speed * delta

func _on_body_entered(body: Node):
    if body.name == "Player":
        return
        
    # ИСПРАВЛЕНИЕ: Так как HealthComponent прикреплен прямо на корень Манекена, 
    # body и является носителем функции take_damage
    if body.has_method("take_damage"):
        body.take_damage(25)
        
    queue_free()