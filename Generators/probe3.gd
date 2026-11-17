extends SceneTree
## Зонд #3: mannequin — POSE(t=0 Spell_Simple_Enter) vs его же BIND REST,
## по мапнутым костям. Если углы большие — bind не совпадает с нейтралью
## анимаций, и референсом должен быть кадр t=0, а не bind.

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const MAP := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l",
	"thigh_r", "calf_r", "foot_r", "ball_r"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(UAL1.get_base_dir())
	var err = fbx_doc.append_from_file(UAL1, state)
	if err != OK:
		print("P3 FAIL FBX")
		quit(1)
		return
	var root_node = fbx_doc.generate_scene(state)
	var skel: Skeleton3D = find_skel(root_node)
	var ap: AnimationPlayer = find_ap(root_node)
	var anim_name := ""
	for n in ap.get_animation_list():
		if String(n).ends_with("Spell_Simple_Enter"):
			anim_name = n
	ap.play(anim_name)
	ap.seek(0.0, true)
	await process_frame
	var worst: Array = []
	for bn in MAP:
		var i := skel.find_bone(bn)
		if i < 0:
			print("P3: нет кости ", bn)
			continue
		var qp: Quaternion = skel.get_bone_global_pose(i).basis.get_rotation_quaternion()
		var qr: Quaternion = skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
		worst.append([rad_to_deg(qp.angle_to(qr)), bn])
	worst.sort()
	worst.reverse()
	print("P3: UAL pose(t=0) vs bind-rest, худшие:")
	for w in worst:
		print("   %.2f°  %s" % [w[0], w[1]])
	quit(0)

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
