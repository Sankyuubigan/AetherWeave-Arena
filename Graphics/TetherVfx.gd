extends Node3D
## Q48 «Эфирный захват» — визуальный слой (ТЗ §5, vfx_guidelines: 0 внешних
## ассетов). Живёт на игроке постоянно (создаётся первым зацепом), держит:
## 1) эфирную нить — ImmediateMesh лента 14 сегментов, ShaderMaterial
##    (unshaded, blend_add, бегущие потоки UV.y - TIME*6); первые 0.12 с по
##    сегментам бежит затухающая синусоида-хлыст, потом ровный жгут;
## 2) сигил-якорь — тор-кольцо (UNSHADED/ALPHA/ADD), ориентируется по
##    hit_normal геометрии либо billboard'ом к камере (воздушный якорь);
## 3) burst зацепа — GPUParticles3D one_shot explosiveness 0.95 + OmniLight,
##    самоудаление lifetime+0.2 (0 утечек);
## 4) шлейф скорости — world-space частицы фиолет→бирюза при активном тросе
##    или скорости > 16 м/с;
## 5) camera juice (ТЗ §4.3): FOV 75→96 по скорости (14→38), крен ±2.5°
##    при боковом полёте, CameraShake 0.12 на зацеп/отрыв. Крыльям (Q20,
##    свой FOV 88) уступаем через wings_fly-гвард.

const EffectScript = preload("res://Logic/Skills/Effect.gd")

const SEGMENTS := 14
const THREAD_WIDTH := 0.035
const WHIP_TIME := 0.12
const WHIP_FREQ := 40.0
const WHIP_WAVE := 2.4
const WHIP_AMP := 1.1
const FOV_MIN_SPEED := 14.0
const FOV_MAX_SPEED := 38.0
const FOV_BASE := 75.0
const FOV_MAX := 96.0
const ROLL_MAX := 0.0436        # ±2.5°
const ROLL_SPEED_K := 0.0365
const ROLL_MIN_SPEED := 10.0
const TRAIL_MIN_SPEED := 16.0

@export var thread_color: Color = Color(0.62, 0.42, 1.0)

