extends SceneTree
## Генератор музыки карт (17.11.26, план «Музыка карт»): синтез WAV из математики.
## Выход: Audio/Music/<name>.wav (послушать) + <name>.res (AudioStreamWAV,
## loop_mode=FORWARD — грузится в игре БЕЗ --import).
##   map1_ambient — тёмный дрон-пэд (арена), 32с
##   map2_ambient — светлый пэд + пентатоника (зелёное поле), 32с
##   combat_loop  — напряжённый: пульс-бас + минорное арпеджио + удары, 16с
## Лупы бесшовные: все частоты квантованы к 1/T (фазы сходятся на стыке).

const RATE := 44100
const OUT := "res://Audio/Music/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_track_map1()
	_track_map2()
	_track_combat()
	print("GEN-MUSIC: DONE")
	quit(0)

## ── Квантизация частоты под длину лупа T (бесшовность) ──────────────────
func _qf(f: float, t_len: float) -> float:
	return floorf(f * t_len + 0.5) / t_len

func _save(name: String, l: PackedFloat32Array, r: PackedFloat32Array) -> void:
	var n := l.size()
	var wav_path := OUT + name + ".wav"
	var f := FileAccess.open(wav_path, FileAccess.WRITE)
	f.store_32(0x46464952)          # RIFF
	f.store_32(36 + n * 4)
	f.store_32(0x45564157)          # WAVE
	f.store_32(0x20746D66)          # fmt
	f.store_32(16)
	f.store_16(1)                   # PCM
	f.store_16(2)                   # stereo
	f.store_32(RATE)
	f.store_32(RATE * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_32(0x61746164)          # data
	f.store_32(n * 4)
	var sb := StreamPeerBuffer.new()
	for i in n:
		var lv := int(clampf(l[i], -1.0, 1.0) * 32000.0)
		var rv := int(clampf(r[i], -1.0, 1.0) * 32000.0)
		f.store_16(lv); f.store_16(rv)
		sb.put_16(lv); sb.put_16(rv)
	f.close()
	var aw := AudioStreamWAV.new()
	aw.format = AudioStreamWAV.FORMAT_16_BITS
	aw.stereo = true
	aw.mix_rate = RATE
	aw.data = sb.data_array
	aw.loop_mode = AudioStreamWAV.LOOP_FORWARD
	aw.loop_begin = 0
	aw.loop_end = n
	var err := ResourceSaver.save(aw, OUT + name + ".res")
	print("GEN-MUSIC: ", name, " ", "%.1f" % (float(n) / RATE), "с save=", error_string(err))

func _norm(l: PackedFloat32Array, r: PackedFloat32Array, peak: float) -> void:
	var mx := 0.0001
	for i in l.size():
		mx = maxf(mx, absf(l[i]))
		mx = maxf(mx, absf(r[i]))
	var k := peak / mx
	for i in l.size():
		l[i] *= k
		r[i] *= k

## ── Карта 1 (арена): медленная музыка A-minor (Am→F→C→G) ────────────────
## Урок 18.11.26 (вердикт юзера «сплошной гул»): статичный дрон 110/165 Гц
## + ветер-шум на все 32с = гул, а не музыка. Теперь: аккордовая прогрессия
## 4×8с с дышащими огибающими, бас-пульс по такту, редкая пентатоника.
## Луп бесшовный: частоты квантованы к 1/T, границы аккордов на такте.
func _track_map1() -> void:
	var t_len := 32.0
	var n := int(t_len * RATE)
	var l := PackedFloat32Array(); l.resize(n)
	var r := PackedFloat32Array(); r.resize(n)
	var chord_len := 8.0
	# Прогрессия: Am → F → C → G (триады, Гц)
	var chords := [
		[220.0, 261.63, 329.63],
		[174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0],
		[196.0, 246.94, 293.66],
	]
	var roots := [_qf(110.0, t_len), _qf(87.31, t_len), _qf(130.81, t_len), _qf(98.0, t_len)]
	# A-minor пентатоника, рисунок по 2с-слотам (0 = пауза)
	var pent := [_qf(440.0, t_len), _qf(523.25, t_len), _qf(587.33, t_len), _qf(659.26, t_len), _qf(783.99, t_len)]
	var melody := [0, 3, 4, 2, 1, 0, 3, 2, 4, 0, 2, 1, 0, 3, 1, 2]  # индексы pent, 0=A4
	var rests := [false, false, true, false, false, true, false, false, false, true, false, false, true, false, false, false]
	var rms := [0.0, 0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		var v_l := 0.0
		var v_r := 0.0
		# Пэд: все 4 аккорда с окном-огибающей (1.2с взлёт/сход) — сумма весов
		# даёт «дыхание» фразы на стыках, частоты квантованы → шов бесшовный.
		for c in chords.size():
			var ct := fmod(t, chord_len)
			var atk := clampf(ct / 1.2, 0.0, 1.0)
			var rel := clampf((chord_len - ct) / 1.2, 0.0, 1.0)
			var env := 0.5 - 0.5 * cos(atk * PI) if atk < rel else 0.5 - 0.5 * cos(rel * PI)
			env *= env
			var ph := TAU * float(c) / 3.0
			v_l += 0.075 * env * sin(TAU * _qf(chords[c][0], t_len) * t + ph)
			v_l += 0.055 * env * sin(TAU * _qf(chords[c][1], t_len) * t + ph + 0.5)
			v_r += 0.075 * env * sin(TAU * _qf(chords[c][0], t_len) * t + ph + 0.6)
			v_r += 0.055 * env * sin(TAU * _qf(chords[c][1], t_len) * t + ph + 1.1)
			v_l += 0.04 * env * sin(TAU * _qf(chords[c][2], t_len) * t + ph + 0.9)
			v_r += 0.04 * env * sin(TAU * _qf(chords[c][2], t_len) * t + ph + 0.2)
		# Бас-пульс: мягкий удар каждые 2с, нота = корень текущего аккорда
		var bt := fmod(t, 2.0)
		var ci := int(t / chord_len) % chords.size()
		v_l += 0.13 * exp(-bt * 2.2) * (sin(TAU * roots[ci] * t) + 0.35 * sin(TAU * roots[ci] * 2.0 * t))
		v_r += 0.13 * exp(-bt * 2.2) * (sin(TAU * roots[ci] * t) + 0.35 * sin(TAU * roots[ci] * 2.0 * t))
		# Пентатоника: нота каждые 2с с паузами, плюк, панорама по слоту
		var slot := int(t / 2.0) % melody.size()
		if not rests[slot]:
			var pt := fmod(t, 2.0)
			var mf: float = pent[melody[slot]]
			var amp := 0.085 * exp(-pt * 1.6)
			var note := amp * (sin(TAU * mf * t) + 0.25 * sin(TAU * mf * 2.0 * t))
			var pan := 0.5 + 0.35 * sin(TAU * float(slot) / 8.0)
			v_l += note * (1.0 - pan)
			v_r += note * pan
		l[i] = v_l
		r[i] = v_r
		rms[ci] += v_l * v_l + v_r * v_r
	_norm(l, r, 0.45)
	for c in chords.size():
		var seg_n := float(int(chord_len * RATE))
		print("GEN-MUSIC: map1 chunk %d RMS=%.3f" % [c, sqrt(rms[c] / seg_n / 2.0)])
	_save("map1_ambient", l, r)

## ── Карта 2 (поле): тёплый пэд C-major + пентатоника-арпеджио ───────────
func _track_map2() -> void:
	var t_len := 32.0
	var n := int(t_len * RATE)
	var l := PackedFloat32Array(); l.resize(n)
	var r := PackedFloat32Array(); r.resize(n)
	var pad := [_qf(130.81, t_len), _qf(196.0, t_len), _qf(329.63, t_len)]
	var pent := [523.25, 587.33, 659.26, 783.99, 880.0]
	var step := 1.0                                                     # нота каждую секунду
	for i in n:
		var t := float(i) / RATE
		var v_l := 0.0
		var v_r := 0.0
		for p in pad.size():
			var env := 0.5 + 0.5 * sin(TAU * t / t_len * 3.0 + TAU * p / 3.0)
			v_l += 0.09 * env * sin(TAU * pad[p] * t)
			v_r += 0.09 * env * sin(TAU * pad[p] * t + 0.9)
		var idx := int(t / step) % pent.size()
		var pt := fmod(t, step)
		var amp := 0.08 * exp(-pt * 3.0)
		var f := _qf(pent[(idx * 3) % pent.size()], t_len)
		var pan := 0.5 + 0.4 * sin(TAU * float(idx) / 5.0)
		var note := amp * (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t))
		v_l += note * (1.0 - pan)
		v_r += note * pan
		l[i] = v_l
		r[i] = v_r
	_norm(l, r, 0.45)
	_save("map2_ambient", l, r)

## ── Боевой луп: 120bpm, 8 тактов = 16с, E-minor ─────────────────────────
func _track_combat() -> void:
	var t_len := 16.0
	var n := int(t_len * RATE)
	var l := PackedFloat32Array(); l.resize(n)
	var r := PackedFloat32Array(); r.resize(n)
	var bass_f := _qf(82.41, t_len)                                     # E2
	var arp: Array[float] = [329.63, 392.0, 493.88, 587.33, 493.88, 392.0]           # E4 G4 B4 D5 B4 G4
	var eighth := 0.25                                                  # восьмые на 120bpm
	var sixt := 0.125                                                   # шестнадцатые
	var gate: Array[float] = [1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0]                # паттерн баса (такт 2с)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		# Бас: восьмые с гейтом и затуханием
		var bt := fmod(t, eighth)
		var bstep := int(t / eighth)
		var g := gate[bstep % 8]
		if g > 0.0:
			var amp := g * (0.3 * exp(-bt * 7.0) + 0.08)
			v += amp * (sin(TAU * bass_f * t) + 0.5 * sin(TAU * bass_f * 2.0 * t) \
					+ 0.2 * sin(TAU * bass_f * 3.0 * t))
		# Арпеджио: шестнадцатые, детерминированный рисунок
		var st := fmod(t, sixt)
		var step_i := int(t / sixt)
		var af := arp[(step_i * 7) % arp.size()]
		var aamp := 0.07 * exp(-st * 9.0)
		v += aamp * (sin(TAU * af * t) + 0.3 * sin(TAU * af * 2.0 * t))
		# Удар в начале такта: шум-всплеск + саб-панч
		var ht := fmod(t, 2.0)
		if ht < 0.4:
			v += 0.22 * exp(-ht * 11.0) * (randf() * 2.0 - 1.0)
			v += 0.3 * exp(-ht * 14.0) * sin(TAU * 60.0 * t)
		# Оффбит-стаб аккордом
		var ot := fmod(t - 0.125, 1.0)
		if ot >= 0.0 and ot < 0.2:
			var oamp := 0.045 * exp(-ot * 16.0)
			v += oamp * (sin(TAU * 329.63 * t) + sin(TAU * 493.88 * t) + sin(TAU * 659.26 * t))
		var pan := 0.5 + 0.15 * sin(TAU * float(step_i % 16) / 16.0)
		l[i] = v * (1.0 - pan + 0.5)
		r[i] = v * (pan + 0.5)
	_norm(l, r, 0.5)
	_save("combat_loop", l, r)
