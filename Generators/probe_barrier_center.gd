extends SceneTree

## Диагностика купола Акустического Барьера (плейтест 22.11.26, вопрос юзера:
## «купол не по центру персонажа»). Проба снимает ЧИСЛА: X/Z кости Hips
## (центр купола = Hips X/Z + player.y+0.95 каждый кадр) против origin тела
## в покое (Idle). Кольцо барьера живёт в локальном (0,0.03,0) VFX-узла, т.е.
## на origin тела. Вывод проба печатает в человекочитаемом виде.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== PROBE: центр купола барьера ===")
	await process_frame

	var player = load("res://Scenes/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	await create_timer(0.6).timeout  # аниматор успевает завести Idle

	var model = player.get_node_or_null("GraphicsWrapper/PlayerModel")
	if model == null:
		print("FAIL: нет GraphicsWrapper/PlayerModel")
		quit(1)
		return
	var skel: Skeleton3D = null
	for c in model.get_children():
		if c is Skeleton3D:
			skel = c
			break
	if skel == null:
		print("FAIL: Skeleton3D не прямой ребёнок PlayerModel")
		quit(1)
		return
	var hip := skel.find_bone("mixamorig_Hips")
	if hip < 0:
		print("FAIL: кость mixamorig_Hips не найдена")
		quit(1)
		return

	var spring = player.get_node_or_null("SpringArm3D")
	if spring != null:
		print("SpringArm position: %s (плечевой сдвиг X=%.2f → персонаж СЛЕВА на экране)" % [
				spring.position, spring.position.x])

	var n_min := Vector2(1e9, 1e9)
	var n_max := Vector2(-1e9, -1e9)
	var origin_xz := Vector2(player.global_position.x, player.global_position.z)
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1200000:
		var gp: Transform3D = skel.global_transform * skel.get_bone_global_pose(hip)
		var xz := Vector2(gp.origin.x, gp.origin.z)
		n_min = Vector2(minf(n_min.x, xz.x), minf(n_min.y, xz.y))
		n_max = Vector2(maxf(n_max.x, xz.x), maxf(n_max.y, xz.y))
		await process_frame

	var cx := (n_min.x + n_max.x) * 0.5 - origin_xz.x
	var cy := (n_min.y + n_max.y) * 0.5 - origin_xz.y
	print("Hips X/Z дрейф за 1.2 с Idle: X [%.3f..%.3f] Z [%.3f..%.3f] (размах %.1f × %.1f см)" % [
			n_min.x - origin_xz.x, n_max.x - origin_xz.x,
			n_min.y - origin_xz.y, n_max.y - origin_xz.y,
			(n_max.x - n_min.x) * 100.0, (n_max.y - n_min.y) * 100.0])
	print("Центр дрейфа Hips vs origin тела: X%+.3f Z%+.3f м" % [cx, cy])
	var mid_y: float = (skel.global_transform * skel.get_bone_global_pose(hip)).origin.y
	print("Hips Y в покое: %.2f м (купольная база player.y+0.95)" % mid_y)

	if absf(cx) < 0.15 and absf(cy) < 0.15:
		print("BARRIER CENTER PASS: купол центрируется по телу (смещение < 15 см)")
		quit(0)
	else:
		print("BARRIER CENTER FAIL: устойчивое смещение > 15 см — копать")
		quit(1)
