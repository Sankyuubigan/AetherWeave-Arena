extends SceneTree
# Генератор звука «Луч»: лазерный чирп (свип частоты вниз + затухание).
# Ассет генерируем сами — лицензия чистая, внешние сайты не нужны.
# Выход: Audio/SFX/laser_zap.res (AudioStreamWAV), подключается без --import.
#
# Запуск:
# & "<движок>" --headless -s res://Generators/build_laser_sfx.gd

const RATE := 22050
const DUR := 0.32

func _init() -> void:
	var n := int(RATE * DUR)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		# Частота 1700→260 Гц по квадрату времени, громкость — exp-затухание.
		var freq := 260.0 + 1440.0 * pow(1.0 - t, 2.0)
		phase += TAU * freq / RATE
		var env := exp(-6.0 * t) * (1.0 - t)
		var s := (sin(phase) * 0.8 + sin(phase * 2.0) * 0.2) * env
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	var err := ResourceSaver.save(stream, "res://Audio/SFX/laser_zap.res")
	print("[LaserSfx] laser_zap.res: ", error_string(err))
	quit()
