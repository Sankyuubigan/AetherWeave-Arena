extends Node3D

## «Акустический Купол» (Q16 Шаг 7, ТЗ спеца ~244): сфера r=1.9 вокруг игрока,
## fresnel + blend_add + cull_disabled (виден изнутри), 12 частотных полос
## спектра (MusicSpectrum.get_analyzer()), бегущие световые кольца от бита
## conductor, DEPTH-пересечение с полом (светящаяся кромка), концентрическая
## рябь от попаданий (notify_impact — кормит BardFlowComponent), цвет по tier.
## Плюс: кольцо-аура на полу (пульс от басов) и орбита нот-частиц на T3.
## Родитель — игрок (узел "AcousticBarrierVFX"), данные — сиблинг
## BardFlowComponent (опрос is_flowing/tier в _process — дешёво и надёжно).

const BANDS := 12
const FREQ_MIN := 40.0
const FREQ_MAX := 16000.0
const DOME_RADIUS := 1.9
const DOME_CENTER_Y := 1.0   # купол от −0.9 до 2.9: тело внутри, низ в полу
const RING_INNER := 1.5
const RING_OUTER := 1.8

const COL_T := Color(0.2, 0.9, 1.0)    # T0–1: бирюза
const COL_P := Color(0.72, 0.3, 1.0)   # T2: фиолет-неон
const COL_G := Color(1.0, 0.8, 0.25)   # T3: золото + орбита нот

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tier_color : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 impact_pos = vec3(0.0, 1.0, 0.0);
uniform float impact_time = -100.0;
uniform float u_time = 0.0;
uniform float beat = 0.0;
uniform float bands[12];
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_view_pos;
varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fresnel: центр почти невидим, кромка светится.
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	// 12 частотных полос: вертикальные пояса по UV.y.
	int bi = clamp(int(UV.y * 12.0), 0, 11);
	float band = bands[bi];
	// Бегущие световые кольца от бита (conductor.beat_tick).
	float rings = pow(max(0.0, sin(UV.y * 9.0 - u_time * 2.2)), 6.0) * (0.25 + beat);
	// Концентрическая рябь от попадания (impact_pos/impact_time).
	float age = u_time - impact_time;
	float dist = distance(v_local, impact_pos);
	float ripple = 0.0;
	if (age > 0.0 && age < 1.2) {
		ripple = sin(dist * 14.0 - age * 16.0) * exp(-age * 3.5)
				* exp(-abs(dist - age * 2.2) * 2.5);
	}
	// DEPTH-пересечение: светящаяся кромка там, где купол встречает пол/геометрию.
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV, scene_d) * 2.0 - 1.0;
	vec4 vs = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vs.xyz /= vs.w;
	float diff = abs(-vs.z - (-v_view_pos.z));
	float edge = 1.0 - smoothstep(0.0, 0.35, diff);

	vec3 col = tier_color * (fres * 1.2 + band * 0.55 + rings * 0.9 + edge * 0.8);
	col += vec3(1.0, 0.95, 0.8) * ripple;
	ALBEDO = col;
	ALPHA = clamp(fres * 0.85 + band * 0.3 + rings * 0.6 + edge * 0.7 + ripple, 0.0, 1.0);
}
"""

var _flow: Node = null
var _cond: Node = null
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _notes: GPUParticles3D
var _bands := PackedFloat32Array()
var _beat := 0.0
var _elapsed := 0.0
var _was_flowing := false
var _tier := -1

func _ready() -> void:
	_bands.resize(BANDS)
	_flow = get_parent().get_node_or_null("BardFlowComponent")
	_cond = get_node_or_null("/root/RhythmConductor")
	_build_dome()
	_build_ring()
	_build_notes()
	visible = false  # показывается только в Потоке
	if _cond != null and not _cond.beat_tick.is_connected(_on_beat):
		_cond.beat_tick.connect(_on_beat)

func _exit_tree() -> void:
	if _cond != null and _cond.beat_tick.is_connected(_on_beat):
		_cond.beat_tick.disconnect(_on_beat)

func _on_beat(_bar: int, _beat_i: int) -> void:
	_beat = 1.0

func _build_dome() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.position = Vector3(0, DOME_CENTER_Y, 0)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	_mesh.material_override = _mat
	add_child(_mesh)

func _build_ring() -> void:
	# Кольцо-аура на полу (пульс от басов — те же полосы спектра).
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.06, 0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(COL_T.r, COL_T.g, COL_T.b, 0.4)
	_ring.material_override = _ring_mat
	add_child(_ring)

func _build_notes() -> void:
	# Орбита нот-частиц (T3, золото): частицы кружат вокруг купола.
	_notes = GPUParticles3D.new()
	_notes.amount = 16
	_notes.lifetime = 3.0
	_notes.local_coords = true  # орбита едет с игроком, хвост не нужен
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = DOME_RADIUS * 0.92
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	m.orbit_velocity_min = 0.25
	m.orbit_velocity_max = 0.5
	m.scale_min = 0.05
	m.scale_max = 0.11
	var grad := Gradient.new()
	grad.colors = [Color(1.0, 0.85, 0.35, 1.0), Color(1.0, 0.7, 0.2, 0.0)]
	grad.offsets = [0.0, 1.0]
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	m.color_ramp = ramp
	var ctex := GradientTexture2D.new()
	var cgrad := Gradient.new()
	cgrad.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
	cgrad.offsets = [0.0, 1.0]
	ctex.gradient = cgrad
	ctex.fill = GradientTexture2D.FILL_RADIAL
	ctex.fill_from = Vector2(0.5, 0.5)
	ctex.fill_to = Vector2(1.0, 0.5)
	ctex.width = 64
	ctex.height = 64
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = ctex
	var quad := QuadMesh.new()
	quad.material = dm
	quad.size = Vector2(0.12, 0.12)
	_notes.draw_pass_1 = quad
	_notes.process_material = m
	_notes.emitting = false
	add_child(_notes)

func _process(delta: float) -> void:
	if _flow == null:
		_flow = get_parent().get_node_or_null("BardFlowComponent")
		return
	var flowing: bool = _flow.is_flowing
	if flowing != _was_flowing:
		_was_flowing = flowing
		visible = flowing
		if not flowing:
			_notes.emitting = false  # орбита T3 глохнет вместе с куполом
			return
	if not flowing:
		return
	_elapsed += delta
	_beat = maxf(0.0, _beat - delta * 2.5)
	# Цвет по tier (опрос — надёжнее сигналов при позднем подключении VFX).
	var t: int = int(_flow.tier)
	if t != _tier:
		_tier = t
		var c := COL_T if t < 2 else (COL_P if t == 2 else COL_G)
		_mat.set_shader_parameter("tier_color", c)
		_ring_mat.albedo_color = Color(c.r, c.g, c.b, _ring_mat.albedo_color.a)
		_notes.emitting = t >= 3
	# Частотные полосы (шина Music через MusicSpectrum — ленивый анализатор).
	var ms = get_node_or_null("/root/MusicSpectrum")
	if ms != null:
		var an = ms.get_analyzer()
		if an != null:
			for b in BANDS:
				var f0 := FREQ_MIN * pow(FREQ_MAX / FREQ_MIN, float(b) / BANDS)
				var f1 := FREQ_MIN * pow(FREQ_MAX / FREQ_MIN, float(b + 1) / BANDS)
				var mg: float = an.get_magnitude_for_frequency_range(f0, f1,
						AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
				_bands[b] = lerpf(_bands[b], mg, 0.35)
			_mat.set_shader_parameter("bands", _bands)
			# Кольцо-аура на полу пульсирует от басов + бита.
			var bass := (_bands[0] + _bands[1] + _bands[2]) / 3.0
			_ring_mat.albedo_color.a = clampf(0.35 + bass * 5.0 + _beat * 0.4, 0.15, 1.0)
	_mat.set_shader_parameter("u_time", _elapsed)
	_mat.set_shader_parameter("beat", _beat)

## Рябь от попадания в купол (BardFlowComponent._absorb_damage, Шаг 6).
func notify_impact(world_pos: Vector3) -> void:
	_mat.set_shader_parameter("impact_pos", _mesh.to_local(world_pos))
	_mat.set_shader_parameter("impact_time", _elapsed)
