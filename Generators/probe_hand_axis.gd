extends SceneTree
## ДИАГНОЗ (26.11.26, жалоба юзера): куда реально идёт кисть в каст-клипе.
## Повод: probe_hand_extent.gd мерил «вперёд» как −Z со ссылкой на старый
## (опровергнутый) вывод «модель смотрит в −Z». Модель Mixamo при yaw=0 смотрит
## в +Z (docs/cast_pipeline.md §7.1, probe_model_forward.gd) ⇒ все прошлые
## замеры выноса были ЗЕРКАЛЬНЫ, и вывод «бросает левая» мог быть инвертирован.
##
## Меряем в ПРОСТРАНСТВЕ СКЕЛЕТА (= пространство модели, скрипты сняты):
##   z > 0 — вперёд (модель смотрит в +Z), x — в сторону, y — вверх.
## Для каждого клипа: пик выноса ВПЕРЁД по каждой кисти + боковой размах.
## Запуск: --headless -s res://Generators/probe_hand_axis.gd -- <клип>...

const LIB := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const FPS := 30.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var quiet := args.has("--quiet")
	var all := args.has("--all")
	var names: Array = []
	for a in args:
		var s := String(a)
		if s != "--quiet" and s != "--all":
			names.append(a)
	if names.is_empty() and not all:
		names = ["Cast_1H_Magic_01", "Spell_Cast", "Spell_Cast_L"]
	var player: Node = load(PLAYER_SCENE).instantiate()
	_strip(player)
	root.add_child(player)
	await process_frame
	var skel := _skel(player)
	var lib = load(LIB)
	var ap := AnimationPlayer.new()
	skel.get_parent().add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())
	ap.add_animation_library("", lib)
	if all:
		names = []
		for an in lib.get_animation_list():
			var s := String(an)
			if s.ends_with("_UB"):
				continue
			names.append(s)
		names.sort()

	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	var origin: Vector3 = skel.get_bone_global_pose(ci).origin

	for n in names:
		var name := String(n)
		if not lib.has_animation(name):
			print("AXIS: нет клипа ", name)
			continue
		var a: Animation = lib.get_animation(name)
		print("=== %s (%.2fс) ===" % [name, a.length])
		var best_r := -1e9
		var best_r_t := 0.0
		var best_l := -1e9
		var best_l_t := 0.0
		var max_side := 0.0
		var min_side := 0.0
		var t := 0.0
		var rows: Array[String] = []
		while t <= a.length + 0.0001:
			ap.stop()
			ap.play(name)
			ap.seek(t, true)
			skel.force_update_all_bone_transforms()
			var pr: Vector3 = skel.get_bone_global_pose(ri).origin - origin
			var pl: Vector3 = skel.get_bone_global_pose(li).origin - origin
			# +Z = вперёд (модель смотрит в +Z)
			if pr.z > best_r:
				best_r = pr.z
				best_r_t = t
			if pl.z > best_l:
				best_l = pl.z
				best_l_t = t
			max_side = maxf(max_side, maxf(absf(pr.x), absf(pl.x)))
			# Левый край экрана — это −X модели или +X? Меряем отдельно.
			min_side = minf(min_side, minf(pr.x, pl.x))
			if not quiet and fmod(t, 0.2) < 1.0 / FPS:
				rows.append("  t=%.2f  ПРАВАЯ z=%+.2f x=%+.2f y=%+.2f | ЛЕВАЯ z=%+.2f x=%+.2f y=%+.2f" % [
					t, pr.z, pr.x, pr.y, pl.z, pl.x, pl.y])
			t += 1.0 / FPS
		for r in rows:
			print(r)
		if quiet:
			print("%-24s %.2fс | правая пик z=%+.2f (t=%.2f) | левая пик z=%+.2f (t=%.2f) | |x|max=%.2f" % [
				name, a.length, best_r, best_r_t, best_l, best_l_t, max_side])
			continue
		print("  ПИК ВПЕРЁД: правая z=%+.3f на t=%.2f | левая z=%+.3f на t=%.2f" % [
			best_r, best_r_t, best_l, best_l_t])
		print("  макс |x| кисти = %.2f м  → %s" % [max_side,
			"ВБОК (рука уходит в сторону)" if max_side > maxf(best_r, best_l) else "вперёд"])
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
