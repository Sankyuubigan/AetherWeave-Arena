extends Area3D
## Портальная пара v2 «живое окно» (Q44-R: юзер 20.11.26 «да гоу делай» +
## ответ спеца 21.11.26, 05-ответ.md = ССОТ этой задачи; файл-план в
## tasks/261117_2355-089dca89). Отличия от v1 (PortalNode.gd, остаётся старой
## версией скилла): перенос НЕ по входу в зону, а в момент пересечения
## ЦЕНТРАЛЬНОЙ ПЛОСКОСТИ мембраны, ЕДИНОЙ МАТРИЦЕЙ portal_matrix() —
## позиция, ориентация и velocity одним махом. Старый exit_pos/exit_velocity
## инвертировал только локальный Z — а поворот 180° инвертирует И X: зеркало
## вместо разворота, камера окна и точка выхода прыгали на противоположный
## край (баг №1 спеца). EXIT_EPS убран: точка на z=−0.01 перед входом
## попадает ровно на z=+0.01 перед выходом, без рывка. lifetime 30 с,
## за 3 с мембрана мигает. Реестр ALL — хитскан-лучи (ray_through).

const RING_SCRIPT := preload("res://Graphics/PortalRing2.gd")
const TELEPORT_SFX := preload("res://Audio/SFX/neural_teleport.res")
const LIFETIME := 30.0
const FADE_WARN := 3.0
const BODY_CD_MS := 700
## Разворот 180° вокруг вертикали — единственный поворот «вход → выход»
## (спец §1, 05-ответ.md: одна матрица на тело/камеру/скорости/снаряды).
const FLIP_Y := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
const RAY_R := 1.15      # радиус диска мембраны для хитскан-лучей

## Живые порталы v2 (хитскан-лучи перебирают реестр).
static var ALL: Array = []

var partner: Area3D = null
var lifetime := LIFETIME
var _life_left := LIFETIME
var _zone: Array = []    # тела/снаряды внутри зоны (тела из фильтра групп,
                         # снаряды — со свойством current_velocity, как v1)
var _prev_z := {}        # instance_id → локальный z на прошлом тике
var _cd := {}            # instance_id → msec-предел (страховка анти-пинг-понг)
var _ring: Node3D
var _sfx: AudioStreamPlayer3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.stream = TELEPORT_SFX
	_sfx.volume_db = 2.0
	_sfx.max_distance = 25.0
	add_child(_sfx)
	ALL.append(self)

func _exit_tree() -> void:
	ALL.erase(self)

## Визуал + коллизия (эффект вызывает ПОСЛЕ add_child и ориентации ноды:
## локальный +Z портала = нормаль наружу). Кворк 4.8-beta: cs.position до
## add_child у существующего Area мёртв — box центрован на узле. Зона глубиной
## 1.2 м: тело входит в список зоны ЗАРАНЕЕ, перенос — по факту пересечения
## плоскости (z=0), а не по факту входа в бокс (вот и «заход», не сдвиг).
func build(color: Color, seed_off: float, dur: float = LIFETIME) -> void:
	lifetime = dur
	_life_left = dur
	_ring = Node3D.new()
	_ring.set_script(RING_SCRIPT)
	add_child(_ring)
	_ring.call("setup", color, seed_off)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.4, 1.2)
	cs.shape = box
	add_child(cs)

## Окно партнёра (камера SubViewport у выхода) — после назначения partner.
func bind_ring() -> void:
	if _ring:
		_ring.call("bind_partner", partner)

func _physics_process(delta: float) -> void:
	# Lifetime: деспавн ПАРЫ (родитель содержит оба портала) по истечении.
	if _life_left > 0.0:
		_life_left -= delta
		if _life_left <= FADE_WARN and _ring:
			_ring.call("set_fade", 0.55 + 0.45 * sin(_life_left * 9.0))
		if _life_left <= 0.0:
			print("[PORTAL2] expire")
			var pair := get_parent()
			if pair and is_instance_valid(pair):
				pair.queue_free()
			return
	# Пересечение центральной плоскости мембраны = момент «проскока».
	for item in _zone:
		if not is_instance_valid(item):
			continue
		var id: int = item.get_instance_id()
		var lz := to_local(item.global_position).z
		var pz := float(_prev_z.get(id, lz))
		_prev_z[id] = lz
		# вошёл = шёл против нормали (+Z наружу): локальный z сменил знак + → −
		if pz > 0.0 and lz <= 0.0:
			_transfer(item)

func _on_body_entered(body: Node3D) -> void:
	# Только игроки и FFA-боты (вердикт юзера 19.11.26, как v1: манекены,
	# мобы и пропы через портал НЕ идут).
	if not (body.is_in_group("player") or body.is_in_group("ffa_bot")):
		return
	_zone.append(body)

func _on_body_exited(body: Node3D) -> void:
	_zone.erase(body)
	_prev_z.erase(body.get_instance_id())

