extends SceneTree
## Зонд тряски камеры (19.11.26): Skill.shake (громовой раскат — момент
## исполнения) и impact_shake (метеорит — момент удара). ГРАБЛИ (пойманы):
## (1) в -s-режиме 4.8-beta3 автолоады ГРУЗЯТСЯ — «суррогат» на /root создавал
## ВТОРОЙ инстанс CameraShake с тем же именем (авто-ренейм), зонд мерял не тот
## узел; (2) headless гонит кадры без cap — бюджеты в реальных секундах;
## (3) ps1-обёртка Start-Process+Redirect временами отдаёт лог прошлого
## прогона — прямой запуск через bash с пайпом надёжнее.

func _init() -> void:
	_run.call_deferred()

func _peak_for(cs, sec: float) -> float:
	var peak := 0.0
	var deadline := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peak = maxf(peak, cs._trauma)
	return peak

func _run() -> void:
	# Автолоад CameraShake в -s ГРУЗИТСЯ — берём настоящий, без суррогата.
	var cs = root.get_node_or_null("CameraShake")
	if cs == null:
		print("PROBE FAIL: автолоад CameraShake не найден")
		quit(1)
		return

	var s1 = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(s1)
	for i in 5:
		await process_frame
	var p = get_first_node_in_group("player")
	if p == null:
		print("PROBE FAIL: player не найден")
		quit(1)
		return

	# Громовой раскат: канал 1 с → execute → Skill.shake=0.4.
	p.get_node("SpellCasterComponent").cast_skill("thunderclap")
	var peak_thunder := await _peak_for(cs, 6.0)

	# Метеорит: канал 2 с → падение с неба (15 м, 20 м/с) → impact_shake=0.6.
	# Прицел В ЗЕМЛЮ рядом (иначе луч в горизонт — снаряд летит мимо пола).
	var cam: Camera3D = p.get_node("SpringArm3D/Camera3D")
	cam.rotation_degrees.x = -60.0
	p.get_node("SpellCasterComponent").cast_skill("meteor")
	var peak_meteor := await _peak_for(cs, 10.0)

	var ok := (peak_thunder > 0.0 and peak_meteor > 0.0)
	print("PROBE camera-shake: thunder_peak=%.3f meteor_peak=%.3f -> %s" % [
		peak_thunder, peak_meteor, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
