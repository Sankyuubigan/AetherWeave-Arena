extends SceneTree

const ArenaSky = preload("res://Graphics/ArenaSky.gd")

func _init():
	var root = Node3D.new()
	root.name = "MainArena"

	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# 19.11.26 (верб. юзера): свет чуть темнее и контрастнее — эмиссия магических
	# сфер (VFX) читается как сгусток энергии на тёмном фоне.
	env.background_color = Color(0.28, 0.42, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.17, 0.17, 0.24)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true # 4.8: multi-bounce AO
	# Объёмный туман (Forward+; фишка из демо 3d/volumetric_fog): лёгкая дымка
	# глубины — эмиссия магических сфер на её фоне читается контрастнее.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.72, 0.78, 0.92)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 64.0
	ArenaSky.apply(env, "main") # небо: один шейдер на 3 карты (мастер-план 18.11.26)
	env_node.environment = env
	root.add_child(env_node)
	env_node.owner = root

	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-35, 45, 0)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.95, 0.88) # тёплый ключ — контраст с холодной эмиссией VFX
	light.shadow_enabled = true
	light.shadow_contact_shadows_allow = true # 4.8: contact shadows — объекты не «парят»
	root.add_child(light)
	light.owner = root

	var arena_scene = load("res://Scenes/arena.tscn")
	var arena = arena_scene.instantiate()
	arena.scale = Vector3(2, 1, 2)
	root.add_child(arena)
	arena.owner = root

	var player_scene = load("res://Scenes/player.tscn")
	var player = player_scene.instantiate()
	player.position = Vector3(0, 1, 0)
	root.add_child(player)
	player.owner = root

	var dummy_scene = load("res://Scenes/dummy.tscn")

	var dummy = dummy_scene.instantiate()
	dummy.position = Vector3(0, 1, -5)
	root.add_child(dummy)
	dummy.owner = root

	# Стоячим мишеням — нейро-манекен (Q37, заказ юзера «только стоячих заменить,
	# у движущихся будет другая модель»): красная капсула скрыта, хитбокс и
	# HealthComponent не тронуты — логика урона/рэгдолла работает как раньше.
	# Манекен-префаб trellis высотой 1.0 юнита → scale 2 = рост капсулы.
	# Скрытие капсулы/глушение дубль-хитбокса — NeuroDummyProp._ready: pack() не
	# сериализует переопределения узлов инстанс-подсцены, инлайн-правки терялись.
	if true: # NEURO_DUMMIES
		var dummy_prop = load("res://Graphics/Environment/Props/training_dummy/training_dummy.tscn").instantiate()
		dummy_prop.scale = Vector3(2, 2, 2)
		dummy_prop.set_script(load("res://Graphics/NeuroDummyProp.gd"))
		dummy.add_child(dummy_prop)
		dummy_prop.owner = root

	var dummy_line = dummy_scene.instantiate()
	dummy_line.position = Vector3(-10, 1, -15)
	dummy_line.name = "DummyLine"
	dummy_line.set_script(load("res://Logic/MovingDummy.gd"))
	dummy_line.set("move_type", "line")
	dummy_line.set("move_speed", 3.0)
	root.add_child(dummy_line)
	dummy_line.owner = root

	var dummy_poly = dummy_scene.instantiate()
	dummy_poly.position = Vector3(15, 1, -10)
	dummy_poly.name = "DummyTriangle"
	dummy_poly.set_script(load("res://Logic/MovingDummy.gd"))
	dummy_poly.set("move_type", "complex_polygon")
	dummy_poly.set("move_speed", 16.0)
	root.add_child(dummy_poly)
	dummy_poly.owner = root

	var friendly_dummy = dummy_scene.instantiate()
	friendly_dummy.position = Vector3(-15, 1, 10)
	friendly_dummy.name = "FriendlyDummy"
	friendly_dummy.set_script(load("res://Logic/FriendlyDummy.gd"))
	friendly_dummy.set("move_type", "triangle")
	friendly_dummy.set("move_speed", 12.0)
	root.add_child(friendly_dummy)
	friendly_dummy.owner = root

	# Стоячий зелёный (заявка 17.11.26): мишень для отхила сердечком —
	# не бегает (walks=false), 10% HP + гниение как у бегуна.
	var friendly_still = dummy_scene.instantiate()
	friendly_still.position = Vector3(-11, 1, 10)
	friendly_still.name = "FriendlyDummyStill"
	friendly_still.set_script(load("res://Logic/FriendlyDummy.gd"))
	friendly_still.set("walks", false)
	root.add_child(friendly_still)
	friendly_still.owner = root
	# Тоже нейро-манекен, но с зелёным tint — заявка 17.11.26 «зелёная
	# стоячая мишень для отхила» сохраняет читаемость цвета.
	var fstill_prop = load("res://Graphics/Environment/Props/training_dummy/training_dummy.tscn").instantiate()
	fstill_prop.scale = Vector3(2, 2, 2)
	fstill_prop.set_script(load("res://Graphics/NeuroDummyProp.gd"))
	fstill_prop.set("tint", Color(0.6, 1.0, 0.6))
	friendly_still.add_child(fstill_prop)
	fstill_prop.owner = root

	var prop_paths = {
		"Boulder": { "path": "res://Graphics/Environment/Props/boulder_01/boulder_01.tscn", "pos": Vector3(5, 0, -3), "scale": Vector3(1, 1, 1) },
		"RockMoss": { "path": "res://Graphics/Environment/Props/rock_moss_set_01/rock_moss_set_01.tscn", "pos": Vector3(-5, 0, -3), "scale": Vector3(0.8, 0.8, 0.8) },
		# Стол зачарований (Q37): у непись-телепортера на углу карты (верб. юзера
		# 19.11.26 «недалеко от синей капсулы на углу, не в середине»). Scale 1.7.
		"EnchantTable": { "path": "res://Graphics/Environment/Props/enchant_table/enchant_table.tscn", "pos": Vector3(35.5, 0, 35.5), "scale": Vector3(1.7, 1.7, 1.7), "rot_y": -45.0 }
	}
	for p_name in prop_paths:
		var p = prop_paths[p_name]
		var inst = load(p.path).instantiate()
		inst.position = p.pos
		inst.scale = p.scale
		if p.has("rot_y"):
			inst.rotation_degrees.y = p.rot_y
		# HLOD-фейк (демо 3d/visibility_ranges): апликатор на инстанс — pack()
		# не сериализует настройки вложенных узлов префаба, а префабы камней
		# одобрены юзером (не перегенерируем). Диапазоны ставит _ready скрипта.
		inst.set_script(load("res://Graphics/PropHLOD.gd"))
		root.add_child(inst)
		inst.owner = root
		# Кузница скиллов (Q36): зона «Z — Кузница скиллов» у стола зачарований.
		# Компонент ребёнком инстанса с owner (паттерн NeuroDummyProp: pack()
		# сериализует только owned-узлы); окно — автолоад /root/SkillForgeWindow.
		if p_name == "EnchantTable":
			var forge_zone = load("res://Logic/SkillForge.gd").new()
			forge_zone.name = "SkillForge"
			inst.add_child(forge_zone)
			forge_zone.owner = root
		print(p_name + " placed at " + str(p.pos))

	# Желе-монстр (QUEUE Q6 → Q25 → v3 по вердикту юзера «хотдог-мешок»):
	# SoftBody3D-слизень. y=1.95: низ купола (r*0.72=1.87) касается пола —
	# пин-юбка фиксирует точки СРАЗУ на уровне пола, без провиса-гамака.
	var jelly = preload("res://Logic/JellyMonster.gd").new()
	jelly.name = "JellyMonster"
	# Меш ДО add_child (грабля 4.8, probe 19.11.26): назначение меша SoftBody3D
	# когда узел уже в дереве, сбрасывает его трансформ в identity — желе
	# уезжало из точки спавна в origin у спавна. Меш попадёт в tscn sub_resource.
	jelly.mesh = preload("res://Logic/JellyMonster.gd").build_blob_mesh(jelly.radius)
	jelly.position = Vector3(7, 1.95, -6)
	root.add_child(jelly)
	jelly.owner = root

	# Непись-телепортер у края арены (19.11.26, верб. юзера): пол 100×100
	# (box 50×1×50 × scale 2), край на ±50 → угол (38, 0, 38) «ближе к краю».
	var npc = load("res://Logic/NPCTeleporter.gd").new()
	npc.name = "NPCTeleporter"
	npc.position = Vector3(38, 0, 38)
	root.add_child(npc)
	npc.owner = root

	# FFA-боты (QUEUE Q10): 3 бота кольцом r=12 — кастуют скиллы через
	# SpellCasterComponent, таргет = ближайший живой (игрок или другой бот).
	# Скины как у врагов ада (Demon/Ganfaul); без сцены — капсульный фолбэк.
	var bot_skin_paths := [
		"res://Scenes/enemy_Demon_T_Wiezzorek.tscn",
		"res://Scenes/enemy_Ganfaul_M_Aure.tscn",
		"res://Scenes/enemy_Demon_T_Wiezzorek.tscn",
	]
	var bot_script := preload("res://Logic/Enemies/BotEnemy.gd")
	for i in bot_skin_paths.size():
		var skin: PackedScene = null
		if ResourceLoader.exists(bot_skin_paths[i]):
			skin = load(bot_skin_paths[i])
		var b = skin.instantiate() if skin else bot_script.new()
		b.set_script(bot_script)
		var ang := TAU * i / bot_skin_paths.size() + 0.6
		b.name = "FFABot_%d" % i
		b.position = Vector3(cos(ang) * 12.0, 0.2, sin(ang) * 12.0)
		root.add_child(b)
		b.owner = root

	# --- Q22 слот ели метода A (процедурный атлас) у спавна. Вердикт юзера
	# 19.11.26: «выглядит неплохо, но возможно можно будет лучше» (методы
	# B/C — в QUEUE); «Конус (старый метод)» удалён («это говно»).
	# Блок атомарный: Q37-агент параллельно правит этот файл, его блоки
	# не тронуты; удаляется целиком одним движением.
	var q22_root := Node3D.new()
	q22_root.name = "Q22TreeCompare"
	q22_root.position = Vector3(-5, 0, -9)
	root.add_child(q22_root)
	var tree_a = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage.tscn").instantiate()
	tree_a.name = "TreeA_AtlasCards"
	q22_root.add_child(tree_a)
	var lbl := Label3D.new()
	lbl.text = "A: процедурный атлас (карточки)"
	lbl.font_size = 220
	lbl.pixel_size = 0.01
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 16.2, 0)
	q22_root.add_child(lbl)
	for n in [tree_a, lbl]:
		n.owner = root
	q22_root.owner = root

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
	print("MainArena generated!")
	quit()
