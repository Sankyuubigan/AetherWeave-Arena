extends AnimatableBody3D
## Хитбокс желе (Q49): SoftBody3D ненадёжен в физ-запросах — контакт
## SoftBody3D-vs-Body в GodotPhysics3D 4.8 СЛОМАН (probe_softcontact, изолят
## Q25-B), Area3D-vs-softbody не ловится (SoftBody3D extends MeshInstance3D,
## не PhysicsBody3D). Урон скиллов идёт duck-typing'ом take_damage по
## результатам intersect_ray/intersect_shape/объёму Area — все они видят
## только тела. AnimatableBody3D-обёртка (двигается JellyMonster за живым
## центром тела) — гарантированный приёмщик урона: рейкаст камеры (aim
## context), хоминг-контакт, АоЕ-shape, aim-assist (группа aim_targets).
## Слой 8 «детект-only»: mask 0 — сам ни с чем не коллизится (мувер-цилиндр
## остаётся ЕДИНСТВЕННЫМ физическим контактом желе с миром — правило v6).

const JellyScript = preload("res://Logic/JellyMonster.gd")

var jelly: SoftBody3D = null

func _ready() -> void:
	add_to_group("aim_targets") # AIM ASSIST Q29: цель «вражеских» скиллов
	collision_layer = 8
	collision_mask = 0

func take_damage(amount: int, impulse_dir: Vector3 = Vector3.ZERO) -> void:
	if jelly != null and is_instance_valid(jelly) \
			and jelly.has_method("take_damage"):
		jelly.take_damage(amount, impulse_dir)
