extends SceneTree
## СМОУК ПРОВОДКИ СКИЛЛОВ (26.11.26) — все 9 скиллов списка юзера.
##
## ПОЧЕМУ: проводка «скилл → клип» — данные в SkillDB, и любая опечатка/пустое
## поле не ломает парсинг, а ТИХО оставляет скилл без анимации (именно так жил
## баг «у wings вообще ничего не стоит»). Смоук кастует каждый скилл на живом
## игроке и проверяет ФАКТ: какой клип реально играет каст-слой.
##
## Запуск: --headless -s res://Generators/smoke_skill_casts.gd (EXIT=0=PASS)

const PLAYER_SCENE := "res://Scenes/player.tscn"
const SKILLDB := preload("res://Logic/Skills/SkillDB.gd")

var player: Node
var caster: Node
var anim_comp: Node
var fails: Array[String] = []
var _rejected: Array[String] = []
var _done := false

## Ожидание: skill_id → что обязан играть каст-слой после каста.
const EXPECT := {
	"portals": "Cast_2H_Spell",
	"portals2": "Cast_2H_Spell",
	"teleport": "Teleport_Vanish",
	"wings": "Wings_Fly",
	"meteor": "Cast_2H_Area_01",
	"thunderclap": "Cast_2H_Magic_01",
	"energy_blade": "Throw",          # первый каст = материализация
}

func _init() -> void:
	_watchdog()
	call_deferred("_run")

