extends SceneTree

## Probe раунд 3 (вердикт спеца 09, В.1.2+В.1.3): анти-спам Потока.
## Спам ЛКМ каждые 0.10 с по часам conductor → fuel_out раньше 3.0 с
## song-времени, tier не доезжает 3, кастов bard_note НОЛЬ (гейт В.1.3:
## каст только за попадание). ЛКМ в chord-ноту → empty_press, chord-нота
## цела. Спам ПКМ вне окон → 0 кастов. EXIT 0 = PASS. Автолоады
## get-or-make (урок 22.11.26). cfg не трогаем.

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
	print("=== PROBE: раунд 3 — анти-спам Потока (В.1.2/В.1.3) ===")
	await process_frame

	for path in ["res://Logic/RhythmJudge.gd", "res://Logic/RhythmConductor.gd",
			"res://Logic/BardFlowComponent.gd", "res://Logic/StanceComponent.gd",
			"res://Logic/SpellCasterComponent.gd"]:
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
	player.name = "AntispamPlayer"
	root.add_child(player)
	var stance = load("res://Logic/StanceComponent.gd").new()
	stance.name = "StanceComponent"
	player.add_child(stance)
	var flow = load("res://Logic/BardFlowComponent.gd").new()
	flow.name = "BardFlowComponent"
	player.add_child(flow)
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar calls := []\nfunc cast_skill(id, ctx):\n\tcalls.append([id, ctx])\n"
	stub.reload()
	var caster = stub.new()
	caster.name = "SpellCasterComponent"
	player.add_child(caster)
	stance.stance_exited.connect(func(_r): pass)
	await process_frame

	# ── 1) Спам ЛКМ каждые 0.10 с → fuel_out < 3.0 с song-времени ────────
	_enter_bard(stance)
	cond.stop()  # часы под наш контроль: song_time двигаем руками
	judge.reset()
	flow.fuel = 5.0
	var presses := 0
	while flow.is_flowing and presses < 200:
		cond.song_time += 0.10
		if not stance.try_handle_slot("ЛКМ"):
			break
		presses += 1
	await process_frame
	await process_frame
	_ck(str(flow.last_exit_reason) == "fuel_out", "спам ЛКМ → fuel_out")
	var song_elapsed := float(presses) * 0.10
	_ck(song_elapsed < 3.0, "fuel_out раньше 3.0 с song-времени (%.1f с)" % song_elapsed)
	_ck(flow.tier < 3, "спам не доезжает Tier 3 (tier=%d)" % flow.tier)
	_ck(presses >= 5, "спам прошёл через анти-дребезг (%d прессов)" % presses)

	# ── 2) ЛКМ в chord-ноту → empty_press, chord-нота цела ───────────────
	_enter_bard(stance)
	cond.stop()
	judge.reset()
	judge.paused = false
	flow.fuel = 5.0
	var chord_id: int = judge.register_note("chord", cond.song_time + 0.01)
	var fuel0: float = flow.fuel
	_ck(stance.try_handle_slot("ЛКМ"), "ЛКМ перехвачен стойкой")
	_ck(caster.calls.is_empty(), "пустой пресс: каста НЕТ (гейт В.1.3)")
	_ck(absf(flow.fuel - (fuel0 - 1.2)) < 0.0001, "empty_press: −1.2 топлива")
	_ck(not bool(judge._notes[chord_id]["judged"]), "chord-нота не тронута чужим прессом")
	# ПКМ в ту же chord-ноту — judged perfect, каст bard_chord есть.
	_ck(stance.try_handle_slot("ПКМ"), "ПКМ перехвачен стойкой")
	_ck(str(caster.calls[caster.calls.size() - 1][0]) == "bard_chord", "ПКМ в chord-ноту → каст")
	_ck(bool(judge._notes[chord_id]["judged"]), "chord-нота судится СВОИМ прессом")

	# ── 3) Спам ПКМ вне окон → 0 кастов bard_chord ───────────────────────
	if stance.is_active:
		stance.exit_stance("probe")  # секция 2 закончилась perfect — стойка жива
	await process_frame
	_enter_bard(stance)
	cond.stop()
	judge.reset()
	flow.fuel = 5.0
	var calls3: int = caster.calls.size()  # касты ТОЛЬКО этой секции
	for i in 30:
		cond.song_time += 0.25  # шаг 0.25 > анти-дребезга 0.18 — каждый штрафует
		if not stance.try_handle_slot("ПКМ"):
			break
	await process_frame
	await process_frame
	var rmb_casts := 0
	var lmb_casts := 0
	for i in range(calls3, caster.calls.size()):
		if str(caster.calls[i][0]) == "bard_chord":
			rmb_casts += 1
		else:
			lmb_casts += 1
	_ck(rmb_casts == 0, "спам ПКМ вне окон → 0 кастов bard_chord")
	_ck(lmb_casts == 0, "спам ПКМ → 0 кастов bard_note тоже")
	_ck(str(flow.last_exit_reason) == "fuel_out", "спам ПКМ → fuel_out (−1.2 × N)")

	# Cleanup
	if flow.is_flowing or stance.is_active:
		stance.exit_stance("probe")
	cond.stop()
	judge.reset()
	player.queue_free()
	await process_frame

	if _fail == 0 and _pass > 0:
		print("BARD ANTISPAM GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BARD ANTISPAM GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
