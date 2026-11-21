extends Node3D
## Крылья-скилл Q20 v9 (19.11.26, вердикт юзера: «лист бумаги А4, видны
## только с 1 ракурса, полёта нет»): перьевой ВЕЕР — 8 изогнутых перьев на
## крыло, развеска по yaw 0.12→1.18 рад и roll −0.35→+0.6 — часть перьев
## всегда почти фронтальна камере → крыло видно с ЛЮБОГО ракурса (v8: 2
## плоские ленты 2×14×4, сбоку ребро, спереди перекрыты в проекции).
## Мах с фазовым сдвигом перьев (концевые отстают и машут сильнее — вторичная
## анимация). Полёт: activate ставит player.wings_fly=true (PlayerController:
## удержание Space в воздухе = тяга 4.2 м/с, без Space глайд −2.0). При наборе
## высоты — энергичный мах (визуальная связь «машу → лечу»).
## Скелет ищется ОТ РОДИТЕЛЯ (грабля Q19): компонент — ребёнок игрока.

const EffectDB = preload("res://Logic/Skills/Effect.gd")
const OVERLAY_SCRIPT := preload("res://Graphics/SpeedLinesOverlay.gd")

const WING_COLOR := Color(0.45, 0.55, 1.0)
const LIFETIME := 10.0
# Q46 (юзер 20.11.26): скорость БАЗОВАЯ при активации; после SPRINT_RAMP секунд
# НЕПРЕРЫВНОГО бега появляется эффект (линии+FOV) и скорость бустится —
# «ещё быстрее чем щас» (было 1.35 сразу). Остановка = сброс рампа и буста.
const SPEED_MULT := 1.6
const SPRINT_RAMP := 2.5
const SPRINT_HVEL := 2.0
const BASE_FOV := 75.0
const BOOST_FOV := 88.0
const GLOW := 1.8

const FEATHERS := 8   # перьев на крыло (8×16 = 128 трис/крыло, 256 всего)
const SEG := 8        # сегментов по длине пера (8 quad = 16 трис/перо)

var _active := false
var _life_left := 0.0
var _flap_phase := 0.0
var _sweep := 0.0
var _run_time := 0.0     # накопитель непрерывного бега (Q46 рамп)
var _boosted := false
var _root: Node3D          # WingsRoot на GraphicsWrapper (не кость — грабля 4.8)
var _wing_l: Node3D        # пивоты целого крыла (sweep + общий мах)
var _wing_r: Node3D
var _feathers_l: Array = []  # пивоты отдельных перьев (фазовый мах)
var _feathers_r: Array = []
var _mats: Array = []
var _light: OmniLight3D
var _trail_l: GPUParticles3D
var _trail_r: GPUParticles3D
var _overlay: Node
var _camera: Camera3D
var _tween: Tween

func _ready() -> void:
	# WingsRoot — ребёнок GraphicsWrapper, НЕ кости Spine2: бон-аттач с
	# ориентацией «на кадр позже» давал NaN-базисы → крылья то рисуются, то
	# исчезают (пробы 02:41-02:45). GW — чистый yaw, базис всегда валиден.
	var gw := get_parent().get_node_or_null("GraphicsWrapper") as Node3D
	if gw == null:
		push_warning("WingsComponent: GraphicsWrapper не найден")
		return
	_root = Node3D.new()
	_root.name = "WingsRoot"
	gw.add_child(_root)
	# Корень на лопатках (модель 1.8: плечи ~1.45-1.5). Веер v9 раскрывается
	# ВВЕРХ-НАЗАД — massa крыла над плечами, корень низко (проба v9: корень
	# 1.95 = «рога на макушке», веер горизонтальный = линия сбоку).
	# Q45 (юзер 20.11.26 «крылья слишком далеко от тела»): было (0,1.5,-0.28) —
	# плюс затемнённые корни перьев читались как фан, висящий в воздухе.
	_root.position = Vector3(0, 1.45, -0.12)
	_wing_l = _build_wing(1)
	_wing_r = _build_wing(-1)
	_root.add_child(_wing_l)
	_root.add_child(_wing_r)
	_light = OmniLight3D.new()
	_light.light_color = WING_COLOR
	_light.omni_range = 4.5
	_light.light_energy = 1.3
	_light.position = Vector3(0, 0.5, -0.15)
	_light.visible = false
	_root.add_child(_light)
	_camera = get_parent().get_node_or_null("SpringArm3D/Camera3D")
	_overlay = CanvasLayer.new()
	_overlay.set_script(OVERLAY_SCRIPT)
	add_child(_overlay)
	visible = false

