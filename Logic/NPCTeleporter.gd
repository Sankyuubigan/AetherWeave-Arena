extends StaticBody3D
## Непись-телепортер (19.11.26, верб. юзера): капсула у края карты; подходишь —
## значок «[Z] Телепорт» слева снизу экрана; по Z — окно телепорта со списком
## ТРЁХ карт (тот же функционал, что был у TeleportMenu по клавише I). Стоит
## на всех картах: MainArena, ProceduralArena, HellArena.

const MAPS := [
	{"title": "Главная арена", "path": "res://Scenes/MainArena.tscn"},
	{"title": "Процедурная арена", "path": "res://Scenes/ProceduralArena.tscn"},
	{"title": "Ад", "path": "res://Scenes/HellArena.tscn"},
]

var _prompt: CanvasLayer
var _dialog: CanvasLayer
var _dialog_open := false
var _player_near := false
var _changing := false
var _z_was := false

func _ready():
	# Тело: капсула-«монолит» с бирюзовым свечением — телепортер читается издалека.
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.35, 0.40)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.6, 0.7)
	mat.emission_energy_multiplier = 1.2
	cap.material = mat
	mi.mesh = cap
	mi.position.y = 1.0
	add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 2.0
	cs.shape = shape
	cs.position.y = 1.0
	add_child(cs)

	var area := Area3D.new()
	area.name = "Interact"
	var acs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.5
	acs.shape = sph
	acs.position.y = 1.0
	area.add_child(acs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	_prompt = _make_prompt()
	add_child(_prompt)
	_dialog = _make_dialog()
	add_child(_dialog)

func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_near = true

func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_near = false

func _physics_process(_delta: float) -> void:
	# Значок виден только рядом и при закрытом окне.
	_prompt.visible = _player_near and not _dialog_open
	if _changing:
		return
	# Ушли от непися с открытым окном — закрываем (мышь обратно в захват).
	if _dialog_open and not _player_near:
		_close_dialog()
		return
	# Z — гранцевый опрос (удержание не мигает открыто/закрыто). ЗАКРЫВАЕТ окно
	# тоже (фидбэк юзера 19.11.26: «окно через z не закрывается» — старое
	# условие «not _dialog_open» не пускало Z до закрытия окна). Фокус-гард
	# только на открытие: после клика по кнопке фокус у неё, а закрывать Z
	# должен всегда.
	var z_pressed := Input.is_key_pressed(KEY_Z)
	if z_pressed and not _z_was:
		if _dialog_open:
			_close_dialog()
		elif _player_near and get_viewport().gui_get_focus_owner() == null:
			_open_dialog()
	_z_was = z_pressed

## Значок «[Z] Телепорт» — слева снизу экрана (верб. юзера).
func _make_prompt() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Prompt"
	layer.layer = 5
	layer.visible = false
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_top = -74
	panel.offset_right = 240
	panel.offset_bottom = -40
	var lbl := Label.new()
	lbl.text = "[Z] Телепорт"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	layer.add_child(panel)
	return layer

## Окно телепорта: список ТРЁХ карт (паттерн TeleportMenu: текущая карта — no-op).
func _make_dialog() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Dialog"
	layer.layer = 20
	layer.visible = false
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(320, 240)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -160
	panel.offset_top = -120
	panel.offset_right = 160
	panel.offset_bottom = 120
	layer.add_child(panel)

	var title := Label.new()
	title.text = "Телепорт"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 14
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "Закрыть — Z"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.position.y = 34
	hint.add_theme_font_size_override("font_size", 12)
	panel.add_child(hint)

	for i in MAPS.size():
		var btn := Button.new()
		btn.text = MAPS[i]["title"]
		btn.position = Vector2(60, 70 + i * 48)
		btn.custom_minimum_size = Vector2(200, 40)
		btn.pressed.connect(_go.bind(MAPS[i]["path"]))
		panel.add_child(btn)
	return layer

func _open_dialog() -> void:
	_dialog_open = true
	_dialog.visible = true
	# Группа-флаг для гварда капчура мыши в PlayerController (Q24/Q27): клик
	# мимо окна при открытом диалоге не должен уходить в захват мира.
	add_to_group("npc_dialog_open")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_dialog() -> void:
	_dialog_open = false
	_dialog.visible = false
	remove_from_group("npc_dialog_open")
	# МЫШЬ ССОТ v2 (docs/ui_input_rules.md): закрытие UI возвращает мышь в
	# игру (вердикт юзера 19.11.26: ушли от непися / Z / телепорт — курсор
	# сразу обратно в захват, без «кликни в мир»).
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Смена сцены с защитой от петли регенераций (паттерн TeleportMenu 17.11.26:
## телепорт на текущую карту — no-op; дебаунс до факта смены сцены).
func _go(path: String) -> void:
	if _changing:
		return
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path == path:
		_close_dialog()
		return
	_changing = true
	_close_dialog()
	get_tree().change_scene_to_file(path)
