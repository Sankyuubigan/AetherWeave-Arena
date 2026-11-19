extends SceneTree
## Проба Q38: HellArena спавнит EliteBot_0..2 со скином Whiteclown (headless).

func _init() -> void:
	_watchdog()
	await process_frame
	var scene := (load("res://Scenes/HellArena.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.5).timeout
	var elites: Array = []
	var elite_scripts: int = 0
	for n in scene.get_children():
		if String(n.name).begins_with("EliteBot_"):
			elites.append(n)
			if n.get_script() and (n.get_script() as GDScript).resource_path.ends_with("EliteBotEnemy.gd"):
				elite_scripts += 1
	print("[PROBE] EliteBot spawned: %d (script ok: %d)" % [elites.size(), elite_scripts])
	for e in elites:
		var model = e.get_node_or_null("GraphicsWrapper/EnemyModel")
		var sc = e.get("_sc")
		print("[PROBE] %s hp=%s mult=%s model=%s" % [e.name, str(e.get("max_health")), str(sc.damage_mult) if sc else "?", "yes" if model else "no"])
	print("[PROBE-RESULT] " + ("PASS" if elites.size() == 3 and elite_scripts == 3 else "FAIL"))
	quit(0 if elites.size() == 3 else 1)

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] timeout")
	quit(1)
