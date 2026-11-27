extends SceneTree
## ГЕЙТ: «жест каста выносит руки ВПЕРЁД, и снаряд рождается из выброшенной руки».
##
## ПЕРЕПИСАН 27.11.26 — ПОЧЕМУ (главный урок, не повторять):
##   Прежняя версия крутила СЫРУЮ библиотеку своим AnimationPlayer и мерила
##   мировые координаты кисти. Игра же играет каст другим путём:
##   PlayerAnimationComponent.play_cast_anim → CastAnimationLayer (CastPlayer,
##   full-body при стоянии / UB при беге, capture-блендинг) + AimSpineModifier
##   (прицел позвоночником меняет позу). Сырой замер давал 87° там, где реальный
##   путь давал 28° — гейт «проходил», а юзер видел руку в боку. Гейт, который
##   мерит не то, что видит игрок, ХУЖЕ отсутствия гейта: он даёт ложную уверенность.
##
##   Поэтому теперь поза берётся ТОЛЬКО через компонент игрока (play_cast_anim),
##   как в игре, а не через собственный AnimationPlayer.
##
## ЧТО ПРОВЕРЯЕТ для каждого скилла с spawn_delay > 0:
##   1. клип cast_anim есть в каст-слое (has_cast_anim);
##   2. в момент spawn_delay КАЖДАЯ кисть впереди корпуса и не в стороне —
##      меряем ОБЕ кисти отдельно (прежняя версия брала максимум по двум, из-за
##      чего «одна вперёд + вторая вбок» читалось как норма);
##   3. окно отмены не открывается раньше заряда (формула — из кастера, не копия).
##
## Классификация: FAIL — клип вынос даёт, но задержка мимо; WARN — клип вообще
## не выносит руки вперёд (выбор клипа, решает юзер).
##
## Запуск: --headless -s res://Generators/probe_spawn_sync.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const SKILLDB := preload("res://Logic/Skills/SkillDB.gd")
## Формулу окна отмены НЕ дублируем — вызываем ту же функцию, что и игра.
const CASTER := preload("res://Logic/SpellCasterComponent.gd")
const MAX_SIDE_DEG := 45.0   # отклонение кисти от «вперёд» в горизонтали
const MIN_FWD := 0.25        # минимум выноса вперёд (м) — кисть реально впереди
const FPS := 30.0

