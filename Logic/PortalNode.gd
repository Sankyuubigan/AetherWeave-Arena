extends Area3D
## Узел портальной пары (Q21, заказ юзера: «туннель между ними проход»):
## вход тела → выход у партнёра (+normal*1.25), velocity по курсу выхода,
## физ-интерполяция сброшена (грабля телепортов), виньетка 0.14с игроку.
## Снаряды (Area3D с current_velocity) переносятся тоже — телепорт-хитскан
## лучей v2 (второй RayCast3D). Анти-пинг-понг: кулдаун на тело в ОБОИХ
## порталах, пока не выйдет из зоны. Звук — нейро-телепорт.

const RING_SCRIPT := preload("res://Graphics/PortalRing.gd")
const TELEPORT_SFX := preload("res://Audio/SFX/neural_teleport.res")
const EXIT_OFFSET := 1.25
const BODY_CD_MS := 700

var partner: Area3D = null
var _cd := {}  # instance_id → msec-предел (анти-пинг-понг)
var _sfx: AudioStreamPlayer3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.stream = TELEPORT_SFX
	_sfx.volume_db = 2.0
	_sfx.max_distance = 25.0
	add_child(_sfx)

## Визуал + коллизия (эффект вызывает ПОСЛЕ add_child и ориентации ноды:
## локальный +Z портала = нормаль наружу, выход по global_basis.z).
func build(color: Color, seed_off: float) -> void:
	var ring := Node3D.new()
	ring.set_script(RING_SCRIPT)
	add_child(ring)
	ring.call("setup", color, seed_off)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 2.4 по Y, БЕЗ offset у shape (кворк 4.8-beta: cs.position до add_child
	# в уже существующем Area — shape мёртв, overlapping=0). Зазор над полом
	# даёт GROUND_LIFT 1.45 у эффекта: грань y[0.25, 2.65] при центре 1.45.
	box.size = Vector3(2.2, 2.4, 0.5)
	cs.shape = box
	add_child(cs)

func _on_body_entered(body: Node3D) -> void:
	# Телепортируем только движущиеся тела. StaticBody3D (пол, арена) игнорим:
	# box-коллизия портала нижней гранью примыкает к поверхности пола — без
	# фильтра Area «ловит» пол и телепортирует ЕГО (проба 19.11: пол улетел
	# на выход портала, игрок проваливался в пустоту).
	if not (body is CharacterBody3D or body is RigidBody3D):
		return
	if partner == null or not is_instance_valid(partner):
		return
	var now := Time.get_ticks_msec()
	_gc_cd(now)
	var id := body.get_instance_id()
	if int(_cd.get(id, 0)) > now:
		return
	var until := now + BODY_CD_MS
	_cd[id] = until
	partner._cd[id] = until
	var out_dir: Vector3 = partner.global_basis.z.normalized()
	body.global_position = partner.global_position + out_dir * EXIT_OFFSET
	body.reset_physics_interpolation()
	if body is CharacterBody3D:
		body.velocity = out_dir * body.velocity.length()
	_sfx.play()
	partner._sfx.play()
	if body.is_in_group("player"):
		_flash(body)

## Снаряды (HomingProjectile/Heal — Area3D с current_velocity): позиция +
## скорость разворачиваются по курсу выхода (QUEUE: «+180°» — выход тем же
## направлением, куда смотрит выходной портал).
func _on_area_entered(a: Area3D) -> void:
	if partner == null or not is_instance_valid(partner):
		return
	if not "current_velocity" in a:
		return
	var out_dir: Vector3 = partner.global_basis.z.normalized()
	a.global_position = partner.global_position + out_dir * EXIT_OFFSET
	a.current_velocity = out_dir * (a.current_velocity as Vector3).length()

func _gc_cd(now: int) -> void:
	for k in _cd.keys():
		if int(_cd[k]) <= now:
			_cd.erase(k)

## Виньетка при проскоке: лёгкая, ввод НЕ лочим («быстрый проскок» QUEUE).
func _flash(body: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 1.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.30, 0.85, d) * strength;
	COLOR = vec4(0.02, 0.02, 0.07, v);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
	body.add_child(layer)
	var tw := body.create_tween()
	tw.tween_method(
		func(v): mat.set_shader_parameter("strength", v), 1.0, 0.0, 0.14)
	tw.tween_callback(layer.queue_free)
