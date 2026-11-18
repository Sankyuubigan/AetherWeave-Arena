extends CanvasLayer

var panel: Panel
var is_open: bool = false
var _changing: bool = false
var _target: String = ""

func _ready():
	name = "TeleportMenu"
	layer = 20
	process_mode = PROCESS_MODE_ALWAYS

	panel = Panel.new()
	panel.custom_minimum_size = Vector2(320, 220)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -160
	panel.offset_top = -110
	panel.offset_right = 160
	panel.offset_bottom = 110

	add_child(panel)

	var title = Label.new()
	title.text = "Телепорт"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 15
	panel.add_child(title)

	var hint = Label.new()
	hint.text = "Закрыть — I"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.position.y = 35
	hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(hint)

	var btn_main = Button.new()
	btn_main.text = "Main Arena"
	btn_main.position = Vector2(60, 70)
	btn_main.custom_minimum_size = Vector2(200, 40)
	btn_main.pressed.connect(func(): _go("res://Scenes/MainArena.tscn"))
	panel.add_child(btn_main)

	var btn_proc = Button.new()
	btn_proc.text = "Procedural Arena"
	btn_proc.position = Vector2(60, 120)
	btn_proc.custom_minimum_size = Vector2(200, 40)
	btn_proc.pressed.connect(func(): _go("res://Scenes/ProceduralArena.tscn"))
	panel.add_child(btn_proc)

	# Ад (19.11.26): список телепортов = 3 карты, как у непися-телепортера.
	var btn_hell = Button.new()
	btn_hell.text = "Ад"
	btn_hell.position = Vector2(60, 170)
	btn_hell.custom_minimum_size = Vector2(200, 40)
	btn_hell.pressed.connect(func(): _go("res://Scenes/HellArena.tscn"))
	panel.add_child(btn_hell)

	panel.hide()

## Телепорт с защитой от петли регенераций (17.11.26, зонд поймал 6 рестартов
## генерации подряд: фриз генерации → юзер долбил кнопку → каждая клика
## рестартила генерацию заново → «телепорт в центр» × N):
## (1) телепорт на ТЕКУЩУЮ карту — no-op (перезагрузка = реген + фриз + спавн в центре);
## (2) дебаунс до факта смены сцены — повторные клики посреди генерации не рестартят её.
func _go(path: String) -> void:
	if _changing:
		return
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path == path:
		_close()
		return
	_changing = true
	_target = path
	_close()
	get_tree().change_scene_to_file(path)

func _close() -> void:
	is_open = false
	panel.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta: float) -> void:
	if _changing and get_tree().current_scene \
			and get_tree().current_scene.scene_file_path == _target:
		_changing = false

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		is_open = not is_open
		if is_open:
			panel.show()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			panel.hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
