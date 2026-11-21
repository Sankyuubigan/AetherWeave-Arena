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

	# Q25-B (26.11.26): МОНОЛИТ пола вместо сэндвича. Родной бокс пола 1 м
	# (mid-plane −0.5) = клифф для софтбоди: покой желе −0.5 достигает мид-плейна
	# → солвер выбрасывает точки через дно → провал в пустоту (репро
	# probe_jelly_arena: 312/726 точек ниже пола за 1 с). Сэндвич
	# floor+backing v1 выдавливал тело вбок (~7 м/с). Монолит FloorBacking
	# 100×8×100 (топ y=0, точно под габаритом пола) — ЕДИНСТВЕННАЯ коллизия
	# пола: мид-плейн на −4 недостижим, родной тонкий бокс отключает runtime-
	# компонент FloorMonolith.gd (pack() не сериализует правки инстансов).
	# SinkGuard в JellyMonster.gd капает промин на пол−0.55 ( dive+glide был
	# позиционно-залочен, параметрами не лечится). За кромкой пола (±50)
	# монолита нет — падение с края карты в пустоту работает как раньше.
	var floor_backing = StaticBody3D.new()
	floor_backing.name = "FloorBacking"
	floor_backing.set_script(load("res://Logic/Props/FloorMonolith.gd"))
	floor_backing.name = "FloorBacking"
	var backing_cs = CollisionShape3D.new()
	var backing_box = BoxShape3D.new()
	backing_box.size = Vector3(100, 8, 100)
	backing_cs.shape = backing_box
	backing_cs.position = Vector3(0, -4, 0)
	root.add_child(floor_backing)
	floor_backing.owner = root
	floor_backing.add_child(backing_cs)
	backing_cs.owner = root # owner — строго после встройки в дерево (предок root)

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
		"EnchantTable": { "path": "res://Graphics/Environment/Props/enchant_table/enchant_table.tscn", "pos": Vector3(35.5, 0, 35.5), "scale": Vector3(1.7, 1.7, 1.7), "rot_y": -45.0 },
		# Гриб-батут (Q31, PRP одобрен 20.11.26): CapStatic держит игрока, шейдерный
		# промин шляпки, подброс по глубине посадки. no_hlod: корень = компонент
		# MushroomBounce.gd — скрипт-оверрайд PropHLOD его бы стёр.
		"MushroomBounce": { "path": "res://Graphics/Environment/Props/mushroom_bounce/mushroom_bounce.tscn", "pos": Vector3(12, 0, -12), "scale": Vector3(1, 1, 1), "no_hlod": true },
		# Q32 мягкий грунт: дюна со следами/проминами у спавна. no_hlod: корень =
		# компонент SoftGround.gd (стемп depth-текстуры) — PropHLOD его стёр бы.
		"SoftGround": { "path": "res://Graphics/Environment/Props/soft_ground/soft_ground.tscn", "pos": Vector3(6, 0, -14), "scale": Vector3(1, 1, 1), "no_hlod": true }
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
		# no_hlod: у инстанса свой корневой скрипт-компонент (гриб Q31) —
		# set_script его стёр бы.
		if not p.has("no_hlod"):
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

	# Q47 шаг 9 (21.11.26, вердикт юзера «А вариант намного лучше»): капсула
	# заменена нейро-аркой A внутри NPCTeleporter._ready (SSOT — все карты
	# сразу). Стенд A/B снят; арка B осталась префабом в Props/ — попадает в
	# каталог объектов (заказ юзера «пусть в каталоге лежит, докрутим потом»).

	# FFA-боты с мейн карты УДАЛЕНЫ (Q38, верб. юзера 19.11.26: «убери с мейн
	# карты их. они не нужны в мейн мапе») — переехали в АД как элитные боты
	# Whiteclown N Hallin (Logic/Enemies/EliteBotEnemy.gd, спавн в HellArena).

	# --- Q22 слот ели метода A (процедурный атлас) у спавна. Вердикт юзера
	# 19.11.26: «выглядит неплохо, но возможно можно будет лучше» (методы
	# B/C — в QUEUE); «Конус (старый метод)» удалён («это говно»).
	# Блок атомарный: Q37-агент параллельно правит этот файл, его блоки
	# не тронуты; удаляется целиком одним движением.
	var q22_root := Node3D.new()
	q22_root.name = "Q22TreeCompare"
	# Q22-сравнение у КРАЯ КАРТЫ (юзер 20.11.26: «деревья на краю карты, там
	# дохуя места»). Кромка пола z≈-50 (рекасты: грунт до -50, пустота на -60;
	# дальше декоративные горы y≈14). z=-45 = край пола, вокруг пусто.
	q22_root.position = Vector3(0, 0, -45)
	root.add_child(q22_root)
	var tree_a = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_a.tscn").instantiate()
	tree_a.name = "TreeA_AtlasCards"
	q22_root.add_child(tree_a)
	var lbl := Label3D.new()
	lbl.text = "A: конус + процедурный атлас"
	lbl.font_size = 96
	lbl.pixel_size = 0.01
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 17.2, 0)
	q22_root.add_child(lbl)
	# Q22-E (20.11.26, заказ юзера «гибрид как D, но форма старая, не конус —
	# старое дерево наше с другой формой»): скан-скелет + СТАРАЯ крона-облако
	# (v2-метод: 550 карточек по вокселям скана, до конуса) + атлас B (CC0).
	# 6531 трис — как у старых A/B. Слот слева от A (справа ряда пол кончается
	# на x≈50, рейкаст GCHK2).
	var tree_e = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage_b.tscn").instantiate()
	tree_e.name = "TreeE_OldCloudAtlasB"
	tree_e.position = Vector3(-16, 0, 0)
	q22_root.add_child(tree_e)
	var lbl_e := Label3D.new()
	lbl_e.text = "E: старая крона + CC0-атлас"
	lbl_e.font_size = 96
	lbl_e.pixel_size = 0.01
	lbl_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_e.position = Vector3(-16, 17.2, 0)
	q22_root.add_child(lbl_e)
	# Q22-B (20.11.26): ель с атласом из CC0-фотоскана иголок (ambientCG
	# PineNeedles001, журнал в docs/asset_sources.md) — тот же скелет/карточки,
	# отлична только текстура: 3 пучка тонированы в хвойный зелёный + 1 «сухой».
	var tree_b = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_b.tscn").instantiate()
	tree_b.name = "TreeB_StockScanCards"
	tree_b.position = Vector3(16, 0, 0)
	q22_root.add_child(tree_b)
	var lbl_b := Label3D.new()
	lbl_b.text = "B: конус + CC0-фотоскан"
	lbl_b.font_size = 96
	lbl_b.pixel_size = 0.01
	lbl_b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_b.position = Vector3(16, 17.2, 0)
	q22_root.add_child(lbl_b)
	# Q22-C (20.11.26): ель целиком из аддона MTree (живой скелет ветвления,
	# атлас хвои тот же CC0 B) — 3830 трис, легче A/B. Спектр сравнения полный.
	var tree_c = load("res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn").instantiate()
	tree_c.name = "TreeC_MTree"
	tree_c.position = Vector3(32, 0, 0)
	q22_root.add_child(tree_c)
	var lbl_c := Label3D.new()
	lbl_c.text = "C: MTree (живой скелет)"
	lbl_c.font_size = 96
	lbl_c.pixel_size = 0.01
	lbl_c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_c.position = Vector3(32, 17.2, 0)
	q22_root.add_child(lbl_c)
	# Q22-D (20.11.26, заказ юзера «жду четвертый гибридный тип»): скелет C
	# (геометрия gltf C 1:1) + атлас A. Сборка: копия gltf C с подменой URI
	# изображений на копии A-атласа — seed C нигде не записан, поэтому
	# геометрия переиспользована напрямую (точный гибрид, без новой случайности).
	var tree_d = load("res://Graphics/Environment/Props/spruce_mtree_D/spruce_mtree_D.tscn").instantiate()
	tree_d.name = "TreeD_MTreeAtlasA"
	tree_d.position = Vector3(48, 0, 0)  # шаг 16 м: пол кончается на x≈50 (рейкаст GCHK2 (52,-45)=ПУСТО)
	q22_root.add_child(tree_d)
	var lbl_d := Label3D.new()
	lbl_d.text = "D: гибрид C-скелет + A-атлас"
	lbl_d.font_size = 96
	lbl_d.pixel_size = 0.01
	lbl_d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_d.position = Vector3(48, 17.2, 0)
	q22_root.add_child(lbl_d)
	# Юзер 20.11.26: «деревья E/A/B висят в воздухе — чтобы росли с земли».
	# Карточные префабы (build_tree_prop.py) имеют origin выше подошвы: проба
	# probe_tree_ground.gd — низ геометрии A/B/E = 0.089 м, у MTree C/D = 0.
	# Опускаем слоты за низ AABB (§9), без врытия — слоты сравнения на полу.
	for t in [tree_a, tree_e, tree_b, tree_c, tree_d]:
		var drop := _geometry_min_y(t)
		print("[ARENA] %s: низ геометрии %.3f → y=%.3f" % [t.name, drop, -drop])
		t.position.y -= drop
	for n in [tree_a, tree_b, tree_c, tree_d, tree_e, lbl, lbl_b, lbl_c, lbl_d, lbl_e]:
		n.owner = root
	q22_root.owner = root

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
	print("MainArena generated!")
	quit()

