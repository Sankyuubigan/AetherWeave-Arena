extends SceneTree
## Диагностика (26.11.26): момент ВЫБРОСА руки в каст-клипе — для spawn_delay
## снаряда/сердечка. Меряем глобальную позицию кисти RightHand/LeftHand в позе
## клипа: forward-компонент (в системе скелета) и высоту. Пик forward = «рука
## выброшена», туда и ставим spawn_delay скилла.
## Запуск: --headless -s res://Generators/probe_hand_extent.gd -- <клип> [<клип>...]

const LIB := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const FPS := 30.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var names: Array = OS.get_cmdline_user_args()
	if names.is_empty():
		names = ["Spell_Cast"]
	var player: Node = load(PLAYER_SCENE).instantiate()
	_strip(player)
	root.add_child(player)
	await process_frame
	var skel := _skel(player)
	var lib = load(LIB)
	# Своя библиотека на отдельном AnimationPlayer: играем клип САМ, без логики.
	var ap := AnimationPlayer.new()
	skel.get_parent().add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())
	ap.add_animation_library("", lib)
	for n in names:
		var name := String(n)
		if not lib.has_animation(name):
			print("PROBE FAIL: нет клипа ", name)
			continue
		var a: Animation = lib.get_animation(name)
		ap.stop()
		ap.play(name)
		print("=== %s (%.2fс, %d треков) ===" % [name, a.length, a.get_track_count()])
		var ri := skel.find_bone("mixamorig_RightHand")
		var li := skel.find_bone("mixamorig_LeftHand")
		var best_r := -1e9
		var best_r_t := 0.0
		var best_l := -1e9
		var best_l_t := 0.0
		var t := 0.0
		while t <= a.length + 0.0001:
			ap.seek(t, true)
			skel.force_update_all_bone_transforms()
			var pr := (skel.global_transform * skel.get_bone_global_pose(ri)).origin
			var pl := (skel.global_transform * skel.get_bone_global_pose(li)).origin
			# «Вперёд» в системе скелета: ось +Z (модель Mixamo смотрит в +Z при
			# wrapper.rotation.y = 0 — docs/cast_pipeline.md §7.1, probe_model_forward).
			# ИСТОРИЯ: здесь стояло −pr.z со ссылкой на опровергнутый вывод «модель
			# смотрит в −Z» — все замеры выноса были ЗЕРКАЛЬНЫ, и решение по
			# фаерболу (cast_hand=Left) приняли наоборот (баг 26.11.26, жалоба юзера
			# «фаербол вылетает с руки, которая сзади»). Знак НЕ менять без замера.
			var fr := pr.z
			var fl := pl.z
			if fr > best_r:
				best_r = fr
				best_r_t = t
			if fl > best_l:
				best_l = fl
				best_l_t = t
			if fmod(t, 0.2) < 1.0 / FPS:
				print("  t=%.2f  правая fwd=%+.3f y=%.3f | левая fwd=%+.3f y=%.3f" % [t, fr, pr.y, fl, pl.y])
			t += 1.0 / FPS
		print("  ПИК: правая t=%.2f (fwd=%.3f) | левая t=%.2f (fwd=%.3f)" % [best_r_t, best_r, best_l_t, best_l])
	quit(0)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null

func _strip(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip(c)
