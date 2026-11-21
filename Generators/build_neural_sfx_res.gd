extends SceneTree
## Конвертация нейро-WAV (MOSS 48кГц 16бит моно) → AudioStreamWAV .res
## для SkillDB (паттерн build_laser_sfx.gd: .res без --import).
##
## Нормализация (17.11.26): K-взвешенная по BS.1770-4 (LUFS) — RMS слеп к
## спектру (бас давит, шипение звенит при равном RMS), поэтому «в игре
## разная громкость». Зеркало логики — plugin-audio-gen-engine wav.rs.
##
## Запуск:
## & "...Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/build_neural_sfx_res.gd

const SRC_DIR := "D:/Projects/3d_game/Audio/Gen/neural"
const DST_DIR := "res://Audio/SFX"

## Цель воспринимаемой громкости: -18 LUFS (K-громкость, BS.1770-4).
const LUFS_TARGET := -18.0
const MS_TARGET := 0.018591  # 10^((-18 + 0.691) / 10)
## Потолок пика -1 dBFS — защита от клиппинга после усиления.
const PEAK_CEIL := 0.891
## RMS-фолбэк для не-48кГц (коэффициенты биквадов посчитаны под 48к).
const TARGET_RMS := 0.126

## Биквады K-фильтра BS.1770-4 @ 48 кГц (high-shelf → RLB high-pass).
const K_SB0 := 1.53512485958697
const K_SB1 := -2.69169618940638
const K_SB2 := 1.19839281085285
const K_SA1 := -1.69065929318241
const K_SA2 := 0.73248097495126
const K_RB1 := -2.0
const K_RA1 := -1.99004745483398
const K_RA2 := 0.99007225036621

## 16-бит PCM → нормализация громкости. 48кГц → K/LUFS, прочие → RMS.
func _normalize_data(src_name: String, data: PackedByteArray, rate: int) -> PackedByteArray:
	if rate == 48000:
		return _normalize_data_k(src_name, data)
	print("[NEURAL-SFX] %s: %d Гц ≠ 48к → RMS-фолбэк" % [src_name, rate])
	return _normalize_data_rms(src_name, data)

## K-взвешенная нормализация (BS.1770-4, 48 кГц, моно): сигнал гоняется через
## K-фильтр (ухо), mean square фильтрованного → LUFS → гейн к цели; пик
## ограничен потолком. Измерение фильтром, усиление — исходного сигнала.
func _normalize_data_k(src_name: String, data: PackedByteArray) -> PackedByteArray:
	if data.size() < 2:
		return data
	var count := data.size() / 2
	var peak := 0.0
	var ms := 0.0
	var s1 := 0.0
	var s2 := 0.0  # состояние шельфа
	var r1 := 0.0
	var r2 := 0.0  # состояние RLB
	for i in count:
		var x := float(data.decode_s16(i * 2)) / 32768.0
		var a := absf(x)
		if a > peak:
			peak = a
		var ys := K_SB0 * x + s1
		s1 = K_SB1 * x - K_SA1 * ys + s2
		s2 = K_SB2 * x - K_SA2 * ys
		var y := ys + r1
		r1 = K_RB1 * ys - K_RA1 * y + r2
		r2 = ys - K_RA2 * y
		ms += y * y
	ms /= count
	if ms < 0.0000001 or peak <= 0.0001:
		return data  # тишина/брак генерации — не трогаем
	var loudness := -0.691 + 10.0 * log(ms) / log(10.0)
	var gain := pow(10.0, (LUFS_TARGET - loudness) / 20.0)
	if gain * peak > PEAK_CEIL:
		gain = PEAK_CEIL / peak  # пик бы вылез за -1 dBFS — режем гейн
	if absf(linear_to_db(gain)) < 0.5:
		return data  # уже в норме
	print("[NEURAL-SFX] K-норма %s: %.1f LUFS → -18, gain=%+.1f dB (peak %.3f)" % [src_name, loudness, linear_to_db(gain), peak * gain])
	var out := data.duplicate()
	for i in count:
		var v := int(round(float(data.decode_s16(i * 2)) * gain))
		out.encode_s16(i * 2, clampi(v, -32768, 32767))
	return out

