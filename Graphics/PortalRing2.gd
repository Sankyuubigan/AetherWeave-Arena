extends Node3D
## Визуал портала v2 «живое окно» (Q44-R по ответу спеца 21.11.26,
## 05-ответ.md = ССОТ): рамка-тор + руны + свет — наследие v1; мембрана —
## МЕМБРАНА-«КАРМАН» (канон Valve): короткий цилиндр БЕЗ передней крышки
## (R=1.15, depth 0.35, сдвинут на −0.175 за плоскость, cull_front — видны
## внутренние стенки и заднее дно). Плоский квад не годится: у near-клипа
## 0.12–0.15 м при FOV 75–90° квад обрезается до свопа — сквозь «окно»
## светится реальный мир (баг подхода 1.0 м из отчёта спецу).
## Шейдер: SCREEN_UV-сэмплинг БЕЗ всяких ratio (баг №2 спеца: SCREEN_UV уже
## нормализован [0..1]); aspect SubViewport = аспекту главного вьюпорта
## (size = main_size * res_scale), fov/keep_aspect синхронно → пиксель-в-пиксель
## шов при залезании. Марево из центра УБРАНО: картинка чистая, вихрь только
## обод (v_r > 0.85). Окно обновляется в RenderingServer.frame_pre_draw —
## 0 кадров рассинхрона (баг №4 спеца: обновление в _process отставало).
## Клип мира за выходом — динамический near по Способу 3А спеца (oblique
## near plane запрещён — баг Godot #124952). Изнанка = задний квад-вихрь.
## LOW-графика / headless: непрозрачный вихрь v1 (окна нет).
## Слой 3 — «портальные» визуалы: камера окна исключает слой (cull_mask) —
## анти-рекурсия (вердикт спеца: слоя 3 достаточно).

const LAYER_BIT := 1 << 2   # layer 3
const RES_FAR := 0.33       # доля разрешения главного вьюпорта (aspect!)
const RES_CLOSE := 0.5      # ближе 8 м — каждый кадр и больше пикселей
const RES_CLOSE_HIGH := 0.75
const UPDATE_EVERY := 3
const MAX_DIST := 45.0
const CLOSE_DIST := 8.0
const RING_R := 1.15
const POCKET_DEPTH := 0.35

const MEMBRANE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform sampler2D view_tex : source_color, filter_linear;
uniform vec4 base_color : source_color = vec4(0.35, 0.55, 1.0, 1.0);
uniform float seed_off = 0.0;
uniform float low_mode = 0.0;
uniform float life_fade = 1.0;
varying float v_r;
varying float v_ang;
void vertex() {
	// Ось цилиндра в модельном пространстве — Y: радиальная плоскость XZ.
	v_r = length(VERTEX.xz) / 1.15;
	v_ang = atan(VERTEX.z, VERTEX.x);
}
void fragment() {
	// Окно = ровно то, что стоит на экране за мембраной (screen-space).
	vec3 win = texture(view_tex, SCREEN_UV).rgb;
	float rim = smoothstep(0.80, 1.0, v_r);
	float face = clamp(rim + low_mode, 0.0, 1.0);
	float bands = sin(v_ang * 3.0 + v_r * 10.0 - TIME * 1.7 - seed_off) * 0.5 + 0.5;
	vec3 col = mix(win, base_color.rgb * (0.55 + 1.25 * bands), face);
	col += vec3(0.9) * pow(smoothstep(0.7, 1.0, v_r), 3.0) * (1.0 - low_mode);
	float a = mix(1.0, clamp(bands * rim + 0.25, 0.0, 1.0), face);
	ALBEDO = col;
	ALPHA = clamp(a * life_fade, 0.0, 1.0);
}
"""

const BACK_VORTEX := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 base_color : source_color = vec4(0.35, 0.55, 1.0, 1.0);
uniform float seed_off = 0.0;
uniform float life_fade = 1.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv) * 2.0;
	if (r > 1.0) { discard; }
	float ang = atan(uv.y, uv.x);
	float bands = sin(ang * 3.0 + r * 10.0 - TIME * 1.7 - seed_off) * 0.5 + 0.5;
	ALBEDO = base_color.rgb * (0.55 + 1.25 * bands);
	ALPHA = clamp(bands * 0.85 + 0.2, 0.0, 1.0) * life_fade;
}
"""

