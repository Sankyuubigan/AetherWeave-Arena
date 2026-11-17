extends SceneTree
## Зеркало каст-жеста для левой руки (17.11.26, вердикт юзера «левой рукой —
## симметричная просто левой»): зеркалим САМИ нейро-данные cast_push и пишем
## cast_push_l. Отражение скелета через плоскость YZ (x→−x):
##   кватернион q=(x,y,z,w) → (x,−y,−z,w)  [ось n→(−nx,ny,nz), угол θ→−θ],
##   слоты L/R суставов обмениваются, корень x→−x.
## Это ТОЧНОЕ локальное зеркало движения (в отличие от свапа мировых дельт:
## «висящая» дельта левой руки на правом rest поднимает руку вверх — мир-
## инвариантен только pitch). Rest-асимметрия mixamo (176.7° RightShoulder)
## дальше гасится ретаргетом v2 — каждая целевая кость якорится СВОИМ rest.
## Запуск: --headless -s res://Generators/mirror_cast_push.gd

const NJ := 30
const SRC := "res://Graphics/Animations/neuro_soma/cast_push"
const DST := "res://Graphics/Animations/neuro_soma/cast_push_l"
## Зеркальные пары SOMA-слотов (индекс → парный), несимметричные — сами в себя.
const MIRROR_PAIR := [0, 1, 2, 3, 4, 5, 6, 7, 9, 8, 16, 17, 18, 19, 20, 21, 10, 11, 12, 13, 14, 15, 26, 27, 28, 29, 22, 23, 24, 25]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var rf := FileAccess.open(SRC + "/root_positions.f32", FileAccess.READ)
	var ff := FileAccess.open(SRC + "/local_rotations_xyzw.f32", FileAccess.READ)
	if rf == null or ff == null:
		print("MIRROR FAIL: нет исходников в " + SRC)
		quit(1)
		return
	var roots := rf.get_buffer(rf.get_length()).to_float32_array()
	var rots := ff.get_buffer(ff.get_length()).to_float32_array()
	rf.close(); ff.close()
	var frames := rots.size() / (NJ * 4)
	var m_roots := roots.duplicate()
	var m_rots := rots.duplicate()
	for k in frames:
		m_roots[k * 3] = -roots[k * 3]  # x → −x (y,z без изменений)
		for j in NJ:
			var base := k * NJ * 4 + j * 4
			# q → (x,−y,−z,w), запись в ЗЕРКАЛЬНЫЙ слот.
			var j2: int = MIRROR_PAIR[j]
			var base2 := k * NJ * 4 + j2 * 4
			m_rots[base2] = rots[base]
			m_rots[base2 + 1] = -rots[base + 1]
			m_rots[base2 + 2] = -rots[base + 2]
			m_rots[base2 + 3] = rots[base + 3]
	DirAccess.make_dir_recursive_absolute(DST)
	var fr := FileAccess.open(DST + "/root_positions.f32", FileAccess.WRITE)
	fr.store_buffer(m_roots.to_byte_array())
	fr.close()
	var fv := FileAccess.open(DST + "/local_rotations_xyzw.f32", FileAccess.WRITE)
	fv.store_buffer(m_rots.to_byte_array())
	fv.close()
	var pf := FileAccess.open(DST + "/prompt.txt", FileAccess.WRITE)
	pf.store_string("Зеркало cast_push (Generators/mirror_cast_push.gd): отражение YZ данных.\n")
	pf.close()
	print("MIRROR OK: %d кадров → %s" % [frames, DST])
	quit(0)
