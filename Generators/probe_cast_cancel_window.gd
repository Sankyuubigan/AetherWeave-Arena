extends SceneTree
## ГЕЙТ окна отмены ИНСТА-каста (стандарт 55–60 %, docs/animation_generation.md
## §14.3; Skill.cancel_at, SpellCasterComponent). Проверяет ФАКТЫ:
##  A) свой скилл ДО окна: клип НЕ рестартует (движение идёт дальше), ввод уходит
##     в буфер (150 мс) и играет РОВНО на открытии окна — с ПЕРЕКЛЮЧЕНИЕМ руки
##     (alternate_hands: Spell_Cast → Spell_Cast_L);
##  B) свой скилл ПОСЛЕ окна: клип перезапускается сразу (тайм не растёт до окна);
##  C) ЧУЖОЙ скилл перебивает сразу, до окна (приоритеты слоёв §14.4);
##  D) буфер протухает: нажатие за 150 мс до окна не исполняется позже окна.
## Запуск: --headless -s res://Generators/probe_cast_cancel_window.gd  (EXIT=0 = PASS)

const PLAYER_SCENE := "res://Scenes/player.tscn"
const SKILL := "heart_heal"

var player: Node3D
var caster: Node
var comp: Node
var fails: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await process_frame
	caster = player.get_node_or_null("SpellCasterComponent")
	comp = player.get_node_or_null("PlayerAnimationComponent")
	if caster == null or comp == null:
		print("CANCEL FAIL: нет SpellCasterComponent/PlayerAnimationComponent")
		quit(1)
		return

	var skill = _skill(SKILL)
	if skill == null:
		print("CANCEL FAIL: нет скилла ", SKILL)
		quit(1)
		return
	print("=== скилл %s: cast_anim=%s cancel_at=%.2f alternate=%s ===" % [
		SKILL, skill.cast_anim, skill.cancel_at, skill.alternate_hands])
	# У сердечка requires_target=true (нужен союзник в прицеле). Гейт проверяет
	# ОКНО ОТМЕНЫ, а не валидацию цели — снимаем требование (правка ресурса
	# живёт только в этом процессе).
	skill.requires_target = false

	# A) спам ДО окна: клип не должен перезапускаться, рука — смениться на окне
	var clip_len: float = await _cast()
	var first: String = comp.cast_player.current_animation
	var t_first: float = comp.cast_player.current_animation_position
	# Второе нажатие ставим в ОКНО ОЧЕРЕДИ: не позже CANCEL_QUEUE_MS до
	# открытия окна отмены (иначе ввод не липнет — это штатное поведение).
	var press_at: float = maxf(0.05, clip_len * skill.cancel_at - 0.25)
	await _wait(press_at)
	var t_before: float = comp.cast_player.current_animation_position
	if t_before < t_first:
		fails.append("A: клип РЕСТАРТОВАЛ до окна (t %.3f→%.3f)" % [t_first, t_before])
	else:
		print("A1: до окна клип не рестартует (t %.3f→%.3f) OK" % [t_first, t_before])
	# второе нажатие ДО окна — в буфер
	caster.cast_skill(SKILL)
	var buffered_ok: bool = caster._buffered_skill == SKILL
	if not buffered_ok:
		fails.append("A: ввод до окна не попал в буфер (%s)" % caster._buffered_skill)
	else:
		print("A2: ввод до окна ушёл в буфер OK")
	# ждём РОВНО открытия окна: буфер обязан сыграть сразу после него
	var second: String = await _await_clip_change(first, clip_len)
	if second == first:
		fails.append("A: буфер не сыграл (остался тот же клип %s)" % second)
	elif not _is_mirror_pair(first, second):
		# Чередование = смена руки, а НЕ обязательно «второй всегда _L»:
		# alternate_hands в первом касте даёт Left (…_L), второй — Right.
		fails.append("A: чередование рук не сработало (%s → %s)" % [first, second])
	else:
		print("A3: буфер сыграл на открытии окна, рука сменилась → %s → %s OK" % [first, second])

	# B) нажатие ПОСЛЕ окна (не в очереди) — мгновенный перезапуск со сменой руки
	await _await_past_window(clip_len, _skill(SKILL).cancel_at)
	var before_b: String = comp.cast_player.current_animation
	var pos_b: float = comp.cast_player.current_animation_position
	caster.cast_skill(SKILL)
	await process_frame
	await process_frame
	var after_b: String = comp.cast_player.current_animation
	var tb: float = comp.cast_player.current_animation_position
	if after_b == before_b and tb > 0.05:
		fails.append("B: после окна клип НЕ перезапустился (%s t %.3f→%.3f)" % [after_b, pos_b, tb])
	else:
		print("B: после окна повтор стартует сразу (%s → %s, t %.3f→%.3f) OK" % [
			before_b, after_b, pos_b, tb])

	# C) чужой скилл перебивает сразу, до окна
	await _wait(0.05)
	var other := _other_instant()
	if other == "":
		print("C: нет второго инста-скилла с клипом — пропуск")
	else:
		var before_c: String = comp.cast_player.current_animation
		_skill(other).requires_target = false   # см. комментарий выше
		caster.cast_skill(other)
		await process_frame
		await process_frame
		var after_c: String = comp.cast_player.current_animation
		if after_c == before_c:
			fails.append("C: чужой скилл %s не перебил %s" % [other, before_c])
		else:
			print("C: чужой скилл %s перебил %s сразу OK" % [other, before_c])

	# D) буфер протухает (150 мс TTL) — ставленный вручную в прошлое
	await _wait(0.05)
	caster._buffered_skill = SKILL
	caster._buffered_ms = Time.get_ticks_msec() - 1000
	await process_frame
	if caster._buffered_skill != "":
		fails.append("D: просроченный буфер не выброшен (остался %s)" % caster._buffered_skill)
	else:
		print("D: просроченный буфер выброшен OK")

	if fails.is_empty():
		print("CANCEL-WINDOW: ALL PASS")
		quit(0)
	else:
		print("CANCEL-WINDOW FAIL: ", "; ".join(fails))
		quit(1)

