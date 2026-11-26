extends SceneTree
## ГЕЙТ «перс смотрит в сторону прицела» (баг 26.11.26, разворот в камеру).
## Прежний probe_cast_facing проверял только ДАННЫЕ (yaw таза в клипах) и кламп —
## и был зелёным, пока баг жил в коде: мировой yaw писался в ЛОКАЛЬНЫЙ rotation.y
## обёртки, ошибка = yaw тела. Этот гейт проверяет РЕЗУЛЬТАТ глазами скелета:
## куда смотрят НОСКИ после face_aim_target при разном повороте тела.
##
## Проверки:
##  1) тело yaw=0, цель впереди (−Z) → носки в −Z (допуск 15°);
##  2) тело yaw=+90°, цель в −X → носки в −X (ошибка осей давала +Z);
##  3) тело yaw=+180°, цель в +Z → носки в +Z;
##  4) цель ЗА спиной (тело 0, цель +Z) → кламп ±100°, НЕ разворот на 180°;
##  5) камера наклонена вниз (pitch −60°) — направление прицела всё равно вперёд,
##     а не в пол под ногами (probe_aim_repro: точка была в 0.9 м).
## Запуск: --headless -s res://Generators/probe_cast_facing.gd  (EXIT=0 = PASS)

const PLAYER_SCENE := "res://Scenes/player.tscn"
const CAST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const MAX_DEG := 8.0
## Наклон таза от rest, выше которого поза считается «не вертикальной» (полёт,
## вис): там twist вокруг мировой вертикали не определён, клип судит зрительный чек.
const TILT_MAX_DEG := 45.0
## Допуск «смотрит туда» по носкам (данные клипа дают до 7° косой постановки стоп).
const AIM_TOL_DEG := 20.0
## Предел доворота к прицелу — зеркало PlayerController.CAST_FACING_MAX_DEG.
const CAST_MAX_DEG := 150.0

