extends SceneTree

## Экспорт папки прослушки A/B: Audio/Gen/AB_listen/
## ВАЖНО (17.11): конвертируем ТЕ ЖЕ .res, что играют в игре (уже с
## RMS-нормализацией), а НЕ сырые WAV из Audio/Gen/neural/ (они до
## нормализации — громкость в папке не совпадала с игрой, вопрос юзера).
## Запуск: Godot --headless -s res://Generators/export_ab_listen.gd

const OUT_DIR := "res://Audio/Gen/AB_listen/"

# Имя → .res из игры (SSOT — Audio/SFX, как в SkillDB).
# 17.11.26 вердикты: лазер-старый удалён; метеор = полёт + удар; v2 у
# сердечка (дзинь) и шаровой (тесла).
const RES_SOURCES := {
	"Луч_НЕЙРО.wav": "res://Audio/SFX/neural_beam.res",
	"Сердечко_НЕЙРО_v2_дзинь.wav": "res://Audio/SFX/neural_heart_heal.res",
	"Сердечко_НЕЙРО_v3a_дзынь.wav": "res://Audio/SFX/heart_heal_v3a.res",
	"Сердечко_НЕЙРО_v3b_звон.wav": "res://Audio/SFX/heart_heal_v3b.res",
	"Сердечко_НЕЙРО_v3c_монетка.wav": "res://Audio/SFX/heart_heal_v3c.res",
	"Сердечко_НЕЙРО_v3d_дзынь.wav": "res://Audio/SFX/heart_heal_v3d.res",
	"Сердечко_НЕЙРО_v3e_звон.wav": "res://Audio/SFX/heart_heal_v3e.res",
	"Сердечко_НЕЙРО_v3f_дзынь.wav": "res://Audio/SFX/heart_heal_v3f.res",
	"Огненный_шар_НЕЙРО.wav": "res://Audio/SFX/neural_fireball.res",
	"Гром_НЕЙРО.wav": "res://Audio/SFX/neural_thunder.res",
	"Метеор_ПОЛЁТ.wav": "res://Audio/SFX/neural_meteor_fly.res",
	"Метеор_УДАР.wav": "res://Audio/SFX/neural_meteor_impact.res",
	"Шаровая_молния_НЕЙРО_v2_тесла.wav": "res://Audio/SFX/neural_ball_lightning.res",
	"Телепорт_НЕЙРО.wav": "res://Audio/SFX/neural_teleport.res",
}

# Нестандартные контейнеры копируем как есть (ogg плеер играет).
const FILE_COPIES := {
	"Сердечко_СТАРЫЙ.ogg": "res://Audio/SFX/cast_healing_1.ogg",
}

func _init():
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)
	var fails: Array[String] = []

	# .res → обычный WAV (PCM16 моно).
	for out_name in RES_SOURCES:
		var stream = load(RES_SOURCES[out_name])
		if stream == null or not (stream is AudioStreamWAV):
			fails.append("не загрузился как AudioStreamWAV: " + RES_SOURCES[out_name])
			continue
		var f := FileAccess.open(out_abs + str(out_name), FileAccess.WRITE)
		if f == null:
			fails.append("не открыть на запись: " + str(out_name))
			continue
		f.store_buffer(_wav_from_stream(stream))
		f.close()

	for out_name in FILE_COPIES:
		var src: String = ProjectSettings.globalize_path(FILE_COPIES[out_name])
		if not FileAccess.file_exists(src):
			fails.append("нет исходника: " + FILE_COPIES[out_name])
			continue
		var dst: String = out_abs + str(out_name)
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(dst)
		var err := DirAccess.copy_absolute(src, dst)
		if err != OK:
			fails.append("копирование %s: ошибка %d" % [out_name, err])

	if fails.is_empty():
		print("AB EXPORT: PASS — ", OUT_DIR)
		quit(0)  # без quit() -s-скрипт висит в главном цикле вечно
	else:
		for e in fails:
			printerr("AB EXPORT FAIL: " + e)
		quit(1)

## Минимальный WAV-писатель: PCM16 моно из AudioStreamWAV.
func _wav_from_stream(stream: AudioStreamWAV) -> PackedByteArray:
	var data: PackedByteArray = stream.data
	var rate: int = stream.mix_rate
	var bytes := PackedByteArray()
	var data_len := data.size()
	# RIFF-заголовок 44 байта: PCM16 моно.
	bytes.append_array("RIFF".to_utf8_buffer())
	_append_u32(bytes, 36 + data_len)
	bytes.append_array("WAVE".to_utf8_buffer())
	bytes.append_array("fmt ".to_utf8_buffer())
	_append_u32(bytes, 16)
	_append_u16(bytes, 1)        # PCM
	_append_u16(bytes, 1)        # каналы: моно
	_append_u32(bytes, rate)
	_append_u32(bytes, rate * 2) # байтрейт = rate * каналы * 2
	_append_u16(bytes, 2)        # блок = каналы * 2
	_append_u16(bytes, 16)       # бит/сэмпл
	bytes.append_array("data".to_utf8_buffer())
	_append_u32(bytes, data_len)
	bytes.append_array(data)
	return bytes

func _append_u32(bytes: PackedByteArray, v: int) -> void:
	bytes.append(v & 0xFF)
	bytes.append((v >> 8) & 0xFF)
	bytes.append((v >> 16) & 0xFF)
	bytes.append((v >> 24) & 0xFF)

func _append_u16(bytes: PackedByteArray, v: int) -> void:
	bytes.append(v & 0xFF)
	bytes.append((v >> 8) & 0xFF)