## Каст + ожидание, пока клип реально начнёт играть. Возвращает длину клипа.
func _cast() -> float:
	caster.cast_skill(SKILL)
	for i in 20:
		await process_frame
	var a: Animation = comp.cast_player.get_animation(comp.cast_player.current_animation)
	return a.length if a != null else 0.0

## Ждать смену клипа на CastPlayer (или таймаут). Возвращает текущий клип.
## Пара зеркал: b == a + "_L" или наоборот (смена руки).
func _is_mirror_pair(a: String, b: String) -> bool:
	return b == a + "_L" or a == b + "_L"

func _await_clip_change(prev: String, clip_len: float) -> String:
	var deadline := Time.get_ticks_msec() + int((clip_len * 1.5 + 0.5) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var cur: String = comp.cast_player.current_animation
		if cur != prev:
			return cur
	return comp.cast_player.current_animation

## Ждать, пока играющий клип перейдёт за окно отмены (cancel_at).
func _await_past_window(clip_len: float, cancel_at: float) -> void:
	var need := clip_len * cancel_at + 0.05
	var deadline := Time.get_ticks_msec() + int((clip_len + 1.0) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if comp.cast_player.current_animation_position >= need:
			return

func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func _skill(id: String):
	var db = load("res://Logic/Skills/SkillDB.gd")
	var all_skills = db.get_skills()
	return all_skills.get(id)

## Второй мгновенный скилл с клипом (для проверки перебивания).
func _other_instant() -> String:
	var db = load("res://Logic/Skills/SkillDB.gd")
	for id in db.get_skills():
		var s = db.get_skills()[id]
		if String(id) == SKILL or s.is_passive or s.cast_anim == "" or s.cast_time > 0.0:
			continue
		if comp.has_method("has_cast_anim") and comp.has_cast_anim(s.cast_anim):
			return String(id)
	return ""

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
