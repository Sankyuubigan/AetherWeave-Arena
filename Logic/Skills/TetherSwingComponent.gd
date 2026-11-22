extends Node
## Эфирный захват (Q48): компонент-стейт-машина полёта на кастере (паттерн
## Blade/Wings — узел-ребёнок, создаётся эффектом лениво). Пока трос активен,
## PlayerController передаёт физику сюда (physics_step) — мышь свободна,
## обычные запись velocity/гравитация/прыжок не исполняются.
## Числа — ТЗ §3 (марвел-стайл аркадная физика, не школьный маятник):
## гравитация свинка бодрее, тангенциальный буст вдоль дуги по камере+WASD,
## срыв сохраняет ВСЮ скорость (инерция после отрыва — ТЗ §4).

enum Mode { NONE, SWING, ZIP }

const MIN_ANCHOR_DIST := 3.0      # ближе — зацеп не валиден (ТЗ §2)
const SWING_UP_GAP := 1.5         # якорь выше кастера на это → SWING, иначе ZIP
const SWING_GRAVITY := 25.0       # бодрее обычной 9.8 — дуга стремительная
const SWING_REEL := 5.0           # подмотка каната, м/с (ТЗ 4–6)
const SWING_REEL_MIN := 6.0       # короче не подматываем
const SWING_REEL_LOW_Y := -2.0    # летит вниз при...
const SWING_REEL_LOW_H := 2.5     # ...высоте до пола < 2.5 м → форсаж подмотки
const SWING_REEL_LOW_MULT := 2.5
const SWING_STRETCH_K := 18.0     # коррекция растяжения каната (ТЗ)
const SWING_BOOST_ACCEL := 42.0   # тангенциальный буст, м/с² (ТЗ 38–45)
const SWING_MAX_SPEED := 38.0
const SWING_KICK_UP := 7.5        # стартовый подпрыг (ТЗ §3.A.1)
const SWING_KICK_TANGENT := 15.0  # стартовый импульс по касательной
const SWING_WASD_WISH := 0.6      # вес WASD в направлении буста (камера = 1.0)
const SWING_TIME_LIMIT := 2.2     # авто-срыв по таймеру (ТЗ)
## Перелетел якорь: скорость направлена ОТ якоря сильнее этого угла + вверх.
## ТЗ писал «~65°» от вектора «якорь→игрок»; на паре (скорость; якорь−игрок)
## 65° срабатывает у низа дуги — каждый свинг рубился бы на взлёте. 110° на
## этих векторах = «якорь по движению позади» — честный маркер перелёта.
const SWING_PASS_ANGLE_DEG := 110.0
const ZIP_SPEED := 40.0           # ТЗ 36–42
const ZIP_ARRIVAL := 2.8          # отрыв при сближении (ТЗ)
const ZIP_TIME_LIMIT := 2.5       # страховка от застревания в стене
const RELEASE_UP := 7.5           # Release Boost (ТЗ §3): +7.5 вверх
const RELEASE_HORIZ_MULT := 1.15  # +15% к горизонтальной скорости
const GLOBAL_SPEED_CAP := 42.0    # общий потолок горизонтали (ТЗ)
const AIR_ANCHOR_DIST := 28.0     # воздушный якорь: дистанция по взгляду (ТЗ 26–30)
const AIR_ANCHOR_LIFT := 10.5     # ...и подъём вверх (ТЗ +9–12)
const AIR_ANCHOR_MIN_UP := 9.0    # якорь всегда заметно выше кастера → SWING
const VFX_SCRIPT := "res://Graphics/TetherVfx.gd"

@export var max_range: float = 45.0
@export var allow_air_anchor: bool = true
@export var thread_color: Color = Color(0.62, 0.42, 1.0)

var mode: Mode = Mode.NONE
var anchor: Vector3 = Vector3.ZERO
var _rope_len := 0.0
var _state_time := 0.0
var _zip_time := 0.0
var _was_space := false
var _is_air_anchor := false
var _anchor_normal := Vector3.ZERO  # нормаль геометрии для ориентации сигила
var _hand := "Left"
var _vfx: Node3D