## RMS-фолбэк (старая логика): к -18 dBFS, пик ≤ потолка. Тихие/битые не трогаем.
func _normalize_data_rms(src_name: String, data: PackedByteArray) -> PackedByteArray:
	if data.size() < 2:
		return data
	var count := data.size() / 2
	var sum_sq := 0.0
	var peak := 0.0
	for i in count:
		var s := float(data.decode_s16(i * 2)) / 32768.0
		sum_sq += s * s
		var a := absf(s)
		if a > peak:
			peak = a
	if count == 0 or peak <= 0.0001:
		return data
	var rms := sqrt(sum_sq / count)
	if rms <= 0.0001:
		return data
	var gain := TARGET_RMS / rms
	if gain * peak > PEAK_CEIL:
		gain = PEAK_CEIL / peak  # пик бы вылез за -1 dBFS — режем гейн
	if absf(linear_to_db(gain)) < 0.5:
		return data  # уже в норме
	print("[NEURAL-SFX] RMS-норма %s: gain=%+.1f dB (rms %.3f→%.3f, peak %.3f)" % [src_name, linear_to_db(gain), rms, rms * gain, peak * gain])
	var out := data.duplicate()
	for i in count:
		var v := int(round(float(data.decode_s16(i * 2)) * gain))
		out.encode_s16(i * 2, clampi(v, -32768, 32767))
	return out

## Имя файла (без .wav) → имя .res (без расширения). Только то, что реально
## подключаем в SkillDB. v2 (17.11.26 вердикты): сердечко-дзинь, тесла-шаровая,
## метеор разделён на полёт (каст) + удар (meta на снаряде).
const MAP := {
	"beam_laser": "neural_beam",
	"fireball": "neural_fireball",
	"thunderclap": "neural_thunder",
	"neural_meteor_fly": "neural_meteor_fly",
	"neural_meteor_impact": "neural_meteor_impact",
	"neural_ball_lightning": "neural_ball_lightning",
	"neural_heart_heal": "neural_heart_heal",
	# v3 «волшебный дзынь» (17.11.26 раунд 3): v3a — вердикт-лидер, v3d/e/f —
	# его родня для рандом-пула (SkillDB heart). v3b/c — запас в прослушке.
	"heart_heal_v3a": "heart_heal_v3a",
	"heart_heal_v3b": "heart_heal_v3b",
	"heart_heal_v3c": "heart_heal_v3c",
	"heart_heal_v3d": "heart_heal_v3d",
	"heart_heal_v3e": "heart_heal_v3e",
	"heart_heal_v3f": "heart_heal_v3f",
	"teleport_warp": "neural_teleport",
	"ui_click": "neural_ui_click",
	# Q47 (21.11.26): магический эмбиент нейро-портала — MOSS 8178, 8 с loop
	# (loop включается рантайм в PortalArchVisual._enable_loop).
	"portal_ambient": "neural_portal_ambient",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DST_DIR)
	var ok := 0
	var failed: Array[String] = []
	for src_name in MAP:
		var dst_name: String = MAP[src_name]
		var wav_path: String = SRC_DIR + "/" + str(src_name) + ".wav"
		if not FileAccess.file_exists(wav_path):
			failed.append(dst_name + ": нет " + wav_path)
			continue
		var stream := _wav_to_stream(wav_path)
		if stream == null:
			failed.append(dst_name + ": битый WAV")
			continue
		var res_path := DST_DIR + "/" + dst_name + ".res"
		var err := ResourceSaver.save(stream, res_path)
		if err != OK:
			failed.append(dst_name + ": save err " + str(err))
		else:
			ok += 1
			var bytes: int = FileAccess.open(res_path, FileAccess.READ).get_length()
			print("[NEURAL-SFX] %s.res: %d байт" % [dst_name, bytes])
	for f in failed:
		print("[NEURAL-SFX] FAIL: ", f)
	print("[NEURAL-SFX] готово: %d ok, %d fail" % [ok, failed.size()])
	quit(0 if failed.is_empty() else 1)

## WAV (PCM 16бит) → AudioStreamWAV. Парсим чанки честно (не хардкод 44 байта).
func _wav_to_stream(path: String) -> AudioStreamWAV:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_32() != 0x46464952:  # "RIFF"
		return null
	f.get_32()  # размер файла
	if f.get_32() != 0x45564157:  # "WAVE"
		return null
	var fmt: int = AudioStreamWAV.FORMAT_16_BITS
	var rate := 48000
	var stereo := false
	var data := PackedByteArray()
	while f.get_position() + 8 <= f.get_length():
		var chunk_id := f.get_32()
		var chunk_size := f.get_32()
		if chunk_id == 0x20746D66:  # "fmt "
			var audio_format := f.get_16()
			var channels := f.get_16()
			rate = f.get_32()
			f.get_32()  # byte rate
			f.get_16()  # block align
			var bits := f.get_16()
			if audio_format != 1 or bits != 16:
				return null  # ждём PCM 16
			stereo = channels >= 2
		elif chunk_id == 0x61746164:  # "data"
			data = f.get_buffer(chunk_size)
		else:
			f.seek(f.get_position() + chunk_size)
		if chunk_size % 2 == 1:
			f.seek(f.get_position() + 1)  # чанки выровнены по 2
	var stream := AudioStreamWAV.new()
	stream.format = fmt
	stream.mix_rate = rate
	stream.stereo = stereo
	stream.data = _normalize_data(path.get_file(), data, rate)
	return stream