## Активация (или продление на полный срок при повторном касте).
func activate(duration: float = LIFETIME) -> void:
	if _root == null:
		return
	_life_left = duration
	if _active:
		return
	_active = true
	visible = true
	_set_glow(1.0)
	_burst(true)
	if _tween: _tween.kill()
	_tween = create_tween()
	_root.scale = Vector3(0.12, 0.08, 0.12)
	_tween.tween_property(_root, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _light: _light.visible = true
	if _trail_l: _trail_l.emitting = true
	if _trail_r: _trail_r.emitting = true
	var player := get_parent()
	# Q46: при активации скорость БАЗОВАЯ (рамп буста — в _process), FOV не трогаем.
	player.set("speed_mult", 1.0)
	_run_time = 0.0
	_boosted = false
	# Полёт (Q20 v2): пока крылья активны — PlayerController держит тягу
	# по Space в воздухе и глайд вместо свободного падения.
	player.set("wings_fly", true)

## Деактивация: dissolve 0.4с (свечение → 0) + искры, всё остальное гасим сразу.
func deactivate() -> void:
	if not _active:
		return
	_active = false
	var player := get_parent()
	player.set("speed_mult", 1.0)
	player.set("wings_fly", false)
	_boosted = false
	_run_time = 0.0
	if _light: _light.visible = false
	if _trail_l: _trail_l.emitting = false
	if _trail_r: _trail_r.emitting = false
	if _camera:
		var tw := create_tween()
		tw.tween_property(_camera, "fov", BASE_FOV, 0.3)
	if _overlay: _overlay.call("set_strength", 0.0)
	_burst(false)
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_glow, 1.0, 0.0, 0.4)
	_tween.parallel().tween_property(_root, "scale", Vector3(0.05, 0.02, 0.05), 0.4)
	_tween.tween_callback(func(): visible = false)

func is_active() -> bool:
	return _active

func _process(delta: float) -> void:
	if not _active or _root == null:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		deactivate()
		return
	var player := get_parent()
	var airborne: bool = player is CharacterBody3D and not player.is_on_floor()
	var vy := 0.0
	if player is CharacterBody3D:
		vy = player.velocity.y
	# Три режима: IDLE-флап на земле; POWER-мах при наборе высоты (держит
	# Space — «машу → лечу», проба v9); GLIDE в воздухе без набора (вперёд-
	# развеска → назад, слабая амплитуда — v8-наследование).
	var amp := 0.5
	var speed := 3.4
	var sweep_target := 0.0
	if airborne:
		if vy > 1.0:
			amp = 0.75
			speed = 7.0
			sweep_target = 0.15
		else:
			amp = 0.16
			speed = 0.9
			sweep_target = 0.9
	_flap_phase += delta * speed
	_sweep = lerpf(_sweep, sweep_target, delta * 6.0)
	var fl := sin(_flap_phase) * amp
	# Целое крыло: лёгкий общий мах вокруг Z + sweep по Y (назад = ∓).
	_wing_l.rotation = Vector3(0.0, _sweep + 0.3, fl * 0.7)
	_wing_r.rotation = Vector3(0.0, -_sweep - 0.3, -fl * 0.7)
	# Фазовый мах перьев: концевые (ti→1) машут сильнее и с запаздыванием
	# фазы — вторичная анимация, крыло «волнуется», а не лопатка.
	for i in FEATHERS:
		var ti := float(i) / float(FEATHERS - 1)
		var k := 0.45 + 0.6 * ti
		var fli := sin(_flap_phase - 0.55 * ti) * amp
		(_feathers_l[i] as Node3D).rotation.z = fli * k
		(_feathers_r[i] as Node3D).rotation.z = -fli * k
	# Q46 рамп спринта: непрерывный бег копит _run_time; через SPRINT_RAMP —
	# буст скорости + эффект (линии + FOV). Остановка — мгновенный сброс.
	var hvel := 0.0
	if player is CharacterBody3D:
		hvel = Vector2(player.velocity.x, player.velocity.z).length()
	if hvel >= SPRINT_HVEL:
		_run_time += delta
	else:
		_run_time = 0.0
	if _boosted and hvel < SPRINT_HVEL:
		_boosted = false
		player.set("speed_mult", 1.0)
		if _camera:
			var tw := create_tween()
			tw.tween_property(_camera, "fov", BASE_FOV, 0.3)
	elif not _boosted and _run_time >= SPRINT_RAMP:
		_boosted = true
		player.set("speed_mult", SPEED_MULT)
		if _camera:
			if _tween: _tween.kill()
			_tween = create_tween()
			_tween.tween_property(_camera, "fov", BOOST_FOV, 0.3) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Оверлей ТОЛЬКО в буст-режиме: до рампа экран чистый (заказ юзера 20.11.26).
	if _boosted:
		_overlay.call("set_strength", clampf(hvel / 6.0, 0.0, 1.0))
	else:
		_overlay.call("set_strength", 0.0)

