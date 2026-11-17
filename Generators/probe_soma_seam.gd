extends SceneTree
## Зонд качества нейро-клипов SOMA (17.11.26): 1) шов лупа — угловая дистанция
## позы кадра 0 vs последнего (Cast_Loop должен быть зацикливаемым);
## 2) дрейф корня — размах root_positions по x/z (касты = ноги на месте).
## Запуск: --headless -s res://Generators/probe_soma_seam.gd

const DIRS := ["cast_enter", "cast_loop", "cast_shoot", "cast_exit", "throw", "pistol_shoot"]
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
		print("PROBE %s: seam avg=%.1f° worst=%.1f° (joint %s) | корень размах x=%.2f z=%.2f y=%.2f" % [
			d, rad_to_deg(sum / NJ), rad_to_deg(worst), _worst_joint(rots, frames), drift.x, drift.z, hi.y - lo.y])
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
