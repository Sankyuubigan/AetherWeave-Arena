extends SceneTree
## Регресс-гейт Q35-фикс (репорт юзера 19.11.26: «боты меня не трогают совсем,
## только друг друга бьют»): добавление is_friendly=true ИГРОКУ (сердечки Q35)
## ломало enemy-валидацию _aim_context — касты ботов/мобов в игрока молча
## отменялись («требует правильную цель»). Дружественность ОТНОСИТЕЛЬНА:
## бот (не-friendly) бьёт всех; игрок не бьёт только «своих» (friendly).
## Тест на РЕАЛЬНОМ PlayerController (мок HealthComponent в test_ffa_bots
## is_friendly не имел — регресс не ловился). current_scene назначаем (Q21).

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
	fbox.size = Vector3(40, 0.5, 40)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.25, 0)
	world.add_child(floor_body)

	# РЕАЛЬНЫЙ игрок (is_friendly=true — то, что сломало бота) + бот.
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	var bot = load("res://Logic/Enemies/BotEnemy.gd").new()
	bot.position = Vector3(6, 0.2, 0)
	world.add_child(bot)
	await process_frame
	await process_frame
	await create_timer(0.4).timeout

	# 1. Таргетинг: реальный игрок в пуле целей бота.
	_ck(bot._acquire_target() == player, "бот таргетит реального игрока")

	# 2. fireball (инста) — спавнился и раньше, контрольный.
	var before := world.get_child_count()
	bot._player = player
	bot._attack()  # _skill_idx 0 → fireball
	await create_timer(0.5).timeout
	var after_fire := world.get_child_count()
	_ck(after_fire > before, "fireball бота спавнится")

	# 3. ГЛАВНЫЙ РЕГРЕСС: ball_lightning (requires_target enemy) в игрока.
	#    До фикса: «Умение требует правильную цель» → снаряда НЕТ.
	var hp_before_bolt: int = player.player_hp
	bot._attack()  # _skill_idx 1 → ball_lightning
	# 0.2с: молния в полёте (6 м/с, ~1с до игрока) — ещё в дереве.
	await create_timer(0.2).timeout
	var bolt = null
	var bolt_script = load("res://Logic/HomingProjectileComponent.gd")
	for ch in world.get_children():
		if ch.get_script() == bolt_script:
			bolt = ch
	_ck(bolt != null and bolt.target == player, "молния бота: target == игрок")

	# 4б. Попадание в игрока снимает HP: адаптивный take_damage на 1-арг
	#    PlayerController без SCRIPT ERROR — урон реально применяется.
	await create_timer(1.6).timeout
	_ck(player.player_hp < hp_before_bolt, "молния бота сняла HP игроку (адаптивный take_damage)")

	# 5. Прямое репро валидации: бот vs friendly-узел (не в группах —
	#    таргетинг не трогаем). enemy-цель для не-friendly кастера ВАЛИДНА.
	var friend := _FriendlyTarget.new()
	# Коллизия обязательна: StaticBody без shape не ловится рейкастом
	# (_aim_context) → target_node = null → чек ложноположительно пуст.
	var fsh := CollisionShape3D.new()
	var tb_box := BoxShape3D.new()
	tb_box.size = Vector3(0.8, 1.8, 0.8)
	fsh.shape = tb_box
	friend.add_child(fsh)
	friend.position = Vector3(2, 1.0, 3)
	world.add_child(friend)
	await process_frame
	var sc = bot.get_node_or_null("SpellCasterComponent")
	var cam = bot.get_node_or_null("SpringArm3D/Camera3D")
	cam.look_at(friend.global_position + Vector3(0, 0.9, 0))
	var skill = _enemy_skill()
	var ctx = sc._aim_context(bot, "ball_lightning", skill, "Right")
	_ck(not ctx.is_empty(), "бот (не-friendly) валидирует enemy-каст в friendly-узел")

	# 6. Симметрия «не бить своих»: игрок vs тот же friendly-узел → ПУСТО.
	var pcam = player.get_node_or_null("SpringArm3D/Camera3D")
	if pcam and player.has_node("SpellCasterComponent"):
		pcam.look_at(friend.global_position + Vector3(0, 0.9, 0))
		var pctx = player.get_node("SpellCasterComponent")._aim_context(
			player, "ball_lightning", skill, "Right")
		_ck(pctx.is_empty(), "игрок (friendly) НЕ валидирует enemy в friendly-узел")
	else:
		_ck(false, "у игрока есть камера/SpellCasterComponent")

	print("BOT-CAST GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

## requires_target enemy-скилл с валидным max_range (как ball_lightning).
func _enemy_skill() -> Resource:
	var s = load("res://Logic/Skills/Skill.gd").new()
	s.skill_name = "ball_lightning"
	s.requires_target = true
	s.target_type = "enemy"
	s.max_range = 40.0
	return s

## Friendly-узел СО СВОИМ is_friendly (HealthComponent свойства не имеет —
## set() на чужое свойство = no-op, и мок не ловил регресс).
class _FriendlyTarget extends StaticBody3D:
	var is_friendly := true
	func take_damage(_d: int, _v = null) -> void:
		pass

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] TIMEOUT 30с — тест завис")
	quit(1)
