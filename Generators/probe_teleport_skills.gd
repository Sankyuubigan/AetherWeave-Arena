extends SceneTree
## Зонд бага «скиллы слетают при телепорте» (19.11.26): симуляция смены карты
## MainArena → HellArena в -s-режиме. Автолоады в -s не грузятся (грабли
## AudioManager) — PlayerSession ставится вручную суррогатом на /root.
## Гейты: после «телепорта» купленный скилл, SP и слот панели совпадают.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# Автолоад-суррогат: в -s-режиме автолоады не загружаются.
	var ps = load("res://Logic/PlayerSession.gd").new()
	ps.name = "PlayerSession"
	root.add_child(ps)

	# Карта 1: MainArena (статичная) — «юзер купил скилл и кинул на панель».
	var s1 = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(s1)
	await process_frame
	var p1 = get_first_node_in_group("player")
	if p1 == null:
		print("PROBE FAIL: player 1 не найден")
		quit(1)
		return
	var sdb = load("res://Logic/Skills/SkillDB.gd").get_skills()
	var sid: String = sdb.keys()[0]
	p1.unlocked_skills[sid] = true
	p1.skill_points = 42
	p1.get_node("ActionBar").slots[0].set_skill(sid)

	# «Телепорт»: уход со сцены — _exit_tree игрока → PlayerSession.capture.
	root.remove_child(s1)
	s1.free()

	# Карта 2: HellArena (генерация по кадрам — игрок появляется в шаге 4).
	var s2 = load("res://Scenes/HellArena.tscn").instantiate()
	root.add_child(s2)
	var p2 = null
	for i in 900:
		await process_frame
		p2 = get_first_node_in_group("player")
		if p2:
			break
	if p2 == null:
		print("PROBE FAIL: player 2 не появился за 900 кадров")
		quit(1)
		return
	await process_frame

	var ab = p2.get_node("ActionBar")
	var ok_unlock: bool = (p2.unlocked_skills.get(sid, false) == true)
	var ok_sp: bool = (p2.skill_points == 42)
	var ok_bar: bool = (ab.slots[0].skill_id == sid)
	print("PROBE teleport-skills: sid=%s unlock=%s sp=%s bar=%s" % [sid, ok_unlock, ok_sp, ok_bar])
	if ok_unlock and ok_sp and ok_bar:
		print("PROBE PASS")
		quit(0)
	else:
		print("PROBE FAIL")
		quit(1)
