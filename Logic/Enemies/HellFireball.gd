extends Area3D
## Фаербол дальнего врага ада (19.11.26): летит по прямой, при попадании в
## игрока наносит % от макс HP (верб. юзера). В рельеф/камни — взрыв,
## врагов пролетает насквозь. Живёт не дольше LIFETIME (самоуничтожение).

const LIFETIME := 6.0

var direction := Vector3.FORWARD
var speed := 14.0
var damage := 2
var _life := LIFETIME

func _ready():
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 2.5
	sm.material = mat
	mi.mesh = sm
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.shadow_enabled = false
	add_child(light)

	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	cs.shape = sh
	add_child(cs)

	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("hell_enemy"):
		return # своих пролетаем
	if body.name == "Player" and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free() # в игрока или в мир (рельеф/камень) — взрыв
