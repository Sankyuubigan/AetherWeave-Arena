extends RefCounted
## «Мозг» желе-монстра v6 (ответ спеца 22.11.26, файл-план 261122_Q25_v6).
## FSM: APPROACH / ORBIT / FLEE / RECOVER. ВСЕ дистанции — ОТ КРОМКИ купола
## (edge = дистанция до центра − radius): v5.2b мерил до центра при радиусе
## 2.6 → «прилипал в упор» (вердикт юзера). Steering: 3 горизонтальных луча
## (0°, ±38°, длина 4.0 м, высота 0.7 м) уводят тягу от препятствий
## (верификация шар-мувер закатывался на валуны) + unstuck-таймер.
## Подключается JellyMonster через preload (class_name в headless -s может
## не резолвиться без свежего --import — грабля).

enum S { APPROACH, ORBIT, FLEE, RECOVER }

# --- Дистанции от КРОМКИ купола (спец §БАГ-D) ---
const AWARE_RANGE := 22.0    # дальше игрок не «замечен» (было CURIOSITY_RANGE)
const ORBIT_MIN := 4.0       # ближе — мягкое отползание
const ORBIT_MAX := 6.5       # дальше — APPROACH сближение
const TOO_CLOSE := 3.0       # игрок сам подошёл вплотную — отползание
const APPROACH_FORCE := 700.0
const RETREAT_FORCE := 500.0
const ORBIT_FORCE := 180.0
const PULSE_RATE := 2.8      # пульс «шажков»: 0.35 + 0.65·max(0, sin(t·2.8))
# --- Испуг/FLEE (спец: таймер 4-5 с, не 0.9; отход реально 5-8 м) ---
const FLEE_TIME_MIN := 4.0
const FLEE_TIME_MAX := 5.0
const FLEE_FORCE := 950.0
const FLEE_UNTIL_EDGE := 9.0 # тяга бегства работает пока кромка ближе 9 м
const FLEE_KICK := 280.0     # стартовый толчок (было 160 → отлёт ~1 м)
const RECOVER_TIME_MIN := 1.5
const RECOVER_TIME_MAX := 2.0
# --- Steering (спец §БАГ-C) ---
const STEER_LEN := 4.0
const STEER_Y := 0.7
const STEER_HALF_DEG := 38.0
const UNSTUCK_WIN := 0.5
const UNSTUCK_DIST := 0.25
const UNSTUCK_HOLD := 1.2
# --- Прыжки в мирных фазах ---
const HOP_MIN_S := 3.0
const HOP_MAX_S := 6.0

var state: int = S.APPROACH
var _flee_left := 0.0
var _recover_left := 0.0
var _unstuck_left := 0.0
var _unstuck_dir := Vector3.ZERO
var _sample_left := 0.0
var _sample_pos := Vector3.ZERO
var _orbit_side := 1.0
var _orbit_swap := 6.0
var _hop_wait := 4.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _player_rid: RID

## Один физ-тик. m — JellyMonster (динамический доступ к _mover/_live_center/
## radius/_home/_hop/_kick_mover — тип не указываем: циклический preload).
func tick(delta: float, m) -> void:
	_t += delta
	# Прыжки живут во всех мирных фазах (APPROACH/ORBIT/RECOVER).
	var peaceful := state != S.FLEE
	_hop_wait -= delta
	if _hop_wait <= 0.0:
		_hop_wait = _rng.randf_range(HOP_MIN_S, HOP_MAX_S)
		if peaceful and m._mover != null \
				and m._mover.global_position.y <= m.RIG_HALF_H + 0.1:
			m._hop()
	var players: Array = m.get_tree().get_nodes_in_group("player")
	var pl: Node3D = null
	if players.size() > 0 and is_instance_valid(players[0]):
		pl = players[0]
		_player_rid = pl.get_rid()
	if pl == null or m._mover == null:
		return
	var base: Vector3 = m._live_center if m._live_center != Vector3.ZERO else m._home
	var to_pl: Vector3 = pl.global_position - base
	to_pl.y = 0.0
	var cd: float = to_pl.length()
	var edge: float = cd - m.radius
	# Смена стороны орбиты раз в несколько секунд («кружит» не по кругу).
	_orbit_swap -= delta
	if _orbit_swap <= 0.0:
		_orbit_swap = _rng.randf_range(4.0, 9.0)
		_orbit_side = -_orbit_side
	match state:
		S.FLEE:
			_flee_left -= delta
			if to_pl.length_squared() > 0.001:
				var away := -to_pl.normalized()
				var f := FLEE_FORCE if edge < FLEE_UNTIL_EDGE else 0.0
				if f > 0.0:
					m._mover.apply_central_force(_steer(m, away) * f)
			_move_unstuck(delta, m)
			if _flee_left <= 0.0:
				state = S.RECOVER
				_recover_left = _rng.randf_range(RECOVER_TIME_MIN, RECOVER_TIME_MAX)
		S.RECOVER:
			# Остановилось вдали, мелко дрожит (idle_poke продолжает), ждёт.
			_recover_left -= delta
			if _recover_left <= 0.0:
				state = S.APPROACH
		_:
			# Мирные фазы; ORBIT/APPROACH выбираются по кромке.
			if cd > AWARE_RANGE:
				pass # далеко — не замечен
			elif edge < TOO_CLOSE:
				# Игрок сам подошёл — плавно отползает (спец §БАГ-D.1).
				m._mover.apply_central_force(
						_steer(m, -to_pl.normalized()) * RETREAT_FORCE)
				state = S.ORBIT
				_move_unstuck(delta, m)
			elif edge > ORBIT_MAX:
				state = S.APPROACH
				# Пульсирующие «шажки» спеца: 0.35 + 0.65·max(0, sin(t·2.8)) —
				# долина пульса 245 Н (трение мувера 0.05 — не мешает).
				var pulse := 0.35 + 0.65 * maxf(0.0, sin(_t * PULSE_RATE))
				m._mover.apply_central_force(
						_steer(m, to_pl.normalized()) * APPROACH_FORCE * pulse)
				_move_unstuck(delta, m)
			else:
				state = S.ORBIT
				# Кружение: тангенциальная тяга + мягкая радиальная коррекция.
				var tang := Vector3(-to_pl.z, 0.0, to_pl.x).normalized()
				if tang.length_squared() < 0.001:
					tang = Vector3(1, 0, 0)
				var radial := Vector3.ZERO
				if edge < 4.5:
					radial = -to_pl.normalized() * 200.0
				elif edge > 6.0:
					radial = to_pl.normalized() * 200.0
				var move_dir := (tang * _orbit_side + radial.normalized() * 0.5)
				m._mover.apply_central_force(_steer(m, move_dir) * ORBIT_FORCE)
				_move_unstuck(delta, m)