var player: Node3D
var wrapper: Node3D
var skel: Skeleton3D
var hips := -1
var fails: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await process_frame
	wrapper = player.get_node_or_null("GraphicsWrapper")
	skel = _find_skel(player)
	if wrapper == null or skel == null:
		print("FACING FAIL: нет GraphicsWrapper/Skeleton3D")
		quit(1)
		return
	hips = skel.find_bone("mixamorig_Hips")
	if hips < 0:
		print("FACING FAIL: нет кости mixamorig_Hips")
		quit(1)
		return

	# ── 1) ДАННЫЕ: yaw таза в full-body клипах ──────────────────
	print("=== 1) разворот таза по full-body каст-клипам (стоя) ===")
	var lib = load(CAST_LIB)
	print("  метрика: swing-twist дельты rest→клип ВОКРУГ МИРОВОЙ ВЕРТИКАЛИ.")
	var names: Array[String] = []
	for an in lib.get_animation_list():
		var n := String(an)
		if not n.ends_with("_UB"):
			names.append(n)
	var skipped: Array[String] = []
	for n in names:
		wrapper.rotation.y = 0.0
		await process_frame
		var comp = player.get_node_or_null("PlayerAnimationComponent")
		comp.play_cast_anim(n)
		for i in 6:
			await process_frame
		var delta := _hips_twist_deg()
		var tilt := _hips_tilt_deg()
		if tilt > TILT_MAX_DEG:
			skipped.append("%s (наклон %.0f°)" % [n, tilt])
			print("  %-20s SKIP: поза не вертикальная (наклон=%.0f°) — зрительный чек" % [n, tilt])
			continue
		var ok := absf(delta) <= MAX_DEG
		if not ok:
			fails.append("%s: таз ушёл на %+.1f°" % [n, delta])
		print("  %-20s twist=%+6.1f° наклон=%.0f° %s" % [
			n, delta, tilt, "OK" if ok else "FAIL"])
	if not skipped.is_empty():
		print("  пропущено (не вертикальные позы): ", ", ".join(skipped))

	# ── 2) РЕЗУЛЬТАТ: куда смотрит тело после face_aim_target ────
	print("")
	print("=== 2) face_aim_target: носки против направления на цель ===")
	# ВАЖНО: тест 1 оставляет скелет в позе последнего клипа (Wings_Fly — плашмя),
	# поэтому носки мерили бы позу полёта. Берём СВЕЖИЙ инстанс игрока: он в Idle.
	var aim_player = load(PLAYER_SCENE).instantiate()
	root.add_child(aim_player)
	aim_player.global_position = Vector3(0, 1.0, 0)
	for i in 20:
		await physics_frame
	var aim_wrapper = aim_player.get_node_or_null("GraphicsWrapper")
	var aim_skel := _find_skel(aim_player)
	# Соглашение (доказано probe_model_forward): yaw обёртки = atan2(dir.x, dir.z)
	# ставит носки В направление dir. body.yaw=0 → модель смотрит в +Z (в камеру),
	# поэтому в игре стартовый yaw = π (PlayerController._ready).
	var cases := [
		[PI, Vector3(0, 0, -30), "−Z"],
		[PI / 2.0, Vector3(-30, 0, 0), "−X"],
		[0.0, Vector3(0, 0, 30), "+Z"],
		[-PI / 2.0, Vector3(30, 0, 0), "+X"],
	]
	for c in cases:
		var body_yaw: float = c[0]
		var offset: Vector3 = c[1]
		var want: String = c[2]
		aim_player.rotation.y = body_yaw
		# стартуем «как в игре»: обёртка смотрит от камеры (−Z в мире)
		var start_local := wrapf(PI - body_yaw, -PI, PI)
		aim_wrapper.rotation.y = start_local
		await physics_frame
		var target: Vector3 = aim_player.global_position + offset
		var want_yaw := atan2(offset.x, offset.z)
		# Ожидаемая ошибка = сколько кламп НЕ даёт довернуть (цель за спиной).
		var need := absf(rad_to_deg(wrapf(want_yaw - (body_yaw + start_local), -PI, PI)))
		var expect_err := maxf(0.0, need - CAST_MAX_DEG)
		aim_player.face_aim_target(target, 2.0)
		for i in 40:
			await physics_frame
		var toe := _toe_of(aim_skel)
		var err := absf(rad_to_deg(wrapf(atan2(toe.x, toe.z) - want_yaw, -PI, PI)))
		# Угол до цели мал → ошибка мерится напрямую; цель за спиной → ожидаем
		# ровно недобор клампа (а не точное попадание).
		var ok := absf(err - expect_err) <= AIM_TOL_DEG
		if not ok:
			fails.append("тело %.0f°, цель %s: носки мимо на %.0f° (ждали %.0f°)" % [
				rad_to_deg(body_yaw), want, err, expect_err])
		print("  тело %+4.0f°, цель %-3s (нужно %3.0f°) → ошибка %5.1f°, ждали %4.1f° %s" % [
			rad_to_deg(body_yaw), want, need, err, expect_err,
			"OK" if ok else "FAIL (смотрит мимо)"])
	aim_player.queue_free()

	# ── 3) кламп: цель ЗА спиной не закручивает на месте ────────
	print("")
	print("=== 3) цель за спиной → кламп доворота (предел %d°) ===" % int(CAST_MAX_DEG))
	player.rotation.y = 0.0
	wrapper.rotation.y = PI          # как в игре: спиной к камере
	await physics_frame
	var before3 := _toe_forward()
	player.face_aim_target(player.global_position + Vector3(0, 0, 30), 2.0)
	for i in 40:
		await physics_frame
	var after3 := _toe_forward()
	var turned3 := absf(rad_to_deg(wrapf(
			atan2(after3.x, after3.z) - atan2(before3.x, before3.z), -PI, PI)))
	if turned3 > CAST_MAX_DEG + 12.0:
		fails.append("цель за спиной: доворот %.1f° (предел %.0f°)" % [turned3, CAST_MAX_DEG])
	else:
		print("  цель за спиной → доворот %.1f° ≤ %d° OK" % [turned3, int(CAST_MAX_DEG)])

	# ── 4) стартовая поза: игра начинается СПИНОЙ к камере ──────
	print("")
	print("=== 4) стартовая ориентация (PlayerController._ready ставит π) ===")
	var fresh = load(PLAYER_SCENE).instantiate()
	root.add_child(fresh)
	for i in 20:
		await physics_frame
	var fresh_wrapper = fresh.get_node_or_null("GraphicsWrapper")
	var fresh_skel := _find_skel(fresh)
	if fresh_wrapper == null or fresh_skel == null:
		fails.append("стартовая поза: нет узлов")
	else:
		var toe0 := _toe_of(fresh_skel)
		var ok0 := toe0.z < -0.5
		if not ok0:
			fails.append("старт: носки в %s — перс смотрит В КАМЕРУ" % toe0)
		print("  свежий игрок: wrapper.yaw=%+.0f°, носки %s => %s %s" % [
			rad_to_deg(fresh_wrapper.rotation.y), toe0.snapped(Vector3(0.01,0.01,0.01)),
			"спиной к камере (OK)" if ok0 else "ЛИЦОМ в камеру (БАГ)", ""])
	fresh.queue_free()

	# ── 5) наклон камеры вниз не уводит прицел в пол ────────────
	print("")
	print("=== 5) наклон камеры вниз: направление прицела остаётся вперёд ===")
	player.rotation.y = 0.0
	wrapper.rotation.y = PI   # спиной к камере, как после бега «вперёд»
	var sc = player.get_node_or_null("SpellCasterComponent")
	if sc == null:
		fails.append("нет SpellCasterComponent")
	else:
		for pitch_deg in [-15.0, -40.0, -60.0, -75.0]:
			player._cam_pitch = deg_to_rad(pitch_deg)
			for i in 4:
				await physics_frame
			var aim: Vector3 = sc._aim_dir_point(player, 30.0)
			var d: Vector3 = aim - player.global_position
			d.y = 0.0
			# при body yaw 0 «вперёд» камеры = −Z; прицел обязан быть в −Z
			var ok: bool = d.length() > 5.0 and d.z < -0.9 * d.length()
			if not ok:
				fails.append("pitch %.0f°: прицел ушёл в (%.1f,%.1f,%.1f)" % [
					pitch_deg, d.x, d.y, d.z])
			print("  pitch %+4.0f° → прицел (%.1f,%.1f,%.1f), |d|=%.1f м %s" % [
				pitch_deg, d.x, d.y, d.z, d.length(), "OK" if ok else "FAIL"])

	if fails.is_empty():
		print("")
		print("FACING: ALL PASS")
		quit(0)
	else:
		print("")
		print("FACING FAIL: ", "; ".join(fails))
		quit(1)

