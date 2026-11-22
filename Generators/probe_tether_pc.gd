extends SceneTree

## Q48 гейт шага 2 (PRP tasks/tether_swing_prp.md): интеграция PlayerController.
## Чеки (ТЗ §4/§7.1): после отрыва горизонтальная скорость в воздухе сохраняется
## (не сбрасывается до run_speed), drag реально тормозит; во время активного
## троса PlayerController отдаёт физику TetherSwingComponent; банни-хоп —
## прыжок в окне 0.14 с после приземления сохраняет ~80% импульса.

const RUN_SPEED := 5.0

var _fails := 0

func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		print("  PASS: %s %s" % [name, detail])
	else:
		_fails += 1
		print("  FAIL: %s %s" % [name, detail])

func _init() -> void:
	await physics_frame

	# 1) PlayerController компилируется.
	var pc := load("res://Logic/PlayerController.gd") as Script
	_check(pc != null and pc.can_instantiate(), "compile_player_controller")

	# Мир: пол + живой player.tscn (полный набор компонентов, как в игре).
	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	fs.shape = box
	floor.add_child(fs)
	floor.position = Vector3(0, -0.5, 0)
	root.add_child(floor)

	var ps: PackedScene = load("res://Scenes/player.tscn")
	if ps == null:
		print("[TETHER-PC] GATE: FAIL (player.tscn не загрузилась)")
		quit(1)
		return
	var player: CharacterBody3D = ps.instantiate()
	root.add_child(player)
	await physics_frame
	await physics_frame
	_check(player.is_inside_tree(), "player_spawned")

	# 2) Инерция в воздухе БЕЗ троса: сначала честно отрываемся от пола
	#    (в тик телепорта is_on_floor() ещё true с прошлого контакта —
	#    штатная запись занулила бы горизонталь, это корректное поведение),
	#    затем горизонтальный разгон 30 м/с и 1 с падения. Ожидание: drag
	#    гасит излишек exp 0.5/с → ~20 м/с (не сброс до 5, но тормозит).
	player.global_position = Vector3(0, 40, 0)
	player.velocity = Vector3(0, 15, 0)
	for t in range(3):
		await physics_frame  # move_and_slide фиксирует «в воздухе»
	player.velocity = Vector3(0, 0, 30)
	for t in range(60):
		await physics_frame
	var v_after := Vector2(player.velocity.x, player.velocity.z).length()
	_check(v_after > 15.0, "momentum_kept", "v=%.1f" % v_after)
	_check(v_after < 26.0, "drag_active", "v=%.1f" % v_after)

	# 3) Трос на живом игроке: делегация физики + импульс после отрыва.
	#    Старт y=10: кик свинга направлен вдоль взгляда (вперёд-вниз) —
	#    с малой высоты дуга чиркает пол, а на полу штатная запись законно
	#    зануляет горизонталь; тест инерции должен жить в воздухе. Старт
	#    y=25: кик идёт вдоль взгляда (вперёд-вниз) → release на пике
	#    пикирования ~y20 — падение до пола ~1.6 с, тесты успевают.
	player.global_position = Vector3(0, 25, 0)
	player.velocity = Vector3.ZERO
	await physics_frame
	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	if not skills.has("ether_tether"):
		print("[TETHER-PC] GATE: FAIL (ether_tether пропал из SkillDB)")
		quit(1)
		return
	var eff = null
	for e in skills["ether_tether"].effects:
		if e.get_script() != null \
				and e.get_script().resource_path.ends_with("TetherSwingEffect.gd"):
			eff = e
	var ctx_air := {
		"target_pos": Vector3(0, 12, -25),
		"hit_normal": Vector3.UP,
		"target_node": null,
		# Камера на высоте тела → якорь высоко, дуга свинга (низ ~11 м) не
		# достаёт до пола: release обязан происходить В ВОЗДУХЕ (на полу
		# штатная запись законно зануляет горизонталь — инерцию там не
		# проверяем).
		"camera_pos": Vector3(0, 25, 0),
		"forward_dir": Vector3(0, 0.3, -0.95).normalized(),
		"hand": "Left",
	}
	eff.apply(player, ctx_air)
	await physics_frame
	var tether = player.get_node_or_null("TetherSwing")
	_check(tether != null and tether.is_active(), "tether_active_on_player")
	for t in range(15):
		await physics_frame  # движок сам зовёт _physics_process → делегация
	var v_swing := Vector2(player.velocity.x, player.velocity.z).length()
	_check(v_swing > 6.0, "swing_drives_velocity",
		"v=%.1f (штатная запись дала бы 0 без ввода)" % v_swing)
	if not tether.is_active():
		print("[TETHER-PC] свинг сорвался раньше чеков (тело у пола?) — см. лог [TETHER]")
		quit(1)
		return
	# Повторный каст при активном тросе = срыв с бустом (погоня инерции).
	eff.apply(player, ctx_air)
	await physics_frame
	_check(tether != null and not tether.is_active(), "reapply_released")
	var v_rel := Vector2(player.velocity.x, player.velocity.z).length()
	_check(v_rel > 10.0, "post_release_momentum", "v=%.1f" % v_rel)
	for t in range(60):
		await physics_frame  # 1 с drag — импульс ещё жив
	var v_1s := Vector2(player.velocity.x, player.velocity.z).length()
	_check(v_1s > 8.0, "momentum_1s", "v=%.1f" % v_1s)

	# 4) Банни-хоп: дождаться приземления, нажать Space в окне 0.14 с.
	var landed := false
	for t in range(240):
		if player.is_on_floor():
			landed = true
			break
		await physics_frame
	_check(landed, "landed_for_bunny_hop")
	var since_land = player.get("_since_landing")
	var landed_h = player.get("_landed_hvel")
	# Инфо (не гейт): чтение состояния на физ-сигнале гонится ДО _physics_process
	# нод — значения могут быть на тик старше; окно и захват горизонтали гейтится
	# самим bunny_hop_kept (формула прыжка требует оба условия).
	print("[TETHER-PC] инфо: окно=%.3f захват=%.1f" % [
		float(since_land) if since_land != null else -1.0,
		(landed_h as Vector2).length() if landed_h != null else -1.0])
	# Реальный ввод: Space вниз через parse_input_event (как «нажал игрок»).
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await physics_frame
	await physics_frame
	_check(player.velocity.y > 0.5, "jump_fired", "vy=%.1f" % player.velocity.y)
	var v_bh := Vector2(player.velocity.x, player.velocity.z).length()
	_check(v_bh > 8.0, "bunny_hop_kept", "v=%.1f (~80%% от воздушной)" % v_bh)
	var landed_after = player.get("_landed_hvel")
	_check(landed_after != null and (landed_after as Vector2).length() > RUN_SPEED,
		"landing_hvel_captured", "v=%.1f" % ((landed_after as Vector2).length() if landed_after != null else -1.0))
	# Отпускаем Space — не оставлять застрявшую клавишу.
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_SPACE
	ev2.physical_keycode = KEY_SPACE
	ev2.pressed = false
	Input.parse_input_event(ev2)

	print("[TETHER-PC] GATE: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
