extends Node3D
## Крылья-скилл (Q20, 19.11.26): процедурные светящиеся крылья на Spine2
## (224 триса, 2×14×4 сетка, unshaded+ADD — без внешних ассетов). Состояния
## FLAP (на земле) / GLIDE (в воздухе — крылья назад + слабая амплитуда).
## Пока активны: speed_mult 1.35 игроку, camera.fov 75→88 (tween 0.28с),
## SpeedLinesOverlay (линии скорости + хроматическая аберрация), трейлы
## за кончиками (GPUParticles3D world-space). Конец — dissolve 0.4с + искры.
## Скелет ищется ОТ РОДИТЕЛЯ (грабля Q19): компонент — ребёнок игрока.

const EffectDB = preload("res://Logic/Skills/Effect.gd")
const OVERLAY_SCRIPT := preload("res://Graphics/SpeedLinesOverlay.gd")

const WING_COLOR := Color(0.45, 0.55, 1.0)
const LIFETIME := 10.0
const SPEED_MULT := 1.35
const BASE_FOV := 75.0
const BOOST_FOV := 88.0
const GLOW := 1.8

const SEG := 14      # сегментов по размаху
const ROWS := 5      # слоёв по хорде (2×14×4 квада = 112 триса на крыло)

var _active := false
var _life_left := 0.0
var _flap_phase := 0.0
var _sweep := 0.0
var _root: Node3D          # автоориентация по скелету (out/up/fwd)
var _wing_l: MeshInstance3D
var _wing_r: MeshInstance3D
var _mats: Array = []
var _light: OmniLight3D
var _trail_l: GPUParticles3D
var _trail_r: GPUParticles3D
var _overlay: Node
var _camera: Camera3D
var _tween: Tween

func _ready() -> void:
	# v8 (финал Q20): WingsRoot — ребёнок GraphicsWrapper, НЕ кости Spine2.
	# Бон-аттач с ориентацией «на кадр позже» дал FPS-зависимую лотерею:
	# базис кости в момент съёма бывал дегенеративным → transform с NaN →
	# крыло то рисуется, то исчезает (пробы 02:41-02:45: валидные вершины/
	# AABB, маркеры в пустоте). GW — чистый yaw scale 1, базис всегда валиден;
	# крылья следуют фейсингу игрока (за позой позвоночника не едут — ок v1).
	var gw := get_parent().get_node_or_null("GraphicsWrapper") as Node3D
	if gw == null:
		push_warning("WingsComponent: GraphicsWrapper не найден")
		return
	_root = Node3D.new()
	_root.name = "WingsRoot"
	gw.add_child(_root)
	# Уровень лопаток: Spine2 глобально ~1.76 (игрок y=0.2, GW -0.8 → локаль
	# 2.56) — проба 02:46 показала крылья НАД макушкой. Опуск до 1.95.
	_root.position = Vector3(0, 1.95, -0.18)
	_wing_l = _build_wing(1)
	_wing_r = _build_wing(-1)
	_root.add_child(_wing_l)
	_root.add_child(_wing_r)
	_trail_l = _make_trail(_wing_l, Vector3(1.35, 1.2, -1.0))
	_trail_r = _make_trail(_wing_r, Vector3(1.35, 1.2, -1.0))
	_light = OmniLight3D.new()
	_light.light_color = WING_COLOR
	_light.omni_range = 4.5
	_light.light_energy = 1.3
	_light.position = Vector3(0, 0.5, -0.3)
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
	player.set("speed_mult", SPEED_MULT)
	if _camera:
		_tween.parallel().tween_property(_camera, "fov", BOOST_FOV, 0.28) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Деактивация: dissolve 0.4с (свечение → 0) + искры, всё остальное гасим сразу.
