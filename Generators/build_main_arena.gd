extends SceneTree

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

	var prop_paths = {
		"Boulder": { "path": "res://Graphics/Environment/Props/boulder_01/boulder_01.tscn", "pos": Vector3(5, 0, -3), "scale": Vector3(1, 1, 1) },
		"RockMoss": { "path": "res://Graphics/Environment/Props/rock_moss_set_01/rock_moss_set_01.tscn", "pos": Vector3(-5, 0, -3), "scale": Vector3(0.8, 0.8, 0.8) }
	}
	for p_name in prop_paths:
		var p = prop_paths[p_name]
		var inst = load(p.path).instantiate()
		inst.position = p.pos
		inst.scale = p.scale
		root.add_child(inst)
		inst.owner = root
		print(p_name + " placed at " + str(p.pos))

	# Непись-телепортер у края арены (19.11.26, верб. юзера): пол 100×100
	# (box 50×1×50 × scale 2), край на ±50 → угол (38, 0, 38) «ближе к краю».
	var npc = load("res://Logic/NPCTeleporter.gd").new()
	npc.name = "NPCTeleporter"
	npc.position = Vector3(38, 0, 38)
	root.add_child(npc)
	npc.owner = root

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
	print("MainArena generated!")
	quit()
