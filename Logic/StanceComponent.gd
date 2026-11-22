extends Node

## Система стоек (Q16, ТЗ спеца 06-ответ.md): одна активная стойка временно
## подменяет 2–3 слота ActionBar под-приёмами (Stance Override — «форма» LoL,
## стили DMC, Hellsinger). Logic-only: состояние живёт здесь, UI (ActionBar,
## BardFlowUI) слушает сигналы и никогда не пишет состояние.
## Компонент вешается на игрока кодом (PlayerController._ready, дубль-гард).

signal stance_entered(overrides: Dictionary, stance_skill_id: String)
## tier: ступень стойки (мана — ступень заряда, бард — Tier нот, Шаг 6 PRP).
signal stance_updated(tier: int, charge: float)
signal stance_exited(reason: String)

## Окно заряда до полной ступени (ТЗ спеца: 0–1.5 с → power 1.0/1.3/1.6).
const CHARGE_WINDOW := 1.5

var is_active := false
var stance_id := ""
var stance_skill_id := ""  # id Skill-сборки стойки (ActionBar подменяет self-слот)
var duration := 0.0
var time_left := 0.0
var charge := 0.0
var tier := 0
## {slot_key: sub_skill_id}; ключи — метки слотов ActionBar ("1".."7", "Q",…,
## "ЛКМ", "ПКМ") и "self" (слот самой стойки).
var overrides := {}
## Tier-множитель урона под-приёмов (Q16 Шаг 6): Поток Барда ставit
## Callable(self, "_tier_power") на входе, мана-стойка оставляет пустым —
## тогда действует зарядовая лестница 1.0/1.3/1.6.
var power_provider: Callable = Callable()
## Вердикт юзера 22.11.26: у мана-стойки ЛЮБОЙ удачный под-приём закрывает
## стойку (приём = разряд). Ставится из config["exit_on_sub"] (SkillDB:
## mana_concentration.stance_exit_on_sub=true). Поток Барда — false.
var exit_on_sub := false

func enter_stance(config: Dictionary) -> bool:
	## Вход в стойку. Одна активная за раз — повторный запрос игнорируется.
	if is_active:
		print("StanceComponent: стойка «%s» активна — вход «%s» игнорирован" % [
			stance_id, str(config.get("stance_id", "?"))])
		return false
	var subs: Array = config.get("sub_skills", [])
	if subs.is_empty():
		push_warning("StanceComponent: вход в «%s» без под-приёмов — отклонён" % str(config.get("stance_id", "?")))
		return false
	stance_id = str(config.get("stance_id", ""))
	stance_skill_id = str(config.get("stance_skill_id", stance_id))
	duration = maxf(float(config.get("duration", 4.0)), 0.5)
	time_left = duration
	charge = 0.0
	tier = 0
	exit_on_sub = bool(config.get("exit_on_sub", false))
	_bind_overrides(subs)
	is_active = true
	_log_event("стойка «%s»: вход (%.1f с), подмены %s" % [stance_id, duration, overrides])
	stance_entered.emit(overrides, stance_skill_id)
	return true

func exit_stance(reason: String) -> void:
	if not is_active:
		return
	is_active = false
	var was := stance_id
	overrides = {}
	charge = 0.0
	tier = 0
	exit_on_sub = false
	stance_id = ""
	stance_skill_id = ""
	_log_event("стойка «%s»: выход (%s)" % [was, reason])
	stance_exited.emit(reason)

func try_handle_slot(slot_key: String) -> bool:
	## Перехват нажатия слота: если слот подменён стойкой — каст под-приёма
	## через SpellCasterComponent (context["stance_power"] = ступень заряда).
	## false = слот не подменён (ActionBar ведёт обычный каст).
	if not is_active or not overrides.has(slot_key):
		return false
	var sub_id := str(overrides[slot_key])
	var sc = get_parent().get_node_or_null("SpellCasterComponent")
	if sc == null:
		push_warning("StanceComponent: нет SpellCasterComponent — под-приём не кастован")
		return false
	sc.cast_skill(sub_id, {"stance_power": stance_power()})
	# Ритм-нажатие (Q16 Шаги 5/6): каждый под-приём = пресс в судью с usec.
	var judge = get_node_or_null("/root/RhythmJudge")
	if judge != null:
		judge.submit_press()
	# Вердикт юзера 22.11.26: приём = разряд стойки (мана) — выход СРАЗУ после
	# успешного каста (Поток Барда exit_on_sub=false — играет до fuel_out).
	if exit_on_sub:
		exit_stance("sub_used")
	return true

func stance_power() -> float:
	## Ступени заряда → множитель урона (ТЗ спеца: 1.0 / 1.3 / 1.6).
	## Provider-ветка: стойки с внешней картой мощности (Поток Барда — tier).
	if power_provider.is_valid():
		return float(power_provider.call())
	if charge < CHARGE_WINDOW / 3.0:
		return 1.0
	if charge < CHARGE_WINDOW * 2.0 / 3.0:
		return 1.3
	return 1.6

func _bind_overrides(subs: Array) -> void:
	## Умные дефолты (default_slot из Skill.stance_sub_skills) + переназначения
	## из ActionBar.stance_binds (UI-редактор — Шаг 8 PRP).
	overrides.clear()
	var bar = get_parent().get_node_or_null("ActionBar")
	var binds: Dictionary = {}
	if bar != null and bar.has_method("get_stance_binds"):
		binds = bar.get_stance_binds(stance_id)
	for s in subs:
		var sub_id := str(s.get("id", ""))
		if sub_id == "":
			continue
		var slot := str(binds.get(sub_id, s.get("default_slot", "")))
		if slot == "":
			continue
		overrides[slot] = sub_id

func _process(delta: float) -> void:
	if not is_active:
		return
	time_left -= delta
	if time_left <= 0.0:
		exit_stance("timeout")
		return
	if charge < CHARGE_WINDOW:
		charge = minf(charge + delta, CHARGE_WINDOW)
		stance_updated.emit(tier, charge)

func _unhandled_input(event: InputEvent) -> void:
	## Esc-отмена стойки (ТЗ спеца). UI-гард: открытое окно (SkillMenu ребёнок
	## игрока, SkillForgeWindow/SettingsMenu автолоады) само обрабатывает Esc —
	## стойку не трогаем (ССОТ ui_input_rules: UI открыто = игра в стороне).
	if not is_active or not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE:
		return
	if _ui_open():
		return
	exit_stance("cancel")

func _ui_open() -> bool:
	var p := get_parent()
	if p != null:
		var menu = p.get_node_or_null("SkillMenu")
		if menu != null and menu.get("is_open") == true:
			return true
	for path in ["/root/SkillForgeWindow", "/root/SettingsMenu"]:
		var w := get_node_or_null(path)
		if w != null and w.get("is_open") == true:
			return true
	return false

func _log_event(what: String) -> void:
	## SSOT логов трансформаций (§2 PRP): StallLogger в живой игре, print в
	## headless-пробах (автолоадов в -s режиме нет).
	var sl = get_node_or_null("/root/StallLogger")
	if sl != null and sl.has_method("event"):
		sl.event("StanceComponent: " + what)
	else:
		print("StanceComponent: " + what)
