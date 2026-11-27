extends SceneTree
## ТОЧНЫЙ ЗАМЕР КИСТЕЙ ПО КЛИПУ (27.11.26) — детерминированный, через seek.
##
## ЗАЧЕМ ЭТОТ ФАЙЛ. Прежние замеры (`probe_heart_profile.gd`,
## `probe_spawn_sync.gd`) на каждом кадре прибавляли к «времени клипа» 1/FPS
## (или 2/FPS), но реальная прокрутка AnimationPlayer зависит от дельты кадра,
## а она в headless НЕ равна 1/30. Итог: колонка «t» в отчёте врала, замер
## читал почти НЕПОДВИЖНУЮ позу в начале клипа — у ВСЕХ клипов сразу выходило
## «кисти вбок». На этом вранье 27.11.26 сердечко заменили на двуручный
## Cast_2H_Push, хотя юзер просил ЧЕРЕДОВАНИЕ РУК (вердикт: «регресс, кривая»).
##
## ПРАВИЛО: время в клипе задаётся ТОЛЬКО `AnimationPlayer.seek(t, true)` —
## прямая установка позиции, от кадров не зависит. После seek обязателен
## `force_update_all_bone_transforms()`, иначе читаются старые позы.
##
## Запуск: --headless -s res://Generators/probe_hands_exact.gd -- <клип> [...]
## Выход: таблица: вынос кисти ВПЕРЁД (fwd, м) и отклонение ВБОК (бок, °).
## «Вперёд» = −Z мира (перс смотрит в −Z), «бок» = |x| относительно прицела.

const PLAYER_SCENE := "res://Scenes/player.tscn"
const SAMPLES := 11

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var names: Array = OS.get_cmdline_user_args()
	if names.is_empty():
		names = ["Spell_Cast", "Spell_Cast_L"]
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	player.rotation.y = 0.0
	var wrapper := player.get_node_or_null("GraphicsWrapper")
	if wrapper:
		wrapper.rotation.y = PI
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var skel := _skel(player)
	if comp == null or skel == null or comp.cast_player == null:
		print("HANDS FAIL: нет PlayerAnimationComponent/скелета/cast_player")
		quit(1)
		return
	var cp: AnimationPlayer = comp.cast_player
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	if ri < 0 or li < 0 or ci < 0:
		print("HANDS FAIL: нет костей кистей/Spine2")
		quit(1)
		return

	for n in names:
		var clip := String(n)
		if not comp.has_cast_anim(clip):
			print("%-18s НЕТ В КАСТ-СЛОЕ" % clip)
			continue
		comp.play_cast_anim(clip)
		var len: float = comp.cast_last_len()
		if len <= 0.0:
			len = cp.get_animation(clip).length if cp.has_animation(clip) else 0.0
		print("=== %s (%.2f с) ===" % [clip, len])
		print("   t   | R fwd   бок | L fwd   бок | впереди")
		var best_r := 0.0
		var best_l := 0.0
		var best_t := 0.0
		var best_lead := ""
		for i in SAMPLES:
			var t := len * float(i) / float(SAMPLES - 1)
			cp.seek(t, true)
			skel.force_update_all_bone_transforms()
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
			var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
			var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
			var fr := -(pr - c).z
			var fl := -(pl - c).z
			var ar := rad_to_deg(atan2(absf((pr - c).x), maxf(fr, 0.001)))
			var al := rad_to_deg(atan2(absf((pl - c).x), maxf(fl, 0.001)))
			var lead := "обе"
			if fr > fl + 0.05:
				lead = "ПРАВАЯ"
			elif fl > fr + 0.05:
				lead = "левая"
			if fr > best_r:
				best_r = fr
			if fl > best_l:
				best_l = fl
			print("  %.2f | %+5.2f %4.0f° | %+5.2f %4.0f° | %s" % [t, fr, ar, fl, al, lead])
			if maxf(fr, fl) > maxf(best_r, best_l) - 0.0001:
				best_t = t
				best_lead = lead
		print("  ЛУЧШИЙ ВЫНОС: R=%.2f L=%.2f на t≈%.2f (%s)" % [best_r, best_l, best_t, best_lead])
		cp.stop()
	quit(0)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null
