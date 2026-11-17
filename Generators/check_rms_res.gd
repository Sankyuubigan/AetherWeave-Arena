extends SceneTree

## Замер громкости итоговых .res игры (те, что реально играют в бою):
## RMS и K-взвешенная LUFS (BS.1770-4, 48 кГц). LUFS — доказательство ровной
## ВОСПРИНИМАЕМОЙ громкости после K-нормы (17.11.26): RMS слеп к спектру.
## Зеркало фильтра — Generators/build_neural_sfx_res.gd и plugin wav.rs.
const FILES := ["neural_beam", "neural_fireball", "neural_thunder", "neural_meteor_fly", "neural_meteor_impact", "neural_ball_lightning", "neural_heart_heal", "neural_teleport", "neural_ui_click"]

# Биквады K-фильтра BS.1770-4 @ 48 кГц (high-shelf → RLB high-pass).
const K_SB0 := 1.53512485958697
const K_SB1 := -2.69169618940638
const K_SB2 := 1.19839281085285
const K_SA1 := -1.69065929318241
const K_SA2 := 0.73248097495126
const K_RB1 := -2.0
const K_RA1 := -1.99004745483398
const K_RA2 := 0.99007225036621

func _init():
	for f in FILES:
		var s = load("res://Audio/SFX/%s.res" % f)
		if s == null or not (s is AudioStreamWAV):
			print(f, ": НЕ ЗАГРУЗИЛСЯ")
			continue
		var data: PackedByteArray = s.data
		var count := data.size() / 2
		var sum_sq := 0.0
		var peak := 0.0
		var ms_k := 0.0
		var s1 := 0.0
		var s2 := 0.0
		var r1 := 0.0
		var r2 := 0.0
		for i in count:
			var x: float = data.decode_s16(i * 2) / 32768.0
			sum_sq += x * x
			peak = maxf(peak, absf(x))
			var ys := K_SB0 * x + s1
			s1 = K_SB1 * x - K_SA1 * ys + s2
			s2 = K_SB2 * x - K_SA2 * ys
			var y := ys + r1
			r1 = K_RB1 * ys - K_RA1 * y + r2
			r2 = ys - K_RA2 * y
			ms_k += y * y
		var rms := sqrt(sum_sq / maxf(1.0, float(count)))
		ms_k /= maxf(1.0, float(count))
		var lufs := -0.691 + 10.0 * log(maxf(ms_k, 0.000000001)) / log(10.0)
		print("%-24s RMS=%5.1f dBFS  K-громкость=%6.1f LUFS  peak=%.3f  rate=%d" % [f, linear_to_db(maxf(rms, 0.000001)), lufs, peak, s.mix_rate])
	quit(0)
