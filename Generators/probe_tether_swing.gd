extends SceneTree

## Q48 гейт шага 1 (PRP tasks/tether_swing_prp.md): физика-ядро «Эфирного
## захвата». Headless, quit(0/1), без bare-автолоадов.
## Чеки (ТЗ §7.1): регистрация в SkillDB + эффект в сборке; SWING от воздушного
## якоря (target_node == null) активируется, разгоняет заметно быстрее бега и
## не утапливает ниже пола, авто-срыв по таймеру; ZIP к геометрии притягивает
## к цели и подбрасывает; зацеп ближе 3 м — валидный отказ; повторный apply
## при активном тросе = срыв с бустом (+7.5 vy).

const RUN_SPEED := 5.0

var _fails := 0

func _init() -> void:
	await physics_frame

	# 1) Регистрация скилла и сборка.
	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	var has_skill: bool = skills.has("ether_tether")
	_check(has_skill, "registered")
	if not has_skill:
		print("[TETHER] GATE: FAIL")
		quit(1)
		return
	var skill = skills["ether_tether"]
	var eff = null
	for e in skill.effects:
		if e.get_script() != null \
				and e.get_script().resource_path.ends_with("TetherSwingEffect.gd"):
			eff = e
	_check(eff != null, "effect_in_skill")
	_check(skill.cast_anim == "" and skill.cast_hand == "Left", "cast_config")
	_check(skill.max_range == 45.0, "skill_range", "=%.1f" % skill.max_range)

	# Мир: пол 200×200 + болванка-кастер + компонент троса.
	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	fs.shape = box
	floor.add_child(fs)
	floor.position = Vector3(0, -0.5, 0)
	root.add_child(floor)

	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.position = Vector3(0, 1.0, 0)
	root.add_child(body)
	await physics_frame

	var tether := Node.new()
	tether.name = "TetherSwing"
	tether.set_script(load("res://Logic/Skills/TetherSwingComponent.gd"))
	body.add_child(tether)
	await physics_frame

	# Контексты каста (как их кладёт SpellCasterComponent._aim_context).
	var ctx_air := {
		"target_pos": Vector3(0, 12, -25),
		"hit_normal": Vector3.UP,
		"target_node": null,          # промах рейкаста = воздух
		"camera_pos": Vector3(0, 2.0, 0),
		"forward_dir": Vector3(0, 0.3, -0.95).normalized(),
		"hand": "Left",
	}
	var ctx_zip := {
		"target_pos": Vector3(0, 0, -20),
		"hit_normal": Vector3.UP,
		"target_node": floor,         # геометрия пола
		"camera_pos": Vector3(0, 1.6, 0),
		"forward_dir": Vector3(0, 0, -1),
		"hand": "Left",
	}
	var ctx_close := {
		"target_pos": Vector3(0, 0, -2),
		"hit_normal": Vector3.UP,
		"target_node": floor,
		"camera_pos": Vector3(0, 1.6, 0),
		"forward_dir": Vector3(0, 0, -1),
		"hand": "Left",
	}

	# 2) Слишком близкий зацеп — валидный отказ.
	body.position = Vector3(0, 1.0, 0)
	body.velocity = Vector3.ZERO
	eff.apply(body, ctx_close)
	_check(not tether.is_active(), "close_whiff")

	# 3) SWING от воздушного якоря: разгон, не ниже пола, авто-срыв.
	body.position = Vector3(0, 1.0, 0)
	body.velocity = Vector3.ZERO
	eff.apply(body, ctx_air)
	await physics_frame
	_check(tether.is_active(), "swing_activated")
	_check(tether.mode == 1, "swing_mode")  # Mode.SWING — воздушный якорь выше
	var max_speed := 0.0
	var min_y := 99.0
	var released_at := -1
	for t in range(200):  # 3.3 с — авто-срыв 2.2 с обязан успеть
		await physics_frame
		if not tether.is_active():
			released_at = t
			break
		tether.physics_step(1.0 / 60.0, Vector2.ZERO, false)
		max_speed = maxf(max_speed, body.velocity.length())
		min_y = minf(min_y, body.global_position.y)
	_check(released_at > 60, "swing_auto_release", "tick=%d" % released_at)
	_check(max_speed > RUN_SPEED * 2.0, "swing_fast", "max=%.1f" % max_speed)
	_check(min_y > 0.3, "swing_above_floor", "min_y=%.2f" % min_y)

	# 4) ZIP к точке на полу: сближение и подброс на отрыве.
	body.position = Vector3(0, 1.0, 0)
	body.velocity = Vector3.ZERO
	await physics_frame
	var zip_target := Vector3(0, 1.2, -20)
	var d0: float = body.global_position.distance_to(zip_target)
	eff.apply(body, ctx_zip)
	_check(tether.mode == 2, "zip_mode")  # Mode.ZIP — якорь низко
	var dmin := d0
	for t in range(180):  # 3 с — прилетает за ~0.6 с при 40 м/с
		await physics_frame
		if not tether.is_active():
			break
		tether.physics_step(1.0 / 60.0, Vector2.ZERO, false)
		dmin = minf(dmin, body.global_position.distance_to(zip_target))
	_check(dmin < 3.0, "zip_arrives", "dmin=%.1f" % dmin)
	_check(not tether.is_active(), "zip_released_on_arrival")
	_check(body.velocity.y > 4.0, "zip_toss", "vy=%.1f" % body.velocity.y)

	# 5) Повторный apply при активном тросе = срыв с бустом.
	body.position = Vector3(0, 1.0, 0)
	body.velocity = Vector3.ZERO
	await physics_frame
	eff.apply(body, ctx_air)
	await physics_frame
	_check(tether.is_active(), "reapply_activated")
	for t in range(30):
		await physics_frame
		if not tether.is_active():
			break
		tether.physics_step(1.0 / 60.0, Vector2.ZERO, false)
	var pre_vy: float = body.velocity.y
	eff.apply(body, ctx_air)  # активен → release(true)
	_check(not tether.is_active(), "reapply_releases")
	_check(body.velocity.y > pre_vy + 6.0, "reapply_boost",
		"vy %.1f → %.1f" % [pre_vy, body.velocity.y])

	# 6) Пробел во время троса = отрыв (грань ввода внутри компонента).
	body.position = Vector3(0, 1.0, 0)
	body.velocity = Vector3.ZERO
	eff.apply(body, ctx_zip)
	await physics_frame
	tether.physics_step(1.0 / 60.0, Vector2.ZERO, true)   # зажат — не срывает
	tether.physics_step(1.0 / 60.0, Vector2.ZERO, false)  # отпустил
	tether.physics_step(1.0 / 60.0, Vector2.ZERO, true)   # нажал — edge → отрыв
	_check(not tether.is_active(), "space_release")

	print("[TETHER] GATE: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		print("  PASS: %s %s" % [name, detail])
	else:
		_fails += 1
		print("  FAIL: %s %s" % [name, detail])
