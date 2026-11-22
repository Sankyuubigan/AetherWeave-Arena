extends SceneTree

## Q16 Шаг 5 (PRP): ритм-луп барда — 120 BPM, D minor пентатоника,
## чёткая перкуссия + аккорды, ~16 с (8 тактов × 2.0 с — сетка такта сходится
## с combat_loop/map1). Выход: Audio/Bard/bard_loop.res (AudioStreamWAV,
## loop_mode=FORWARD — грузится в игре БЕЗ --import). Паттерн gen_music.gd.
## Бесшовность: частоты квантованы к 1/T (фазы сходятся на стыке),
## все события заканчиваются до границы лупа (wrap не нужен).

const RATE := 44100
const OUT := "res://Audio/Bard/"
const T_LEN := 16.0
const BAR := 2.0
const SAMPLES := 705600  # 16.0 * 44100

## Прогрессия 4 такта × 2: Dm | Bb | F | C (аккорды из D натурального минора,
## мелодия сверху остаётся пентатонике D minor).
const CHORDS := [
	[146.83, 174.61, 220.00],   # Dm: D3 F3 A3
	[116.54, 146.83, 174.61],   # Bb: Bb2 D3 F3
	[174.61, 220.00, 261.63],   # F:  F3 A3 C4
	[130.81, 164.81, 196.00],   # C:  C3 E3 G3
]
const BASS := [73.42, 58.27, 87.31, 65.41]  # D2 Bb1 F2 C2

## Мелодия: 8 тактов × 8 восьмых, 0 = пауза. Пентатоника D minor.
const MEL := [
	[1, 0, 2, 0, 4, 0, 3, 0],   # D4 . F4 . A4 . G4 .
	[1, 0, 2, 0, 5, 0, 4, 0],   # D4 . F4 . C5 . A4 .
	[5, 0, 4, 0, 2, 0, 3, 0],   # C5 . A4 . F4 . G4 .
	[3, 0, 4, 0, 5, 0, 6, 0],   # G4 . A4 . C5 . D5 .
	[1, 0, 2, 0, 4, 0, 3, 0],
	[1, 0, 2, 0, 5, 0, 4, 0],
	[5, 0, 4, 0, 2, 0, 3, 0],
	[6, 0, 5, 0, 4, 0, 3, 0],   # нисходящее завершение D5 C5 A4 G4
]
const PENTA := [0.0, 293.664, 349.228, 392.000, 440.000, 523.251, 587.330]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var buf := PackedFloat32Array()
	buf.resize(SAMPLES)
	for bar in 8:
		var t0 := bar * BAR
		var ci := bar % 4
		_bass(buf, t0, BASS[ci])
		_chord(buf, t0, CHORDS[ci])
		_melody(buf, bar)
		for k in 2:                       # kick: 0.0 и 1.0 такта
			_kick(buf, t0 + k)
		for k in 2:                       # snare: 0.5 и 1.5 такта
			_snare(buf, t0 + 0.5 + k)
		for e in 8:                       # hats на восьмые
			_hat(buf, t0 + e * 0.25, 0.06 if e % 2 == 1 else 0.03)
	_norm(buf, 0.85)
	_save(buf)
	print("GEN-BARD-LOOP: DONE")
	quit(0)

## Частота квантуется к 1/T_LEN (бесшовный стык лупа).
func _qf(f: float) -> float:
	return floorf(f * T_LEN + 0.5) / T_LEN

func _add_tone(buf: PackedFloat32Array, start_s: float, f: float, dur: float,
		amp: float, decay: float) -> void:
	var start := int(start_s * RATE)
	var f_q := _qf(f)
	for i in int(dur * RATE):
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		buf[idx] += amp * minf(t / 0.004, 1.0) * exp(-t / decay) * sin(TAU * f_q * t)

func _bass(buf: PackedFloat32Array, t0: float, f: float) -> void:
	for k in 4:  # пульс на каждую долю 0.5 с
		_add_tone(buf, t0 + k * 0.5, f, 0.22, 0.30, 0.08)

func _chord(buf: PackedFloat32Array, t0: float, triad: Array) -> void:
	# Пэд: мягкая атака 0.15, релиз в хвосте — до конца такта не дотягивает.
	for f_v in triad:
		var f: float = f_v
		var start := int(t0 * RATE)
		for i in int(1.7 * RATE):
			var idx := start + i
			if idx >= buf.size():
				break
			var t := float(i) / RATE
			var env: float = minf(t / 0.15, 1.0) * minf((1.7 - t) / 0.3, 1.0)
			buf[idx] += 0.09 * sin(TAU * _qf(f) * t) * env

func _melody(buf: PackedFloat32Array, bar: int) -> void:
	var degs: Array = MEL[bar]
	for e in 8:
		var d: int = degs[e]
		if d > 0:
			_add_tone(buf, bar * BAR + e * 0.25, PENTA[d], 0.4, 0.22, 0.12)

func _kick(buf: PackedFloat32Array, start_s: float) -> void:
	var start := int(start_s * RATE)
	for i in int(0.25 * RATE):
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		# Глайд 150→45 Гц: фаза = интеграл частоты (закрытая форма).
		var ph := TAU * (45.0 * t + 105.0 * 0.035 * (1.0 - exp(-t / 0.035)))
		buf[idx] += 0.55 * exp(-t / 0.11) * sin(ph)

func _snare(buf: PackedFloat32Array, start_s: float) -> void:
	var start := int(start_s * RATE)
	for i in int(0.14 * RATE):
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var env: float = exp(-t / 0.045)
		var s := 0.30 * (randf() * 2.0 - 1.0) * env
		s += 0.18 * sin(TAU * 190.0 * t) * env
		buf[idx] += s

func _hat(buf: PackedFloat32Array, start_s: float, amp: float) -> void:
	var start := int(start_s * RATE)
	for i in int(0.04 * RATE):
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		buf[idx] += amp * (randf() * 2.0 - 1.0) * exp(-t / 0.012)

func _norm(l: PackedFloat32Array, peak: float) -> void:
	var mx := 0.0001
	for i in l.size():
		mx = maxf(mx, absf(l[i]))
	var k := peak / mx
	for i in l.size():
		l[i] *= k

func _save(l: PackedFloat32Array) -> void:
	var n := l.size()
	var aw := AudioStreamWAV.new()
	aw.format = AudioStreamWAV.FORMAT_16_BITS
	aw.stereo = false
	aw.mix_rate = RATE
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(l[i], -1.0, 1.0) * 32000.0))
	aw.data = bytes
	aw.loop_mode = AudioStreamWAV.LOOP_FORWARD
	aw.loop_begin = 0
	aw.loop_end = n
	var err := ResourceSaver.save(aw, OUT + "bard_loop.res")
	print("GEN-BARD-LOOP: bard_loop %.1fс save=%s" % [float(n) / RATE, error_string(err)])
