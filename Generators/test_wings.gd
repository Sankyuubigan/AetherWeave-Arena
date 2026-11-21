extends SceneTree
## Гейт Q20 v9 (крылья-скилл): статика SkillDB + рантайм на player.tscn
## (активация, wings_fly, speed_mult, fov, оверлей, ПЕРЬЕВОЙ веер 8 перьев,
## трейл концевого пера, deactivate). + ФИЗИКА ПОЛЁТА: удержание Space в
## воздухе = тяга вверх (WINGS_LIFT), отпускание = глайд (WINGS_GLIDE),
## снятие крыльев = свободное падение. Паттерн test_energy_blade.
## Q45/Q46 (юзер 20.11.26): корень крыльев ближе к спине (0,1.45,-0.12);
## при активации скорость БАЗОВАЯ — буст 1.6 + FOV + оверлей только после
## 2.5 с НЕПРЕРЫВНОГО бега (KEY_W), остановка = сброс.

var _fails := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		print("[OK] " + label)
	else:
		_fails += 1
		printerr("[FAIL] " + label)

func _init() -> void:
	# Вотчдог: корутина-смертник без quit = зомби Godot (урок Q10/Q19).
	_watchdog()
	await process_frame
	await process_frame
	var SkillDB = load("res://Logic/Skills/SkillDB.gd")
	var skills = SkillDB.get_skills()
	_ck(skills.has("wings"), "SkillDB: скилл wings есть")
	if skills.has("wings"):
		var w = skills["wings"]
		_ck(w.price == 2, "wings price == 2")
		_ck(w.cast_anim == "", "wings cast_anim пуст (жест в эффекте)")
		_ck(w.effects.size() == 1, "wings effects == 1")
		_ck(w.effects[0] != null, "wings effect создан")

	var player_scene = load("res://Scenes/player.tscn")
	var player = player_scene.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame

	var anim_comp = player.get_node_or_null("PlayerAnimationComponent")
	_ck(anim_comp != null and anim_comp.has_cast_anim("Cast_Enter"),
		"Cast_Enter_UB в аним-либе игрока")

	var effect = load("res://Logic/Skills/SpawnWingsEffect.gd").new()
	effect.apply(player, {})
	await process_frame
	var wings = player.get_node_or_null("Wings")
	_ck(wings != null, "Wings-компонент создан на игроке")
	if wings == null:
		quit(1); return
	_ck(wings.is_active(), "wings is_active после activate")
	_ck(wings.visible, "wings видимы")
	_ck(player.get("speed_mult") == 1.0, "Q46: при активации скорость БАЗОВАЯ (1.0)")
	_ck(player.get("wings_fly") == true, "wings_fly == true (полёт разрешён)")

	var cam = player.get_node_or_null("SpringArm3D/Camera3D")
	_ck(cam != null, "камера игрока найдена")
	await create_timer(0.5).timeout
	_ck(cam and absf(cam.fov - 75.0) < 1.0,
		"Q46: FOV не бустится при активации (%.1f)" % (cam.fov if cam else -1.0))

	# WingsRoot на GraphicsWrapper (не кости — FPS-зависимая лотерея
	# бон-базиса, пробы 02:41-02:45); позиция уровня лопаток.
	var gw = player.get_node_or_null("GraphicsWrapper")
	_ck(gw != null, "GraphicsWrapper найден")
	var wroot = gw.get_node_or_null("WingsRoot") if gw else null
	_ck(wroot != null and wroot.get_child_count() >= 3,
		"WingsRoot: 2 пивота крыльев + свет (%d детей)"
			% (wroot.get_child_count() if wroot else -1))
	_ck(wroot != null and wroot.position.is_equal_approx(Vector3(0, 1.45, -0.12)),
		"Q45: WingsRoot прижат к спине (0,1.45,-0.12)")
	var ovs = wings.get_children().filter(func(c): return c is CanvasLayer)
	_ck(ovs.size() == 1, "SpeedLinesOverlay (CanvasLayer) на игроке")

	# v9 перьевой веер: 8 перьев на крыло, 16 MeshInstance3D всего,
	# 256 трис (8 сегментов × 2 триса на перо). Перья — ВНУКИ WingsRoot.
	var feathers := []
	if wroot:
		_all_meshes(wroot, feathers)
	var feather_meshes = feathers.filter(func(n): return n is MeshInstance3D)
	_ck(feather_meshes.size() == 16, "16 мешей перьев (8 на крыло): %d"
		% feather_meshes.size())
	var tri_count := 0
	for mi in feather_meshes:
		if mi.mesh:
			var arrs = mi.mesh.surface_get_arrays(0)
			var idx = arrs[Mesh.ARRAY_INDEX]
			if idx != null:
				tri_count += idx.size() / 3
			else:
				tri_count += arrs[Mesh.ARRAY_VERTEX].size() / 3
	_ck(tri_count >= 240 and tri_count <= 280,
		"трисы перьевого веера 240-280 (%d)" % tri_count)

	# FLAP-анимация: перья вращаются на своих пивотах (фаза с запаздыванием).
	await create_timer(0.45).timeout
	var flap_ok := false
	for fp in feathers:
		if not is_instance_valid(fp):
			continue  # transient-искры _burst успевают освободиться (таймер 0.8с)
		if fp is Node3D and fp.get_parent() != wroot:
			if absf(fp.rotation.z) > 0.01:
				flap_ok = true
				break
	_ck(flap_ok, "FLAP: перья анимируются на пивотах")

	# Трейл концевого пера: перо-пивот → MeshInstance → Tip → GPUParticles3D.
	var trail: GPUParticles3D = null
	for fp in feathers:
		if not is_instance_valid(fp):
			continue  # transient-искры _burst успевают освободиться (таймер 0.8с)
		if fp is Node3D and fp.get_parent() != wroot and fp.get_child_count() > 0:
			var mi = fp.get_child(0)
			if mi is MeshInstance3D and mi.get_child_count() > 0:
				var tip = mi.get_child(0)
				for ch in tip.get_children():
					if ch is GPUParticles3D:
						trail = ch
	_ck(trail != null and trail.emitting, "трейл концевого пера emitит")

	# --- ФИЗИКА ПОЛЁТА (Q20 v2): пол 60×0.5×60, верх y=0 (60 — чтобы 3 с бега
	# Q46 не свалили игрока с края) ---
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 0.5, 60)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.25, 0)
	root.add_child(floor_body)
	await physics_frame

	# Тяга: игрок в воздухе, Space зажат → взлёт (v → WINGS_LIFT 4.2).
	player.global_position = Vector3(0, 3.0, 0)
	await physics_frame
	await physics_frame
	_press_space(true)
	await create_timer(0.6).timeout
	var vy_up: float = player.velocity.y
	_ck(vy_up > 3.0, "тяга: Space в воздухе → взлёт (vy=%.2f)" % vy_up)
	_ck(player.global_position.y > 3.2, "высота растёт (y=%.2f)"
		% player.global_position.y)

	# Глайд: Space отпущен, крылья активны → падение зажато на WINGS_GLIDE.
	_press_space(false)
	await create_timer(1.2).timeout
	var vy_glide: float = player.velocity.y
	_ck(vy_glide <= 0.0 and vy_glide >= -2.5,
		"глайд: падение зажато -2.0 (vy=%.2f)" % vy_glide)

	# --- Q46 РАМП СПРИНТА: эффект и буст НЕ сразу, а после 2.5 с непрерывного
	# бега; остановка = сброс. Бег симулируем зажатием KEY_W (сырая клавиатура
	# PlayerController — паттерн probe_q23_start). ---
	player.global_position = Vector3(0, 0.6, 0)
	player.velocity = Vector3.ZERO
	_press_w(true)
	await create_timer(0.5).timeout
	_ck(player.get("speed_mult") == 1.0,
		"Q46: 0.5с бега — скорость ещё базовая (%.2f)" % player.get("speed_mult"))
	_ck(cam and cam.fov < 80.0, "Q46: 0.5с бега — FOV ещё базовый")
	await create_timer(2.5).timeout  # суммарно ~3.0 с зажатого W
	_ck(player.get("speed_mult") == 1.6,
		"Q46: ~3с непрерывного бега — буст 1.6 (%.2f)" % player.get("speed_mult"))
	_ck(cam and cam.fov > 82.0, "Q46: буст — FOV 88 (%.1f)" % cam.fov)
	_press_w(false)
	await create_timer(0.4).timeout
	_ck(player.get("speed_mult") == 1.0, "Q46: остановка — буст сброшен")
	_ck(cam and absf(cam.fov - 75.0) < 2.5, "Q46: остановка — FOV назад (%.1f)" % cam.fov)

	# Свободное падение: крылья сняты → обычная гравитация. Подъём на 12 м —
	# за 0.8с окна замера глайд-высота уже съедена, игрок у пола (vy=0 на земле).
	player.global_position = Vector3(0, 12.0, 0)
	wings.call("deactivate")
	await create_timer(0.8).timeout
	_ck(not wings.is_active(), "deactivate снял активность")
	_ck(player.get("speed_mult") == 1.0, "speed_mult вернулся к 1.0")
	_ck(player.get("wings_fly") == false, "wings_fly == false (полёт закрыт)")
	var vy_fall: float = player.velocity.y
	_ck(vy_fall < -4.0, "свободное падение после deactivate (vy=%.2f)" % vy_fall)
	_ck(not wings.visible, "dissolve скрыл крылья")
	_ck(cam and absf(cam.fov - 75.0) < 1.0, "fov вернулся к 75 (%.1f)" % cam.fov)

	print("WINGS GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

## Зажатие Space: parse_input_event (headless-симуляция клавиатуры —
## PlayerController читает Input.is_key_pressed(KEY_SPACE)).
func _press_space(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

## Зажатие W для рамп-секции Q46 (та же headless-симуляция).
func _press_w(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _all_meshes(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_all_meshes(c, out)

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] TIMEOUT 30с — тест завис")
	quit(1)
