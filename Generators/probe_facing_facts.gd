extends SceneTree
## ДИАГНОСТ «куда реально смотрит персонаж» (баг «разворот в камеру», 26.11.26).
## Никаких предположений: печатаем МИРОВЫЕ направления.
##  1) где камера относительно тела и куда она смотрит;
##  2) куда смотрят НОСКИ (Toe - Foot) при wrapper.yaw = 0 — это и есть «вперёд»;
##  3) что делает face_aim_target(точка впереди/сзади): yaw обёртки и носки;
##  4) то же при повёрнутом теле (мышь) — ловим world↔local смешение.
## Запуск: --headless -s res://Generators/probe_facing_facts.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

var player: Node3D
var wrapper: Node3D
var skel: Skeleton3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	wrapper = player.get_node_or_null("GraphicsWrapper")
	skel = _find_skel(player)
	if wrapper == null or skel == null:
		print("FACTS FAIL: нет GraphicsWrapper/Skeleton3D")
		quit(1)
		return

	# ── 1) камера ───────────────────────────────────────────────
	var cam: Camera3D = player.get_node_or_null("SpringArm3D/Camera3D")
	var rel := cam.global_position - player.global_position
	var fwd := -cam.global_transform.basis.z
	print("=== 1) КАМЕРА ===")
	print("  камера относительно тела = ", rel.snapped(Vector3(0.01,0.01,0.01)),
		"  (|rel|=%.2f)" % rel.length())
	print("  куда смотрит камера (world) = ", fwd.snapped(Vector3(0.01,0.01,0.01)))
	print("  => камера ", "СЗАДИ (+Z)" if rel.z > 0.5 else ("СПЕРЕДИ (−Z)" if rel.z < -0.5 else "сбоку/сверху"))

	# ── 2) носки при wrapper.yaw = 0 ────────────────────────────
	print("")
	print("=== 2) «ВПЕРЁД» МОДЕЛИ при wrapper.yaw = 0 (по носкам) ===")
	wrapper.rotation.y = 0.0
	await physics_frame
	await physics_frame
	var toe := _toe_forward()
	print("  носки (Toe−Foot, горизонталь, world) = ", toe.snapped(Vector3(0.01,0.01,0.01)))
	print("  => модель при yaw=0 смотрит в ", _dir_name(toe))

	# ── 3) face_aim_target: цель ВПЕРЕДИ камеры (−Z) ────────────
	print("")
	print("=== 3) face_aim_target(цель на −Z, т.е. ПЕРЕД камерой) ===")
	wrapper.rotation.y = 0.0
	player.face_aim_target(player.global_position + Vector3(0, 0, -30), 1.0)
	for i in 30:
		await physics_frame
	var toe2 := _toe_forward()
	print("  wrapper.yaw = %+.1f°  носки = %s  => смотрит %s" % [
		rad_to_deg(wrapper.rotation.y), toe2.snapped(Vector3(0.01,0.01,0.01)), _dir_name(toe2)])
	print("  ОЖИДАНИЕ: смотрит на −Z (ОТ камеры, спиной к ней)")

	# ── 4) то же, но тело повёрнуто мышью на 90° ───────────────
	print("")
	print("=== 4) ТО ЖЕ, но тело повёрнуто мышью (body yaw = +90°) ===")
	player.rotation.y = PI / 2.0
	wrapper.rotation.y = 0.0
	await physics_frame
	# при body yaw 90° «вперёд» в мире = −X; цель ставим именно туда
	var target := player.global_position + Vector3(-30, 0, 0)
	player.face_aim_target(target, 1.0)
	for i in 30:
		await physics_frame
	var toe3 := _toe_forward()
	print("  wrapper.yaw(ЛОКАЛЬНЫЙ) = %+.1f°  body.yaw = %+.1f°" % [
		rad_to_deg(wrapper.rotation.y), rad_to_deg(player.rotation.y)])
	print("  носки(world) = %s  => смотрит %s" % [
		toe3.snapped(Vector3(0.01,0.01,0.01)), _dir_name(toe3)])
	print("  ОЖИДАНИЕ: смотрит на −X (в сторону цели)")

	# ── 5) тот же вопрос для кода ДВИЖЕНИЯ (W = local −Z) ──────
	print("")
	print("=== 5) движение: body yaw = 0, W (local −Z) → yaw = atan2(0,−1) = 180° ===")
	player.rotation.y = 0.0
	wrapper.rotation.y = PI
	await physics_frame
	await physics_frame
	var toe4 := _toe_forward()
	print("  носки = %s => бег «вперёд» смотрит %s" % [
		toe4.snapped(Vector3(0.01,0.01,0.01)), _dir_name(toe4)])
	print("  ОЖИДАНИЕ (видео юзера): спиной к камере, т.е. −Z")
	quit(0)

## Горизонтальное направление носков в мировых осях (Toe − Foot).
func _toe_forward() -> Vector3:
	var v := Vector3.ZERO
	var n := 0
	for side in ["Left", "Right"]:
		var f := skel.find_bone("mixamorig_%sFoot" % side)
		var t := skel.find_bone("mixamorig_%sToeBase" % side)
		if f < 0 or t < 0:
			continue
		var fp: Vector3 = skel.global_transform * skel.get_bone_global_pose(f).origin
		var tp: Vector3 = skel.global_transform * skel.get_bone_global_pose(t).origin
		var d := tp - fp
		d.y = 0.0
		if d.length() > 0.01:
			v += d.normalized()
			n += 1
	if n == 0:
		return Vector3.ZERO
	return (v / float(n)).normalized()

func _dir_name(d: Vector3) -> String:
	if d.length() < 0.01:
		return "?"
	var a := rad_to_deg(atan2(d.x, d.z))
	var names := ["+Z", "+X/+Z", "+X", "+X/−Z", "−Z", "−X/−Z", "−X", "−X/+Z"]
	var i := int(round(fposmod(a, 360.0) / 45.0)) % 8
	return "%s (yaw %+.0f°)" % [names[i], a]

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null