var _runes: Node3D
var _spin := 0.25
var _view: SubViewport
var _cam: Camera3D
var _mmat: ShaderMaterial
var _fade_mats: Array = []
var _on_screen := false
var _frame := 0
var _partner: Area3D
var _update_frame := false
## Гейт-пробы шва ставят 1.0 — пиксель-в-пиксель сравнение без апскейла.
var res_override := 0.0

## color — цвет пары, seed_off — фаза вихря (кольца не крутятся синхронно).
func setup(color: Color, seed_off: float) -> void:
	var low := false
	var gq = get_node_or_null("/root/GraphicsQuality")
	if gq and int(gq.get("quality")) == 0:
		low = true
	# headless: рендера нет — окно не строим (гейты тестов это знают).
	if DisplayServer.get_name() == "headless":
		low = true

	var sm := Shader.new()
	sm.code = MEMBRANE
	_mmat = ShaderMaterial.new()
	_mmat.shader = sm
	_mmat.set_shader_parameter("base_color", color)
	_mmat.set_shader_parameter("seed_off", seed_off)
	_mmat.set_shader_parameter("low_mode", 1.0 if low else 0.0)
	_fade_mats = [_mmat]

	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = BACK_VORTEX
	vm.shader = vs
	vm.set_shader_parameter("base_color", color)
	vm.set_shader_parameter("seed_off", seed_off)
	_fade_mats.append(vm)

	if not low:
		_view = SubViewport.new()
		# Размер = доля ГЛАВНОГО вьюпорта → aspect всегда совпадает (баг
		# №2 спеца: фиксированные 426×240 ломали screen-space сэмплинг).
		_view.size = _want_size(RES_FAR)
		_view.msaa_3d = Viewport.MSAA_DISABLED
		_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_view.positional_shadow_atlas_size = 0
		# Прогрев по спецу: UPDATE_DISABLED — первый кадр без фриза открытия.
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_cam = Camera3D.new()
		_cam.fov = 70.0
		_cam.near = 0.05
		_cam.far = 90.0
		_cam.cull_mask = (1 << 20) - 1 & ~LAYER_BIT
		_view.add_child(_cam)
		add_child(_view)
		_mmat.set_shader_parameter("view_tex", _view.get_texture())
		# 0 кадров рассинхрона: поза камеры окна + UPDATE_ONCE строго перед
		# отрисовкой кадра (баг №4 спеца — обновление в _process отставало
		# на кадр, картинка «доигрывала» движение).
		RenderingServer.frame_pre_draw.connect(_sync_window)

	if low:
		# LOW / headless: непрозрачный вихрь (старое поведение, окна нет).
		var quad := QuadMesh.new()
		quad.size = Vector2(2.3, 2.3)
		quad.material = vm
		var lmi := MeshInstance3D.new()
		lmi.mesh = quad
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lmi.layers = LAYER_BIT
		add_child(lmi)
	else:
		# Карман-цилиндр: передняя крышка открыта (входим внутрь), заднее
		# дно = экран окна. rotation X 90° ставит ось Y цилиндра вдоль Z.
		var cyl := CylinderMesh.new()
		cyl.top_radius = RING_R
		cyl.bottom_radius = RING_R
		cyl.height = POCKET_DEPTH
		cyl.cap_top = false
		cyl.cap_bottom = true
		cyl.radial_segments = 48
		cyl.rings = 4
		cyl.material = _mmat
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation_degrees.x = 90.0
		mi.position = Vector3(0, 0, -POCKET_DEPTH * 0.5)  # передний срез в z=0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER_BIT
		add_child(mi)

		# Изнанка: задний квад-вихрь (сзади карман прозрачен — cull_front
		# клипает его стенки; без квада сквозь кольцо был бы мир за порталом).
		var bquad := QuadMesh.new()
		bquad.size = Vector2(2.3, 2.3)
		bquad.material = vm
		var bmi := MeshInstance3D.new()
		bmi.mesh = bquad
		bmi.position = Vector3(0, 0, -POCKET_DEPTH - 0.01)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bmi.layers = LAYER_BIT
		add_child(bmi)

	# Нотифайер видимости мембраны — окно обновляется только на экране.
	var vis := VisibleOnScreenNotifier3D.new()
	vis.set_aabb(AABB(Vector3(-1.2, -1.2, -0.5), Vector3(2.4, 2.4, 1.0)))
	vis.screen_entered.connect(func(): _on_screen = true)
	vis.screen_exited.connect(func(): _on_screen = false)
	add_child(vis)

	# Рамка-тор: TorusMesh лежит в XZ — поворот X 90° ставит его вертикально.
	var tor := TorusMesh.new()
	tor.inner_radius = 0.95
	tor.outer_radius = 1.12
	tor.rings = 48
	tor.ring_segments = 12
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = color * 0.5
	tm.emission_enabled = true
	tm.emission = color
	tm.emission_energy_multiplier = 1.5
	var tmi := MeshInstance3D.new()
	tmi.mesh = tor
	tmi.material_override = tm
	tmi.rotation_degrees.x = 90.0
	tmi.layers = LAYER_BIT
	add_child(tmi)

	# Руны-бусины по кольцу (медленное вращение по нормали).
	_runes = Node3D.new()
	add_child(_runes)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.75, 0.85, 1.0, 1.0) * 1.4
	for i in 12:
		var rq := QuadMesh.new()
		rq.size = Vector2(0.09, 0.09)
		rq.material = bm
		var rb := MeshInstance3D.new()
		rb.mesh = rq
		rb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / 12.0
		rb.position = Vector3(cos(ang) * 1.15, sin(ang) * 1.15, 0.06)
		rb.layers = LAYER_BIT
		_runes.add_child(rb)

	# Свет портала.
	var lt := OmniLight3D.new()
	lt.light_color = color
	lt.omni_range = 4.5
	lt.light_energy = 1.2
	lt.position = Vector3(0, 0, 0.6)
	add_child(lt)

