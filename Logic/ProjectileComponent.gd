extends Area3D

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")
const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

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

    # Пятно взрыва на поверхности (аним. декаль 4.8): спавн ДО release —
    # узел ещё в дереве, декаль живёт в current_scene независимо от пула.
    _spawn_scorch()

    # Звук удара (meta от SpawnProjectileEffect, 17.11: взрыв метеора о землю):
    # play_sfx создаёт отдельный плеер AudioManager — release снаряда не глушит.
    if has_meta("impact_sfx"):
        AudioManager.play_sfx(get_meta("impact_sfx"))

    ProjectilePool.release(self)

func _spawn_scorch():
    var scene := get_tree().current_scene if get_tree() else null
    if not scene:
        return
    var dir := direction if direction.length_squared() > 0.001 else Vector3.DOWN
    var normal := AnimatedDecalComponent.surface_normal(get_world_3d(), global_position, dir, Vector3.UP)
    var frames := DecalFrames.explosion_scorch(Color(1.0, 0.45, 0.1))
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 12.0, 5.0, 1.6)
    scene.add_child(decal)
    decal.place(global_position, normal)

func pooled_reset():
    direction = Vector3.FORWARD
    # Шлейф Trail3D при переиспользовании из пула: старая лента должна
    # исчезнуть, иначе от спавна тянется след прошлого полёта.
    var ribbon := get_node_or_null("TrailRibbon")
    if ribbon and ribbon.has_method("clear"):
        ribbon.clear()