func _on_area_entered(a: Area3D) -> void:
	# Снаряды ОБОИХ семейств проекта: homing-компоненты несут current_velocity,
	# прямой ProjectileComponent летит по direction+speed и current_velocity
	# НЕ имеет (гейт-болванка ловила только первый тип — живые файрболы
	# пролетали мембрану насквозь, репорт юзера 20.11.26).
	if "current_velocity" in a or ("direction" in a and "speed" in a):
		_zone.append(a)

func _on_area_exited(a: Area3D) -> void:
	_zone.erase(a)
	_prev_z.erase(a.get_instance_id())

## Единая матрица переноса «вход → выход» (ССОТ спеца, 05-ответ.md §1):
## глобалы выхода · разворот 180° · обратные глобалы входа. Ей маппятся
## тело, камера окна, velocity, снаряды, лучи — одна математика на всё.
func portal_matrix() -> Transform3D:
	return partner.global_transform * FLIP_Y * global_transform.affine_inverse()

## Проскок: перенос ЕДИНОЙ МАТРИЦЕЙ — позиция, ориентация и скорость
## поворачиваются одним махом (модуль скорости не тронут): вошёл ВНУТРЬ →
## вышел НАРУЖУ, боковые/вертикальные составляющие сохранены.
func _transfer(item: Node3D) -> void:
	if partner == null or not is_instance_valid(partner):
		return
	var now := Time.get_ticks_msec()
	_gc_cd(now)
	var id: int = item.get_instance_id()
	if int(_cd.get(id, 0)) > now:
		return
	var until := now + BODY_CD_MS
	_cd[id] = until
	partner._cd[id] = until
	var m := portal_matrix()
	item.global_transform = m * item.global_transform
	item.reset_physics_interpolation()
	# Скорость на входе — из того свойства, каким семейством летит объект.
	var vel := Vector3.ZERO
	if item is CharacterBody3D:
		vel = item.velocity
	elif "current_velocity" in item:
		vel = item.current_velocity
	elif "direction" in item and "speed" in item:
		vel = item.direction * item.speed
	var v_out := m.basis * vel
	if item is CharacterBody3D:
		item.velocity = v_out
	elif "current_velocity" in item:
		item.current_velocity = v_out
	elif "direction" in item and "speed" in item:
		if vel.length_squared() > 0.0001:
			item.direction = v_out.normalized()
	if item.is_in_group("player"):
		_update_phase_meta(item, now)
	print("[PORTAL2] transfer %s" % ("body" if item is CharacterBody3D else "proj"))
	_sfx.play()
	partner._sfx.play()
	if item.is_in_group("player"):
		_flash(item)

## Фазовые меты игрока (PlayerController._update_camera_pivot читает
## p2_entry): свежий проход → Фаза 1 (входной портал = self). Откат через
## выходной (тело вернулось через partner, пока камера ещё не прошла) →
## меты прочь — Фаза 0, pivot чисто возвращается за тело.
func _update_phase_meta(item: Node3D, now: int) -> void:
	var rolled_back := false
	if item.has_meta("p2_entry"):
		var old = item.get_meta("p2_entry")
		if old is Node3D and is_instance_valid(old) and old == partner:
			item.remove_meta("p2_entry")
			item.remove_meta("p2_t0")
			rolled_back = true
	if not rolled_back:
		item.set_meta("p2_entry", self)
		item.set_meta("p2_t0", now)

## Хитскан-луч сквозь окно (рецепт спеца «второй RayCast3D из Portal_B на
## остаток длины»): пересечение луча с диском мембраны. Возвращает {}
## или {"portal": вход, "t": дистанция до мембраны} — ближайший по t.
static func ray_through(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var dir_n := dir.normalized()
	for p in ALL:
		if not is_instance_valid(p) or p.partner == null \
				or not is_instance_valid(p.partner):
			continue
		var n: Vector3 = p.global_basis.z.normalized()
		var denom := n.dot(dir_n)
		if denom >= -0.001:
			continue  # луч не входит спереди мембраны
		var t := n.dot(p.global_position - from) / denom
		if t < 0.05 or t > max_dist:
			continue
		var off: Vector3 = from + dir_n * t - p.global_position
		if Vector2(p.global_basis.x.dot(off), p.global_basis.y.dot(off)).length() \
				> RAY_R:
			continue  # мимо диска
		if best.is_empty() or t < float(best["t"]):
			best = {"portal": p, "t": t}
	return best

func _gc_cd(now: int) -> void:
	for k in _cd.keys():
		if int(_cd[k]) <= now:
			_cd.erase(k)

## Виньетка при проскоке (клон v1, чуть короче — «быстрый проскок»).
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
		func(v): mat.set_shader_parameter("strength", v), 1.0, 0.0, 0.12)
	tw.tween_callback(layer.queue_free)
