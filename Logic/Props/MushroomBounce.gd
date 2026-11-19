extends Node3D
## Q31 гриб-батут (PRP одобрен 20.11.26): CapStatic (convex купола) держит
## игрока, подброс velocity.y по глубине посадки; визуальный промин —
## шейдерное вертексное смещение шляпки. SSOT пружины: только здесь.
## ПОЧЕМУ ШЕЙДЕР, а не SoftBody3D-точки: рантайм-манипуляция точками
## SoftBody3D сломана в 4.x (godot issues #93847/#108090) — сим игнорирует
## set_point_transform/set_point_pinned mid-run; PRP-фолбэк задействован.

@export var v_ref := 12.0         # скорость посадки → 100% промина (м/с)
@export var dent_max := 0.45      # глубина промина при 100% (м)
@export var dent_radius := 1.3    # радиус воронки промина (м)
@export var bounce_min_h := 1.2   # высота подброса при слабом промине (м)
@export var bounce_max_h := 4.5   # высота подброса при 100% промине (м)
@export var min_impact := 1.5     # ниже — не батут (просто стоять)
@export var cooldown := 0.2       # с, против дребезга
@export var bounce_min_y := 1.9   # центр тела выше — посадка на шляпку (не на землю рядом)
@export var dent_release := 0.5   # с, время возврата шляпки после промина

var dent_current := 0.0           # текущая видимая глубина промина (читает гейт-проба)

var _area: Area3D
var _vis: MeshInstance3D
var _mat: ShaderMaterial
var _cd := 0.0
var _bodies := {}                 # body → пиковая скорость падения внутри зоны

func _ready() -> void:
	_vis = get_node_or_null("CapVisual") as MeshInstance3D
	_area = get_node_or_null("BounceArea") as Area3D
	if _vis == null or _area == null:
		push_error("[MUSH-BOUNCE] нет CapVisual/BounceArea в префабе")
		set_physics_process(false)
		return
	_mat = _vis.material_override as ShaderMaterial
	if _mat == null:
		push_error("[MUSH-BOUNCE] нет ShaderMaterial на CapVisual")
		set_physics_process(false)
		return
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_area.monitoring = true
	print("[MUSH-BOUNCE] ready")

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or body is StaticBody3D:
		return
	_bodies[body] = body.velocity.y  # старт трекинга (обычно отрицат.)

func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body)

## Посадка = is_on_floor + ПИКОВАЯ скорость падения внутри зоны: тело входит
## в зону тем же тиком, что и контакт (move_and_slide обнуляет vy об пол),
## «последний тик» не ловит удар — latch держит самую быструю отметку.
## Гард bounce_min_y: не батутить, если игрок стоит на ЗЕМЛЕ в кольце зоны.
func _physics_process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta
	for body in _bodies.keys():
		if body.velocity.y < _bodies[body]:
			_bodies[body] = body.velocity.y
		if (body.is_on_floor() and _bodies[body] < -min_impact
				and _cd <= 0.0 and body.global_position.y > bounce_min_y):
			_bounce(body, -_bodies[body])
	if dent_current > 0.0:
		dent_current = move_toward(dent_current, 0.0, dent_max * delta / dent_release)
		_mat.set_shader_parameter("dent_depth", dent_current)

## Глубина промина от скорости посадки; подброс = f(глубина).
func _bounce(body: CharacterBody3D, v_impact: float) -> void:
	_cd = cooldown
	_bodies[body] = body.velocity.y  # сброс пика (иначе эскалация на след. посадке)
	var depth := clampf(v_impact / v_ref, 0.0, 1.0)
	print("[MUSH-BOUNCE] посадка v=%.1f → промин %.0f%%" % [v_impact, depth * 100.0])
	_dent(depth, body)
	# Подброс: h = lerp(min,max,depth) → v = sqrt(2*g*h)
	var h := lerpf(bounce_min_h, bounce_max_h, depth)
	var bv := sqrt(2.0 * 9.8 * h)
	body.velocity.y = bv
	print("[MUSH-BOUNCE] подброс h=%.1f м (v=%.1f)" % [h, bv])

## Воронка промина: центр = посадка (mesh-локальные координаты CapVisual),
## гаусс по dent_radius, затухание в _physics_process (dent_release).
func _dent(depth: float, body: CharacterBody3D) -> void:
	var local_c: Vector3 = _vis.to_local(body.global_position)
	_mat.set_shader_parameter("dent_center", local_c)
	dent_current = depth * dent_max
	_mat.set_shader_parameter("dent_depth", dent_current)
	print("[MUSH-BOUNCE] промин: глубина %.2f м, удерж %.1f с" % [dent_current, dent_release])
