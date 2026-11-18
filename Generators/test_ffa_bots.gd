extends SceneTree

## Тест QUEUE Q10: FFA-боты — BotEnemy переиспользует FSM базы, кастует
## скиллы через SpellCasterComponent, таргет = ближайший живой. Гейт: GATE ALL PASS.

const BotScript = preload("res://Logic/Enemies/BotEnemy.gd")
const SkillDB = preload("res://Logic/Skills/SkillDB.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _run() -> void:
	_check("BotEnemy компилируется", BotScript != null)

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var floor_body := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 0.5, 40)
	fshape.shape = fbox
	floor_body.add_child(fshape)
	floor_body.position = Vector3(0, -0.25, 0)
	scene.add_child(floor_body)

	# Два бота (капсульный фолбэк без скина) + мок-игрок.
	var bot1 = BotScript.new()
	bot1.position = Vector3(0, 0.2, 0)
	scene.add_child(bot1)
	var bot2 = BotScript.new()
	bot2.position = Vector3(6, 0.2, 0)
	scene.add_child(bot2)

	# Мок-игрок = HealthComponent (StaticBody3D, take_damage, is_dead) —
	# валидная «вражеская» цель для requires_target-скилла бота.
	var mock = load("res://Logic/HealthComponent.gd").new()
	var mshape := CollisionShape3D.new()
	var mbox := BoxShape3D.new()
	mbox.size = Vector3(0.8, 1.8, 0.8)
	mshape.shape = mbox
	mock.add_child(mshape)
	mock.position = Vector3(8, 0.9, 0)
	scene.add_child(mock)
	mock.add_to_group("player")
	await create_timer(0.4).timeout

	_check("бот в группе ffa_bot", bot1.is_in_group("ffa_bot") and bot2.is_in_group("ffa_bot"))
	var sc = bot1.get_node_or_null("SpellCasterComponent")
	_check("SpellCasterComponent на боте, каст-бар скрыт", sc != null and sc.get("show_cast_bar") == false)
	var cams := bot1.find_children("*", "Camera3D", true, false)
	_check("aim-камера на боте (1 шт)", cams.size() == 1)

	# Выбор цели: мок-игрок (8 м) ближе bot2 (6 м по X, но считаем от bot1 —
	# bot1 в (0,0,0): bot2=6 м, мок=8 м → bot2 БЛИЖЕ. Мок с is_dead=false.
	# Для проверки «мёртвые не таргетятся» убьём bot2 (is_dead вручную).
	var t1: Node = bot1._acquire_target()
	_check("цель по умолчанию — ближайший (bot2)", t1 == bot2)
	bot2.is_dead = true
	var t2: Node = bot1._acquire_target()
	_check("мёртвый бот не таргетится — цель мок-игрок", t2 == mock)
	bot2.is_dead = false

	# Атака: fireball (инста) → снаряд спавнится в current_scene.
	var before := scene.get_child_count()
	bot1._player = mock
	bot1._attack()
	await create_timer(0.5).timeout
	var after := scene.get_child_count()
	_check("fireball бота спавнит снаряд", after > before)

	# Атака: ball_lightning (requires_target enemy) → валидная цель по рейкасту
	# aim-камеры (мок стоит в 8 м, луч из глаз бота попадает в бокс).
	bot1._attack()
	await create_timer(0.8).timeout
	_check("ball_lightning бота спавнит самонаводящийся снаряд",
		scene.get_child_count() > after)
	_check("кулдаун сожжён атакой", bot1._cd_left > 0.0)

	# Регресс базы: ад-враг по-прежнему берёт группу player первой целью.
	var hell = load("res://Logic/Enemies/HellMeleeEnemy.gd").new()
	hell.position = Vector3(0, 0.2, -4)
	scene.add_child(hell)
	await create_timer(0.3).timeout
	_check("HellEnemyBase._acquire_target не сломан", hell._acquire_target() == mock)

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)

## DEBUG-проба (удаляется после диагностики)
