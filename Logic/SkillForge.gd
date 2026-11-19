extends Area3D

## Кузница скиллов (Q36) — зона взаимодействия у стола зачарований.
## Паттерн NPCTeleporter: подсказка «[Z] …» при игроке в зоне; Z поллится
## edge-детектом в _physics_process (вердикт-фикс NPCTeleporter: ЗАКРЫТИЕ по Z
## работает всегда независимо от фокуса контролов, фокус-гард только на
## ОТКРЫТИЕ — иначе «окно через z не закрывается»). Окно — автолоад
## /root/SkillForgeWindow, duck-typed open()/close()/is_open: окно само
## управляет мышью по ССОТ docs/ui_input_rules.md, эта зона мышь не трогает.

const WINDOW_PATH := "/root/SkillForgeWindow"
const ZONE_RADIUS := 1.6  # эфф. ~2.7 м: Area3D ребёнок стола (scale 1.7)

var _player_near := false
var _z_was := false
var _prompt: CanvasLayer = null


func _ready() -> void:
	monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = ZONE_RADIUS
	cs.shape = sph
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = _make_prompt()
	add_child(_prompt)


func _make_prompt() -> CanvasLayer:
	## Подсказка внизу слева — 1:1 паттерн NPCTeleporter._make_prompt.
	var layer := CanvasLayer.new()
	layer.name = "ForgePrompt"
	layer.layer = 5
	layer.visible = false
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_top = -74
	panel.offset_right = 280
	panel.offset_bottom = -40
	var lbl := Label.new()
	lbl.text = "[Z] — Кузница скиллов"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	layer.add_child(panel)
	return layer


func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player":
		_player_near = true
		_prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.name == "Player":
		_player_near = false
		_prompt.visible = false
		# Уход от стола с открытым окном — авто-закрытие (паттерн NPCTeleporter).
		var win = get_node_or_null(WINDOW_PATH)
		if win != null and win.is_open:
			win.close()


func _physics_process(_delta: float) -> void:
	var z_pressed := Input.is_key_pressed(KEY_Z)
	if z_pressed and not _z_was:
		var win = get_node_or_null(WINDOW_PATH)
		if win != null and win.is_open:
			win.close()  # Z закрывает ВСЕГДА, даже с фокусом на контролах
		elif _player_near and get_viewport().gui_get_focus_owner() == null:
			if win != null:
				win.open()
			else:
				print("SkillForge: окно не найдено (", WINDOW_PATH,
					") — автолоад SkillForgeWindow не добавлен?")
	_z_was = z_pressed
