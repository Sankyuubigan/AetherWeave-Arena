extends SceneTree
## Композитор единого каст-жеста cast_push (17.11.26): правая рука = резкий
## толчок из панч-клипа (z0.39→0.82 на высоте груди — вердикт юзера «фаербол
## машет как волейбол»), левая = донор ВИСЯЩЕЙ руки из handshake-клипа
## (pistol_shoot_f: левая y0.87 всю клипу). Панч-промпты дают боксёрскую
## стойку (обе руки в guard, левую нейросеть не опускает) — сшиваем
## «правая из панча, левая из релакса». Оба источника 24 кадра @30fps.
## Запуск: --headless -s res://Generators/compose_cast_push.gd

const NJ := 30
const SRC_PUNCH := "D:/nn/kimodo.cpp/out/cast_push_a"
const SRC_ARM_DONOR := "D:/nn/kimodo.cpp/out/pistol_shoot_f"
const DST := "res://Graphics/Animations/neuro_soma/cast_push"
## Цепь левой руки: SOMA-индексы (Shoulder 10 → Arm 11 → ForeArm 12 → Hand 13).
const CHAIN := [10, 11, 12, 13]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var pr := FileAccess.open(SRC_PUNCH + "/root_positions.f32", FileAccess.READ)
	var pf := FileAccess.open(SRC_PUNCH + "/local_rotations_xyzw.f32", FileAccess.READ)
	var dr := FileAccess.open(SRC_ARM_DONOR + "/root_positions.f32", FileAccess.READ)
	var df := FileAccess.open(SRC_ARM_DONOR + "/local_rotations_xyzw.f32", FileAccess.READ)
	if pr == null or pf == null or dr == null or df == null:
		print("COMPOSE FAIL: нет исходников")
		quit(1)
		return
	var proots := pr.get_buffer(pr.get_length()).to_float32_array()
	var prots := pf.get_buffer(pf.get_length()).to_float32_array()
	var droots := dr.get_buffer(dr.get_length()).to_float32_array()
	var drots := df.get_buffer(df.get_length()).to_float32_array()
	pr.close(); pf.close(); dr.close(); df.close()
	var frames := prots.size() / (NJ * 4)
	if drots.size() / (NJ * 4) != frames:
		print("COMPOSE FAIL: разное число кадров %d vs %d" % [frames, drots.size() / (NJ * 4)])
		quit(1)
		return
	# Копируем локальные кватернионы левой руки из донора (кадр в кадр).
	# Корень/позвоночник/правая рука/ноги — от панча.
	for k in frames:
		for j: int in CHAIN:
			var dst := k * NJ * 4 + j * 4
			for a in 4:
				prots[dst + a] = drots[dst + a]
	DirAccess.make_dir_recursive_absolute(DST)
	var fr := FileAccess.open(DST + "/root_positions.f32", FileAccess.WRITE)
	fr.store_buffer(proots.to_byte_array())
	fr.close()
	var ff := FileAccess.open(DST + "/local_rotations_xyzw.f32", FileAccess.WRITE)
	ff.store_buffer(prots.to_byte_array())
	ff.close()
	var prompt := FileAccess.open("D:/nn/kimodo.cpp/prompts/cast_push.txt", FileAccess.READ)
	if prompt:
		var txt := prompt.get_as_text()
		prompt.close()
		var pf2 := FileAccess.open(DST + "/prompt.txt", FileAccess.WRITE)
		pf2.store_string(txt + "\n[композит: правая+корпус из cast_push_a seed7, левая рука из pistol_shoot_f seed202]\n")
		pf2.close()
	print("COMPOSE OK: %d кадров → %s" % [frames, DST])
	quit(0)
