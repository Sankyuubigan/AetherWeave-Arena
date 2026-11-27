extends SceneTree
## ГЕЙТ: «жест каста выносит руку ВПЕРЁД, и снаряд рождается из выброшенной руки».
##
## ПЕРЕПИСАН 27.11.26 (второй раз) — ПОЧЕМУ:
##   Прошлая версия «крутила время» счётчиком `elapsed += 1.0/FPS` на каждый
##   `await process_frame`. В headless дельта кадра НЕ равна 1/30 — цикл бежит
##   быстрее реального времени, AnimationPlayer не успевает продвинуться, и
##   замер читал почти НЕПОДВИЖНУЮ позу в начале клипа. У ВСЕХ клипов выходило
##   «кисть вбок», на этом вранье сердечко заменили двуручным Cast_2H_Push —
##   юзер увидел регресс («обе руки вытягивает, а надо по очереди»).
##
##   ПРАВИЛО ЗАМЕРА: время в клипе задаётся ТОЛЬКО `AnimationPlayer.seek(t, true)`
##   (прямая установка позиции, от кадров не зависит) + `force_update_all_bone_transforms()`.
##   Никаких счётчиков 1/FPS. Эталон — Generators/probe_hands_exact.gd.
##
##   ВТОРОЙ УРОК: при `alternate_hands` каст идёт ТО ПО ОДНОЙ, ТО ПО ДРУГОЙ руке.
##   Проверять «обе кисти вперёд» бессмысленно и вредно: жест одноручный, вторая
##   рука внизу — это норма. Гейт меряет ТУ руку, которой идёт каст, и ОБЯЗАН
##   прогнать ОБЕ фазы чередования (правую и левую), иначе половина кастов
##   остаётся непроверенной.
##
## ЧТО ПРОВЕРЯЕТ для каждого скилла с spawn_delay > 0:
##   1. клип cast_anim есть в каст-слое (has_cast_anim);
##   2. в момент spawn_delay КАСТУЮЩАЯ кисть впереди корпуса и не в стороне;
##      при alternate_hands — для БАЗОВОГО клипа (правая) и `<clip>_L` (левая);
##   3. окно отмены не открывается раньше заряда (формула — из кастера, не копия).
##
## Классификация: FAIL — клип вынос даёт, но задержка мимо; WARN — клип вообще
## не выносит руку вперёд (выбор клипа, решает юзер).
##
## Запуск: --headless -s res://Generators/probe_spawn_sync.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const SKILLDB := preload("res://Logic/Skills/SkillDB.gd")
## Формулу окна отмены НЕ дублируем — вызываем ту же функцию, что и игра.
const CASTER := preload("res://Logic/SpellCasterComponent.gd")
const MAX_SIDE_DEG := 45.0   # отклонение кисти от «вперёд» в горизонтали
const MIN_FWD := 0.25        # минимум выноса вперёд (м) — кисть реально впереди

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
	if comp == null or skel == null or comp.cast_player == null:
		fails.append("нет PlayerAnimationComponent/скелета/cast_player в " + PLAYER_SCENE)
		_finish()
		return
	var cp: AnimationPlayer = comp.cast_player
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
		var base_clip: String = sk.cast_anim
		var spd := maxf(0.01, float(sk.cast_speed))
		# spawn_delay задан в СЕКУНДАХ РЕАЛЬНОГО ВРЕМЕНИ (Skill.cast_speed),
		# а клип играет со speed_scale = spd ⇒ в координатах клипа это delay*spd.
		var clip_t := delay * spd
		# Фазы чередования: (клип, какая кисть кастует, метка)
		var phases: Array = [[base_clip, str(sk.cast_hand), "база"]]
		if bool(sk.alternate_hands):
			var mirrored: String = base_clip + "_L"
			if comp.has_cast_anim(mirrored):
				phases.append([mirrored, "Left" if str(sk.cast_hand) != "Left" else "Right", "чередование"])
			else:
				fails.append("%s: alternate_hands=true, но зеркала «%s» нет в каст-слое — чередование молча играет один клип" % [sid, mirrored])
		for ph in phases:
			var clip: String = String(ph[0])
			var use_r: bool = String(ph[1]) != "Left"
			var tag := "%-18s %-20s %-12s" % [sid, clip, String(ph[2])]
			if not comp.has_cast_anim(clip):
				fails.append("%s: клипа «%s» нет в каст-слое (has_cast_anim)" % [sid, clip])
				continue
			comp.play_cast_anim(clip, spd)
			var len: float = comp.cast_last_len()
			if len <= 0.0:
				fails.append("%s: cast_last_len=0 для «%s» — клип не играет" % [sid, clip])
				continue
			# ── ЗАМЕР: seek, а не счётчик кадров (см. шапку файла).
			# Клип идёт со speed_scale=spd, поэтому позиция клипа = delay*spd.
			var pos := clampf(clip_t, 0.0, maxf(len * spd - 0.001, 0.0))
			cp.seek(pos, true)
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
			var fwd: float = fr if use_r else fl
			var ang: float = ar if use_r else al
			var ok_pose: bool = fwd >= MIN_FWD and ang <= MAX_SIDE_DEG
			print("  %s t=%.2f  R fwd=%+.2f %3.0f° | L fwd=%+.2f %3.0f° | кастует %s %s" % [
				tag, delay, fr, ar, fl, al,
				"R" if use_r else "L", "OK" if ok_pose else "FAIL"])
			if not ok_pose:
				var best: float = _best_angle(comp, cp, skel, clip, spd, ci, ri, li, use_r)
				if best > MAX_SIDE_DEG:
					warns.append("%s: клип «%s» НЕ выносит %s кисть вперёд ни в одной позе (мин. откл %.0f°) — нужен другой клип (решение юзера)" % [
						sid, clip, "правую" if use_r else "левую", best])
				else:
					fails.append("%s: на spawn_delay=%.2f %s кисть в стороне (fwd=%+.2f < %.2f, откл %.0f° > %.0f°), хотя клип вынос даёт — задержка мимо пика" % [
						sid, delay, "правая" if use_r else "левая", fwd, MIN_FWD, ang, MAX_SIDE_DEG])
			cp.stop()

		# Инвариант отмены: окно не открывается раньше заряда (+ зазор).
		# Длину берём из каст-слоя (уже делится на темп ⇒ реальные секунды) —
		# ту же, что видит игра в _insta_len. Формулу НЕ дублируем: зовём
		# cancel_fraction кастера (расхождение двух формул уже ловили).
		comp.play_cast_anim(base_clip, spd)
		var insta_len: float = comp.cast_last_len()
		comp.cast_player.stop()
		var eff_cancel: float = CASTER.cancel_fraction(sk, insta_len)
		var need := clampf((delay + CASTER.SPAWN_GUARD) / maxf(insta_len, 0.001), 0.0, 1.0)
		print("      отмена: cancel_at=%.2f, заряд %.2f с из %.2f с → окно %.2f (нужно ≥%.2f)" % [
			clampf(float(sk.cancel_at), 0.0, 1.0), delay, insta_len, eff_cancel, need])
		if delay > insta_len + 0.0001:
			fails.append("%s: spawn_delay %.2f с БОЛЬШЕ длины клипа %.2f с — заряд не успевает" % [sid, delay, insta_len])
		elif eff_cancel < need - 0.0001:
			fails.append("%s: окно отмены %.2f МЕНЬШЕ заряда+зазор %.2f — спам перезапустит клип до спавна" % [
				sid, eff_cancel, need])

	print("=== проверено скиллов с зарядом: %d ===" % checked)
	_finish()

## Минимальное отклонение кастующей кисти от «вперёд» за весь клип: нужно
## отличить «клип вообще не выносит руку» (WARN) от «задержка мимо пика» (FAIL).
## Время — ТОЛЬКО через seek (шапка файла).
func _best_angle(comp, cp: AnimationPlayer, skel: Skeleton3D, clip: String,
		spd: float, ci: int, ri: int, li: int, use_r: bool) -> float:
	var best := 180.0
	comp.play_cast_anim(clip, spd)
	var len: float = comp.cast_last_len()
	if len <= 0.0:
		return best
	var raw := len * spd
	var steps := 24
	for i in steps + 1:
		cp.seek(raw * float(i) / float(steps), true)
		skel.force_update_all_bone_transforms()
		var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri if use_r else li).origin
		var fwd := -(p - c).z
		if fwd > 0.0:
			best = minf(best, rad_to_deg(atan2(absf((p - c).x), fwd)))
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