func _watchdog() -> void:
	await create_timer(60.0).timeout
	if not _done:
		print("SMOKE FAIL: сторож 60 с")
		quit(1)

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 20:
		await process_frame
	caster = player.get_node_or_null("SpellCasterComponent")
	anim_comp = player.get_node_or_null("PlayerAnimationComponent")
	if caster == null or anim_comp == null:
		print("SMOKE FAIL: нет компонентов каста/анимации")
		_done = true
		quit(1)
		return
	if player.get_node_or_null("SpringArm3D/Camera3D") == null:
		print("SMOKE FAIL: нет камеры — все касты отменятся в _aim_context")
		_done = true
		quit(1)
		return
	caster.cast_rejected.connect(func(reason: String): _rejected.append(reason))

	# ── 1) ДАННЫЕ: у каждого скилла списка задано ровно то, что решил юзер
	print("=== 1) данные SkillDB ===")
	var skills = SKILLDB.get_skills()
	_ck(str(skills["portals"].cast_anim) == "Cast_2H_Spell",
			"portals.cast_anim = " + str(skills["portals"].cast_anim))
	_ck(str(skills["portals2"].cast_anim) == "Cast_2H_Spell",
			"portals2.cast_anim = " + str(skills["portals2"].cast_anim))
	_ck(str(skills["teleport"].cast_anim) == "Teleport_Vanish",
			"teleport.cast_anim = " + str(skills["teleport"].cast_anim))
	_ck(str(skills["wings"].cast_anim) == "Wings_Fly" and bool(skills["wings"].cast_anim_loop),
			"wings: cast_anim=%s loop=%s" % [skills["wings"].cast_anim, skills["wings"].cast_anim_loop])
	_ck(str(skills["meteor"].cast_anim) == "Cast_2H_Area_01",
			"meteor.cast_anim = " + str(skills["meteor"].cast_anim))
	_ck(str(skills["thunderclap"].cast_anim) == "Cast_2H_Magic_01",
			"thunderclap.cast_anim = " + str(skills["thunderclap"].cast_anim))
	_ck(str(skills["energy_blade"].cast_anim) == "Blade_Swing_A"
			and str(skills["energy_blade"].next_cast_anim) == "Blade_Swing_B",
			"energy_blade: %s → %s" % [skills["energy_blade"].cast_anim,
					skills["energy_blade"].next_cast_anim])
	_ck(str(skills["bard_flow"].stance_loop_anim) == "Bard_Guitar",
			"bard_flow.stance_loop_anim = " + str(skills["bard_flow"].stance_loop_anim))
	_ck(str(skills["bard_groove"].stance_loop_anim) == "Bard_Guitar_2",
			"bard_groove.stance_loop_anim = " + str(skills["bard_groove"].stance_loop_anim))

	# ── 2) КЛИПЫ СУЩЕСТВУЮТ в библиотеке (иначе каст молча без анимации)
	print("=== 2) клипы есть в каст-библиотеке ===")
	for n in ["Cast_2H_Spell", "Teleport_Vanish", "Teleport_Appear", "Wings_Fly",
			"Cast_2H_Area_01", "Cast_2H_Magic_01", "Blade_Swing_A", "Blade_Swing_B",
			"Bard_Guitar", "Bard_Guitar_2", "Tether_Hang"]:
		_ck(anim_comp.has_cast_anim(n), "клип в библиотеке: " + str(n))

	# ── 3) РЕАЛЬНЫЕ КАСТЫ: играет ожидаемый клип
	print("=== 3) касты на живом игроке ===")
	for sid in EXPECT:
		await _wait_until_idle()
		var rej_before: int = _rejected.size()
		var got: String = await _cast_and_read(sid)
		if _rejected.size() > rej_before:
			_ck(false, "%s ОТКЛОНЁН: %s" % [sid, _rejected[-1]])
			continue
		_ck(got.trim_suffix("_UB") == str(EXPECT[sid]),
				"%s → %s (получено %s)" % [sid, EXPECT[sid], got])

	# ── 4) клип-состояние крыльев гасится владельцем (WingsComponent)
	print("=== 4) клип-состояние: включение и гашение ===")
	await _wait_until_idle()
	await _cast_skill("wings", 3)
	_ck(str(anim_comp.cast_player.current_animation) == "Wings_Fly_UB",
			"wings держит позу Wings_Fly_UB, получено: " + str(anim_comp.cast_player.current_animation))
	var wings = player.get_node_or_null("Wings")
	if wings != null:
		wings.call("deactivate")
		await process_frame
		_ck(not bool(anim_comp.has_loop_state()), "wings.deactivate снял клип-состояние")
	else:
		fails.append("wings.deactivate: нет узла Wings")

	# ── 5) трос: поза появляется при ЗАЦЕПЕ и снимается при отрыве
	# Зацеп в воздух — ЛЕГАЛЬНЫЙ режим (ТЗ: ЛКМ в небо = эфирный якорь), поэтому
	# проверяем не «нет цели», а контракт владельца: activate → поза есть,
	# release → позы нет. Раньше ждал «нет зацепа» — падало на здоровом коде.
	print("=== 5) трос: поза при зацепе и снятие при отрыве ===")
	await _wait_until_idle()
	await _cast_skill("ether_tether", 3)
	var tether = player.get_node_or_null("TetherSwing")
	if tether == null:
		fails.append("ether_tether: нет узла TetherSwing — эффект не активировался")
	else:
		_ck(bool(anim_comp.has_loop_state()),
				"зацеп включил позу Tether_Hang (состояние: %s)" % str(anim_comp.cast_player.current_animation))
		tether.call("release", false)
		await process_frame
		_ck(not bool(anim_comp.has_loop_state()), "release снял позу Tether_Hang")

	print("")
	if fails.is_empty():
		print("SMOKE: ALL PASS")
		_done = true
		quit(0)
	else:
		print("SMOKE: FAIL (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		_done = true
		quit(1)

func _cast_skill(sid: String, frames: int) -> void:
	caster.call("cast_skill", sid)
	for i in frames:
		await process_frame

func _cast_and_read(sid: String) -> String:
	caster.call("cast_skill", sid)
	for i in 6:
		await process_frame
	return str(anim_comp.cast_player.current_animation)

## Дождаться конца инсты/канала: иначе следующий каст отклоняется «Идёт другой каст».
func _wait_until_idle() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var busy := bool(caster.get("_channeling")) or bool(caster.call("_insta_running"))
		if not busy:
			return
		await process_frame

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)

func _ck(ok: bool, msg: String) -> void:
	if ok:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
		fails.append(msg)
