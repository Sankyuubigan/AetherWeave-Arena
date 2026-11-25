extends SkeletonModifier3D
class_name HandPoseModifier3D
const HPL = preload("res://Graphics/HandPoseLibrary.gd")
## Позы пальцев поверх анимации (вердикт спеца 23.11.26).
## Аддитивный сгиб вокруг локальной оси каждой фаланги (seg1→curl.x,
## seg2→curl.y, seg3→curl.z). Вес/preset ведёт PlayerAnimationComponent
## (SkillDB.hand_pose): вес 0 = клип с родными пальцами (Mixamo) — не трогаем;
## вес 1 = нейро/UAL-клип без пальцев — накладываем пресет.
## SkeletonModifier3D применяется ПОСЛЕ всей анимации.

var anim_comp: Node = null   # PlayerAnimationComponent (вес/preset)
var weight: float = 0.0      # 0 = не трогать, 1 = пресет
var preset: String = "RELAXED"

var _bones: Array = []       # [ [idx, seg, finger], ... ] на 30 фаланг

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for side in ["Left", "Right"]:
		for finger in HPL.FINGERS:
			for seg in [1, 2, 3]:
				var idx := skel.find_bone(HPL.bone_name(side, finger, seg))
				if idx >= 0:
					_bones.append([idx, seg, finger])

func _process_modification_with_delta(_delta: float) -> void:
	if weight <= 0.001 or _bones.is_empty():
		return
	var skel := get_skeleton()
	if skel == null:
		return
	for b in _bones:
		var idx: int = b[0]
		var seg: int = b[1]
		var finger: String = b[2]
		var curl := HPL.curl_for(preset, finger)  # Vector3 deg
		var deg: float = curl.x if seg == 1 else (curl.y if seg == 2 else curl.z)
		var q: Quaternion = skel.get_bone_pose_rotation(idx)
		q = q * Quaternion(Vector3(1, 0, 0), deg_to_rad(deg) * weight)
		skel.set_bone_pose_rotation(idx, q.normalized())