## Unstuck: если тяга есть, а смещение за UNSTUCK_WIN меньше UNSTUCK_DIST —
## принудительный обходной вектор ±90° на UNSTUCK_HOLD (спец §БАГ-C.2).
func _move_unstuck(delta: float, m) -> void:
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	var p: Vector3 = m._mover.global_position
	if _sample_pos != Vector3.ZERO \
			and p.distance_to(_sample_pos) < UNSTUCK_DIST:
		var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
				_rng.randf_range(-1.0, 1.0))
		if side.length_squared() < 0.001:
			side = Vector3(1, 0, 0)
		_unstuck_dir = side.normalized()
		_unstuck_left = UNSTUCK_HOLD
	_sample_pos = p
	_sample_left = UNSTUCK_WIN

## Whisker-steering: 3 луча (центральный dir, ±STEER_HALF_DEG) из центра
## мувера на высоте STEER_Y, длина STEER_LEN, маска статики (слой 1),
## исключены сам мувер и игрок. Свободный боковой луч предпочтён; при блоке
## центра подмешивается касательная к нормали препятствия (спец §БАГ-C.2).
func _steer(m, dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.001:
		return dir
	if _unstuck_left > 0.0:
		_unstuck_left -= m.get_physics_process_delta_time()
		return _unstuck_dir
	var space: PhysicsDirectSpaceState3D = m.get_world_3d().direct_space_state
	var origin: Vector3 = m._mover.global_position + Vector3(0, STEER_Y, 0)
	var exclude: Array[RID] = [m._mover.get_rid()]
	if _player_rid.is_valid():
		exclude.append(_player_rid)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * STEER_LEN)
	q.collision_mask = 1
	q.exclude = exclude
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return dir
	var n: Vector3 = hit.normal
	n.y = 0.0
	if n.length_squared() < 0.001:
		n = Vector3(0, 0, 1)
	n = n.normalized()
	var tangent := Vector3(-n.z, 0.0, n.x)
	var best_dir := Vector3.ZERO
	var best_free := -1.0
	for a in [STEER_HALF_DEG, -STEER_HALF_DEG]:
		var rd := dir.rotated(Vector3.UP, deg_to_rad(a)).normalized()
		var qr := PhysicsRayQueryParameters3D.create(origin, origin + rd * STEER_LEN)
		qr.collision_mask = 1
		qr.exclude = exclude
		var hr: Dictionary = space.intersect_ray(qr)
		if hr.is_empty():
			best_dir = rd
			best_free = STEER_LEN
			break
		var d: float = origin.distance_to(hr.position)
		if d > best_free:
			best_free = d
			best_dir = rd
	if best_dir == Vector3.ZERO:
		# Оба бока блокированы: скользим по касательной к нормали.
		best_dir = tangent
	else:
		best_dir = (best_dir + tangent * 0.5).normalized()
	return best_dir

## Испуг (выстрел/взрыв, jolt_from scary=true): FSM-фаза FLEE + стартовый
## кик 280·k Н·с (спец §БАГ-D: старый отлёт ~1 м и «секунда испуга» не давали
## отхода; вердикт юзера «отходит на 1 метр и прилипает»). Дальше тяга
## бегства 950 Н работает в tick() пока кромка ближе FLEE_UNTIL_EDGE.
func scare(m, away: Vector3, k: float) -> void:
	state = S.FLEE
	_flee_left = _rng.randf_range(FLEE_TIME_MIN, FLEE_TIME_MAX)
	if m._mover != null:
		m._kick_mover(away, FLEE_KICK * k)
