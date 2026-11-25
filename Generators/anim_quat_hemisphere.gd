class_name AnimQuatHemisphere
## Quaternion Hemisphere Continuity (вердикт спеца 23.11.26).
##   q[0] → полусфера rest-кости (dot(q0, rest) < 0 → negate);
##   q[i]·q[i−1] < 0 → negate (каждый следующий ключ — ближайшая полусфера).
## Лечит флип 310° в ретаргете: без этого компонентная интерполяция кватернионов
## идёт «долгой дугой» (визуально — вывих/перекрут кисти на середине клипа).
## Применяется ПОСЛЕ сборки Animation, ДО бейка UB/сохранения.

static func apply(anim: Animation, rest: Dictionary = {}) -> void:
	if anim == null:
		return
	for tr in anim.get_track_count():
		if anim.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var kc := anim.track_get_key_count(tr)
		if kc == 0:
			continue
		var bone := ""
		var path := anim.track_get_path(tr)
		if path.get_subname_count() > 0:
			bone = path.get_subname(0)
		var rest_q: Quaternion = rest.get(bone, Quaternion.IDENTITY)
		var prev: Quaternion = anim.track_get_key_value(tr, 0)
		if prev.dot(rest_q) < 0.0:
			prev = -prev
			anim.track_set_key_value(tr, 0, prev)
		for k in range(1, kc):
			var q: Quaternion = anim.track_get_key_value(tr, k)
			if q.dot(prev) < 0.0:
				q = -q
				anim.track_set_key_value(tr, k, q)
			prev = q