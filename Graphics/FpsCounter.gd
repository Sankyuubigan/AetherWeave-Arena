extends CanvasLayer

## FPS-индикатор в углу экрана (17.11.26, очередь юзера).
## Автозагрузка — живёт на всех картах поверх HUD. F3 — скрыть/показать.

var label: Label
var _accum := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.text = "FPS —"
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		label.text = "FPS %d" % Engine.get_frames_per_second()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F3:
		visible = not visible
