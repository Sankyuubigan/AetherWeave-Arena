extends Area3D

@export var speed: float = 15.0
var direction: Vector3 = Vector3.FORWARD

func set_direction(dir: Vector3):
    direction = dir.normalized()

func _ready():
    body_entered.connect(_on_body_entered)

func _physics_process(delta):
    global_position += direction * speed * delta

func _on_body_entered(body: Node):
    var health = body.get_node_or_null("HealthComponent")
    if health and health.has_method("take_damage"):
        health.take_damage(25)
    queue_free()