var _body: CharacterBody3D
var _camera: Camera3D
var _thread: MeshInstance3D
var _im: ImmediateMesh
var _sigil: MeshInstance3D
var _trail: GPUParticles3D
var _tethered := false
var _air_anchor := false
var _anchor := Vector3.ZERO
var _hand := "Left"
var _attach_t := 0.0

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	# Нить: лента в мировых координатах (top_level), перестраивается каждый
	# физ-тик от живой кисти до якоря.
	_im = ImmediateMesh.new()
	_thread = MeshInstance3D.new()
	_thread.mesh = _im
	_thread.top_level = true
	_thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_thread.visible = false
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 0.42, 1.0, 1.0);
uniform float flow_speed : hint_range(0.0, 20.0) = 6.0;
void fragment() {
	float flow = fract(UV.y - TIME * flow_speed);
	vec4 col = mix(glow_color, core_color, pow(flow, 3.0));
	ALBEDO = col.rgb * (0.7 + 0.6 * flow);
	ALPHA = col.a;
}
"""
	mat.shader = sh
	mat.set_shader_parameter("glow_color", thread_color)
	_thread.material_override = mat
	add_child(_thread)
	_trail = _make_trail()
	add_child(_trail)

## ── Хуки TetherSwingComponent ──

## Зацеп (и повторный): нить + сигил + burst + шейк.
func attach(anchor: Vector3, is_air: bool, normal: Vector3, hand: String) -> void:
	_anchor = anchor
	_air_anchor = is_air
	_hand = hand
	_tethered = true
	_attach_t = 0.0
	_thread.visible = true
	_sigil_refresh(anchor, normal)
	_burst(anchor)
	var cs = get_node_or_null("/root/CameraShake")
	if cs:
		cs.add_trauma(0.12)

## Перестройка нити (каждый физ-тик активного троса) + вращение сигила.
func update_thread(delta: float) -> void:
	if not _tethered:
		return
	_attach_t += delta
	if _camera == null and _body != null:
		_camera = _body.get_node_or_null("SpringArm3D/Camera3D")
		if _camera == null and _body.get_viewport() != null:
			_camera = _body.get_viewport().get_camera_3d()
	_rebuild_thread()
	if _sigil != null:
		if _air_anchor and _camera != null:
			_sigil.look_at(_camera.global_position)
		_sigil.rotate_object_local(Vector3.UP, delta * 3.0)

## Отрыв: нить и сигил гаснут, шейк (burst уже отыграл и умер сам).
func detach() -> void:
	_tethered = false
	_thread.visible = false
	if _sigil != null:
		_sigil.queue_free()
		_sigil = null
	# Абсолютный путь работает ТОЛЬКО из живого дерева: detach зовётся и из
	# TetherSwingComponent._exit_tree (узел уже отцеплен) — там шейк не нужен,
	# а get_node("/root/...") валит ERROR (поймано смоуком 26.11.26).
	if is_inside_tree():
		var cs = get_node_or_null("/root/CameraShake")
		if cs:
			cs.add_trauma(0.12)

## ── Нить ──

func _rebuild_thread() -> void:
	if _im == null or _body == null:
		return
	var from := EffectScript.hand_pos(_body, _hand)
	var to := _anchor
	var seg := to - from
	var length := seg.length()
	if length < 0.05:
		_im.clear_surfaces()
		return
	seg /= length
	var cam_z := Vector3(0, 0, 1)
	if _camera != null:
		cam_z = _camera.global_transform.basis.z
	var side := seg.cross(cam_z)
	if side.length() < 0.01:
		side = seg.cross(Vector3(0, 1, 0))
	side = side.normalized() * THREAD_WIDTH
	var up := seg.cross(side).normalized()
	# Хлыст: волна бежит от руки к якорю и гаснет за WHIP_TIME.
	var amp := 0.0
	if _attach_t < WHIP_TIME:
		amp = WHIP_AMP * (1.0 - _attach_t / WHIP_TIME)
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var p: Vector3 = from + seg * (length * t)
		if amp > 0.0:
			p += up * sin(t * WHIP_WAVE * SEGMENTS * 0.35 - _attach_t * WHIP_FREQ) * amp * (0.25 + 0.75 * t)
		_im.surface_set_uv(Vector2(0.0, t))
		_im.surface_add_vertex(p - side)
		_im.surface_set_uv(Vector2(1.0, t))
		_im.surface_add_vertex(p + side)
	_im.surface_end()

## ── Сигил-якорь ──

func _sigil_refresh(anchor: Vector3, normal: Vector3) -> void:
	if _sigil == null:
		_sigil = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.55
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.albedo_color = thread_color
		torus.material = sm
		_sigil.mesh = torus
		_sigil.top_level = true
		_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sigil)
	_sigil.position = anchor
	if not _air_anchor and normal.length() > 0.5:
		# Кольцо лежит в плоскости поверхности (нормаль — ось Y тора).
		if absf(normal.dot(Vector3.UP)) > 0.999:
			_sigil.basis = Basis()
		else:
			var y := normal.normalized()
			var x := y.cross(Vector3.UP).normalized()
			var z := x.cross(y)
			_sigil.basis = Basis(x, y, z)

## ── Burst зацепа ──

func _burst(anchor: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 36
	p.lifetime = 0.45
	p.emitting = true
	p.top_level = true
	p.position = anchor
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -4, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color_ramp = _ramp()
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(0.09)
	add_child(p)
	var light := OmniLight3D.new()
	light.light_color = thread_color
	light.light_energy = 3.5
	light.omni_range = 7.0
	p.add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	# Самоудаление: lifetime + 0.2 (ТЗ §5.2) — 0 утечек.
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)

## ── Шлейф скорости ──

func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.55
	p.amount_ratio = 0.0  # включается по скорости/тросу в _process
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp()
	p.process_material = pm
	p.draw_pass_1 = _particle_quad(0.07)
	return p

## Фиолет → бирюза → прозрачный (палитра vfx_guidelines).
func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 1.0, 1.0), thread_color, Color(0.2, 0.95, 0.9, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _particle_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q

## ── Camera juice (каждый кадр) ──

func _process(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	if _camera == null:
		_camera = _body.get_node_or_null("SpringArm3D/Camera3D")
		if _camera == null and _body.get_viewport() != null:
			_camera = _body.get_viewport().get_camera_3d()
	var vel: Vector3 = _body.velocity
	var speed := vel.length()
	var k := minf(delta * 6.0, 1.0)
	# FOV 75→96 по скорости (14→38 м/с). Крылья (Q20, свой FOV) — не трогаем.
	if _camera != null and _body.get("wings_fly") != true:
		var t := clampf((speed - FOV_MIN_SPEED) / (FOV_MAX_SPEED - FOV_MIN_SPEED), 0.0, 1.0)
		var target := FOV_BASE + (FOV_MAX - FOV_BASE) * t
		_camera.fov = lerpf(_camera.fov, target, k)
	# Крен ±2.5° по боковой составляющей скорости; у земли/медленно — 0.
	if _camera != null:
		if speed > ROLL_MIN_SPEED:
			var side := vel.dot(_camera.global_transform.basis.x)
			var roll := clampf(-side * ROLL_SPEED_K, -ROLL_MAX, ROLL_MAX)
			_camera.rotation.z = lerpf(_camera.rotation.z, roll, minf(delta * 5.0, 1.0))
		else:
			_camera.rotation.z = lerpf(_camera.rotation.z, 0.0, minf(delta * 5.0, 1.0))
	# Шлейф: активный трос или разгон > 16 м/с.
	if _trail != null:
		var on := _tethered or speed > TRAIL_MIN_SPEED
		_trail.amount_ratio = 1.0 if on else 0.0
