extends Node3D
## Визуал портала (Q21): вертикальное кольцо «лицом» в +Z локала портала —
## мембрана-вихрь (шейдер), тор-рамка, светящиеся руны-бусины по кольцу,
## OmniLight. В LOW-режиме графики вихрь непрозрачный (QUEUE-техчасть).

const VORTEX := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(0.35, 0.55, 1.0, 1.0);
uniform float seed_off = 0.0;
uniform float opaque_mode = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv) * 2.0;
	if (r > 1.0) { discard; }
	float ang = atan(uv.y, uv.x);
	float spin = TIME * 1.7 + seed_off;
	float bands = sin(ang * 3.0 + r * 10.0 - spin) * 0.5 + 0.5;
	float rim = smoothstep(0.3, 1.0, r);
	float depth = smoothstep(1.0, 0.55, r);
	float a = mix(0.12, 0.95, bands * rim + depth * 0.55);
	vec3 col = base_color.rgb * (0.55 + 1.25 * bands) + vec3(0.9) * pow(rim, 3.0);
	ALBEDO = col;
	ALPHA = mix(clamp(a, 0.0, 1.0), 1.0, opaque_mode);
}
"""

var _runes: Node3D
var _spin := 0.25

## color — цвет пары (вход синий / выход оранжевый), seed_off — фаза вихря,
## чтобы два кольца не крутились синхронно.
func setup(color: Color, seed_off: float) -> void:
	var low := false
	var gq = get_node_or_null("/root/GraphicsQuality")
	if gq and int(gq.get("quality")) == 0:
		low = true

	# Мембрана-вихрь: QuadMesh (XY, нормаль +Z) с шейдером-кругом.
	var sm := Shader.new()
	sm.code = VORTEX
	var mat := ShaderMaterial.new()
	mat.shader = sm
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("seed_off", seed_off)
	mat.set_shader_parameter("opaque_mode", 1.0 if low else 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.3, 2.3)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position = Vector3(0, 0, 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

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
	add_child(tmi)

	# Руны-бусины по кольцу (медленное вращение по нормали).
	_runes = Node3D.new()
	add_child(_runes)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.75, 0.85, 1.0, 1.0) * 1.4
	bm.no_shadow = true
	for i in 12:
		var rq := QuadMesh.new()
		rq.size = Vector2(0.09, 0.09)
		rq.material = bm
		var rb := MeshInstance3D.new()
		rb.mesh = rq
		var ang := TAU * float(i) / 12.0
		rb.position = Vector3(cos(ang) * 1.15, sin(ang) * 1.15, 0.06)
		_runes.add_child(rb)

	# Свет портала.
	var lt := OmniLight3D.new()
	lt.light_color = color
	lt.omni_range = 4.5
	lt.light_energy = 1.2
	lt.position = Vector3(0, 0, 0.6)
	add_child(lt)

func _process(delta: float) -> void:
	if _runes:
		_runes.rotation.z += _spin * delta