func deactivate() -> void:
	if not _active:
		return
	_active = false
	var player := get_parent()
	player.set("speed_mult", 1.0)
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
	# FLAP на земле (сильная амплитуда, чаще), GLIDE в воздухе (крылья назад).
	_flap_phase += delta * (0.9 if airborne else 3.4)
	var amp := 0.16 if airborne else 0.5
	_sweep = lerpf(_sweep, 0.5 if airborne else 0.0, delta * 6.0)
	var fl := sin(_flap_phase) * amp
	# Базовый развыск ∓0.55 рад: v5-парус висит вертикально, со спины виден
	# ребром-«палкой» (проба 02:39). Знаки «от камеры»: левое (+X extent) yaw<0
	# уводит кончик в +Z назад, правое зеркально yaw>0. Проба 02:41 с yaw «к
	# камере» дала крылья-в-одном (перекрылись в проекции).
	# Базовый развыск ±0.55 «к камере» (со спины видна плоскость мембраны;
	# проба 02:41 — лучший вид). «От камеры» (∓0.55, проба 02:42) прячет
	# мембраны за телом игрока.
	_wing_l.rotation = Vector3(0.0, _sweep + 0.55, fl)
	_wing_r.rotation = Vector3(0.0, -_sweep - 0.55, -fl)
	# Оверлей — только когда игрок реально разгоняется (как спринт Minecraft).
	var hvel := 0.0
	if player is CharacterBody3D:
		hvel = Vector2(player.velocity.x, player.velocity.z).length()
	_overlay.call("set_strength", clampf(hvel / 6.0, 0.0, 1.0))

## Свечение 0..1: эмиссия материалов + альбедо-альфа (ADD-блендинг = яркость).
func _set_glow(g: float) -> void:
	for m in _mats:
		m.emission_energy_multiplier = GLOW * g
		m.albedo_color.a = g
	if _light:
		_light.light_energy = 1.3 * g

## Вершина крыла: t — по размаху (0 корень → 1 кончик), u — по хорде
## (0 передняя кромка → 1 задняя). Размах 2.05 м, взмывает до ~74°,
## уводит назад и мочет кончик (droop).
func _wing_vertex(t: float, u: float) -> Vector3:
	# v4 (рендер-пробы v1-v3): мембрана с chord НАЗАД смотрится ребром
	# (нормаль вверх → сзади виден росчерк). Парус должен висеть ВНИЗ от
	# дуги: chord (0,-1,-0.35) — вертикальный парус за спиной, видимый сзади.
	# v5 (доказано пробами: рендерится; v7-мембрана в 4.8-beta НЕ рисуется
	# при валидных вершинах/AABB — глючная, выброшена). Дуга-парус: радиус
	# растёт от позвоночника, хорда висит вниз-назад.
	var phi := lerpf(0.1, 0.85, t)
	var r := 2.05 * (0.12 + 0.88 * t)
	var lead := Vector3(cos(phi), sin(phi) * 0.85, -0.2 - 0.45 * sin(phi)) * r
	var chord_dir := Vector3(0.0, -1.0, -0.35).normalized()
	var chord_len := (0.35 + 0.55 * t) * 0.95
	var p := lead + chord_dir * (chord_len * u)
	p.y -= 0.14 * u * t
	return p

func _build_wing(side: int) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.emission_enabled = true
	mat.emission = WING_COLOR
	mat.emission_energy_multiplier = 1.6
	mat.no_shadow = true
	mat.disable_receive_shadows = true
	_mats.append(mat)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in SEG:
		var t0 := float(seg) / SEG
		var t1 := float(seg + 1) / SEG
		for row in ROWS - 1:
			var u0 := float(row) / (ROWS - 1)
			var u1 := float(row + 1) / (ROWS - 1)
			var quad := [_wing_vertex(t0, u0), _wing_vertex(t1, u0),
				_wing_vertex(t1, u1), _wing_vertex(t0, u1)]
			for vi in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				var v: Vector3 = vi
				if side < 0:
					v.x = -v.x  # зеркало В ГЕОМЕТРИИ: node scale(-1) на правом
					# крыле в 4.8-beta не рисуется (проба 02:43 — маркеры левого
					# крыла в пустоте, рисуется только зеркальное)
				var t: float = v.length() / 2.05
				var c := WING_COLOR * (1.45 - 0.4 * t - 0.2 * u0)  # HDR>1 в ADD клампится в белое
				c.a = 1.0
				st.set_color(c)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Трейл за кончиком крыла: GPUParticles3D world-space (не local) — точка
## движется с махом, частицы остаются в мире = шлейф.
func _make_trail(wing: MeshInstance3D, tip_local: Vector3) -> GPUParticles3D:
	var tip := Node3D.new()
	tip.position = tip_local
	wing.add_child(tip)
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
