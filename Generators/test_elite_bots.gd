extends SceneTree
## Гейт Q38 (элитные боты Whiteclown N Hallin в аду, заказ юзера 19.11.26):
## скин применился, HP 450, урон ×2.5 (damage_mult-конвейер), размер ×1.4,
## враждебность игроку (таргет + fireball В игрока — фикс кастер-меты
## ProjectileComponent вместо body.name == "Player"), пул-безопасность
## (pooled_reset сброс damage).
##
## УРОКИ ПРОГОНОВ (нельзя потерять):
## - элита — ЖИВОЙ ИИ: самокастует по cooldown С aggro-тика t=0 → заморозка
##   set_physics_process(false) СРАЗУ после add_child (до первого физ-тика),
##   иначе _skill_idx сдвигается и касты едут.
## - каст-анимация вытягивает руку: spawn_from_hand берёт cast_origin ПОСЛЕ
##   delay — спавн ~2.2 м ближе к цели → полёт 0.2 с. Живое окно снаряда
##   ловится ПОЛЛИНГОМ 0.05, а не фиксированной паузой.
## - для damage/меты-чеков использую ПРЯМОЙ apply эффектов (без cast_skill:
##   спавн от тела, spawn_delay инстанса 0) — детерминировано.

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

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 0.5, 60)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.25, 0)
	world.add_child(floor_body)

	# Реальный игрок + элита через скин (паттерн HellArena._spawn_enemy).
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	var skin: PackedScene = load("res://Scenes/enemy_Whiteclown_N_Hallin.tscn")
	var elite = skin.instantiate()
	elite.set_script(load("res://Logic/Enemies/EliteBotEnemy.gd"))
	# Заморозка ДО add_child: флаг стоит до входа в дерево — ИИ не тикает ни
	# разу (поздняя заморозка ловила самокаст элиты в окне setup: второй
	# fireball в игрока = двойной урон 100→0 → смерть → молния ретаргетила
	# мимо по Q34 — вот источник последнего FAIL).
	elite.set_physics_process(false)
	elite.position = Vector3(7, 0.2, 0)
	world.add_child(elite)
	await process_frame
	await process_frame
	await create_timer(0.3).timeout

	# 1-4. Конфиг элиты + враждебность.
	_ck(int(elite.max_health) == 450, "HP элиты 450 (%d)" % int(elite.max_health))
	_ck(elite.scale.is_equal_approx(Vector3(1.4, 1.4, 1.4)), "размер элиты ×1.4")
	var sc = elite.get_node_or_null("SpellCasterComponent")
	_ck(sc != null and is_equal_approx(float(sc.damage_mult), 2.5),
		"damage_mult элиты 2.5")
	_ck(elite.is_in_group("ffa_bot"), "элита в группе ffa_bot")
	_ck(elite._acquire_target() == player, "элита таргетит игрока")
	_ck(elite.get_node_or_null("GraphicsWrapper/EnemyModel") != null,
		"скин Whiteclown применился (модель на месте)")

	var proj_comp = load("res://Logic/ProjectileComponent.gd")
	var bolt_comp = load("res://Logic/HomingProjectileComponent.gd")

	# 5. ПРЯМОЙ apply fireball (детерминированный: спавн от ТЕЛА элиты (7, 1.4),