func is_active() -> bool:
	return mode != Mode.NONE

## Зацеп (ТЗ §2–3): якорь из контекста каста (рейкаст прицела НЕ дублируется).
func activate(context: Dictionary) -> void:
	var body := get_parent() as CharacterBody3D
	if body == null or mode != Mode.NONE:
		return
	_is_air_anchor = false
	_hand = str(context.get("hand", "Left"))
	var caster_pos := body.global_position
	if context.get("target_node") != null:
		# Геометрия в прицеле — ручной зацеп в точку.
		anchor = context.get("target_pos", caster_pos) as Vector3
		_anchor_normal = context.get("hit_normal", Vector3.ZERO) as Vector3
		var dist := anchor.distance_to(caster_pos)
		if dist < MIN_ANCHOR_DIST or dist > max_range:
			print("[TETHER] зацеп мимо: дист %.1f вне [%.1f..%.1f]" % [dist, MIN_ANCHOR_DIST, max_range])
			return
	else:
		# Ткнул в небо (target_node == null на промахе рейкаста) — эфирный якорь
		# в воздухе по взгляду камеры; путь луча свободен гарантированно.
		if not allow_air_anchor:
			return
		_anchor_normal = Vector3.ZERO  # воздушный якорь — сигил billboard'ом
		var cam_pos := context.get("camera_pos", caster_pos + Vector3(0, 1.6, 0)) as Vector3
		var fwd := context.get("forward_dir", -body.global_transform.basis.z) as Vector3
		anchor = cam_pos + fwd * AIR_ANCHOR_DIST + Vector3.UP * AIR_ANCHOR_LIFT
		anchor.y = maxf(anchor.y, caster_pos.y + AIR_ANCHOR_MIN_UP)
		_is_air_anchor = true

	mode = Mode.SWING if anchor.y >= caster_pos.y + SWING_UP_GAP else Mode.ZIP
	_rope_len = anchor.distance_to(caster_pos)
	_state_time = 0.0
	_zip_time = 0.0
	_was_space = true  # не срывать от пробела, зажатого ещё до каста
	_vfx_on_attach()
	if mode == Mode.SWING:
		_swing_kick(body, context)
	print("[TETHER] зацеп %s якорь=%s канат=%.1f режим=%s" % [
		"ВОЗДУХ" if _is_air_anchor else "ГЕОМ", anchor, _rope_len,
		"SWING" if mode == Mode.SWING else "ZIP"])

## Физический шаг — вызывает PlayerController вместо штатной физики,
## пока трос активен (PRP шаг 2). input_dir — тот же расчёт хода (x right,
## y back в базисе кастера), space_pressed — уже с гейтами ввода.
func physics_step(delta: float, input_dir: Vector2, space_pressed: bool) -> void:
	var body := get_parent() as CharacterBody3D
	if body == null or mode == Mode.NONE:
		return
	var space_edge := space_pressed and not _was_space
	_was_space = space_pressed
	if space_edge:
		release(true)
		return
	if body.get("is_dying") == true:
		release(false)
		return
	_state_time += delta
	if mode == Mode.SWING:
		_swing_step(body, delta, input_dir)
	elif mode == Mode.ZIP:
		_zip_step(body, delta)
	if mode == Mode.NONE:
		return  # шаг сам сделал release — velocity уже с бустом
	_face_and_tilt(body, delta, input_dir)
	body.move_and_slide()

