extends SceneTree
## Гейт Q33-Q35 (фидбек-батч): Q34 ретаргет молнии на живую цель (+friendly-гейт
## молнии игрока, инерция без цели), Q35 ретаргет сердечка на раненого союзника
## (включая инициатора), все сыты — висит на месте. Q33 — статик-чек окна.
## current_scene назначаем: Area-внук CharacterBody в -s не мониторится (Q21).

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

	# --- Q33: SettingsMenu — выезд сверху ---
	var sm = load("res://Graphics/SettingsMenu.gd").new()
	_ck(sm.has_method("_slide_in"), "Q33: SettingsMenu._slide_in есть")

	# --- Моки: CharacterBody3D с API молний/сердечек ---
	# Поле-мир как current_scene (в -s null → иначе Area-внук player не
	# мониторится; снаряды сами в root, но _avoidance/tree ждут мир).
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	await process_frame
	await process_frame

	var mob_a := _Mob.new()
	mob_a.position = Vector3(5, 1.0, 0)
	world.add_child(mob_a)
	mob_a.add_to_group("aim_targets")
	var mob_b := _Mob.new()
	mob_b.position = Vector3(8, 1.0, 0)
	world.add_child(mob_b)
	mob_b.add_to_group("aim_targets")
	var mob_c := _Mob.new()  # союзник: молния игрока на него НЕ перебивается
	mob_c.is_friendly = true
	mob_c.position = Vector3(2, 1.0, 0)
	world.add_child(mob_c)
	mob_c.add_to_group("aim_targets")
	var mob_d := _Mob.new()  # раненый союзник: цель сердечка
	mob_d.is_friendly = true
	mob_d.player_hp = 5
	mob_d.position = Vector3(4, 1.0, 0)
	world.add_child(mob_d)
	mob_d.add_to_group("aim_targets")
	await process_frame

	# --- Q34: молния — ретаргет мёртвой цели ---
	var bolt = load("res://Logic/HomingProjectileComponent.gd").new()
	bolt.position = Vector3(0, 1.0, 0)
	root.add_child(bolt)
	bolt.set_caster(player)
	bolt.set_target(mob_a)
	await physics_frame
	await physics_frame
	_ck(bolt.target == mob_a, "Q34: молния держит живую цель A")

	# A умирает: C (союзник, ближе) должен быть отфильтрован; B — новая цель.
	mob_a.is_dead = true
	await physics_frame
	await physics_frame
	await physics_frame
	_ck(bolt.target == mob_b, "Q34: ретаргет A→B (мимо союзника C)")
	_ck(bolt.target != mob_c, "Q34: friendly-гейт — C не стал целью")

	# Все не-friendly мертвы → молния игрока не бьёт союзников/игрока →
	# кандидатов нет → инерция (velocity сохраняется, не гаснет).
	mob_b.is_dead = true
	await physics_frame
	await physics_frame
	await physics_frame
	_ck(bolt.current_velocity.length() > 5.0,
		"Q34: без живых целей — инерция (%.2f)" % bolt.current_velocity.length())

	# --- Q35: сердечко — ретаргет сытой цели ---
	var heart = load("res://Logic/HomingHealProjectileComponent.gd").new()
	heart.position = Vector3(0, 1.0, 0)
	root.add_child(heart)
	heart.set_caster(player)
	heart.set_target(player)  # игрок сыт → ищет раненого союзника
	await physics_frame
	await physics_frame
	await physics_frame
	_ck(heart.target == mob_d, "Q35: ретаргет сытый player→раненый D")

	# Инициатор: caster — раненый мок E НЕ из aim_targets → сердечко летит в него.
	var mob_e := _Mob.new()
	mob_e.is_friendly = true
	mob_e.player_hp = 4
	mob_e.position = Vector3(12, 1.0, 0)
	world.add_child(mob_e)
	var heart2 = load("res://Logic/HomingHealProjectileComponent.gd").new()
	heart2.position = Vector3(10, 1.0, 0)
	root.add_child(heart2)
	heart2.set_caster(mob_e)
	heart2.set_target(player)  # сыт → ретаргет; E (2м) ближе D (5м от heart2)
	await physics_frame
	await physics_frame
	await physics_frame
	_ck(heart2.target == mob_e, "Q35: сердечко летит в инициатора E")

	# Все сыты → сердечко гасит скорость и висит.
	mob_d.player_hp = 10
	mob_e.player_hp = 10
	await physics_frame
	await physics_frame
	for i in 40:
		await physics_frame
	_ck(heart2.current_velocity.length() < 1.0,
		"Q35: все сыты — сердечко висит (%.2f)" % heart2.current_velocity.length())

	print("FEEDBACK GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

## Мок цели: API, которое проверяют молния (_target_dead/_retarget) и
## сердечко (_hp_full/_find_hurt_ally): take_damage/heal, is_dead/is_dying,
## is_friendly, HP-поля (player_hp/MAX_HP — как у PlayerController).
class _Mob extends CharacterBody3D:
	var is_dead := false
	var is_dying := false
	var is_friendly := false
	var player_hp := 10
	var MAX_HP := 10
	var hits := 0
	func take_damage(_d: int, _v = null) -> void:
		hits += 1
	func heal(a: int) -> void:
		player_hp = mini(player_hp + a, MAX_HP)

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] TIMEOUT 30с — тест завис")
	quit(1)
