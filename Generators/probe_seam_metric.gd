extends SceneTree
## Замер шва лупа ДВУМЯ метриками (18.11.26, раунд 23г):
##   WRAP  — угол между последним и первым ключом (старая метрика);
##   ADJ   — средний угол между СОСЕДНИМИ ключами трека (норма движения за шаг).
## Критерий непрерывности фазы: WRAP ≈ ADJ (шов неотличим от обычного кадра).
## У кроссфейд-версии 23в WRAP был 0.00°, но ADJ-движение в хвосте УМИРАЛО
## (смешивались позы ~11 исходных кадров по фазе) — вердикт юзера «тормозит».

func _init() -> void:
	var lib: AnimationLibrary = load("res://Graphics/Animations/shared_animations.res")
	for anim_name in ["Run", "Run_Test", "Walk_Test"]:
		if not lib.has_animation(anim_name):
			continue
		var anim: Animation = lib.get_animation(anim_name)
		var w_wrap := 0.0
		var tot_wrap := 0.0
		var tot_adj := 0.0
		var tot_tail := 0.0  # последние 3 шага (не умирает ли движение в кроссфейде)
		var cnt := 0
		var worst_track := ""
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var n := anim.track_get_key_count(i)
			if n < 2:
				continue
			var qa: Quaternion = anim.track_get_key_value(i, n - 1)
			var qb: Quaternion = anim.track_get_key_value(i, 0)
			var a: float = rad_to_deg(2.0 * acos(clampf(absf(qa.dot(qb)), 0.0, 1.0)))
			tot_wrap += a
			if a > w_wrap:
				w_wrap = a
				worst_track = str(anim.track_get_path(i))
			for k in n - 1:
				var qc: Quaternion = anim.track_get_key_value(i, k)
				var qd: Quaternion = anim.track_get_key_value(i, k + 1)
				tot_adj += rad_to_deg(2.0 * acos(clampf(absf(qc.dot(qd)), 0.0, 1.0)))
			tot_adj += a  # шов тоже часть цикла соседей
			for k in mini(3, n - 1):
				var qe: Quaternion = anim.track_get_key_value(i, n - 2 - k)
				var qf: Quaternion = anim.track_get_key_value(i, n - 1 - k)
				tot_tail += rad_to_deg(2.0 * acos(clampf(absf(qe.dot(qf)), 0.0, 1.0)))
			cnt += 1
		var adj := tot_adj / maxf(cnt * maxf(anim.track_get_key_count(0) - 1 + 1, 1), 1)
		var tail := tot_tail / maxf(cnt * mini(3, anim.track_get_key_count(0) - 1), 1)
		print("SEAM %s: WRAP avg %.2f° max %.2f° (%s) | ADJ avg %.2f° | TAIL(3) avg %.2f° | ratio %.2f | длина %.2f с, ключей/трек %d" % [
			anim_name, tot_wrap / maxf(cnt, 1), w_wrap, worst_track,
			adj, tail, (tot_wrap / maxf(cnt, 1)) / maxf(adj, 0.001), anim.length, anim.track_get_key_count(0)])
	quit(0)