var fails: Array[String] = []
var warns: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	# Дать физике осесть: play_cast_anim выбирает full-body только при
	# hs<0.2 && is_on_floor — иначе меряем UB-клип, а не тот, что видит игрок.
	for i in 30:
		await physics_frame
	player.rotation.y = 0.0
	# Модель Mixamo смотрит в +Z при yaw 0; камера в игре СЗАДИ (смотрит в −Z),
	# поэтому wrapper.yaw = π — так же, как в probe_heart_pick/profile.
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	if wrapper:
		wrapper.rotation.y = PI
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var skel := _skel(player)
	if comp == null or skel == null:
		fails.append("нет PlayerAnimationComponent/скелета в " + PLAYER_SCENE)
		_finish()
		return
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	if ri < 0 or li < 0 or ci < 0:
		fails.append("скелет: не найдены кости кистей/Spine2")
		_finish()
		return

	var all = SKILLDB.get_skills()
	var checked := 0
	for sid in all:
		var sk = all[sid]
		if sk.cast_time > 0.0 or sk.cast_anim == "":
			continue
		var delay := CASTER.max_spawn_delay(sk)
		if delay <= 0.0:
			continue
		checked += 1
		var clip: String = sk.cast_anim
		if not comp.has_cast_anim(clip):
			fails.append("%s: клипа «%s» нет в каст-слое (has_cast_anim)" % [sid, clip])
			continue
		# Реальный путь: играем клип как игра и прокручиваем до spawn_delay.
		comp.play_cast_anim(clip)
		var len: float = comp.cast_last_len()
		var spd := maxf(0.01, float(sk.cast_speed))
		var target := clampf(delay, 0.0, len)
		var elapsed := 0.0
		while elapsed < target:
			await process_frame
			elapsed += 1.0 / FPS
		skel.force_update_all_bone_transforms()
		var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
		var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
		var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
		# forward в мире = −Z (камера игрока смотрит в −Z), кисть впереди,
		# если её проекция по −Z положительна ⇒ fwd = −d.z.
		var fr: float = -(pr - c).z
		var fl: float = -(pl - c).z
		var ar := rad_to_deg(atan2(absf((pr - c).x), maxf(fr, 0.001)))
		var al := rad_to_deg(atan2(absf((pl - c).x), maxf(fl, 0.001)))
		var use_r: bool = str(sk.cast_hand) != "Left"
		var fwd: float = fr if use_r else fl
		var ang: float = ar if use_r else al
		var ok_pose: bool = fwd >= MIN_FWD and ang <= MAX_SIDE_DEG
		print("  %-18s %-16s t=%.2f/%.2f  R fwd=%+.2f %3.0f° | L fwd=%+.2f %3.0f° | рука %s %s" % [
			sid, clip, delay, len, fr, ar, fl, al,
			"R" if use_r else "L", "OK" if ok_pose else "FAIL"])
		if not ok_pose:
			var best: float = await _best_angle(comp, skel, clip, ci, ri, li, use_r)
			if best > MAX_SIDE_DEG:
				warns.append("%s: клип «%s» НЕ выносит кисть вперёд ни в одной позе (мин. откл %.0f°) — нужен другой клип (решение юзера)" % [
					sid, clip, best])
			else:
				fails.append("%s: на spawn_delay=%.2f кисть %s в стороне (fwd=%+.2f < %.2f, откл %.0f° > %.0f°), хотя клип вынос даёт — задержка мимо пика" % [
					sid, delay, "R" if use_r else "L", fwd, MIN_FWD, ang, MAX_SIDE_DEG])

		# Инвариант отмены: окно не открывается раньше заряда (+ зазор).
		# Формулу НЕ дублируем — берём ту же функцию кастера (единственный
		# источник). Расхождение двух формул уже ловили на _zero_hips_yaw.
		var eff_cancel: float = CASTER.cancel_fraction(sk, len)
		var need := clampf((delay + CASTER.SPAWN_GUARD) / len, 0.0, 1.0) if len > 0.0 else 0.0
		print("      отмена: cancel_at=%.2f, заряд %.2f с → окно %.2f (нужно ≥%.2f)" % [
			clampf(float(sk.cancel_at), 0.0, 1.0), delay, eff_cancel, need])
		if delay > len + 0.0001:
			fails.append("%s: spawn_delay %.2f с БОЛЬШЕ длины клипа %.2f с — заряд не успевает" % [sid, delay, len])
		elif eff_cancel < need - 0.0001:
			fails.append("%s: окно отмены %.2f МЕНЬШЕ заряда+зазор %.2f — спам перезапустит клип до спавна" % [
				sid, eff_cancel, need])

	print("=== проверено скиллов с зарядом: %d ===" % checked)
	_finish()

## Минимальное отклонение кисти от «вперёд» за весь клип (через реальный путь):
## нужно отличить «клип вообще не выносит руку» (WARN) от «задержка мимо пика» (FAIL).
func _best_angle(comp, skel: Skeleton3D, clip: String, ci: int, ri: int, li: int,
		use_r: bool) -> float:
	var best := 180.0
	comp.play_cast_anim(clip)
	var len: float = comp.cast_last_len()
	var t := 0.0
	while t <= len + 0.0001:
		await process_frame
		skel.force_update_all_bone_transforms()
		var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri if use_r else li).origin
		var fwd := -(p - c).z
		if fwd > 0.0:
			best = minf(best, rad_to_deg(atan2(absf((p - c).x), fwd)))
		t += 1.0 / FPS
	return best

func _finish() -> void:
	for w in warns:
		print("SPAWN_SYNC WARN: ", w)
	if fails.is_empty():
		print("SPAWN_SYNC: ALL PASS (%d warn)" % warns.size())
		quit(0)
	else:
		for f in fails:
			print("SPAWN_SYNC FAIL: ", f)
		quit(1)

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
