extends SceneTree
## Гейт Q20 (крылья-скилл): статика SkillDB/аним-либы + рантайм на player.tscn
## (активация, speed_mult, fov, оверлей, трейлы, deactivate). Паттерн
## test_energy_blade: моки через root.add_child (current_scene == null в -s).

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
	_ck(player.get("speed_mult") == 1.35, "speed_mult == 1.35")

	var cam = player.get_node_or_null("SpringArm3D/Camera3D")
	_ck(cam != null, "камера игрока найдена")
	await create_timer(0.5).timeout
	_ck(cam and cam.fov > 82.0, "fov бустится (текущий %.1f)" % cam.fov)

	# v8: WingsRoot на GraphicsWrapper (не кости — FPS-зависимая лотерея
	# бон-базиса, пробы 02:41-02:45); чистый yaw, позиция уровня лопаток.
	var gw = player.get_node_or_null("GraphicsWrapper")
	_ck(gw != null, "GraphicsWrapper найден")
	var wroot = gw.get_node_or_null("WingsRoot") if gw else null
	_ck(wroot != null and wroot.get_child_count() >= 3,
		"WingsRoot на GraphicsWrapper: крылья+свет+искры (%d детей)"
			% (wroot.get_child_count() if wroot else -1))
	_ck(wroot != null and wroot.position.is_equal_approx(Vector3(0, 1.95, -0.18)),
		"WingsRoot на уровне лопаток (0,1.95,-0.18)")
	var ovs = wings.get_children().filter(func(c): return c is CanvasLayer)
	_ck(ovs.size() == 1, "SpeedLinesOverlay (CanvasLayer) на игроке")

	# FLAP-анимация крыльев: фаза крутится, поворот ненулевой на пике.
	await create_timer(0.45).timeout
	var wl = wroot.get_children().filter(func(c): return c is MeshInstance3D) if wroot else []
	if wl.size() != 2:
		print("WINGS GATE: FAIL (мешей крыльев %d)" % wl.size())
		quit(1)
		return
	_ck(wl.size() == 2, "2 меша крыльев")
	if wl.size() == 2:
		var tri_count := 0
		for mi in wl:
			if mi.mesh:
				# ArrayMesh 4.8: get_face_count нет, меш не-индексированный —
				# трисы = вершины / 3.
				var arrs = mi.mesh.surface_get_arrays(0)
				var idx = arrs[Mesh.ARRAY_INDEX]
				if idx != null:
					tri_count += idx.size() / 3
				else:
					tri_count += arrs[Mesh.ARRAY_VERTEX].size() / 3
		_ck(tri_count >= 200 and tri_count <= 500,
			"трисы крыльев в норме 200-500 (%d)" % tri_count)
		var rotated: bool = abs(wl[0].rotation.z) > 0.01 or abs(wl[0].rotation.y) > 0.01
		_ck(rotated, "FLAP: крылья анимируются")

	# Трейлы за кончиками: GPUParticles3D — внук крыла (Tip-нода между ними).
	var tip = wl[0].get_child(0) if wl[0].get_child_count() > 0 else null
	var trails = []
	if tip:
		trails = tip.get_children().filter(func(c): return c is GPUParticles3D)
	_ck(trails.size() == 1 and trails[0].emitting, "трейл левого крыла emitит")

	# Деактивация: speed_mult и fov возвращаются, крылья гаснут.
	wings.call("deactivate")
	await create_timer(0.8).timeout
	_ck(not wings.is_active(), "deactivate снял активность")
	_ck(player.get("speed_mult") == 1.0, "speed_mult вернулся к 1.0")
	_ck(not wings.visible, "dissolve скрыл крылья")
	_ck(cam and absf(cam.fov - 75.0) < 1.0, "fov вернулся к 75 (%.1f)" % cam.fov)

	print("WINGS GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

func _watchdog() -> void:
	await create_timer(20.0).timeout
	print("[WDT] TIMEOUT 20с — тест завис")
	quit(1)

func _find_skeleton(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
