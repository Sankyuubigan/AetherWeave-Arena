extends SkeletonModifier3D
class_name AimSpineModifier
## Мягкий прицел позвоночником+головой к точке прицела (вердикт спеца 23.11.26,
## замена 2-bone IK на дальних кастах). Аддитивно в МОДЕЛЬНЫХ осях (конъюгация
## через global-поворот родителя) — сохраняет 100% анимации рук/локтей из клипа.
## pitch кламп ±45°, остаточный yaw ±35°. Распределение: Spine 25/25,
## Spine1 30/30, Spine2 30/30, Head 15/15 (pitch%/yaw%). Вес ведёт PCA
## (вход 0.08с / выход 0.20с). recoil — Spine2 назад 4–6° (пружина 0.15с).

const PITCH_MAX := 45.0
const YAW_MAX := 35.0
const DIST := {
	"mixamorig_Spine": [0.25, 0.25],
	"mixamorig_Spine1": [0.30, 0.30],
	"mixamorig_Spine2": [0.30, 0.30],
	"mixamorig_Head": [0.15, 0.15],
}

var anim_comp: Node = null   # PlayerAnimationComponent (aim_point/aim_weight/recoil)

func _process_modification_with_delta(_delta: float) -> void:
	if anim_comp == null:
		return
	var w: float = anim_comp.aim_weight
	if w <= 0.001:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var aim: Vector3 = anim_comp.aim_point
	# ОСИ (баг 26.11.26): aim_point МИРОВОЙ, а позы скелета — локальные.
	# atan2 по мировым осям давал ошибку ровно на yaw тела+обёртки: при повороте
	# камеры на 90° позвоночник «прицеливался» на 90° мимо (и добавлял скрутку).
	# Переводим точку в пространство скелета — дальше все оси уже локальные.
	aim = skel.global_transform.affine_inverse() * aim
	# Направление на цель в локальных осях скелета от Spine2.
	var s2 := skel.find_bone("mixamorig_Spine2")
	if s2 < 0:
		return
	var origin: Vector3 = skel.get_bone_global_pose(s2).origin
	var d := aim - origin
	if d.length() < 0.05:
		return
	d = d.normalized()
	var pitch := clampf(rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), -PITCH_MAX, PITCH_MAX)
	var yaw := clampf(rad_to_deg(atan2(d.x, d.z)), -YAW_MAX, YAW_MAX)
	var recoil: float = anim_comp.recoil_amount
	for bone in DIST:
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var pc: float = DIST[bone][0]
		var yc: float = DIST[bone][1]
		var q: Quaternion = skel.get_bone_pose_rotation(bi)
		var pg := _parent_global_rot(skel, bi)
		var delta := Quaternion.from_euler(Vector3(deg_to_rad(pitch * pc), deg_to_rad(yaw * yc), 0.0))
		q = pg.inverse() * delta * pg * q
		if bone == "mixamorig_Spine2" and recoil > 0.001:
			var rq := Quaternion(Vector3(1, 0, 0), deg_to_rad(-6.0) * recoil)
			q = pg.inverse() * rq * pg * q
		skel.set_bone_pose_rotation(bi, q.normalized())

func _parent_global_rot(skel: Skeleton3D, bone_i: int) -> Quaternion:
	var par := skel.get_bone_parent(bone_i)
	if par < 0:
		return Quaternion.IDENTITY
	return skel.get_bone_global_pose(par).basis.get_rotation_quaternion()