## Отрыв (ТЗ §3): with_boost = срыв/зип — +7.5 вверх и +15% горизонтали
## (потолок 42); false — тихий разрыв (смерть/чистка).
func release(with_boost: bool) -> void:
	if mode == Mode.NONE:
		return
	mode = Mode.NONE
	_vfx_off_attach()
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	var vel := body.velocity
	if with_boost:
		vel.y += RELEASE_UP
		var h := Vector2(vel.x, vel.z) * RELEASE_HORIZ_MULT
		if h.length() > GLOBAL_SPEED_CAP:
			h = h.normalized() * GLOBAL_SPEED_CAP
		vel.x = h.x
		vel.z = h.y
	body.velocity = vel
	print("[TETHER] отрыв%s vel=%s" % [" с бустом" if with_boost else "", vel])
	_reset_pose(body)

## ── SWING (ТЗ §3.A): маятник + подмотка + тангенциальный буст ──

func _swing_kick(body: CharacterBody3D, context: Dictionary) -> void:
	# Мгновенный срыв с места: подпрыг + импульс по касательной к канату
	# в сторону взгляда камеры.
	var vel := body.velocity
	if body.is_on_floor() or vel.y < 2.0:
		vel.y = maxf(vel.y, SWING_KICK_UP)
	var fwd := context.get("forward_dir", -body.global_transform.basis.z) as Vector3
	var dir := (anchor - body.global_position).normalized()
	var tangent := fwd - dir * fwd.dot(dir)
	if tangent.length() > 0.1:
		vel += tangent.normalized() * SWING_KICK_TANGENT
	body.velocity = vel

func _swing_step(body: CharacterBody3D, delta: float, input_dir: Vector2) -> void:
	var pos := body.global_position
	var vel := body.velocity
	var to_anchor := anchor - pos
	var dist := to_anchor.length()
	var dir := to_anchor / maxf(dist, 0.001)

	# Подмотка каната + форсаж у пола при спуске (защита от шкрябания, ТЗ §3.A.2).
	var reel := SWING_REEL
	if vel.y < SWING_REEL_LOW_Y and _height_above_floor(body) < SWING_REEL_LOW_H:
		reel *= SWING_REEL_LOW_MULT
	_rope_len = maxf(SWING_REEL_MIN, _rope_len - reel * delta)

	vel.y -= SWING_GRAVITY * delta

	# Ограничение каната: на натяжении убираем радиальную (от якоря)
	# составляющую и мягко гасим растяжение (ТЗ §3.A.2).
	if dist >= _rope_len and vel.dot(dir) < 0.0:
		vel -= dir * vel.dot(dir)
		vel += dir * (dist - _rope_len) * SWING_STRETCH_K * delta

	# Тангенциальный буст — главный драйв скорости (ТЗ §3.A.3):
	# (камера + WASD) проецируем на плоскость ⊥ каната и разгоняемся вдоль дуги.
	var wish := _wish_dir(body, input_dir)
	var tangent := wish - dir * wish.dot(dir)
	if tangent.length() > 0.05:
		vel += tangent.normalized() * SWING_BOOST_ACCEL * delta

	if vel.length() > SWING_MAX_SPEED:
		vel = vel.normalized() * SWING_MAX_SPEED

	body.velocity = vel
	_vfx_update_thread(delta)

	# Авто-срыв: перелетел якорь (якорь позади по движению и идёт вверх)
	# или таймер (ТЗ §3.A.4).
	var vel_dir := vel.normalized()
	if _state_time > SWING_TIME_LIMIT \
			or (vel.y > 1.0 and rad_to_deg(vel_dir.angle_to(dir)) > SWING_PASS_ANGLE_DEG):
		print("[TETHER] авто-срыв свинга t=%.2f" % _state_time)
		release(true)

## ── ZIP (ТЗ §3.B): прямая тяга к цели ──

