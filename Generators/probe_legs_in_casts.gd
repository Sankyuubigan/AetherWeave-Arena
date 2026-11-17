extends SceneTree
## Зонд: сколько движения НОГ в каждом каст-клипе — что потеряет «всегда UB»
## при кастовании стоя. Максим угол ротации каждой ноги-кости от rest
## (в градусах) + вертикальный ход Hips (метры).
## Запуск: --headless -s res://Generators/probe_legs_in_casts.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"

const LEG_BONES := [
	"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
	"mixamorig_LeftLeg", "mixamorig_RightLeg",
	"mixamorig_LeftFoot", "mixamorig_RightFoot",
	"mixamorig_LeftToeBase", "mixamorig_RightToeBase",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	var skel: Skeleton3D = _find_skeleton(player)
	if skel == null:
		print("PROBE FAIL: нет скелета")
		quit(1)
		return

	for anim_name in lib.get_animation_list():
		var anim: Animation = lib.get_animation(anim_name)
		var max_leg_deg := 0.0
		var worst_leg := ""
		var hips_dy := 0.0
		var hips_hz := 0.0
		for i in anim.get_track_count():
			var t := anim.track_get_type(i)
			var path := String(anim.track_get_path(i))
			var bone := path.substr(path.rfind(":") + 1)
			if bone == "mixamorig_Hips" and t == Animation.TYPE_POSITION_3D:
				var y0: float = anim.track_get_key_value(i, 0).y
				for k in anim.track_get_key_count(i):
					var v: Vector3 = anim.track_get_key_value(i, k)
					hips_dy = maxf(hips_dy, absf(v.y - y0))
					hips_hz = maxf(hips_hz, Vector2(v.x, v.z).length())
			elif bone in LEG_BONES and t == Animation.TYPE_ROTATION_3D:
				var bi := skel.find_bone(bone)
				var q0: Quaternion = anim.track_get_key_value(i, 0)
				for k in anim.track_get_key_count(i):
					var q: Quaternion = anim.track_get_key_value(i, k)
					var deg := rad_to_deg(absf(q.angle_to(q0)))
					if deg > max_leg_deg:
						max_leg_deg = deg
						worst_leg = bone.trim_prefix("mixamorig_")
		print("PROBE %s: ноги макс %.1f° (%s), Hips Y ±%.3f м, Hips гориз ±%.3f м" % [
			anim_name, max_leg_deg, worst_leg, hips_dy, hips_hz])
	quit(0)

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
