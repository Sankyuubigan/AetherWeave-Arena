extends SceneTree

## Probe Q16 Шаг 3 (PRP §Шаг 3): HealthComponent баффы защиты/отражения.
## Гейт: клампы в сеттерах (0..0.5 / 0..0.6 — инвариант спеца №36), редукция
## режет урон ровно, отражение наносит attacker ровно raw×ratio, is_reflected
## НЕ отражается обратно (пинг-понг гард), сигнал damage_reflected, старые
## вызовы (1–2 арга) совместимы. EXIT 0 = PASS.

const HC := preload("res://Logic/HealthComponent.gd")

var _pass := 0
var _fail := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _init() -> void:
	call_deferred("_run")

func _mk_hc(pos: Vector3):
	var hc = HC.new()
	root.add_child(hc)
	hc.global_position = pos
	return hc

func _run() -> void:
	print("=== PROBE: Q16 Шаг 3 — HealthComponent баффы ===")
	await process_frame
	var sc = load("res://Logic/HealthComponent.gd")
	_ck(sc != null and sc.can_instantiate(), "парс HealthComponent.gd")

	# 1) Клампы держат (сеттеры — инвариант Logic)
	var hc = _mk_hc(Vector3.ZERO)
	await process_frame
	await process_frame
	hc.damage_reduction = 0.9
	hc.reflect_ratio = 2.0
	_ck(hc.damage_reduction == 0.5, "кламп damage_reduction 0.9 → 0.5")
	_ck(hc.reflect_ratio == 0.6, "кламп reflect_ratio 2.0 → 0.6")
	hc.damage_reduction = -1.0
	hc.reflect_ratio = -1.0
	_ck(hc.damage_reduction == 0.0, "кламп damage_reduction −1 → 0")
	_ck(hc.reflect_ratio == 0.0, "кламп reflect_ratio −1 → 0")
	hc.damage_reduction = 0.0
	hc.reflect_ratio = 0.0

	# 2) Старые сигнатуры совместимы: (amount) и (amount, dir)
	hc.take_damage(30)
	_ck(hc.current_health == 70, "старый вызов (amount): 100−30=70")
	hc.take_damage(10, Vector3(0, 0, -1))
	_ck(hc.current_health == 60, "старый вызов (amount, dir): 70−10=60")

	# 3) Редукция 0.5 режет урон ровно вдвое
	hc.damage_reduction = 0.5
	hc.take_damage(20)
	_ck(hc.current_health == 50, "редукция 0.5: 20 → 10 (hp 50)")

	# 4) Отражение: attacker получает ровно raw × ratio; сигнал жив
	hc.reflect_ratio = 0.3
	hc.damage_reduction = 0.0
	hc.current_health = 100
	var foe = _mk_hc(Vector3(0, 0, -3))
	await process_frame
	var refl_box := []
	hc.damage_reflected.connect(func(a, d, _p): refl_box.append([a, d]))
	var foe_hp_before: int = foe.current_health
	hc.take_damage(20, Vector3.ZERO, foe)
	_ck(foe.current_health == foe_hp_before - 6, "отражение: attacker получил ровно 6 (20×0.3)")
	_ck(hc.current_health == 80, "владелец получил полный 20 (hp 80)")
	_ck(refl_box.size() == 1, "сигнал damage_reflected — 1 раз")
	if refl_box.size() == 1:
		_ck(refl_box[0][0] == foe, "сигнал: attacker передан")
		_ck(int(refl_box[0][1]) == 6, "сигнал: reflected_dmg = 6")

	# 5) Пинг-понг гард: оба с отражением — второго раунда нет
	var a = _mk_hc(Vector3(0, 0, 3))
	await process_frame
	a.reflect_ratio = 0.3
	foe.reflect_ratio = 0.3
	var a_hp: int = a.current_health
	var f_hp: int = foe.current_health
	foe.take_damage(20, Vector3.ZERO, a)
	_ck(foe.current_health == f_hp - 20, "пинг-понг: foe получил 20")
	_ck(a.current_health == a_hp - 6, "пинг-понг: a получил отражение 6")
	_ck(foe.current_health == f_hp - 20, "пинг-понг: повторного раунда нет (foe стабилен)")

	hc.queue_free()
	foe.queue_free()
	a.queue_free()

	if _fail == 0 and _pass > 0:
		print("HEALTH BUFFS GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("HEALTH BUFFS GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
