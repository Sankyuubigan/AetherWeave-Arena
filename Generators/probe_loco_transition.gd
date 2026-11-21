extends SceneTree
## Q23 (20.11.26) численный гейт переходных клипов локомоции (Idle_to_Run
## «run_start», обратный Run_Stop-декелю). Метрики спеца (QUEUE Q23):
## старт из стойки (v_start ≤0.7), финиш в полном беге БЕЗ тормоза
## (v_end 3.2–6.5), направление вперёд +Z, латеральный снос <0.8 м,
## бёдра y∈[0.70,1.25] (не прыгает/не проседает), каденс ≤3.4 шаг/с
## (>3.4 = «таракан» — вердикт юзера на mb_run_c), без повторного торможения
## в хвосте (мин скорости хвоста ≥0.55·v_end). Только root_positions.f32 —
## позу проверяет визуальный чек (§11.27).
## Запуск: timeout 90 $G --headless -s res://Generators/probe_loco_transition.gd -- <dir> [<dir> ...]
## EXIT 0 = есть PASS (WINNER: минимальный |v_end−4.5|), EXIT 1 = все FAIL.

const FPS := 30.0
const TARGET_END_SPEED := 4.5  # м/с (Run_MB A326 4.49; Run_Stop декелил с 4.6)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("LOCO GATE FAIL: аргументы: <dir> [<dir> ...]")
		quit(1)
		return
	var best: String = ""
	var best_err := 1e9
	for dir in args:
		var err := _probe(dir)
		if err >= 0.0 and err < best_err:
			best_err = err
			best = dir
	if best == "":
		print("LOCO GATE: ALL FAIL")
		quit(1)
	else:
		print("WINNER: %s (|v_end-%.1f|=%.2f)" % [best, TARGET_END_SPEED, best_err])
		quit(0)

func _probe(dir: String) -> float:
	var rf := FileAccess.open(dir + "/root_positions.f32", FileAccess.READ)
	if rf == null:
		print("LOCO GATE FAIL %s: нет root_positions.f32" % dir)
		return -1.0
	var bytes := rf.get_buffer(rf.get_length())
	var n := bytes.size() / 12  # кадров × 3 float32
	if n < 20:
		print("LOCO GATE FAIL %s: слишком коротко (%d кадров)" % [dir, n])
		return -1.0
	var pts: Array[Vector3] = []
	for f in range(n):
		pts.append(Vector3(
			bytes.decode_float((f * 3 + 0) * 4),
			bytes.decode_float((f * 3 + 1) * 4),
			bytes.decode_float((f * 3 + 2) * 4)))
	var dt := 1.0 / FPS
	var spd: Array[float] = []
	for f in range(n - 1):
		var d := pts[f + 1] - pts[f]
		spd.append(Vector2(d.x, d.z).length() / dt)

	var v_start := 0.0
	for f in range(5):
		v_start += spd[f]
	v_start /= 5.0
	var v_end := 0.0
	for f in range(n - 6, n - 1):
		v_end += spd[f]
	v_end /= 5.0

	var fails := 0
	if v_start > 0.7:
		print("LOCO GATE FAIL %s: старт не из стойки v_start=%.2f (>0.70)" % [dir, v_start])
		fails += 1
	if v_end < 3.2 or v_end > 6.5:
		print("LOCO GATE FAIL %s: финиш не в беге v_end=%.2f (нужен 3.2–6.5)" % [dir, v_end])
		fails += 1
	if v_end < v_start + 1.5:
		print("LOCO GATE FAIL %s: разгона нет (v_end−v_start=%.2f <1.5)" % [dir, v_end - v_start])
		fails += 1
	# направление хвоста: вектор последних 6 кадров против +Z (лицо SOMA)
	var tail := pts[n - 1] - pts[n - 7]
	var td := Vector2(tail.x, tail.z)
	if td.length() > 1e-4 and (td / td.length()).dot(Vector2(0, 1)) < 0.7:
		print("LOCO GATE FAIL %s: бег не вперёд +Z (cos=%.2f)" % [dir, (td / td.length()).dot(Vector2(0, 1))])
		fails += 1
	var lateral := absf(pts[n - 1].x - pts[0].x)
	if lateral > 0.8:
		print("LOCO GATE FAIL %s: латеральный снос %.2f м (>0.8)" % [dir, lateral])
		fails += 1
	var y_min := pts[0].y
	var y_max := pts[0].y
	for p in pts:
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
	if y_min < 0.70 or y_max > 1.25:
		print("LOCO GATE FAIL %s: бёдра вне [0.70,1.25] (min=%.2f max=%.2f)" % [dir, y_min, y_max])
		fails += 1
	# повторное торможение в хвосте: после разгона скорость не падает
	var tail_min := v_end
	for f in range(n - 9, n - 1):
		tail_min = minf(tail_min, spd[f])
	if tail_min < 0.55 * v_end:
		print("LOCO GATE FAIL %s: тормозит в хвосте (min_tail=%.2f <0.55·v_end=%.2f)" % [dir, tail_min, 0.55 * v_end])
		fails += 1
	# каденс: минимумы высоты бёдер (два на цикл = шаги) после разгона (>2 м/с)
	var i0 := 0
	for f in range(n - 1):
		if spd[f] > 2.0:
			i0 = f
			break
	var steps := 0
	for f in range(max(2, i0), n - 2):
		if pts[f].y < pts[f - 1].y and pts[f].y <= pts[f + 1].y \
				and pts[f].y < pts[f - 2].y and pts[f].y < pts[f + 2].y:
			steps += 1
	var run_dur := float(n - 1 - i0) / FPS
	var cadence := 0.0
	if run_dur > 0.2:
		cadence = steps / run_dur
	if cadence > 3.4:
		print("LOCO GATE FAIL %s: «таракан» каденс=%.1f шаг/с (>3.4)" % [dir, cadence])
		fails += 1
	elif cadence < 1.5 and i0 > 0:
		print("LOCO GATE FAIL %s: шаги слишком редкие каденс=%.1f (<1.5)" % [dir, cadence])
		fails += 1
	print("LOCO GATE %s: v_start=%.2f v_end=%.2f каденс=%.1f снос=%.2f minY=%.2f maxY=%.2f шагов=%d -> %s"
		% [dir, v_start, v_end, cadence, lateral, y_min, y_max, steps,
		"PASS" if fails == 0 else "FAIL(%d)" % fails])
	if fails == 0:
		return absf(v_end - TARGET_END_SPEED)
	return -1.0
