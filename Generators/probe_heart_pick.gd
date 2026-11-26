extends SceneTree
## ВЫБОР КЛИПА СЕРДЕЧКА (26.11.26, жалоба юзера «руки то влево то вправо»).
## Меряем в МИРОВЫХ осях через РЕАЛЬНЫЙ путь воспроизведения
## (PlayerAnimationComponent.play_cast_anim — с aim-модификатором и UB-слоем),
## а не по сырому клипу: модификатор меняет позу, поэтому сырые замеры врут.
##
## Для каждого клипа:
##   peak_fwd  — максимальный вынос ЛЮБОЙ кисти вперёд от Spine2 (dot с aim)
##   peak_side — максимальный боковой вынос ЛЮБОЙ кисти (|x|)
##   ratio     — peak_fwd / peak_side: >1.5 = рука идёт вперёд, <1 = вбок
## Запуск: --headless -s res://Generators/probe_heart_pick.gd [-- --all | клип...]

const PLAYER_SCENE := "res://Scenes/player.tscn"
const FPS := 30.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var names: Array = []
	var all := args.has("--all")
	for a in args:
		if String(a) != "--all":
			names.append(String(a))
	if names.is_empty() and not all:
		names = ["Spell_Cast", "Pistol_Shoot", "Cast_Shoot", "Heart_Cast", "Throw"]
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	player.rotation.y = 0.0
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	wrapper.rotation.y = PI
	var skel := _skel(player)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if skel == null or comp == null:
		print("PICK FAIL: нет скелета/компонента")
		quit(1)
		return
	if all:
		names = []
		var lib: AnimationLibrary = load("res://Graphics/Animations/ual_casts_test.res")
		for an in lib.get_animation_list():
			var s := String(an)
			if s.ends_with("_UB"):
				continue
			names.append(s)
		names.sort()
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	var aim_dir := Vector3(0, 0, -1)   # камера смотрит в −Z
	print("aim_dir(мир)=(0,0,-1)  body.yaw=0  wrapper.yaw=π")
	print("%-24s %7s %7s %6s  %s" % ["клип", "fwd", "side", "ratio", "вердикт"])

	for n in names:
		var name := String(n)
		if not comp.has_cast_anim(name):
			print("%-24s  нет клипа" % name)
			continue
		comp.play_cast_anim(name)
		var len: float = comp.cast_last_len()
		var peak_fwd := -1e9
		var peak_fwd_t := 0.0
		var peak_side := 0.0
		var peak_side_t := 0.0
		var t := 0.0
		while t <= len + 0.0001:
			await process_frame
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
			var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
			var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
			for p in [pr, pl]:
				var d: Vector3 = p - c
				d.y = 0.0
				var f: float = d.dot(aim_dir)
				var s: float = absf(d.x)
				if f > peak_fwd:
					peak_fwd = f
					peak_fwd_t = t
				if s > peak_side:
					peak_side = s
					peak_side_t = t
			t += 1.0 / FPS
		var ratio := peak_fwd / maxf(peak_side, 0.001)
		var verdict := "ВПЕРЁД" if ratio >= 1.5 else ("спорно" if ratio >= 1.0 else "ВБОК")
		print("%-24s %+6.2f %6.2f %6.2f  %s  (fwd t=%.2f, side t=%.2f)" % [
			name, peak_fwd, peak_side, ratio, verdict, peak_fwd_t, peak_side_t])
	quit(0)

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null