## Разворот таза вокруг МИРОВОЙ вертикали: swing-twist дельты rest→текущая поза.
func _hips_twist_deg() -> float:
	var rest_g := skel.get_bone_global_rest(hips).basis.get_rotation_quaternion()
	var cur_g := skel.get_bone_global_pose(hips).basis.get_rotation_quaternion()
	var q := (rest_g.inverse() * cur_g).normalized()
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * atan2(q.y, q.w))

## Наклон таза от rest (градусы) — контекст: >45° = поза не вертикальная
## (полёт/лежачая), там «лицом куда» вопрос бессмысленный.
func _hips_tilt_deg() -> float:
	var rest_g := skel.get_bone_global_rest(hips).basis.get_rotation_quaternion()
	var cur_g := skel.get_bone_global_pose(hips).basis.get_rotation_quaternion()
	var q := (rest_g.inverse() * cur_g).normalized()
	if q.w < 0.0:
		q = -q
	var twist := Vector3(0.0, q.y, 0.0)
	if twist.length() > 0.0001:
		twist = twist.normalized()
		var tw_q := Quaternion(twist, 2.0 * atan2(Vector3(0.0, q.y, 0.0).length(), q.w))
		var swing := (q * tw_q.inverse()).normalized()
		return rad_to_deg(absf(swing.get_angle()))
	return rad_to_deg(absf(q.get_angle()))

## Горизонтальное направление носков в МИРОВЫХ осях (Toe − Foot).
func _toe_forward() -> Vector3:
	return _toe_of(skel)

func _toe_of(s: Skeleton3D) -> Vector3:
	var v := Vector3.ZERO
	var n := 0
	for side in ["Left", "Right"]:
		var f := s.find_bone("mixamorig_%sFoot" % side)
		var t := s.find_bone("mixamorig_%sToeBase" % side)
		if f < 0 or t < 0:
			continue
		var fp: Vector3 = s.global_transform * s.get_bone_global_pose(f).origin
		var tp: Vector3 = s.global_transform * s.get_bone_global_pose(t).origin
		var d := tp - fp
		d.y = 0.0
		if d.length() > 0.01:
			v += d.normalized()
			n += 1
	if n == 0:
		return Vector3.ZERO
	return (v / float(n)).normalized()

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
