extends Node3D

## Нейро-манекен (Q37, trellis) поверх капсулы dummy.tscn. pack() НЕ сериализует
## переопределения свойств узлов инстанс-подсцены (visible=false на MeshInstance3D
## капсулы не попадает в MainArena.tscn — арена рисовала красную капсулу поверх
## манекена), поэтому капсула прячется и свой дубль-хитбокс глушится в рантайме.
## Хитбокс и HealthComponent самой капсулы не тронуты — урон/рэгдолл как раньше.

## Tint поверх альбедо (alpha > 0 — применить): зелёная стоячая мишень отхила.
@export var tint: Color = Color(0, 0, 0, 0)

func _ready() -> void:
	var body := get_parent() as Node3D
	if body:
		var mi := body.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mi:
			mi.visible = false
	# Вложенный StaticBody дублирует капсульный хитбокс — глушим deferred
	# (disabled напрямую запрещён менять во время физического шага).
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.set_deferred("disabled", true)
	if tint.a > 0.0:
		var mis := find_children("*", "MeshInstance3D", true, false)
		if mis.size() > 0:
			var mesh := (mis[0] as MeshInstance3D).mesh
			if mesh and mesh.get_surface_count() > 0:
				var pm := mesh.surface_get_material(0).duplicate()
				pm.albedo_color = tint
				(mis[0] as MeshInstance3D).material_override = pm

## Жизненный цикл (фидбэк юзера 19.11.26): die() прячет капсулу, но respawn()
## (через 5 с) делает mesh.show() — красная капсула ВОЗВРАЩАЕТСЯ внутрь
## манекена, а сам манекен при смерти оставался висеть. Капсула здесь — прокси
## состояния жизни (hide=мёртв до респавна), поэтому: манекен зеркалит
## is_dead, а капсула не рендерится никогда, сколько бы show() ни было.
func _process(_delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var cap := body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if cap == null:
		return
	visible = body.get("is_dead") != true
	if cap.visible:
		cap.visible = false
