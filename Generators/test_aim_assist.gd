extends SceneTree

## Тест QUEUE Q29: aim assist — скан aim_targets (угловая толерантность + LOS),
## get_marked по типам, assist-first в SpellCasterComponent._aim_context,
## SettingsMenu.aim_assist_deg + ActionBar.key_label_for_skill. Гейт: GATE ALL PASS.

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _make_target(script_path: String, pos: Vector3, friendly: bool) -> StaticBody3D:
	var body: StaticBody3D = load(script_path).new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	body.is_friendly = friendly
	return body

func _run() -> void:
	var assist_s = load("res://Logic/AimAssistComponent.gd")
	var marker_s = load("res://Graphics/AimMarker.gd")
	var settings_s = load("res://Graphics/SettingsMenu.gd")
	_check("AimAssistComponent компилируется", assist_s != null)
	_check("AimMarker компилируется", marker_s != null)
	var sm_props := []
	for p in settings_s.get_script_property_list():
		sm_props.append(p.name)
	_check("SettingsMenu.aim_assist_deg есть", "aim_assist_deg" in sm_props)
	var sm_meths := []
	for m in settings_s.get_script_method_list():
		sm_meths.append(m.name)
	_check("SettingsMenu _save_aim/_load_aim есть", "_save_aim" in sm_meths and "_load_aim" in sm_meths)
	var bar_s = load("res://Graphics/ActionBar.gd")
	var bar_meths := []
	for m in bar_s.get_script_method_list():
		bar_meths.append(m.name)
	_check("ActionBar.key_label_for_skill есть", "key_label_for_skill" in bar_meths)

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene # ТОЛЬКО после add_child (грабля 4.8)

	var floor_body := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 0.5, 40)
	fshape.shape = fbox
	floor_body.add_child(fshape)
	floor_body.position = Vector3(0, -0.25, 0)
	scene.add_child(floor_body)

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1, 0)
	scene.add_child(player)
	await create_timer(0.5).timeout

	var assist = player.get_node_or_null("AimAssist")
	_check("AimAssist на игроке", assist != null)
	var cam = player.get_node_or_null("SpringArm3D/Camera3D")
	_check("камера найдена", cam != null)
	if assist == null or cam == null:
		quit(1)
		return
	var cam_pos: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var right: Vector3 = cam.global_transform.basis.x

	# Цели вдоль оси прицела: точка прицеливания ассиста = origin + 1м вверх.
	var aim10: Vector3 = cam_pos + fwd * 10.0
	var enemy1 = _make_target("res://Logic/HealthComponent.gd", aim10 - Vector3(0, 1, 0), false)
	var friend = _make_target("res://Logic/HealthComponent.gd", aim10 + right * -0.3 - Vector3(0, 1, 0), true)
	var enemy2 = _make_target("res://Logic/HealthComponent.gd", aim10 + right * 3.0 - Vector3(0, 1, 0), false)
	var e3_center: Vector3 = cam_pos + fwd * 12.0 + right * 0.5
	var enemy3 = _make_target("res://Logic/HealthComponent.gd", e3_center - Vector3(0, 1, 0), false)
	scene.add_child(enemy1)
	scene.add_child(friend)
	scene.add_child(enemy2)
	scene.add_child(enemy3)
	# enemy3 в конусе по углу (~2.4° < 4°), но за узкой стеной — LOS-чек.
	var wall := StaticBody3D.new()
	var wshape := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.4, 4, 0.6)
	wshape.shape = wbox
	wall.add_child(wshape)
	wall.global_position = (cam_pos + e3_center) * 0.5
	scene.add_child(wall)

	await create_timer(0.6).timeout

	_check("enemy1 в центре помечен (enemy)", assist.get_marked("enemy") == enemy1)
	_check("friend в конусе помечен (friendly)", assist.get_marked("friendly") == friend)
	_check("enemy2 вне конуса (3м вбок) не помечен", assist.get_marked("enemy") != enemy2)
	_check("enemy3 за стеной не помечен (LOS)", assist.get_marked("enemy") != enemy3)
	_check("_has_los ложно сквозь стену", assist.call("_has_los", cam_pos, e3_center, enemy3) == false)
	_check("_has_los истинно к enemy1", assist.call("_has_los", cam_pos, aim10, enemy1) == true)

	# Assist-first в касте: requires_target-скиллы получают ПОМЕЧЕННУЮ цель.
	var sc = player.get_node_or_null("SpellCasterComponent")
	_check("SpellCasterComponent найден", sc != null)
	var ctx_ball: Dictionary = sc.call("_aim_context", player, "ball_lightning", SkillDB.get_skills()["ball_lightning"], "Left")
	_check("молния кастуется в помеченную цель", not ctx_ball.is_empty() and ctx_ball.get("target_node") == enemy1)
	var ctx_heart: Dictionary = sc.call("_aim_context", player, "heart_heal", SkillDB.get_skills()["heart_heal"], "Left")
	_check("сердечко кастуется в помеченную friendly", not ctx_heart.is_empty() and ctx_heart.get("target_node") == friend)

	var bar = player.get_node_or_null("ActionBar")
	_check("key_label_for_skill не падает, String", typeof(bar.call("key_label_for_skill", "ball_lightning")) == TYPE_STRING)
	_check("CanvasLayer маркеров: 2 Control", assist.get_node_or_null("AimMarkers") != null and assist.get_node("AimMarkers").get_child_count() == 2)

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
