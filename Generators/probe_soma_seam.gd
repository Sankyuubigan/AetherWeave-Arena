extends SceneTree
## Зонд качества нейро-клипов SOMA (17.11.26): 1) шов лупа — угловая дистанция
## позы кадра 0 vs последнего (Cast_Loop должен быть зацикливаемым);
## 2) дрейф корня — размах root_positions по x/z (касты = ноги на месте).
## Запуск: --headless -s res://Generators/probe_soma_seam.gd

const DIRS := ["cast_enter", "cast_loop", "cast_shoot", "cast_exit", "throw", "pistol_shoot",
	# Q23: лупы/переходы локомоции — там метрики спеца (RSV/каденс/сим) осмысленны.
	"mb_run_d", "mb_walk_test", "run_stop", "run_start"]
const NJ := 30
const BASE := "res://Graphics/Animations/neuro_soma"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for d in DIRS:
		var f := FileAccess.open("%s/%s/local_rotations_xyzw.f32" % [BASE, d], FileAccess.READ)
		var rf := FileAccess.open("%s/%s/root_positions.f32" % [BASE, d], FileAccess.READ)
		if f == null or rf == null:
			print("PROBE SKIP: ", d)
			continue
		var rots: PackedFloat32Array = f.get_buffer(f.get_length()).to_float32_array()
		var roots: PackedFloat32Array = rf.get_buffer(rf.get_length()).to_float32_array()
		f.close()
		rf.close()
		var frames := rots.size() / (NJ * 4)
		# Шов: средняя/макс угловая дистанция q[frame0] vs q[last] по суставам.
		var sum := 0.0
		var worst := 0.0
		for j in NJ:
			var b0 := j * 4
			var bl := (frames - 1) * NJ * 4 + j * 4
			var q0 := Quaternion(rots[b0], rots[b0 + 1], rots[b0 + 2], rots[b0 + 3])
			var ql := Quaternion(rots[bl], rots[bl + 1], rots[bl + 2], rots[bl + 3])
			var ang := absf(q0.angle_to(ql))
			sum += ang
			worst = maxf(worst, ang)
		# Дрейф корня.
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for k in frames:
			var p := Vector3(roots[k * 3], roots[k * 3 + 1], roots[k * 3 + 2])
			lo = lo.min(p)
			hi = hi.max(p)
		var drift := Vector3(hi.x - lo.x, 0, hi.z - lo.z)
		# Q23 метрики спеца (20.11.26): Root Speed Variance <8–10% (луп ровный
		# без «пульсации темпа»), каденс 2.5–3.0 шаг/с (>3.4 = «таракан»),
		# Stride Symmetry <5% (чётные/нечётные минимумы высоты бёдер — лёвые/
		# правые шаги одинаковой глубины). Лупы: Run_Test/Walk_Test/Run_Stop.
		var dur := float(frames - 1) / 30.0
		var spd: Array[float] = []
		var v_mean := 0.0
		for k in range(frames - 1):
			var dv := Vector3(roots[(k + 1) * 3] - roots[k * 3], 0,
				roots[(k + 1) * 3 + 2] - roots[k * 3 + 2])
			spd.append(dv.length() * 30.0)
			v_mean += spd[k]
		v_mean /= maxf(1.0, spd.size())
		var v_var := 0.0
		for s in spd:
			v_var += (s - v_mean) * (s - v_mean)
		v_var = sqrt(v_var / maxf(1.0, spd.size()))
		var rsv := (v_var / v_mean * 100.0) if v_mean > 0.1 else 0.0
		var mins: Array[int] = []
		for k in range(2, frames - 2):
			var y := roots[k * 3 + 1]
			if y < roots[(k - 1) * 3 + 1] and y <= roots[(k + 1) * 3 + 1] \
					and y < roots[(k - 2) * 3 + 1] and y < roots[(k + 2) * 3 + 1]:
				mins.append(k)
		var cadence := mins.size() / maxf(0.2, dur)
		var d_even := 0.0
		var n_even := 0
		var d_odd := 0.0
		var n_odd := 0
		for mi in range(mins.size()):
			var k2 := mins[mi]
			var y2 := roots[k2 * 3 + 1]
			var base_y := (roots[(k2 - 2) * 3 + 1] + roots[(k2 + 2) * 3 + 1]) * 0.5
			if mi % 2 == 0:
				d_even += base_y - y2
				n_even += 1
			else:
				d_odd += base_y - y2
				n_odd += 1
		var sym := -1.0
		if n_even > 0 and n_odd > 0:
			d_even /= n_even
			d_odd /= n_odd
			var dm := (d_even + d_odd) * 0.5
			if dm > 1e-4:
				sym = absf(d_even - d_odd) / dm * 100.0
		print("PROBE %s: seam avg=%.1f° worst=%.1f° (joint %s) | корень размах x=%.2f z=%.2f y=%.2f | RSV=%.1f%% каденс=%.1f шаг/с сим=%.1f%% шагов=%d" % [
			d, rad_to_deg(sum / NJ), rad_to_deg(worst), _worst_joint(rots, frames), drift.x, drift.z, hi.y - lo.y,
			rsv, cadence, sym, mins.size()])
	quit(0)

func _worst_joint(rots: PackedFloat32Array, frames: int) -> String:
	var names := ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw",
		"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"LThumbEnd", "LMidEnd", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"RThumbEnd", "RMidEnd", "LeftLeg", "LeftShin", "LeftFoot", "LeftToeBase",
		"RightLeg", "RightShin", "RightFoot", "RightToeBase"]
	var worst := -1.0
	var wj := 0
	for j in NJ:
		var b0 := j * 4
		var bl := (frames - 1) * NJ * 4 + j * 4
		var q0 := Quaternion(rots[b0], rots[b0 + 1], rots[b0 + 2], rots[b0 + 3])
		var ql := Quaternion(rots[bl], rots[bl + 1], rots[bl + 2], rots[bl + 3])
		var ang := absf(q0.angle_to(ql))
		if ang > worst:
			worst = ang
			wj = j
	return names[wj]
