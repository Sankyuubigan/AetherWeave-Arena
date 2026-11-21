extends SceneTree
## Гейт Q44 (порталы v2 «живое окно», юзер 20.11.26 «да гоу делай»):
## a) SkillDB-поля + v1 «portals» не тронут; b) apply() создаёт пару v2;
## c) ПРОСКОК тела A→B (юзер: «перс должен туда заходить, а не
## телепортироваться»: выход РЯДОМ с плоскостью B, velocity НАРУЖУ, модуль
## сохранён); d) возврат B→A; e) снаряд (current_velocity) проходит внутрь;
## f) кулдаун — немедленный повторный вход НЕ переносит; g) манекен без
## групп НЕ переносится (фильтр v1); h) lifetime → пара деспавнится.
## Headless: окно = low-вихрь (DisplayServer headless) — переносы не зависят
## от окна (окно проверяет рендер-проба probe_portal2_view).

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

	# --- a) SkillDB ---
	var SkillDB = load("res://Logic/Skills/SkillDB.gd")
	var skills = SkillDB.get_skills()
	_ck(skills.has("portals2"), "SkillDB: portals2 есть")
	_ck(skills.has("portals"), "SkillDB: v1 portals НЕ тронут")
	if not skills.has("portals2"):
		quit(1); return
	var p2 = skills["portals2"]
	_ck(p2.price == 4, "portals2 price == 4")
	_ck(p2.max_range == 40.0, "portals2 max_range == 40")
	_ck(p2.cast_anim == "", "portals2 cast_anim пуст (жест в эффекте)")
	_ck(p2.effects.size() == 2, "portals2 effects == 2 (спавн+звук)")

	# --- b) apply(): реальный путь скилла ---
	var player = load("res://Scenes/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var eff = load("res://Logic/Skills/SpawnPortals2Effect.gd").new()
	eff.apply(player, {"target_pos": player.global_position + Vector3(8, 0, 0)})
	await process_frame
	await process_frame
	var ps = load("res://Logic/PortalNode2.gd")
	var pair_meta = player.get_meta("portal_pair2", null)
	_ck(pair_meta != null and is_instance_valid(pair_meta), "apply создал пару v2")
	if pair_meta and is_instance_valid(pair_meta):
		var portals = pair_meta.get_children().filter(
			func(n): return n.get_script() == ps)
		_ck(portals.size() == 2, "в паре два PortalNode2: %d" % portals.size())
		if portals.size() == 2:
			_ck(portals[0].partner == portals[1]
				and portals[1].partner == portals[0], "partner ссылки A↔B")
			var ring = portals[0].get_children().filter(
				func(n): return n.get_script() == load(
					"res://Graphics/PortalRing2.gd"))
			_ck(ring.size() == 1, "PortalRing2 у портала")
		pair_meta.queue_free()
		player.set_meta("portal_pair2", null)

	# --- Контролируемая пара для переносов: оба смотрят +Z, A(0) B(10) ---
	var pair := Node3D.new()
	root.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	b.global_transform = Transform3D(Basis(), Vector3(10, 1.5, 0))
	a.call("build", Color(0.3, 0.9, 0.8), 0.0)
	b.call("build", Color(0.85, 0.4, 1.0), 3.1)
	a.partner = b
	b.partner = a
	await physics_frame

	# --- c) ПРОСКОК тела A→B (ключевой чек юзера) ---
	var body := CharacterBody3D.new()
	body.add_to_group("player")
	# Area3D детектит тело только по геометрии: болванке нужен shape
	# (поймано probe_portal2_zone: без shape body_entered НЕ эмитится).
	var bcs := CollisionShape3D.new()
	var bsh := SphereShape3D.new()
	bsh.radius = 0.4
	bcs.shape = bsh
	body.add_child(bcs)
	root.add_child(body)
	body.global_position = Vector3(0, 1.5, 3)
	await physics_frame
	body.velocity = Vector3(0, 0, -6)
	var transferred := false
	for i in 120:
		body.move_and_slide()
		await physics_frame
		# Критерий: тело у B-столбца (x>9) с velocity наружу — т.к. резюм
		# корутины идёт ДО физ-степа тика, dist-чек пропускал момент
		# (поймано на 2-м прогоне; перенос физикой доказан velocity).
		if body.global_position.x > 9.0 and body.velocity.z > 5.0:
			transferred = true
			break
	_ck(transferred, "тело перенеслось A→B")
	var rel_b: Vector3 = (b.global_transform.basis.inverse() \
			* (body.global_position - b.global_position))
	_ck(absf(rel_b.z) < 0.5,
		"проскок: выход РЯДОМ с плоскостью B (z=%.2f, v1 был 1.25)" % rel_b.z)
	_ck(absf(body.velocity.length() - 6.0) < 0.05,
		"velocity модуль сохранён (%.2f)" % body.velocity.length())
	_ck(body.velocity.z > 5.0, "velocity НАРУЖУ от B (+Z)")
	# Тело спавнилось лицом в мембрану A (basis identity, взгляд -z); после
	# проскока «камера доигрывает поворот» (PRP шаг 3) — взгляд = наружу B.
	_ck(-body.global_basis.z.dot(b.global_basis.z) > 0.9,
		"yaw: выход лицом НАРУЖУ B (dot=%.2f)" % -body.global_basis.z.dot(b.global_basis.z))
	for i in 30:
		body.move_and_slide()
		await physics_frame
	_ck(body.global_position.z > 1.0,
		"тело улетает от B (z=%.2f)" % body.global_position.z)

	# --- d) возврат B→A (кулдаун 700 мс уже истёк за 30 тиков ожидания) ---
	body.global_position = Vector3(10, 1.5, 3)
	body.velocity = Vector3(0, 0, -6)
	var back := false
	for i in 120:
		body.move_and_slide()
		await physics_frame
		if body.global_position.x < 1.0 and body.velocity.z > 5.0:
			back = true
			break
	_ck(back, "возврат B→A")
	var rel_a: Vector3 = (a.global_transform.basis.inverse() \
			* (body.global_position - a.global_position))
	_ck(absf(rel_a.z) < 0.5, "возврат: выход рядом с плоскостью A (z=%.2f)" % rel_a.z)

	# --- e) снаряд (Area3D + current_velocity) проходит внутрь ---
	var gs := GDScript.new()
	gs.source_code = "extends Area3D\nvar current_velocity := Vector3.ZERO\n"
	gs.reload()
	var proj = Area3D.new()
	proj.set_script(gs)
	var pcs := CollisionShape3D.new()
	var psh := SphereShape3D.new()
	psh.radius = 0.25
	pcs.shape = psh
	proj.add_child(pcs)
	root.add_child(proj)
	proj.global_position = Vector3(0, 1.5, 2)
	proj.current_velocity = Vector3(0, 0, -8)
	var ptrans := false
	for i in 90:
		proj.global_position += proj.current_velocity / 60.0
		await physics_frame
		if proj.global_position.x > 9.0 and proj.current_velocity.z > 7.0:
			ptrans = true
			break
	_ck(ptrans, "снаряд прошёл A→B")
	_ck(proj.current_velocity.z > 7.0, "снаряд вылетает наружу B (+Z)")
	_ck(absf(proj.current_velocity.length() - 8.0) < 0.05,
		"скорость снаряда сохранена (%.2f)" % proj.current_velocity.length())

	# --- e2) прямой снаряд (direction+speed, как ProjectileComponent) ---
	# Репорт юзера 20.11.26: файрболы пролетали мембрану насквозь — фильтр
	# зоны знал только current_velocity.
	var gs2 := GDScript.new()
	gs2.source_code = "extends Area3D\nvar direction := Vector3.ZERO\nvar speed := 8.0\n"
	gs2.reload()
	var proj2 = Area3D.new()
	proj2.set_script(gs2)
	var pcs2 := CollisionShape3D.new()
	pcs2.shape = psh
	proj2.add_child(pcs2)
	root.add_child(proj2)
	proj2.global_position = Vector3(0, 1.5, 2)
	proj2.direction = Vector3(0, 0, -1)
	var ptrans2 := false
	for i in 90:
		proj2.global_position += proj2.direction * proj2.speed / 60.0
		await physics_frame
		if proj2.global_position.x > 9.0 and proj2.direction.z > 0.5:
			ptrans2 = true
			break
	_ck(ptrans2, "прямой снаряд (direction+speed) прошёл A→B")
	_ck(proj2.direction.z > 0.9,
		"прямой снаряд вылетает наружу B (dir.z=%.2f)" % proj2.direction.z)

	# --- f) кулдаун: немедленный повторный вход НЕ телепортит ---
	body.global_position = Vector3(0, 1.5, 0.3)
	body.velocity = Vector3(0, 0, -6)
	var blocked := true
	for i in 40:
		body.move_and_slide()
		await physics_frame
		if body.global_position.distance_to(Vector3(10, 1.5, 0)) < 9.0:
			blocked = false
	_ck(blocked, "кулдаун: немедленный повторный вход НЕ телепортит")

	# --- g) манекен без групп НЕ переносится ---
	var dummy := CharacterBody3D.new()
	var dcs := CollisionShape3D.new()
	var dsh := SphereShape3D.new()
	dsh.radius = 0.4
	dcs.shape = dsh
	dummy.add_child(dcs)
	root.add_child(dummy)
	dummy.global_position = Vector3(0, 1.5, 3)
	dummy.velocity = Vector3(0, 0, -6)
	for i in 80:
		dummy.move_and_slide()
		await physics_frame
	_ck(dummy.global_position.distance_to(Vector3(10, 1.5, 0)) > 8.0,
		"манекен НЕ перенесло (фильтр player/ffa_bot)")

	# --- h) lifetime: пара деспавнится ---
	var pair2 := Node3D.new()
	root.add_child(pair2)
	var c = Area3D.new(); c.set_script(ps); pair2.add_child(c)
	c.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var d = Area3D.new(); d.set_script(ps); pair2.add_child(d)
	d.global_transform = Transform3D(Basis(), Vector3(5, 1.5, 0))
	c.call("build", Color.WHITE, 0.0, 0.35)
	d.call("build", Color.WHITE, 1.0, 0.35)
	c.partner = d
	d.partner = c
	await create_timer(0.8).timeout
	_ck(not is_instance_valid(pair2) or pair2.is_queued_for_deletion(),
		"lifetime 0.35 с → пара деспавнится")

	print("PORTALS2 GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

func _watchdog() -> void:
	await create_timer(60.0).timeout
	print("[WDT] TIMEOUT 60с — тест завис")
	quit(1)