## Камера окна у ПАРТНЁРА (PortalNode2.bind_ring ПОСЛЕ назначения partner).
## Статичная поза не нужна: _sync_window ставит её каждый кадр перед
## отрисовкой; здесь только первый прогрев-кадр (готово ДО первого взгляда).
func bind_partner(p: Area3D) -> void:
	if _view == null or p == null or not is_instance_valid(p):
		return
	_partner = p
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE

## Мигание перед деспавном (PortalNode2.set_fade, жизнь <= 3 с).
func set_fade(f: float) -> void:
	for m in _fade_mats:
		if m:
			m.set_shader_parameter("life_fade", clampf(f, 0.15, 1.0))

## Разрешение окна = доля главного вьюпорта → aspect совпадает всегда.
func _want_size(scale: float) -> Vector2i:
	if res_override > 0.0:
		scale = res_override
	var ts := Vector2(get_viewport().size) * scale
	return Vector2i(maxi(64, int(ts.x)), maxi(48, int(ts.y)))

func _process(delta: float) -> void:
	if _runes:
		_runes.rotation.z += _spin * delta
	if _view == null:
		return
	_frame += 1
	if not _on_screen:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and player.global_position.distance_to(global_position) > MAX_DIST:
		return
	var eye := get_viewport().get_camera_3d()
	var close := false
	if eye:
		close = eye.global_position.distance_to(global_position) < CLOSE_DIST
	var want := _want_size(RES_CLOSE if close else RES_FAR)
	if _view.size != want:
		_view.size = want
	# Вблизи окно обновляется КАЖДЫЙ кадр (запрет пропусков ближе 8 м —
	# спец); вдали — раз в UPDATE_EVERY (экономика).
	_update_frame = close or _frame % UPDATE_EVERY == 0

## Перед отрисовкой кадра: камера окна = взгляд игрока, перенесённый той
## же матрицей, что и тело (спец §1) — картинка в окне пиксельно совпадает
## с реальностью после свопа, шов невидим.
func _sync_window() -> void:
	if _view == null or not _on_screen or _update_frame == false:
		return
	var eye := get_viewport().get_camera_3d()
	if eye == null or _partner == null or not is_instance_valid(_partner):
		return
	var entry := get_parent()
	if entry == null or not entry.has_method("portal_matrix"):
		return
	var m: Transform3D = entry.call("portal_matrix")
	_cam.global_transform = m * eye.global_transform
	_cam.fov = eye.fov
	_cam.keep_aspect = eye.keep_aspect
	# Клип мира за выходом без oblique near plane (Способ 3А спеца):
	# near встаёт по плоскости кольца с запасом на наклон взгляда.
	var p_local := _cam.to_local(_partner.global_position)
	var min_depth := -p_local.z
	var n := (_cam.global_basis.inverse() * _partner.global_basis.z).normalized()
	var sin_ang := sqrt(maxf(0.0, 1.0 - n.z * n.z))
	_cam.near = maxf(0.05, min_depth - RING_R * sin_ang - 0.05)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_frame = false
