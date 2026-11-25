extends SkeletonModifier3D
class_name SkeletonLeanModifier
## Процедурные наклоны корпуса поверх анимации (вердикт спеца 23.11.26).
##   lean — наклон вперёд/назад: Spine/Spine1 по 50% вокруг модельного X
##          (+ = вперёд);
##   bank — крен в повороте вокруг модельного Z (+ = влево, в сторону
##          поворота);
##   dip  — микро-присед: сдвиг Hips вниз, метры.
## Величины ведёт PlayerAnimationComponent (пружины в _update_proc_deltas).
## SkeletonModifier3D применяется ПОСЛЕ всей анимации — поверх AnimationTree
## и CastPlayer, порядок гарантирован пайплайном модификаторов.
## Аддитив в модельном осях: ось переводится в пространство родителя кости
## (конъюгация через global-поворот родителя) — не зависит от rest-ориентации
## Mixamo-костей.

var anim_comp: Node = null  # PlayerAnimationComponent (пружины)

var _spine_i := -1
var _spine1_i := -1
var _hips_i := -1

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_spine_i = skel.find_bone("mixamorig_Spine")
	_spine1_i = skel.find_bone("mixamorig_Spine1")
	_hips_i = skel.find_bone("mixamorig_Hips")

func _process_modification_with_delta(_delta: float) -> void:
	if anim_comp == null:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var lean: float = anim_comp.lean_amount
	var bank: float = anim_comp.bank_amount
	var dip: float = anim_comp.dip_amount
	if absf(lean) < 0.0005 and absf(bank) < 0.0005 and dip < 0.0005:
		return
	# lean/bank: половина на Spine, половина на Spine1 (50/50, спец).
	for bone_i in [_spine_i, _spine1_i]:
		if bone_i < 0:
			continue
		var q: Quaternion = skel.get_bone_pose_rotation(bone_i)
		# Родитель Spine — Hips: его модельный поворот переводит аддитив
		# в его локаль (Godot: A*B = «сначала B»).
		var pg := _parent_global_rot(skel, bone_i)
		if absf(lean) >= 0.0005:
			q = pg.inverse() * Quaternion(Vector3(1, 0, 0), lean * 0.5) * pg * q
		if absf(bank) >= 0.0005:
			# +bank = крен влево → вокруг Z берём отрицательный угол
			# (положительный валит верх к -X).
			q = pg.inverse() * Quaternion(Vector3(0, 0, 1), -bank * 0.5) * pg * q
		skel.set_bone_pose_rotation(bone_i, q)
	if _hips_i >= 0 and dip >= 0.0005:
		var p := skel.get_bone_pose_position(_hips_i)
		p.y -= dip
		skel.set_bone_pose_position(_hips_i, p)

func _parent_global_rot(skel: Skeleton3D, bone_i: int) -> Quaternion:
	var par := skel.get_bone_parent(bone_i)
	if par < 0:
		return Quaternion.IDENTITY
	return skel.get_bone_global_pose(par).basis.get_rotation_quaternion()
