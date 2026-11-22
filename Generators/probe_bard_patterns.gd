extends SceneTree

## Probe раунд 3 (вердикт спеца 09, В.2): пул фраз Потока по tier. Прямые
## вызовы _on_subdivision_tick(bar, 0) для 16 тактов, детерминизм через
## фиксированный seed _rng. Проверки: фраза ∈ пула своего tier, без повтора
## фразы 2 раза подряд, ≥3 разных паттерна за 8 тактов, ноты строго на
## четвертях сетки (шаг 0.5 с), одна нота на долю (0 одновременных), зазор
## same-lane ≥ 0.45, синкопа (+0.25) только T3 и только на 4-й доле,
## ≥1 синкопа за 16 тактов T3 (фикс. seed). EXIT 0 = PASS.

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

func _get_or_make(script_path: String, node_name: String) -> Node:
	var n = root.get_node_or_null(node_name)
	if n != null:
		return n
	n = load(script_path).new()
	n.name = node_name
	root.add_child(n)
	return n

func _enter_bard(stance: Node) -> void:
	stance.enter_stance({
		"stance_id": "bard_flow",
		"stance_skill_id": "bard_flow",
		"duration": 99.0,
		"rhythm_gate": true,
		"sub_kinds": {"bard_note": "harmony", "bard_chord": "chord"},
		"sub_skills": [
			{"id": "bard_note", "label": "Ноты", "default_slot": "ЛКМ"},
			{"id": "bard_chord", "label": "Аккорд", "default_slot": "ПКМ"},
			{"id": "bard_drop", "label": "Дроп", "default_slot": "self"},
		],
	})

func _run() -> void:
	print("=== PROBE: раунд 3 — пул фраз Потока (В.2) ===")
	await process_frame

	for path in ["res://Logic/RhythmJudge.gd", "res://Logic/RhythmConductor.gd",
			"res://Logic/BardFlowComponent.gd", "res://Logic/StanceComponent.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)

	var cond = _get_or_make("res://Logic/RhythmConductor.gd", "RhythmConductor")
	var judge = _get_or_make("res://Logic/RhythmJudge.gd", "RhythmJudge")
	await process_frame
	judge.conductor = cond
	judge.paused = false

	var pscr := GDScript.new()
	pscr.source_code = "extends Node3D\nvar speed_mult: float = 1.0\n"
	pscr.reload()
	var player = pscr.new()
	player.name = "PatternsPlayer"
	root.add_child(player)
	var stance = load("res://Logic/StanceComponent.gd").new()
	stance.name = "StanceComponent"
	player.add_child(stance)
	var flow = load("res://Logic/BardFlowComponent.gd").new()
	flow.name = "BardFlowComponent"
	player.add_child(flow)
	await process_frame

	# ── Детерминизм: seed задаётся в цикле прогонов (enter делает
	# _rng.randomize() — BardFlowComponent.gd:135), часы — под контролем ──
	_enter_bard(stance)
	flow.fuel = 14.0  # запас: _process тикает только между кадрами, а их нет
	cond.stop()  # часы под контроль пробы: song_time не двигается сам

	# ── 4 прогона по 16 тактов (tier 0..3) ────────────────────────────────
	var all_gaps_ok := true
	var distinct8 := 0
	var syncopa_count := 0
	var pool_ok := true
	var grid_ok := true
	var no_dup_ok := true
	var no_repeat_ok := true
	var tier_stats := ""
	for t in 4:
		flow.tier = t
		# T0–T2: фиксированный seed. T3: скан seed до первой синкопы —
		# положительное покрытие редкого события (15%) с детерминизмом.
		var seed_try := 0
		var syncopa_seen := 0
		while true:
			seed_try += 1
			judge.reset()
			flow._rng.seed = 20261122 + seed_try
			flow._next_phrase = ""
			flow._prev_phrase = ""
			syncopa_seen = 0
			for bar in 16:
				flow._on_subdivision_tick(bar, 0)
			for n in judge.get_notes():
				var tt0: float = float(n["time"])
				var b0 := int(tt0 / 2.0)
				var s0 := int(floor((tt0 - b0 * 2.0) / 0.5))
				var fr0: float = tt0 - (b0 * 2.0 + s0 * 0.5)
				if t == 3 and s0 == 3 and absf(fr0 - 0.25) < 0.000001:
					syncopa_seen += 1
			if t != 3 or syncopa_seen >= 1 or seed_try >= 60:
				break
		if t == 3:
			syncopa_count = syncopa_seen
		# Реконструкция фраз из нот судьи.
		var notes = judge.get_notes()
		var slots: Dictionary = {}
		for n in notes:
			var tt: float = float(n["time"])
			var bidx := int(tt / 2.0)
			var sidx := int(floor((tt - bidx * 2.0) / 0.5))
			var frac: float = tt - (bidx * 2.0 + sidx * 0.5)
			if not slots.has(bidx):
				slots[bidx] = [".", ".", ".", "."]
			if str(slots[bidx][sidx]) != ".":
				no_dup_ok = false  # две ноты на одну долю — запрещено (В.2)
			if absf(frac) > 0.000001 and (t != 3 or sidx != 3 \
					or absf(frac - 0.25) > 0.000001):
				grid_ok = false  # вне сетки четвертей (синкопа только T3/доля 4/+0.25)
			slots[bidx][sidx] = "L" if str(n["kind"]) == "harmony" else "R"
		# Пул, повторы, разнообразие.
		var phrases: Array = []
		for bidx in 16:
			var ph: String = "".join(PackedStringArray(slots[bidx]))
			var in_pool := false
			for p in flow.PHRASES[t]:
				if str(p) == ph:
					in_pool = true
					break
			if not in_pool:
				pool_ok = false
			if bidx > 0 and ph == str(phrases[bidx - 1]):
				no_repeat_ok = false
			phrases.append(ph)
		var d8 := {}
		for i in 8:
			d8[phrases[i]] = true
		if t == 3:
			distinct8 = d8.size()
		# Зазор same-lane ≥ 0.45 (глобально внутри прогона; гард синкопы —
		# первая нота следующего такта другой дорожки — держит зазор).
		for kind in ["harmony", "chord"]:
			var times: Array = []
			for n in notes:
				if str(n["kind"]) == kind:
					times.append(float(n["time"]))
			times.sort()
			for i in range(1, times.size()):
				if float(times[i]) - float(times[i - 1]) < 0.45:
					all_gaps_ok = false
		tier_stats += "T%d:[%s] " % [t, ", ".join(PackedStringArray(phrases.slice(0, 4)))]

	_ck(pool_ok, "фразы из пула своего tier (16 тактов × 4 tier)")
	_ck(no_repeat_ok, "без повтора фразы 2 раза подряд")
	_ck(distinct8 >= 3, "≥3 разных паттерна за 8 тактов T3 (%d)" % distinct8)
	_ck(grid_ok, "ноты на четвертях сетки (синкопа только T3/4-я доля/+0.25)")
	_ck(no_dup_ok, "одна нота на долю (0 одновременных)")
	_ck(all_gaps_ok, "зазор same-lane ≥ 0.45")
	_ck(syncopa_count >= 1, "синкопа встретилась в T3 (%d раз)" % syncopa_count)
	print("  INFO  %s" % tier_stats)

	# ── Cleanup ───────────────────────────────────────────────────────────
	if flow.is_flowing or stance.is_active:
		stance.exit_stance("probe")
	judge.reset()
	player.queue_free()
	await process_frame

	if _fail == 0 and _pass > 0:
		print("BARD PATTERNS GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BARD PATTERNS GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
