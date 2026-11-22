extends SceneTree

## Q16 Шаг 5 (PRP): синтез нот барда — 6 нот пентатоники D minor
## (D4 F4 G4 A4 C5 D5) + приглушённый Miss-звук.
## Выход: Audio/Bard/note_*.res (AudioStreamWAV 16 бит, mono, БЕЗ лупа).
## Паттерн gen_music.gd; нейро-сэмплы позже через MOSS v2 (как Q14).

const RATE := 44100
const OUT := "res://Audio/Bard/"
const NOTES := {
	"d4": 293.664, "f4": 349.228, "g4": 392.000,
	"a4": 440.000, "c5": 523.251, "d5": 587.330,
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for key in NOTES:
		_note("note_" + key, NOTES[key])
	_miss()
	print("GEN-BARD-SFX: DONE")
	quit(0)

## Колокольно-щипковый тон: 3 гармоники с разным затуханием + лёгкая расстройка
## верхней октавы, мягкая атака 5 мс (без клика), нормировка к пику 0.8.
func _note(name: String, f: float) -> void:
	var dur := 0.7
	var n := int(dur * RATE)
	var l := PackedFloat32Array()
	l.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = minf(t / 0.005, 1.0) * exp(-t / 0.18)
		var ph := TAU * f * t
		var s := 0.62 * sin(ph)
		s += 0.28 * sin(ph * 2.02) * exp(-t / 0.09)
		s += 0.14 * sin(ph * 3.01) * exp(-t / 0.05)
		l[i] = s * env
	_norm(l, 0.8)
	_save(name, l)

## Miss: глухой низкий шлепок — тон 130 Гц с быстрым затуханием + короткий
## шумовой щелчок. Слушается «приглушённо» против звонких нот.
func _miss() -> void:
	var dur := 0.35
	var n := int(dur * RATE)
	var l := PackedFloat32Array()
	l.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = minf(t / 0.003, 1.0) * exp(-t / 0.05)
		var s := 0.5 * sin(TAU * 130.0 * t) * exp(-t / 0.06)
		s += 0.2 * (randf() * 2.0 - 1.0) * exp(-t / 0.015)
		l[i] = s * env
	_norm(l, 0.6)
	_save("note_miss", l)

func _norm(l: PackedFloat32Array, peak: float) -> void:
	var mx := 0.0001
	for i in l.size():
		mx = maxf(mx, absf(l[i]))
	var k := peak / mx
	for i in l.size():
		l[i] *= k

## AudioStreamWAV 16 бит mono без лупа: loop_mode = LOOP_DISABLED.
func _save(name: String, l: PackedFloat32Array) -> void:
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
	aw.loop_mode = AudioStreamWAV.LOOP_DISABLED
	aw.loop_begin = 0
	aw.loop_end = n
	var err := ResourceSaver.save(aw, OUT + name + ".res")
	print("GEN-BARD-SFX: ", name, " %.2fс" % (float(n) / RATE), " save=", error_string(err))
