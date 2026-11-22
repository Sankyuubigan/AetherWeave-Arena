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
## Центр купола (вердикт 11-ответа): Hips X/Z + feet_y + 0.95. feet_y — НОГИ
## из кеша коллайдера (origin капсулы НЕ пол: h=2.0 в origin → покой на 1.0 м).
const DOME_CENTER_Y := 0.95
## Кольцо основания: бублик шириной 0.18 м. Строится с радиусом base_fit
## (сечение сферы полом); в рантайме масштаб = sqrt(R²−dy²)/base_fit по
## реальному ground_y (raycast), лежит плоским ободом на полу (scale.y=0.15).
const RING_WIDTH := 0.18
## Raycast пола вниз от origin игрока (вердикт 11): длина с запасом.
const GROUND_RAY_LEN := 2.6

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
uniform float u_floor_y = 0.2;  // мир y пола (raycast ground_y + 0.18)
uniform float beat = 0.0;
uniform float bands[12];
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_view_pos;
varying vec3 v_local;
varying float v_world_y;

void vertex() {
	v_local = VERTEX;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// В.7 (вердикт 09): fresnel 3.0 — центр купола чище, кромка резче.
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	// В.7: тонкие волны эквалайзера от MusicSpectrum вместо широких поясов:
	// каждая полоса — узкая горизонтальная линия на своей высоте UV.y,
	// яркость = магнитуда полосы, лёгкое дыхание по высоте и яркости.
		float eq = 0.0;
		for (int i = 0; i < 12; i++) {
			// Вердикт 11: порог отсечки шума — в тишине полосы молчат.
			float mag = max(0.0, bands[i] - 0.08);
		float cy = (float(i) + 0.5) / 12.0 + sin(u_time * 1.7 + float(i) * 1.3) * 0.015;
		float d = (UV.y - cy) * 28.0;
		eq += exp(-d * d) * mag * (0.55 + 0.45 * sin(u_time * 2.3 + float(i) * 0.9));
	}
	// Бегущие световые кольца от бита (conductor.beat_tick).
	// Вердикт 11: база 0.03 вместо 0.25 — в тишине нет ложного пояса,
	// кольца вспыхивают только в бит.
	float rings = pow(max(0.0, sin(UV.y * 9.0 - u_time * 2.2)), 6.0) * (0.03 + beat * 0.75);
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
	// Вердикт 11: скрытый баг — в Forward+/Vulkan глубина уже [0,1] (Reverse-Z),
	// а в Compatibility (OpenGL) — [-1,1]. Умножать scene_d на 2-1 можно
	// ТОЛЬКО в Compatibility, иначе реконструкция vs.z ломается.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene_d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d);
#endif
	vec4 vs = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vs.xyz /= vs.w;
	float diff = abs(-vs.z - (-v_view_pos.z));
	float edge = 1.0 - smoothstep(0.0, 0.35, diff);
	// Фикс Б: DEPTH-пересечение только у ПОЛА (мир y ниже player_y+0.20) —
	// стены/препятствия больше не «прожигают» купол насквозь.
	edge *= 1.0 - smoothstep(u_floor_y - 0.05, u_floor_y, v_world_y);

	vec3 col = tier_color * (fres * 1.2 + eq * 1.1 + rings * 0.9 + edge * 0.8);
	col += vec3(1.0, 0.95, 0.8) * ripple;
	ALBEDO = col;
	// В.7: base alpha 0.03 — тело купола чуть читается, не только линии;
	// clamp ≤ 0.55 (Фикс Б) — купол не превращается в белое пятно.
	ALPHA = clamp(0.03 + fres * 0.85 + eq * 0.5 + rings * 0.6 + edge * 0.7 + ripple, 0.0, 0.55);
}
"""

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
## Вердикт 11-ответа: локальный оффсет origin игрока → подошва (кеш из
## CollisionShape3D); INF = ещё не посчитан. Реальный игрок: −1.0.
var _feet_local_y := INF
var _ring_base_fit := 1.0  # радиус, которым построен торус (масштаб 1.0 = база)
var _last_ground_y := 0.0  # последний валидный пол (raycast мимо — держим)

func _ready() -> void:
	_bands.resize(BANDS)
	_cond = get_node_or_null("/root/RhythmConductor")
	_build_dome()
	_build_ring()
	_build_notes()
	_cache_feet(get_parent() as Node3D)
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
	# Фикс Б: строго на полу y+0.03, бублик (не залитый круг) шириной 0.18.
	# Плейтест-4: радиус = окружность встречи купола с полом.
	var fit := sqrt(DOME_RADIUS * DOME_RADIUS - DOME_CENTER_Y * DOME_CENTER_Y)
	_ring_base_fit = fit  # база для рантайм-масштаба сечения (вердикт 11)
	var torus := TorusMesh.new()
	torus.inner_radius = fit - RING_WIDTH
	torus.outer_radius = fit
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.03, 0)
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
	# В.7 (вердикт 09): процедурная 64×64 чёткая текстура — острая 4-лучевая
	# искра-нота вместо размытого кружка (GradientTexture2D FILL_RADIAL).
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for py in 64:
		for px in 64:
			var dx := (float(px) + 0.5) / 64.0 - 0.5
			var dy := (float(py) + 0.5) / 64.0 - 0.5
			var star := pow(absf(dx) / 0.5, 0.35) + pow(absf(dy) / 0.5, 0.35)
			var a := clampf((1.0 - star) * 4.0, 0.0, 1.0)
			var dist := sqrt(dx * dx + dy * dy)
			var core := clampf(1.0 - dist / 0.16, 0.0, 1.0)  # яркая головка
			img.set_pixel(px, py, Color(1, 1, 1, maxf(a, core)))
	var ctex := ImageTexture.create_from_image(img)
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
	# Единый источник (спец 11-ответ Блок 3 п.1): активный бард-компонент —
	# «Пульс» (bard_groove, is_active) ИЛИ «Поток» (bard_flow, is_flowing);
	# купол один на обе стойки, tier/барьер-цвет общие.
	var bard := _active_bard()
	var flowing: bool = bard != null
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
	# Вердикт 11-ответа: все высоты от НОГ (feet_y = origin + оффсет коллайдера),
	# пол — короткий raycast (ground_y). Центр купола: Hips X/Z + feet_y + 0.95.
	var player := get_parent() as Node3D
	if player != null:
		if is_inf(_feet_local_y):
			_cache_feet(player)
		var feet_y := player.global_position.y + _feet_local_y
		var cx := player.global_position.x
		var cz := player.global_position.z
		var bp := _hips_pos(player)
		if bp != Vector3.INF:
			cx = bp.x
			cz = bp.z
		var center_y := feet_y + DOME_CENTER_Y
		_mesh.global_position = Vector3(cx, center_y, cz)
		# Кольцо-шов: на реальном полу под ногами, радиус = сечение сферы полом.
		var ground_y := _ground_y(player)
		var dy := center_y - ground_y
		if dy >= 0.0 and dy < DOME_RADIUS - 0.1:
			_ring.visible = true
			_ring.global_position = Vector3(cx, ground_y + 0.02, cz)
			var sec := sqrt(maxf(0.0, DOME_RADIUS * DOME_RADIUS - dy * dy))
			var s := sec / _ring_base_fit
			_ring.scale = Vector3(s, 0.15, s)  # 0.15: плоский световой обод
		else:
			# Прыжок выше купола / raycast мимо пола — шов не парит в воздухе.
			_ring.visible = false
		_mat.set_shader_parameter("u_floor_y", ground_y + 0.18)
	# Цвет по tier (опрос — надёжнее сигналов при позднем подключении VFX).
	var t: int = int(bard.tier)
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

## Рябь от попадания в купол (BardFlowComponent/BardGrooveComponent._absorb_damage).
func notify_impact(world_pos: Vector3) -> void:
	_mat.set_shader_parameter("impact_pos", _mesh.to_local(world_pos))
	_mat.set_shader_parameter("impact_time", _elapsed)

## Единый источник данных купола (спец 11-ответ Блок 3 п.1): активный
## бард-компонент — «Пульс» (bard_groove) или «Поток» (bard_flow); null —
## вне обеих стоек (купол скрыт).
func _active_bard() -> Node:
	var parent := get_parent()
	var g = parent.get_node_or_null("BardGrooveComponent")
	if g != null and bool(g.is_active):
		return g
	var f = parent.get_node_or_null("BardFlowComponent")
	if f != null and bool(f.is_flowing):
		return f
	return null

## ── Вердикт 11-ответа: ноги из коллайдера + raycast пола ──────────────────
var _feet_cached := false

## Кеш высоты ног: локальный оффсет origin→подошва из CollisionShape3D.
## Capsule/Cylinder: position.y − height·0.5; Box: position.y − size.y·0.5.
## Нет коллайдера / неизвестный шейп → fallback −1.0 (вердикт 11), НЕ INF:
## стабы проб без коллайдера обязаны работать как игрок-«эталон».
func _cache_feet(player: Node3D) -> void:
	if _feet_cached or player == null:
		return
	var col := _find_collision(player)
	if col == null or col.shape == null:
		_feet_local_y = -1.0
		_feet_cached = true
		return
	var sh: Shape3D = col.shape
	if sh is CapsuleShape3D:
		_feet_local_y = col.position.y - (sh as CapsuleShape3D).height * 0.5
	elif sh is CylinderShape3D:
		_feet_local_y = col.position.y - (sh as CylinderShape3D).height * 0.5
	elif sh is BoxShape3D:
		_feet_local_y = col.position.y - (sh as BoxShape3D).size.y * 0.5
	else:
		_feet_local_y = -1.0
	_feet_cached = true

static func _find_collision(node: Node) -> CollisionShape3D:
	if node == null:
		return null
	if node is CollisionShape3D:
		return node
	for c in node.get_children():
		var r := _find_collision(c)
		if r != null:
			return r
	return null

## Пол под ногами: 1 raycast вниз от origin (исключая игрока), маска слоя 1.
func _ground_y(player: Node3D) -> float:
	var space := player.get_world_3d().direct_space_state
	var excl: Array[RID] = [player.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(
			player.global_position,
			player.global_position + Vector3.DOWN * GROUND_RAY_LEN,
			1, excl)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return _last_ground_y
	_last_ground_y = hit.position.y
	return _last_ground_y

## ── Фикс Б: привязка купола к кости Hips ─────────────────────────────────
var _hips_bone := -1
var _skel: Skeleton3D = null

## Мировая позиция кости mixamorig_Hips (кеш скелета/индекса); INF — нет.
func _hips_pos(player: Node3D) -> Vector3:
	if _skel == null or not is_instance_valid(_skel):
		_skel = _find_skeleton(player.get_node_or_null("GraphicsWrapper/PlayerModel"))
		_hips_bone = -1
	if _skel == null:
		return Vector3.INF
	if _hips_bone < 0:
		_hips_bone = _skel.find_bone("mixamorig_Hips")
	if _hips_bone < 0:
		return Vector3.INF
	return (_skel.global_transform * _skel.get_bone_global_pose(_hips_bone)).origin

static func _find_skeleton(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
