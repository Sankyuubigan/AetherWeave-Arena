extends SceneTree

## Probe Q16 Шаг 2 (PRP §Шаг 2): вертикальный срез «Концентрация маны».
## Гейт: вход по Q, ступени заряда power 1.0/1.3/1.6, Сокрушение (ЛКМ) бьёт
## манекен и отбрасывает, Сгусток (ПКМ) летит и попадает, Серп (self/Q) бьёт
## 2 цели в секторе ±60° и НЕ бьёт за спиной, таймаут закрывает стойку
## (reason="timeout"), Esc отменяет ("cancel"), после выхода обычные касты.
## exit_on_sub (вердикт юзера 22.11.26): каждый приём разряжает стойку
## (reason="sub_used"), повторный вход между ступенями заряда. EXIT 0 = PASS.

const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SKILL := preload("res://Logic/Skills/Skill.gd")
const StanceScript := preload("res://Logic/StanceComponent.gd")
const ActionBarScript := preload("res://Graphics/ActionBar.gd")
const SpellCasterScript := preload("res://Logic/SpellCasterComponent.gd")
const VFXScript := preload("res://Graphics/ManaStanceVFX.gd")

const STUB_PLAYER := "extends CharacterBody3D\nvar unlocked_skills := {}\nvar skill_points := 10\nfunc use_skill(id: String) -> void:\n\tif not unlocked_skills.get(id, false):\n\t\treturn\n\tvar sc = get_node_or_null(\"SpellCasterComponent\")\n\tif sc:\n\t\tsc.cast_skill(id)\n"
const PROBE_EFFECT := 'extends "res://Logic/Skills/Effect.gd"\nfunc apply(caster: Node, _ctx: Dictionary) -> void:\n\tcaster.set_meta("probe_normal_cast", "yes")\n'
const MANNEQUIN := "extends CharacterBody3D\nfunc take_damage(amount, impulse_dir = Vector3.ZERO):\n\tvar h = get_meta(\"hits\", [])\n\th.append({\"dmg\": amount, \"imp\": impulse_dir})\n\tset_meta(\"hits\", h)\n"

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

func _mk_dyn(src: String):
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	return gs.new()