func _zip_step(body: CharacterBody3D, delta: float) -> void:
	_zip_time += delta
	var target := anchor + Vector3.UP * 1.2
	var to_t := target - body.global_position
	var dist := to_t.length()
	# Скорость задана жёстко (не копится) — рывок «почти по прямой».
	body.velocity = to_t.normalized() * ZIP_SPEED
	_vfx_update_thread(delta)
	# Отрыв: сближение / пробел (в physics_step) / страховка-таймаут.
	# Касание пола НЕ срывает: цель всегда +1.2 над якорем — низкий зип
	# легально скользит над землёй до точки (ТЗ: «катапульта» от земли).
	if dist < ZIP_ARRIVAL or _zip_time > ZIP_TIME_LIMIT:
		print("[TETHER] зип завершён t=%.2f дист=%.1f" % [_zip_time, dist])
		release(true)

## ── Помощники ──

## Направление желания полёта: взгляд камеры + WASD (вес SWING_WASD_WISH).
func _wish_dir(body: CharacterBody3D, input_dir: Vector2) -> Vector3:
	var wish := Vector3.ZERO
	var cam := body.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if cam == null and body.get_viewport() != null:
		cam = body.get_viewport().get_camera_3d()
	if cam:
		wish += -cam.global_transform.basis.z
	var wasd := Vector3(input_dir.x, 0.0, input_dir.y)
	if wasd.length() > 0.1:
		wish += (body.global_transform.basis * wasd) * SWING_WASD_WISH
	return wish

## Высота до пола под кастером (луч вниз, 4 м) — для форсажа подмотки.
func _height_above_floor(body: CharacterBody3D) -> float:
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return 100.0
	var from := body.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0))
	q.exclude = [body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 4.0
	return from.y - float(hit["position"].y)

## Лицом по полёту + наклон корпуса вдоль скорости (ТЗ §6): pitch по
## вертикальной составляющей, roll по боковому вводу. rotation.y ведём сами —
## PlayerController в тросе не вращает модель.
func _face_and_tilt(body: CharacterBody3D, delta: float, input_dir: Vector2) -> void:
	var gw := body.get_node_or_null("GraphicsWrapper") as Node3D
	if gw == null:
		return
	var vel := body.velocity
	if Vector2(vel.x, vel.z).length() > 2.0:
		gw.rotation.y = lerp_angle(gw.rotation.y, atan2(vel.x, vel.z), delta * 10.0)
	var pitch := clampf(-vel.y * 0.025, -0.55, 0.55)
	var roll := clampf(-input_dir.x * 0.3, -0.35, 0.35)
	gw.rotation.x = lerpf(gw.rotation.x, pitch, delta * 8.0)
	gw.rotation.z = lerpf(gw.rotation.z, roll, delta * 8.0)

## Плавный возврат наклона в 0 после отрыва (rotation.y не трогаем —
## его снова ведёт PlayerController).
func _reset_pose(body: CharacterBody3D) -> void:
	var gw := body.get_node_or_null("GraphicsWrapper") as Node3D
	if gw == null or (absf(gw.rotation.x) < 0.001 and absf(gw.rotation.z) < 0.001):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(gw, "rotation:x", 0.0, 0.25)
	tw.tween_property(gw, "rotation:z", 0.0, 0.25)

## ── VFX-хуки (Graphics/TetherVfx.gd — нить/сигил/burst/шлейф/camera juice) ──

func _vfx_on_attach() -> void:
	var body := get_parent()
	if body == null:
		return
	if _vfx == null:
		_vfx = body.get_node_or_null("TetherVfx")
		if _vfx == null:
			_vfx = Node3D.new()
			_vfx.name = "TetherVfx"
			_vfx.set_script(load(VFX_SCRIPT))
			body.add_child(_vfx)
	_vfx.set("thread_color", thread_color)
	_vfx.call("attach", anchor, _is_air_anchor, _anchor_normal, _hand)

func _vfx_update_thread(delta: float) -> void:
	if _vfx != null and is_instance_valid(_vfx):
		_vfx.call("update_thread", delta)

func _vfx_off_attach() -> void:
	if _vfx != null and is_instance_valid(_vfx):
		_vfx.call("detach")

func _exit_tree() -> void:
	# Узел умирает вместе с кастером — VFX-хук на чистку (шаг 3).
	_vfx_off_attach()
