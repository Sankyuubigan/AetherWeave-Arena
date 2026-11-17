extends SceneTree
## Зонд ретаргета #2 (жалоба: «перекашивает как куклу»). Уточнение:
##  1) углы rest Idle.fbx vs rest СКИНА — только по 23 МАПНУТЫМ костям
##  2) инвариант конца-в-конец: Cast_Enter t=0 (mannequin rest) должен
##     давать на скине РОВНО rest-позу скина (углы ≈ 0)
##  3) мультисэмпл Cast_Enter/Pistol_Shoot 0.05..0.55 — нет ли скачков

const IDLE_FBX := "res://Graphics/Animations/raw/Idle.fbx"
const MAP_PAIRS := {
	"mixamorig_Hips": "pelvis", "mixamorig_Spine": "spine_01",
	"mixamorig_Spine1": "spine_02", "mixamorig_Spine2": "spine_03",
	"mixamorig_Neck": "neck_01", "mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "clavicle_l", "mixamorig_LeftArm": "upperarm_l",
	"mixamorig_LeftForeArm": "lowerarm_l", "mixamorig_LeftHand": "hand_l",
	"mixamorig_RightShoulder": "clavicle_r", "mixamorig_RightArm": "upperarm_r",
	"mixamorig_RightForeArm": "lowerarm_r", "mixamorig_RightHand": "hand_r",
	"mixamorig_LeftUpLeg": "thigh_l", "mixamorig_LeftLeg": "calf_l",
	"mixamorig_LeftFoot": "foot_l", "mixamorig_LeftToeBase": "ball_l",
	"mixamorig_RightUpLeg": "thigh_r", "mixamorig_RightLeg": "calf_r",
	"mixamorig_RightFoot": "foot_r", "mixamorig_RightToeBase": "ball_r",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var idle_root = load_fbx(IDLE_FBX)
	var idle_skel: Skeleton3D = find_skel(idle_root)

	var ps = load("res://Scenes/player.tscn")
	var player = ps.instantiate()
	root.add_child(player)
	await process_frame
	var pskel: Skeleton3D = find_skel(player)

	# ── 1. Rest-углы по мапнутым костям: Idle.fbx vs скин ────────────────
	var worst: Array = []  # [deg, name]
	for mix_name in MAP_PAIRS:
		var i1 := idle_skel.find_bone(mix_name)
		if i1 < 0:  # Idle.fbx хранит имена с префиксом mixamorig1_
			i1 = idle_skel.find_bone(mix_name.replace("mixamorig_", "mixamorig1_"))
		var i2 := pskel.find_bone(mix_name)
		if i1 < 0 or i2 < 0:
			print("PROBE2: нет кости ", mix_name)
			continue
		var q1: Quaternion = idle_skel.get_bone_global_rest(i1).basis.get_rotation_quaternion()
		var q2: Quaternion = pskel.get_bone_global_rest(i2).basis.get_rotation_quaternion()
		worst.append([rad_to_deg(q1.angle_to(q2)), mix_name])
	worst.sort()
	worst.reverse()
	print("PROBE2: rest IdleFBX vs SKIN по мапнутым (худшие 8):")
	for w in worst.slice(0, 8):
		print("   %.2f°  %s" % [w[0], w[1]])

	# ── 2. Инвариант: Cast_Enter t=0 → поза = rest скина? ────────────────
	var ap: AnimationPlayer = find_ap(player)
	ap.play("Cast_Enter")
	ap.seek(0.0, true)
	await process_frame
	var max_deg := 0.0
	var wname := ""
	for mix_name in MAP_PAIRS:
		var pi := pskel.find_bone(mix_name)
		var q_pose: Quaternion = pskel.get_bone_global_pose(pi).basis.get_rotation_quaternion()
		var q_rest: Quaternion = pskel.get_bone_global_rest(pi).basis.get_rotation_quaternion()
		var d: float = rad_to_deg(q_pose.angle_to(q_rest))
		if d > max_deg:
			max_deg = d
			wname = mix_name
	print("PROBE2: Cast_Enter t=0 vs rest СКИНА: max=%.2f° (%s)  [0° = идеал]" % [max_deg, wname])

	# ── 3. Мультисэмпл: нет ли скачков/вывихов по времени ────────────────
	for clip in ["Cast_Enter", "Pistol_Shoot", "Throw"]:
		ap.play(clip)
		var line := "PROBE2 [%s] RightHand/LeftHand/RightFoot rel Hips (y;x;z):" % clip
		for t in [0.05, 0.15, 0.25, 0.35, 0.45, 0.55]:
			if t > ap.get_animation(clip).length:
				break
			ap.seek(t, true)
			await process_frame
			var hips := pskel.find_bone("mixamorig_Hips")
			var hp := pskel.get_bone_global_pose(hips).origin
			var s := " |"
			for bn in ["RightHand", "LeftHand", "RightFoot"]:
				var v: Vector3 = pskel.get_bone_global_pose(pskel.find_bone("mixamorig_" + bn)).origin - hp
				s += " (%.2f;%.2f;%.2f)" % [v.y, v.x, v.z]
			line += "\n   t=%.2f%s" % [t, s]
		print(line)
	quit(0)

func load_fbx(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("PROBE2 FAIL: FBX err=", error_string(err))
		quit(1)
	return fbx_doc.generate_scene(state)

static func find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skel(c)
		if r:
			return r
	return null

static func find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_ap(c)
		if r:
			return r
	return null
