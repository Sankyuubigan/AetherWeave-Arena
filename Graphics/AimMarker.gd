extends Control
## Анимированная отметка цели (QUEUE Q29): кольцо с вращающимися засечками,
## ромб-прицел, текст клавиши под ним. Ставит AimAssistComponent.

const SIZE := Vector2(96, 96)

var color: Color = Color(0.35, 0.9, 1.0)
var key_text: String = ""
var screen_pos: Vector2 = Vector2.ZERO
var active: bool = false

var _time := 0.0
var _alpha := 0.0
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	visible = false
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.position = Vector2(0, 78)
	_label.size = Vector2(SIZE.x, 18)
	add_child(_label)

func _process(delta: float) -> void:
	_time += delta
	_alpha = move_toward(_alpha, 1.0 if active else 0.0, delta * 6.0)
	visible = _alpha > 0.01
	modulate.a = _alpha
	if visible:
		position = screen_pos - SIZE * 0.5
		if _label and _label.text != key_text:
			_label.text = key_text
		queue_redraw()

func _draw() -> void:
	var c := SIZE * 0.5
	var pulse := 1.0 + 0.08 * sin(_time * 6.0)
	var r := 24.0 * pulse
	draw_arc(c, r, 0.0, TAU, 40, color, 2.5, true)
	for k in 4:
		var a0 := _time * 2.4 + float(k) * TAU / 4.0
		draw_arc(c, r + 6.0, a0, a0 + 0.9, 10, Color(color, 0.85), 3.0, true)
	var d := 8.0 * pulse
	var pts := PackedVector2Array([
		c + Vector2(0, -d), c + Vector2(d, 0),
		c + Vector2(0, d), c + Vector2(-d, 0),
	])
	pts.append(c + Vector2(0, -d))
	draw_polyline(pts, color, 2.0, true)
