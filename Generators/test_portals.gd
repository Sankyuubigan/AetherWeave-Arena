extends SceneTree
## Гейт Q21 (порталы-скилл): SkillDB-поля, спавн пары (A за спиной, B в
## точке прицела), телепорт тела A→B, анти-пинг-понг (кулдаун), возврат B→A,
## перенос снаряда. current_scene назначаем (пол-мир): в -s он null, и без
## этого эффект кладёт pair на кастера — Area-внук CharacterBody не мониторится.

var _fails := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		print("[OK] " + label)
	else:
		_fails += 1
		printerr("[FAIL] " + label)

func _init() -> void:
	_watchdog()
	await process_frame
	await process_frame

	# --- SkillDB ---
	var SkillDB = load("res://Logic/Skills/SkillDB.gd")
	var skills = SkillDB.get_skills()
	_ck(skills.has("portals"), "SkillDB: скилл portals есть")
	if not skills.has("portals"):
		quit(1)
		return
	var ptl = skills["portals"]
	_ck(ptl.price == 2, "portals price == 2")
	_ck(ptl.max_range == 40.0, "portals max_range == 40")
	_ck(ptl.cast_anim == "", "portals cast_anim пуст (жест в эффекте)")
	_ck(ptl.effects.size() == 2, "portals effects == 2 (пара + звук)")

	# --- Мир: пол и игрок ---
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(24, 0.5, 24)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.25, 0)  # верх пола на y=0
	root.add_child(floor_body)
	# В -s current_scene null → эффект кладёт pair НА КАСТЕРА, а Area-внук
	# CharacterBody3D в 4.8-beta НЕ мониторится (TD3-эксперимент 19.11:
	# тот же Area со скриптом в root — overlapping=1, в игроке — 0).
	# В игре current_scene = арена; здесь назначаем пол-мир.
	current_scene = floor_body

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await process_frame
	await process_frame

	# --- Каст: B в точке прицела (6, 0, 4) ---
	var effect = load("res://Logic/Skills/SpawnPortalsEffect.gd").new()
	effect.apply(player, {"target_pos": Vector3(6, 0.2, 4)})
	await process_frame
	await physics_frame
	var pair = player.get_meta("portal_pair", null)  # -s: world == caster
	_ck(pair != null, "PortalPair создана")
	if pair == null:
		quit(1)
		return
	var pa = pair.get_node_or_null("PortalA")
	var pb = pair.get_node_or_null("PortalB")
	_ck(pa != null and pb != null, "оба портала на месте")
	if pa == null or pb == null:
		quit(1)
		return
	_ck(pa.partner == pb and pb.partner == pa, "партнёры связаны двусторонне")
	var fwd := Vector3(0, 0, 1)  # игрок без поворота: модель смотрит +Z
	var exp_a := Vector3(0, 1.45, -1.7)
	var exp_b := Vector3(6, 1.45, 4)
	_ck(pa.global_position.distance_to(exp_a) < 0.5,
		"PortalA за спиной (%.2f м)" % pa.global_position.distance_to(exp_a))
	_ck(pb.global_position.distance_to(exp_b) < 0.5,
		"PortalB в точке прицела (%.2f м)" % pb.global_position.distance_to(exp_b))
	var meshes_a = _all_meshes(pa)
	_ck(meshes_a.size() >= 2, "визуал PortalA (мембрана+рамка): %d мешей" % meshes_a.size())

	# --- Телепорт тела A→B ---
	var dummy := CharacterBody3D.new()
	dummy.velocity = Vector3(2, 0, 0)
	var dcs := CollisionShape3D.new()
	var dbox := BoxShape3D.new()
	dbox.size = Vector3(0.5, 0.5, 0.5)
	dcs.shape = dbox
	dummy.add_child(dcs)
	root.add_child(dummy)
	dummy.global_position = pa.global_position
	dummy.move_and_slide()  # «физическое» движение — будим broadphase
	await physics_frame
	await physics_frame
	await physics_frame
	var exp_out := exp_b + fwd * 1.25
	var dxz := Vector2(dummy.global_position.x - exp_out.x,
		dummy.global_position.z - exp_out.z).length()
	_ck(dxz < 0.45, "тело телепортировано A→выход B (%.2f м)" % dxz)
	_ck(absf(dummy.velocity.length() - 2.0) < 0.01,
		"модуль скорости сохранён (%.2f)" % dummy.velocity.length())

	# --- Анти-пинг-понг: сразу в выходной портал — не кидает к A ---
	dummy.global_position = pb.global_position
	await physics_frame
	await physics_frame
	await physics_frame
	var still_b: bool = Vector2(dummy.global_position.x - pb.global_position.x,
		dummy.global_position.z - pb.global_position.z).length() < 0.3
	_ck(still_b, "кулдаун: немедленный вход в B не телепортирует")

	# --- Возврат B→A после кулдауна (выйти и войти заново) ---
	await create_timer(0.8).timeout
	dummy.global_position = pb.global_position + Vector3(0, 0, 2.5)
	await physics_frame
	await physics_frame
	dummy.global_position = pb.global_position
	await physics_frame
	await physics_frame
	await physics_frame
	var exp_out_a := exp_a + fwd * 1.25
	var dxz2 := Vector2(dummy.global_position.x - exp_out_a.x,
		dummy.global_position.z - exp_out_a.z).length()
	_ck(dxz2 < 0.45, "двусторонность: B→выход A (%.2f м)" % dxz2)

	# --- Перенос снаряда (Area3D с current_velocity) ---
	var proj := _Proj.new()
	proj.current_velocity = Vector3(0, 0, 10)
	var pcs := CollisionShape3D.new()
	var psph := SphereShape3D.new()
	psph.radius = 0.15
	pcs.shape = psph
	proj.add_child(pcs)
	root.add_child(proj)
	proj.global_position = pa.global_position
	await physics_frame
	await physics_frame
	await physics_frame
	var dxz3 := Vector2(proj.global_position.x - exp_out.x,
		proj.global_position.z - exp_out.z).length()
	_ck(dxz3 < 0.45, "снаряд перенесён A→выход B (%.2f м)" % dxz3)
	if "current_velocity" in proj:
		_ck(absf((proj.current_velocity as Vector3).length() - 10.0) < 0.01,
			"скорость снаряда развёрнута по выходу (%.2f)"
				% (proj.current_velocity as Vector3).length())

	# --- Повторный каст переносит пару ---
	effect.apply(player, {"target_pos": Vector3(-5, 0.2, 3)})
	await process_frame
	await physics_frame
	var pair2 = player.get_meta("portal_pair") if player.has_meta("portal_pair") else null
	var pb2 = pair2.get_node_or_null("PortalB") if pair2 else null
	_ck(pb2 != null and Vector2(pb2.global_position.x + 5,
		pb2.global_position.z - 3).length() < 0.5, "ре-каст перенёс пару")

	print("PORTALS GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

## Мок боевого снаряда (HomingProjectileComponent: скриптовое свойство
## current_velocity — именно его проверяет PortalNode через `in`).
class _Proj extends Area3D:
	var current_velocity := Vector3.ZERO

func _all_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] TIMEOUT 30с — тест завис")
	quit(1)
