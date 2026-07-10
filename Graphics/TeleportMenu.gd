extends CanvasLayer

var panel: Panel
var is_open: bool = false

func _ready():
	name = "TeleportMenu"
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

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
	btn_main.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/MainArena.tscn"))
	panel.add_child(btn_main)

	var btn_proc = Button.new()
	btn_proc.text = "Procedural Arena"
	btn_proc.position = Vector2(60, 120)
	btn_proc.custom_minimum_size = Vector2(200, 40)
	btn_proc.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/ProceduralArena.tscn"))
	panel.add_child(btn_proc)

	panel.hide()

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		is_open = not is_open
		if is_open:
			panel.show()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			panel.hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
