extends SceneTree
## Q19 Энергетический клинок — гейты (headless):
## SkillDB-запись, свинги в библиотеке (+UB), эффект на игроке создаёт
## клинок в руке, взмах наносит урон моку-врагу, растворение выключает.
## Запуск: --headless -s res://Generators/test_energy_blade.gd

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")
const BLADE_LIB := "res://Graphics/Animations/ual_casts_test.res"
const EFFECT := preload("res://Logic/Skills/SpawnBladeEffect.gd")
const HEALTH := preload("res://Logic/HealthComponent.gd")

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: ", name)
	else:
		fails += 1
		print("FAIL: ", name)

func _run() -> void:
	var skills := SkillDB.get_skills()
	_check("energy_blade в SkillDB", skills.has("energy_blade"))
	var bl = skills.get("energy_blade")
	_check("клинок: price=2, не пассив", bl and bl.price == 2 and not bl.is_passive)
	_check("клинок: cast_anim='' (режимы в эффекте)", bl and bl.cast_anim == "")
	_check("клинок: SpawnBladeEffect в effects", bl and bl.effects.size() > 0)

	var lib = load(BLADE_LIB)
	_check("ual-библиотека загружена", lib is AnimationLibrary)
	_check("Blade_Swing_A ретаргечен", lib.has_animation("Blade_Swing_A"))
	_check("Blade_Swing_B ретаргечен", lib.has_animation("Blade_Swing_B"))
	_check("Blade_Swing_A_UB собран", lib.has_animation("Blade_Swing_A_UB"))
	_check("Blade_Swing_B_UB собран", lib.has_animation("Blade_Swing_B_UB"))
	_check("длина свинга A ≈0.43 с", absf(lib.get_animation("Blade_Swing_A").length - 0.43) < 0.15)
	_check("SpawnBladeEffect компилируется", EFFECT != null)

	# Рантайм: игрок → материализация → клинок активен и в руке.
	var player = load("res://Scenes/player.tscn").instantiate()
	root.add_child(player)
	var anim_comp = player.get_node_or_null("PlayerAnimationComponent")
	_check("у игрока has_cast_anim(Blade_Swing_A)",
		anim_comp != null and anim_comp.has_cast_anim("Blade_Swing_A"))

	EFFECT.new().apply(player, {"forward_dir": Vector3.FORWARD})
	await process_frame
	await process_frame
	var blade = player.get_node_or_null("EnergyBlade")
	_check("клинок создан на игроке", blade != null)
	if blade == null:
		print("GATE FAILURES: ", fails)
		quit(1)
		return
	await process_frame
	_check("клинок активен", blade.is_active())
	_check("клинок виден", blade._blade.visible)
	var skel = blade._attach.get_parent()
	_check("клинок на скелете игрока", skel is Skeleton3D \
		and skel.find_bone("mixamorig_RightHand") >= 0)
	_check("BoneAttachment привязан к кости", blade._attach.bone_idx >= 0)

	# Взмах: мок-враг HealthComponent в конусе → урон; дружественный — нет.
	var enemy = HEALTH.new()
	enemy.name = "MockEnemy"
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	enemy.add_child(mi)
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.8, 1.8, 0.8)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	enemy.add_child(cs)
	enemy.position = player.global_position + Vector3(0, 1.0, -1.5)
	root.add_child(enemy)
	await process_frame
	var hp_before: int = enemy.current_health
	var hits: int = blade.swing({"forward_dir": Vector3.FORWARD})
	_check("взмах поразил врага (1 хит)", hits == 1)
	_check("урон снят HP", enemy.current_health < hp_before)

	var friend = HEALTH.new()
	friend.name = "MockFriend"
	friend.is_friendly = true
	friend.position = player.global_position + Vector3(0, 1.0, -1.5)
	root.add_child(friend)
	await process_frame
	var fh: int = friend.current_health
	enemy.is_dead = true  # мёртвые не таргетятся — второй взмах никого не достаёт
	var hits2: int = blade.swing({"forward_dir": Vector3.FORWARD})
	_check("дружественный/мёртвый не поражён", hits2 == 0 and friend.current_health == fh)

	# Растворение: active=false, клинок скрыт.
	blade.dissolve()
	_check("растворение: не активен", not blade.is_active())

	print("GATE ALL PASS" if fails == 0 else "GATE FAILURES: " + str(fails))
	quit(1 if fails > 0 else 0)
