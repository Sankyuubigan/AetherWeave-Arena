extends CanvasLayer
## SpeedLinesOverlay (Q20, 19.11.26): полноэкранный пост-эффект ускорения
## «как в Minecraft» — линии скорости от центра + хроматическая аберрация
## на внешних 15-20% кадра. НЕ radial blur (вердикт спеца: 0.1-0.2 мс/кадр).
## Степень эффекта задаёт WingsComponent через set_strength() (tween).
## Рендерится только при strength > 0.01 — ноль стоимости в покое.

const SHADER_CODE := "
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);
	float r = length(centered) * 2.0;
	float ca = smoothstep(0.75, 1.05, r);
	vec2 dir = centered / max(r * 0.5, 1e-4);
	float ca_off = ca * 0.007 * strength;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + dir * ca_off).r;
	col.g = texture(screen_tex, SCREEN_UV).g;
	col.b = texture(screen_tex, SCREEN_UV - dir * ca_off).b;
	float ang = atan(centered.y, centered.x);
	float seg = floor((ang / 6.28318 + 0.5) * 36.0);
	float seed = fract(sin(seg * 91.17) * 43758.5453);
	float gate = step(0.68, seed);
	float radial = fract(r * 2.6 - TIME * (1.2 + strength * 2.2));
	float streak = smoothstep(0.62, 0.95, radial) * gate;
	streak *= smoothstep(0.30, 0.85, r) * (0.75 + 0.25 * sin(TIME * 40.0 + seg));
	col += vec3(0.80, 0.90, 1.0) * streak * 0.30 * strength;
	COLOR = vec4(col, 1.0);
}
"

var _mat: ShaderMaterial
var _strength := 0.0

func _ready() -> void:
	layer = 45
	visible = false
	var rect := ColorRect.new()
	rect.name = "Fx"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	rect.material = _mat
	add_child(rect)

## Степень эффекта 0..1 (крутит uniform + экономия: скрыт при нуле).
func set_strength(s: float) -> void:
	_strength = clampf(s, 0.0, 1.0)
	visible = _strength > 0.01
	if _mat:
		_mat.set_shader_parameter("strength", _strength)

func get_strength() -> float:
	return _strength