## Свечение 0..1: эмиссия материалов + альбедо-альфа (ADD-блендинг = яркость).
## База 0.35 (см. материал) — слоёное сложение 8 перьев не климпится в белое.
func _set_glow(g: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = 0.35 * GLOW * g
		m.albedo_color.a = 0.55 * g
	if _light:
		_light.light_energy = 1.3 * g

## Параметры пера ti (0 внутреннее → 1 концевое). Веер v9.1: азимут от +X
## ЗА СПИНУ (−Z: модель смотрит +Z — проба вскрыла, что +Z-веер торчит в
## лицо сквозь голову) и элевация ВВЕРХ (вертикальный раскрыл — иначе сбоку
## веер-в-одну-линию). Roll наклоняет плоскость ленты — ловит камеру с любых
## ракурсов. Q45 (юзер 20.11.26 «слишком далеко от тела»): короче (1.25–1.8,
## было 1.5–2.2) и плотнее к спине (yaw 0.10–0.72, было 0.15–0.85) —
## визуальная масса веера прижата к спине.
func _feather_params(ti: float) -> Dictionary:
	return {
		"yaw": lerpf(0.10, 0.72, ti),
		"elev": lerpf(0.10, 1.05, ti),
		"roll": lerpf(-0.35, 0.6, ti),
		"length": lerpf(1.25, 1.8, ti),
		"width": lerpf(0.30, 0.17, ti),
	}

## Направление хребта пера: азимут от +X к −Z (спина), подъём elev вверх.
func _spine_dir(p: Dictionary) -> Vector3:
	var cy: float = cos(p.yaw)
	var sy: float = sin(p.yaw)
	var ce: float = cos(p.elev)
	var se: float = sin(p.elev)
	return Vector3(cy * ce, se, -sy * ce)

## Хребет пера при s (0 корень → 1 кончик): луч по хребту + прогиб вниз.
func _feather_spine(p: Dictionary, s: float) -> Vector3:
	var v: Vector3 = _spine_dir(p) * (p.length * s)
	v.y -= 0.22 * p.length * s * s
	return v

## Направление ширины ленты: UP спроецированный ⊥ хребту, roll вокруг оси
## хребта валит плоскость — перья ловят камеру с любых ракурсов.
func _feather_width_dir(p: Dictionary) -> Vector3:
	var d: Vector3 = _spine_dir(p)
	var w: Vector3 = Vector3.UP - d * Vector3.UP.dot(d)
	if w.length() < 0.05:
		w = Vector3(0, 0, -1) + d * d.z
	return w.normalized().rotated(d, p.roll)

## Полуширина «пера»: узкий корень → широкая середина → остриё (sin-профиль).
func _feather_halfwidth(p: Dictionary, s: float) -> float:
	var t := clampf(pow(s, 0.7), 0.02, 0.98)
	return p.width * 0.5 * maxf(sin(PI * t), 0.10)

## Меш одного пера: лента SEG-сегментов вдоль хребта. Зеркало правого крыла
## В ГЕОМЕТРИИ (node scale(-1) в 4.8-beta не рисуется — проба 02:43).
func _feather_mesh(p: Dictionary, side: int, ti: float) -> ArrayMesh:
	var wd := _feather_width_dir(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in SEG:
		var s0 := float(seg) / SEG
		var s1 := float(seg + 1) / SEG
		var a0 := _feather_spine(p, s0)
		var a1 := _feather_spine(p, s1)
		var h0 := _feather_halfwidth(p, s0)
		var h1 := _feather_halfwidth(p, s1)
		var quad := [a0 - wd * h0, a0 + wd * h0, a1 + wd * h1, a1 - wd * h1]
		var ss := [s0, s0, s1, s1]
		for oi in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = quad[oi]
			if side < 0:
				v.x = -v.x
			# Ярче к кончикам (HDR>1 клампится в белое). Q45: корни подняты
			# 0.7→0.95 — веер читается ПРИКРЕПЛЁННЫМ к спине, не висящим.
			var c: Color = WING_COLOR * (0.95 + 0.6 * ss[oi]) * (0.85 + 0.15 * ti)
			c.a = 1.0
			st.set_color(c)
			st.add_vertex(v)
	return st.commit()

## Крыло: пивот + FEATHERS перьев-детей (ось маха каждого — своё вращение Z).
## У концевого пера — трейл (GPUParticles3D world-space у кончика).
func _build_wing(side: int) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.emission_enabled = true
	mat.emission = WING_COLOR
	# 8 перьев перекрываются у корня — ADD складывает эмиссию СЛОЯМИ (проба
	# v9: 8×1.6 ≈ 13× = сплошной белый «лист А4»). 0.35/перо ≈ 2.8 у корня.
	mat.emission_energy_multiplier = 0.35
	mat.no_shadow = true
	mat.disable_receive_shadows = true
	_mats.append(mat)
	var pivot := Node3D.new()
	var feathers: Array = []
	for i in FEATHERS:
		var ti := float(i) / float(FEATHERS - 1)
		var p := _feather_params(ti)
		var fp := Node3D.new()
		pivot.add_child(fp)
		var mi := MeshInstance3D.new()
		mi.mesh = _feather_mesh(p, side, ti)
		# БЕЗ override перья рисуются ДЕФОЛТНЫМ материалом (белый «лист А4» +
		# cull BACK → крыло видно с одной стороны — вердикт юзера про v8;
		# найдено изо-пробой 19.11: AABB валиден, меш серый).
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fp.add_child(mi)
		feathers.append(fp)
		if i == FEATHERS - 1:
			var tr := _make_trail(mi, _feather_spine(p, 1.0))
			if side > 0:
				_trail_l = tr
			else:
				_trail_r = tr
	if side > 0:
		_feathers_l = feathers
	else:
		_feathers_r = feathers
	return pivot

## Трейл за кончиком крыла: GPUParticles3D world-space (не local) — точка
## движется с махом, частицы остаются в мире = шлейф.
func _make_trail(host: Node3D, tip_local: Vector3) -> GPUParticles3D:
	var tip := Node3D.new()
	tip.position = tip_local
	host.add_child(tip)
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.55
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0, 0.4, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = WING_COLOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.no_shadow = true
	quad.material = m
	p.draw_pass_1 = quad
	tip.add_child(p)
	return p

## Всплеск искр при открытии/закрытии (one-shot, паттерн клинка Q19).
func _burst(open: bool) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36 if open else 24
	p.lifetime = 0.45
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -3.5, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = WING_COLOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.no_shadow = true
	quad.material = m
	p.draw_pass_1 = quad
	_root.add_child(p)
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)
