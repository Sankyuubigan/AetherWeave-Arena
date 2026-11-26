extends SceneTree
## ГЕЙТ 26.11.26: «снаряд рождается из ВЫБРОШЕННОЙ руки, а не из позы в стороне».
##
## Ловит класс бага, на котором сгорели сердечки: spawn_delay скилла указывал на
## t, где кисть В СТОРОНЕ (откл 87° от «вперёд»), потому что прежний замер
## считал forward как −z (зеркально). Визуально юзер видел «руки влево/вправо
## вместо вперёд», и никакой существующий гейт этого не ловил.
##
## Для каждого скилла с эффектом spawn_delay > 0:
##   1. клип cast_anim есть в библиотеке;
##   2. в момент spawn_delay кисть cast_hand ВПЕРЕДИ корпуса и НЕ в стороне;
##   3. окно отмены не открывается раньше заряда (_cancel_at_of >= delay/len).
##
## Запуск: --headless -s res://Generators/probe_spawn_sync.gd

const LIB := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const SKILLDB := preload("res://Logic/Skills/SkillDB.gd")
## Формулу окна отмены НЕ дублируем — вызываем ту же функцию, что и игра.
const CASTER := preload("res://Logic/SpellCasterComponent.gd")
const MAX_SIDE_DEG := 45.0   # отклонение кисти от «вперёд» в горизонтали
const MIN_FWD := 0.25        # минимум z (м) — кисть реально впереди корпуса

var fails: Array[String] = []
var warns: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player: Node = load(PLAYER_SCENE).instantiate()
	_strip(player)
	root.add_child(player)
	await process_frame
	var skel := _skel(player)
	var lib = load(LIB)
	var ap := AnimationPlayer.new()
	skel.get_parent().add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())
	ap.add_animation_library("", lib)
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	if ri < 0 or li < 0:
		fails.append("скелет: не найдены кости кистей")
		_finish()
		return

	var all = SKILLDB.get_skills()
	var checked := 0
	for sid in all:
		var sk = all[sid]
		if sk.cast_time > 0.0 or sk.cast_anim == "":
			continue
		var delay := 0.0
		for eff in sk.effects:
			if "spawn_delay" in eff:
				delay = maxf(delay, float(eff.get("spawn_delay")))
		if delay <= 0.0:
			continue
		checked += 1
		var clip: String = sk.cast_anim
		if not lib.has_animation(clip):
			fails.append("%s: клипа «%s» нет в библиотеке" % [sid, clip])
			continue
		var a: Animation = lib.get_animation(clip)
		ap.stop()
		ap.play(clip)
		# spawn_delay задан в РЕАЛЬНОМ времени, а seek — в времени КЛИПА:
		# при cast_speed 2.0 клип за 0.67 с реальных успевает уйти на 1.34 с
		# (иначе гейт ложно валит фаербол — проверено 26.11.26).
		var spd := maxf(0.01, float(sk.cast_speed))
		ap.seek(clampf(delay * spd, 0.0, a.length), true)
		skel.force_update_all_bone_transforms()
		var pr: Vector3 = (skel.global_transform * skel.get_bone_global_pose(ri)).origin
		var pl: Vector3 = (skel.global_transform * skel.get_bone_global_pose(li)).origin
		var use_r: bool = str(sk.cast_hand) != "Left"
		var p: Vector3 = pr if use_r else pl
		var ang := rad_to_deg(atan2(absf(p.x), p.z))
		var ok_pose := p.z >= MIN_FWD and ang <= MAX_SIDE_DEG
		print("  %-18s %-16s t=%.2f/%.2f  %s x=%+.2f z=%+.2f откл=%.0f° %s" % [
			sid, clip, delay, a.length, "R" if use_r else "L",
			p.x, p.z, ang, "OK" if ok_pose else "FAIL"])
		if not ok_pose:
			# Клип вообще не выносит кисть вперёд (Cast_Shoot — кисть статично в
			# стороне): это выбор КЛИПА, а не сбитый spawn_delay. Такие случаи —
			# WARN (видно в списке, решение за юзером), FAIL — только когда клип
			# вынос даёт, но задержка указывает мимо него.
			var best_ang := _best_angle(ap, lib, clip, skel, ri, li, use_r)
			if best_ang > MAX_SIDE_DEG:
				warns.append("%s: клип «%s» НЕ выносит кисть вперёд ни в одной позе (мин. откл %.0f°) — снаряд из боковой кисти; нужен другой клип (решение юзера)" % [
					sid, clip, best_ang])
			else:
				fails.append("%s: на spawn_delay=%.2f кисть %s в стороне (z=%.2f < %.2f, откл %.0f° > %.0f°), хотя клип вынос даёт — задержка мимо пика" % [
					sid, delay, "R" if use_r else "L", p.z, MIN_FWD, ang, MAX_SIDE_DEG])

		# Инвариант отмены: окно не открывается раньше заряда (+ зазор).
		# Формулу НЕ дублируем — берём ту же функцию кастера (единственный
		# источник). Расхождение двух формул уже ловили на _zero_hips_yaw.
		var len: float = a.length / maxf(1.0, float(sk.cast_speed))
		var eff_cancel: float = CASTER.cancel_fraction(sk, len)
		var frac_delay := clampf(delay / len, 0.0, 1.0) if len > 0.0 else 0.0
		print("      отмена: skill.cancel_at=%.2f, заряд=%.2f (%.0f%% клипа) → окно %.2f (с зазором)" % [
			clampf(float(sk.cancel_at), 0.0, 1.0), delay, frac_delay * 100.0, eff_cancel])
		if frac_delay > 1.0 + 0.0001:
			fails.append("%s: spawn_delay %.2f с БОЛЬШЕ длины клипа %.2f с — заряд не успевает" % [sid, delay, len])
		var need := clampf((delay + CASTER.SPAWN_GUARD) / len, 0.0, 1.0) if len > 0.0 else 0.0
		if eff_cancel < need - 0.0001:
			fails.append("%s: окно отмены %.2f МЕНЬШЕ заряда+зазор %.2f — спам перезапустит клип до спавна" % [
				sid, eff_cancel, need])

	print("=== проверено скиллов с зарядом: %d ===" % checked)
	_finish()

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

## Минимальное отклонение кисти от «вперёд» за весь клип: нужно отличить
## «клип ВООБЩЕ не выносит руку вперёд» (выбор клипа, WARN) от «задержка
## указывает мимо пика» (баг данных, FAIL).
func _best_angle(ap: AnimationPlayer, lib, clip: String, skel: Skeleton3D,
		ri: int, li: int, use_r: bool) -> float:
	var a: Animation = lib.get_animation(clip)
	var best := 180.0
	var t := 0.0
	while t <= a.length + 0.0001:
		ap.play(clip)
		ap.seek(t, true)
		skel.force_update_all_bone_transforms()
		var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(ri if use_r else li)).origin
		if p.z > 0.0:
			best = minf(best, rad_to_deg(atan2(absf(p.x), p.z)))
		t += 0.05
	return best

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null

func _strip(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip(c)