## Низ геометрии инстанса (все MeshInstance3D/MultiMeshInstance3D, 8 углов
## AABB, трансформы НАКОПЛЕНИЕМ локальных — генератор строит detached-иерархию,
## global_transform не работает). Для карточных деревьев origin выше подошвы
## → слот опускается за низ AABB.
func _geometry_min_y(n: Node3D) -> float:
	# ВИСИТ (низ выше origin, lo>0) → опустить на lo; уже врыт (lo<0) → не трогать.
	# Грабля: minf(lo, 0.0) вместо maxf съедал именно висячий случай (0.089→0) —
	# все деревья «опускались на 0» и баг оставался (20.11.26).
	return maxf(_geometry_lowest_y(n), 0.0)

## Сырой низ геометрии (может быть ОТРИЦАТЕЛЬНЫМ: у trellis-выхода обломки-ножки
## уходят ниже origin → пропы «проваливаются в пол», баг-репорт Q47 21.11.26).
## Деревьям Q22 нужен clamp только вверх (врытое не трогать), аркам Q47 —
## точная постановка низа на пол в обе стороны.
func _geometry_lowest_y(n: Node3D) -> float:
	var lo := 1e9
	# (узел, трансформ родителя в пространстве слота). AABB — РЕСУРСНЫЕ
	# (mesh.get_aabb()/multimesh.get_aabb()): узловой get_aabb() на detached-
	# иерархии пуст (генератор строит сцену вне дерева).
	var stack: Array = [[n, Transform3D()]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var nd: Node = e[0]
		var xf: Transform3D = e[1]
		if nd is Node3D:
			xf = xf * (nd as Node3D).transform
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			var ab: AABB = (nd as MeshInstance3D).mesh.get_aabb()
			for cx in [ab.position.x, ab.end.x]:
				for cy in [ab.position.y, ab.end.y]:
					for cz in [ab.position.z, ab.end.z]:
						lo = minf(lo, (xf * Vector3(cx, cy, cz)).y)
		elif nd is MultiMeshInstance3D and (nd as MultiMeshInstance3D).multimesh != null:
			var ab2: AABB = (nd as MultiMeshInstance3D).multimesh.get_aabb()
			for cx2 in [ab2.position.x, ab2.end.x]:
				for cy2 in [ab2.position.y, ab2.end.y]:
					for cz2 in [ab2.position.z, ab2.end.z]:
						lo = minf(lo, (xf * Vector3(cx2, cy2, cz2)).y)
		for c in nd.get_children():
			stack.append([c, xf])
	if lo >= 1e9:
		return 0.0 # мешей нет — слот не трогать
	return lo
