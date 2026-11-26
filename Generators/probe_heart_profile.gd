extends SceneTree
## ПРОФИЛЬ (26.11.26): покадрово, КУДА идут ОБЕ кисти в мировых осях через
## реальный путь воспроизведения. Нужен, чтобы отличить два разных диагноза:
##   A) симметричный широкий жест — кисти ЗЕРКАЛЬНЫ (x одной +, другой −);
##   B) обе кисти уходят В ОДНУ СТОРОНУ — значит скрутка/поворот, а не жест.
## Плюс угол от направления прицела: 0° = строго вперёд, 90° = строго вбок.
## Запуск: --headless -s res://Generators/probe_heart_profile.gd -- <клип>

const PLAYER_SCENE := "res://Scenes/player.tscn"
const FPS := 30.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var names: Array = OS.get_cmdline_user_args()
	if names.is_empty():
		names = ["Spell_Cast"]
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	player.rotation.y = 0.0
	player.get_node_or_null("GraphicsWrapper").rotation.y = PI
	var skel := _skel(player)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	var aim_dir := Vector3(0, 0, -1)

	for n in names:
		var name := String(n)
		if not comp.has_cast_anim(name):
			print("нет клипа ", name)
			continue
		comp.play_cast_anim(name)
		var len: float = comp.cast_last_len()
		print("=== %s (%.2fс) ===" % [name, len])
		print("   t   | R: x     fwd    ang | L: x     fwd    ang | знак x")
		var t := 0.0
		while t <= len + 0.0001:
			await process_frame
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
			var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
			var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
			var dr: Vector3 = pr - c
			var dl: Vector3 = pl - c
			dr.y = 0.0
			dl.y = 0.0
			var fr: float = dr.dot(aim_dir)
			var fl: float = dl.dot(aim_dir)
			var ar: float = rad_to_deg(atan2(absf(dr.x), maxf(fr, 0.001)))
			var al: float = rad_to_deg(atan2(absf(dl.x), maxf(fl, 0.001)))
			var sgn := "ЗЕРКАЛО" if signf(dr.x) != signf(dl.x) else ("обе " + ("вправо" if dr.x > 0 else "влево"))
			print("  %.2f | %+5.2f %+6.2f %5.0f° | %+5.2f %+6.2f %5.0f° | %s" % [
				t, dr.x, fr, ar, dl.x, fl, al, sgn])
			t += 2.0 / FPS
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