##   без каст-анимации и живой кисти) в игрока: ×2.5 → damage 62 + мета.
	var fb_effect = load("res://Logic/Skills/SpawnProjectileEffect.gd").new()
	fb_effect.projectile_scene = load("res://Scenes/fireball.tscn")
	fb_effect.apply(elite, {"damage_mult": 2.5,
		"target_pos": player.global_position + Vector3(0, 1.0, 0)})
	var fb = await _poll_alive(world, proj_comp)
	_ck(fb != null, "fireball элиты спавнится (живой)")
	if fb:
		_ck(int(fb.damage) == 62, "fireball элиты damage 62 = 25×2.5 (%d)" % int(fb.damage))
		_ck(fb.has_meta("cast_caster") and fb.get_meta("cast_caster") == elite,
			"fireball: cast_caster == элита")
		var to_p: Vector3 = (player.global_position - (fb.global_position as Vector3)).normalized()
		_ck((fb.direction as Vector3).dot(to_p) > 0.9, "fireball летит в игрока")

	# 6. ГЛАВНЫЙ ФИКС Q38: fireball бота попадает В ИГРОКА (старый фильтр
	#    body.name == "Player" делал его безвредным): HP −62.
	# Игрок ПЕРЕЖИВАЕТ: смерть → die() → коллизия off + молния ретаргетит
	# мимо (Q34) — хит-чек молнии требует живого игрока на весь тест.
	player.player_hp = 500
	var hp_before: int = player.player_hp
	await create_timer(0.6).timeout  # полёт ~7 м / 20 м/с ≈ 0.35 с
	_ck(player.player_hp < hp_before,
		"fireball элиты снял HP игроку (500 → %d)" % int(player.player_hp))

	# 7. ПРЯМОЙ apply молнии (детерминированный): ×2.5 → 87, caster == элита,
	#    наведение на игрока, попадание −87.
	var bl_effect = load("res://Logic/Skills/SpawnHomingProjectileEffect.gd").new()
	bl_effect.projectile_scene = load("res://Scenes/ball_lightning.tscn")
	bl_effect.apply(elite, {"damage_mult": 2.5, "target_node": player})
	var bolt = await _poll_alive(world, bolt_comp)
	_ck(bolt != null, "молния элиты спавнится (живая)")
	if bolt:
		_ck(bolt.get("caster") == elite, "молния: caster == элита")
		_ck(int(bolt.damage) == 87, "молния элиты damage 87 = 35×2.5 (%d)" % int(bolt.damage))
		var to_t: Vector3 = (player.global_position + Vector3(0, 1.0, 0) - (bolt.global_position as Vector3)).normalized()
		_ck((bolt.current_velocity as Vector3).normalized().dot(to_t) > 0.9,
			"молния летит к игроку (target-наведение)")
	var hp_b2: int = player.player_hp
	for st in 15:
		await create_timer(0.1).timeout
		if is_instance_valid(bolt) and bolt.visible:
			print("[DIAG] bolt t=%.1f pos=%v" % [0.1 * (st + 1), bolt.global_position])
	await create_timer(0.1).timeout  # суммарно ~1.6 с — хит должен был быть
	_ck(player.player_hp < hp_b2,
		"молния элиты сняла HP игроку (%d → %d)" % [hp_b2, int(player.player_hp)])

	# 8. Пул-безопасность: элитные снаряды вернулись (попали), ОБЫЧНЫЙ бот
	#    кастует через _attack (поллинг живого окна) → его ЖИВОЙ fireball 25
	#    (pooled_reset сброс базы; без него прилипла бы 62 через узел пула).
	var plain = load("res://Logic/Enemies/BotEnemy.gd").new()
	plain.set_physics_process(false)  # ДО add_child: самокаст в окне setup сдвинул бы _skill_idx
	plain.position = Vector3(-6, 0.2, 0)
	world.add_child(plain)
	await create_timer(0.2).timeout
	var hp_guard: int = player.player_hp
	player.player_hp = 500  # страх обычного каста
	plain._player = player
	plain._attack()  # fireball (idx 0)
	var fb2 = await _poll_alive(world, proj_comp)
	_ck(fb2 != null and int(fb2.damage) == 25,
		"пул чист: обычный бот кастует damage 25 (%d)" % (int(fb2.damage) if fb2 else -1))

	print("ELITE-BOTS GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

## Живой (visible) снаряд скрипта comp: поллинг 12×0.05 с — живое окно
## полёта (спавн из живой кисти при каст-анимации сокращает полёт до 0.2 с).
func _poll_alive(world: Node, comp: GDScript) -> Node:
	for i in 12:
		await create_timer(0.05).timeout
		for ch in world.get_children():
			if ch.get_script() == comp and ch.visible:
				return ch
	return null

func _watchdog() -> void:
	await create_timer(40.0).timeout
	print("[WDT] TIMEOUT 40с — тест завис")
	quit(1)
