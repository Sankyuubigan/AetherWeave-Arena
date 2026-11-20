extends SceneTree
## Q11-гейт: 5 новых камней .res грузятся как Mesh (load молча отдаёт null
## при ошибке — смоук этого не ловит).

func _init():
	var ok := true
	for rp in ["moon_rock_02", "moon_rock_03", "rock_07", "stone_01", "namaqualand_boulder_04"]:
		var m: Mesh = load("res://Graphics/Environment/Props/%s/%s_mesh_0.res" % [rp, rp])
		if m == null:
			printerr("ROCK-LOAD FAIL: %s -> null" % rp)
			ok = false
		else:
			print("ROCK-LOAD OK: %s (%s)" % [rp, m.get_class()])
	if ok:
		print("ROCKS-LOAD GATE PASS")
		quit(0)
	else:
		quit(1)