func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _mouse_event(btn: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	return ev

func _slot_by_label(bar, label: String):
	for slot in bar.slots:
		if str(slot.key_info.get("label", "")) == label:
			return slot
	return null

func _mk_mannequin(pos: Vector3):
	var m = _mk_dyn(MANNEQUIN)
	m.set_meta("hits", [])
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.6
	cs.shape = sh
	m.add_child(cs)
	root.add_child(m)
	m.global_position = pos
	return m

func _hits(m) -> Array:
	return m.get_meta("hits", [])

func _wait_charge(stance, target: float) -> void:
	var guard := 0
	while stance.charge < target and guard < 10000:
		guard += 1
		await process_frame

func _run() -> void:
	print("=== PROBE: Q16 Шаг 2 — «Концентрация маны» ===")
	await process_frame

	# 0) Парс затронутых скриптов + ассет снаряда
	for path in ["res://Logic/Skills/MeleeShoveEffect.gd", "res://Logic/Skills/CrescentWaveEffect.gd",
			"res://Logic/Skills/AoeDamageEffect.gd", "res://Logic/Skills/SpawnProjectileEffect.gd",
			"res://Logic/Skills/EnterStanceEffect.gd", "res://Logic/StanceComponent.gd",
			"res://Graphics/ManaStanceVFX.gd", "res://Logic/Skills/SkillDB.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)
	_ck(ResourceLoader.exists("res://Scenes/mana_bolt.tscn"), "сцена mana_bolt.tscn существует")

	# 1) SkillDB-сборка: стойка + под-приёмы (гварды магазина)
	var all := SDB.get_skills()
	_ck(all.has("mana_concentration"), "mana_concentration в реестре")
	_ck(all.has("mana_crush") and all.has("mana_bolt") and all.has("mana_crescent"), "3 под-приёма в реестре")
	_ck(all["mana_crush"].is_sub_skill and all["mana_bolt"].is_sub_skill \
			and all["mana_crescent"].is_sub_skill, "под-приёмы is_sub_skill=true")
	_ck(not SDB.get_shop_skills().has("mana_crush"), "под-приём скрыт из магазина")
	_ck(SDB.get_shop_skills().has("mana_concentration"), "стойка видна в магазине")
	_ck(all["mana_concentration"].stance_sub_skills.size() == 3, "стойка несёт 3 под-приёма")

	# 2) Стаб игрока + компоненты + манекены
	var player = _mk_dyn(STUB_PLAYER)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	arm.add_child(cam)
	player.add_child(arm)
	var sc_node := Node.new()
	sc_node.name = "SpellCasterComponent"
	sc_node.set_script(SpellCasterScript)
	player.add_child(sc_node)
	var stance := Node.new()
	stance.name = "StanceComponent"
	stance.set_script(StanceScript)
	player.add_child(stance)
	var vfx := Node.new()
	vfx.name = "ManaStanceVFX"
	vfx.set_script(VFXScript)
	player.add_child(vfx)
	var bar := ActionBarScript.new()
	player.add_child(bar)
	root.add_child(player)
	await process_frame
	await process_frame

	var mkA = _mk_mannequin(Vector3(0, 1.0, -4.5))
	var mkB = _mk_mannequin(Vector3(-2, 1.0, -6.0))
	var mkC = _mk_mannequin(Vector3(2, 1.0, -7.0))
	var mkD = _mk_mannequin(Vector3(0, 1.0, 5.0))

	# 3) Раскладка + вход по Q (обычный путь ActionBar → SkillDB-сборка)
	player.unlocked_skills["mana_concentration"] = true
	_slot_by_label(bar, "Q").set_skill("mana_concentration")
	var probe_skill = SKILL.new()
	probe_skill.id = "probe_normal"
	probe_skill.skill_name = "probe_normal"
	probe_skill.icon = "🅝"
	probe_skill.effects.append(_mk_dyn(PROBE_EFFECT))
	SDB._skills["probe_normal"] = probe_skill
	player.unlocked_skills["probe_normal"] = true
	_slot_by_label(bar, "5").set_skill("probe_normal")

	var exit_box := [""]
	stance.stance_exited.connect(func(r): exit_box[0] = r)

	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	await process_frame
	_ck(stance.is_active, "вход по Q: стойка активна")
	_ck(stance.overrides.get("ЛКМ", "") == "mana_crush", "дефолт ЛКМ → mana_crush")
	_ck(stance.overrides.get("ПКМ", "") == "mana_bolt", "дефолт ПКМ → mana_bolt")
	_ck(stance.overrides.get("self", "") == "mana_crescent", "дефолт self → mana_crescent")
	_ck(stance.stance_entered.get_connections().size() >= 2, "ActionBar и ManaStanceVFX слушают стойку")

	# 4) Ступень 1 (power 1.0): Сокрушение бьёт и отбрасывает
	bar._input(_mouse_event(MOUSE_BUTTON_LEFT))
	await process_frame
	var hA := _hits(mkA)
	_ck(hA.size() == 1, "Сокрушение попало ровно в ближний манекен")
	if hA.size() >= 1:
		_ck(int(hA[0]["dmg"]) == 30, "урон Сокрушения = 30 (power 1.0)")
		_ck((hA[0]["imp"] as Vector3).length() > 0.01, "отброс рэгдолла приложен")
	# exit_on_sub (вердикт юзера 22.11.26): приём = разряд стойки — закрытие
	# сразу после успешного каста под-приёма.
	_ck(not stance.is_active, "exit_on_sub: Сокрушение закрыло стойку")
	_ck(exit_box[0] == "sub_used", "reason приёма = sub_used")

	# 5) Ступень 2 (power 1.3): повторный вход — exit_on_sub закрыл стойку
	#    после Сокрушения; Сгусток летит и попадает, снова разряд.
	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	await process_frame
	_ck(stance.is_active, "повторный вход после разряда (ступень 2)")
	await _wait_charge(stance, 0.55)
	_ck(stance.stance_power() == 1.3, "ступень 2 заряда → power 1.3")
	var before := _hits(mkA).size()
	bar._input(_mouse_event(MOUSE_BUTTON_RIGHT))
	var bolt_guard := 0
	while bolt_guard < 900 and _hits(mkA).size() <= before:
		bolt_guard += 1
		await process_frame
	_ck(_hits(mkA).size() > before, "Сгусток долетел и попал в манекен")
	if _hits(mkA).size() > before:
		var bd := int(_hits(mkA)[_hits(mkA).size() - 1]["dmg"])
		_ck(bd == 32, "урон Сгустка = 32 (25 × 1.3), получено %d" % bd)
	# Разряд повторяется на КАЖДОМ приёме: Сгусток тоже закрыл стойку.
	_ck(not stance.is_active, "exit_on_sub: Сгусток тоже закрыл стойку")
	_ck(exit_box[0] == "sub_used", "reason Сгустка = sub_used")

	# 6) Ступень 3 (power 1.6): повторный вход; Серп бьёт сектор ±60°, за спину
	#    не достаёт; снова разряд.
	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	await process_frame
	_ck(stance.is_active, "повторный вход после разряда (ступень 3)")
	await _wait_charge(stance, 1.05)
	_ck(stance.stance_power() == 1.6, "ступень 3 заряда → power 1.6")
	var nA := _hits(mkA).size()
	var nB := _hits(mkB).size()
	var nC := _hits(mkC).size()
	var nD := _hits(mkD).size()
	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	_ck(_hits(mkA).size() == nA + 1, "Серп бьёт центральную цель")
	_ck(_hits(mkB).size() == nB + 1, "Серп бьёт левую цель в секторе")
	_ck(_hits(mkC).size() == nC + 1, "Серп бьёт правую цель в секторе")
	_ck(_hits(mkD).size() == nD, "Серп НЕ бьёт за спиной")
	if _hits(mkA).size() == nA + 1:
		var cd := int(_hits(mkA)[_hits(mkA).size() - 1]["dmg"])
		_ck(cd == 35, "урон Серпа = 35 (22 × 1.6), получено %d" % cd)
	# Разряд повторяется на КАЖДОМ приёме: Серп тоже закрыл стойку.
	_ck(not stance.is_active, "exit_on_sub: Серп тоже закрыл стойку")
	_ck(exit_box[0] == "sub_used", "reason Серпа = sub_used")

	# 7) Таймаут закрывает стойку (ускорение ×5; повторный вход — exit_on_sub
	#    закрыл стойку после Серпа)
	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	await process_frame
	_ck(stance.is_active, "повторный вход для таймаута")
	Engine.time_scale = 5.0
	var tguard := 0
	while stance.is_active and tguard < 20000:
		tguard += 1
		await process_frame
	Engine.time_scale = 1.0
	_ck(not stance.is_active, "таймаут закрыл стойку")
	_ck(exit_box[0] == "timeout", "reason таймаута = timeout (получено «%s»)" % exit_box[0])

	# 8) Esc отменяет активную стойку (UI-гард: окон нет — отмена разрешена)
	bar._unhandled_input(_key_event(KEY_Q))
	await process_frame
	await process_frame
	_ck(stance.is_active, "повторный вход по Q работает")
	_ck(not stance._ui_open(), "UI-гард: окна закрыты → Esc пройдёт")
	stance._unhandled_input(_key_event(KEY_ESCAPE))
	_ck(not stance.is_active, "Esc отменил стойку")
	_ck(exit_box[0] == "cancel", "reason Esc = cancel (получено «%s»)" % exit_box[0])

	# 9) После выхода обычные касты работают
	bar._unhandled_input(_key_event(KEY_5))
	await process_frame
	_ck(player.has_meta("probe_normal_cast"), "после выхода KEY_5 кастует обычный скилл")
	_ck(not stance.try_handle_slot("ЛКМ"), "try_handle_slot после выхода = false")

	# Cleanup
	SDB._skills.erase("probe_normal")
	for m in [mkA, mkB, mkC, mkD]:
		m.queue_free()
	player.queue_free()

	if _fail == 0 and _pass > 0:
		print("STANCE MANA GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("STANCE MANA GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
