extends SceneTree
## Рендер-проба Шага 7 (Q16): купол + дуги Потока в скрытом окне (не headless:
## null viewport, кадр не снимается). PNG: _tmp_probe/bard_check_a.png (T0
## бирюза) / bard_check_b.png (T3 золото + рябь). Запуск: ps1-обёртка.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	root.add_child(sun)
	# Пол — кромка DEPTH-пересечения купола светится на нём.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.5, 0.45)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	# Стаб игрока + РЕАЛЬНЫЕ компоненты (те же, что у игрока в _ready).
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar speed_mult: float = 1.0\n"
	stub.reload()
	var pl := Node3D.new()
	pl.set_script(stub)
	root.add_child(pl)
	var flow = load("res://Logic/BardFlowComponent.gd").new()
	flow.name = "BardFlowComponent"
	pl.add_child(flow)
	var dome = load("res://Graphics/AcousticBarrierVFX.gd").new()
	dome.name = "AcousticBarrierVFX"
	pl.add_child(dome)
	var ui = load("res://Graphics/BardFlowUI.gd").new()
	ui.name = "BardFlowUI"
	pl.add_child(ui)
	# Ритм: conductor + ноты в судье — UI рисует летящие ноты на дорожках.
	var cond = root.get_node_or_null("RhythmConductor")
	var judge = root.get_node_or_null("RhythmJudge")
	if cond != null and not cond.is_running:
		cond.start(120.0)
	if judge != null:
		judge.conductor = cond
		judge.reset()
		var t0: float = cond.song_time if cond != null else 0.0
		for i in 8:
			judge.register_note("harmony", t0 + 0.25 * (i + 1))
		judge.register_note("chord", t0 + 1.5)
		judge.register_note("chord", t0 + 2.0)
	# Симуляция активного Потока (как при stance_entered, без стойки).
	flow.is_flowing = true
	flow.fuel = 9.0
	flow.barrier = 76
	flow.tier = 0
	flow.fuel_changed.emit(flow.fuel)
	flow.barrier_changed.emit(flow.barrier)
	flow.flow_tier_changed.emit(flow.tier)
	# Камера — 3rd person как в игре; прицел = центр экрана.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 2.4, 5.5)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.current = true
	for i in 30:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/bard_check_a.png")
	print("RB: кадр A (T0 бирюза, купол+дуги+ноты)")
	# Кадр B: Tier 3 (золото + орбита нот) + рябь от удара в купол.
	flow.tier = 3
	flow.flow_tier_changed.emit(3)
	dome.notify_impact(Vector3(0.8, 1.9, 0.0))
	for i in 8:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/bard_check_b.png")
	print("RB: кадр B (T3 золото, орбита нот, рябь)")
	quit(0)
