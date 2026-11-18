extends Node
## IK-доводка кастов (заказ юзера 18.11.26): двухкостная доводка руки
## (Arm→ForeArm→Hand) к точке прицела ПОВЕРХ UB-клипа на CastPlayer.
## SkeletonIK3D в 4.8-beta не применился (зонд: активен, кости резолвит,
## кисть 1.80→1.79 м и в headless, и с рендером) — решаем вручную: каждый
## кадр окна каста читаем анимированные позы, закон косинусов (2-bone IK),
## доворот кости от текущего направления к желаемому, slerp-бленд по влиянию.
## Порядок в дереве гарантирует «поверх»: AnimationPlayer'ы (GraphicsWrapper)
## пишут позы раньше, чем _process компонента (SpellCasterComponent позже).
## Окно каста: инста — длина UB-клипа; канал — cast_time + Cast_Shoot_UB.
## После окна влияние плавно → 0 — рука без рывка возвращается под контроль клипа.

const FADE_OUT := 0.15
const BEND_R := 1.0    # знак полюса изгиба локтя (право/лево зеркально)
const BEND_L := -1.0
const MIN_REACH := 0.1

var skeleton: Skeleton3D = null  # задаёт SpellCasterComponent до add_child
var _bones := {}       # side -> {arm, fore, hand} — индексы костей
var _targets := {}     # side -> Node3D-цель прицела
var _active_side := ""
var _provider := Callable()
var _w := 0.0          # влияние IK: 1 = полный довод
var _fade: Tween
var _window: Timer

func _ready() -> void:
	_window = Timer.new()
	_window.one_shot = true
	_window.timeout.connect(_finish)
	add_child(_window)
	if skeleton == null:
		set_process(false)
		return
	for side in ["Right", "Left"]:
		var arm_i := skeleton.find_bone("mixamorig_%sArm" % side)
		var fore_i := skeleton.find_bone("mixamorig_%sForeArm" % side)
		var hand_i := skeleton.find_bone("mixamorig_%sHand" % side)
		if arm_i < 0 or fore_i < 0 or hand_i < 0:
			continue
		_bones[side] = {"arm": arm_i, "fore": fore_i, "hand": hand_i}
		var t := Node3D.new()
		t.name = "CastIKTarget_" + side
		skeleton.add_child(t)
		_targets[side] = t

func _process(_delta: float) -> void:
	if skeleton == null or _active_side == "":
		return
	if _provider.is_valid():
		var t: Node3D = _targets.get(_active_side)
		if t:
			t.global_position = _provider.call()
	if _w > 0.0:
		_solve(_active_side, _w)

## Открыть окно доводки: side "Right"/"Left", aim_provider выдаёт точку прицела
## каждый кадр окна, duration — длина окна (0 = до end_now/повторного begin).
func begin(side: String, aim_provider: Callable, duration: float) -> void:
	if not _bones.has(side) or not aim_provider.is_valid():
		return
	_active_side = side
	_provider = aim_provider
	_kill_fade()
	_window.stop()
	_w = 1.0
	var t: Node3D = _targets[side]
	t.global_position = aim_provider.call()
	if duration > 0.0:
		_window.start(duration)

## Снятие IK сразу (тесты/форс-стоп), без фейда.
func end_now() -> void:
	_window.stop()
	_active_side = ""
	_w = 0.0

## Конец окна: плавный возврат руки под контроль клипа.
func _finish() -> void:
	if _active_side == "":
		return
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(self, "_w", 0.0, FADE_OUT)
	_fade.tween_callback(func() -> void: _active_side = "")

func _kill_fade() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
		_fade = null

## 2-bone IK: закон косинусов по текущим анимированным длинам, довороты костей
## от текущего направления «кость→ребёнок» к желаемому (позиции суставов — на
## месте, ведём только повороты; кисть остаётся под контролем клипа).
func _solve(side: String, w: float) -> void:
	var bi: Dictionary = _bones.get(side, {})
	if bi.is_empty():
		return
	var skel := skeleton
	var arm_i: int = bi.arm
	var fore_i: int = bi.fore
	var hand_i: int = bi.hand
	var sh: Vector3 = skel.get_bone_global_pose(arm_i).origin
	var el: Vector3 = skel.get_bone_global_pose(fore_i).origin
	var tgt: Vector3 = skel.global_transform.affine_inverse() * _targets[side].global_position
	var to_t := tgt - sh
	var d := to_t.length()
	if d < 0.05:
		return
	var dir := to_t / d
	var upper := (el - sh).length()
	var fore := (skel.get_bone_global_pose(hand_i).origin - el).length()
	var reach := clampf(d, MIN_REACH, (upper + fore) * 0.999)
	var a := (upper * upper + reach * reach - fore * fore) / (2.0 * reach)
	var h := sqrt(maxf(0.0, upper * upper - a * a))
	# Полюс изгиба: локоть ниже линии «плечо→цель» («пистолетная» рука).
	var pole := Vector3.DOWN
	if absf(dir.dot(Vector3.DOWN)) > 0.95:
		pole = Vector3.FORWARD
	var n := dir.cross(pole).normalized().cross(dir).normalized()
	var bend := BEND_R if side == "Right" else BEND_L
	var elbow := sh + dir * a + n * (h * bend)
	var hand := sh + dir * reach
	# Плечевая: текущее направление на локоть → (плечо→локоть IK).
	_bone_aim(skel, arm_i, el, elbow, w)
	# Локоть: get_bone_global_pose(hand) уже отражает решённое плечо.
	_bone_aim(skel, fore_i, skel.get_bone_global_pose(hand_i).origin, hand, w)

## Поворот кости: доворот от текущего направления «кость→ребёнок» к желаемому,
## записанный в локальную позу с slerp-блендом анимация→IK по w.
func _bone_aim(skel: Skeleton3D, bone_i: int, cur_child: Vector3, new_child: Vector3, w: float) -> void:
	var anim_q := skel.get_bone_pose_rotation(bone_i)
	var cur_basis := skel.get_bone_global_pose(bone_i)
	var cd := (cur_child - cur_basis.origin).normalized()
	var nd := (new_child - cur_basis.origin).normalized()
	if cd.length() < 0.01 or nd.length() < 0.01:
		return
	if cd.dot(nd) < -0.99:  # разворот на 180° — кватернион дуги вырождается
		return
	var q := Quaternion(cd, nd)
	var new_g_basis := Basis(q) * cur_basis.basis
	var parent_g := skel.get_bone_global_pose(skel.get_bone_parent(bone_i))
	var new_local := parent_g.affine_inverse() * Transform3D(new_g_basis, cur_basis.origin)
	var ik_q := new_local.basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(bone_i, anim_q.slerp(ik_q, w))
