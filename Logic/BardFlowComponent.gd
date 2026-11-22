extends Node

## «Поток Гармонии» (Q16 Шаг 6, ТЗ спеца): ритм-стойка барда. Держит ВСЮ
## бард-балансную математику: топливо, барьер купола, tier-карту баффов,
## планирование нот по lookahead RhythmConductor, полифонию нот + ритм-луп
## на шине Bard, duck фоновой музыки, Ноту-Рикошет на damage_reflected.
## Выход: нулевое топливо / срыв барьера / Бас-Дроп / Esc / timeout.
## ССЫЛКИ: docs/stance_system.md (Шаг 9), PRP tasks/q16_stances_bard_prp.md.

signal fuel_changed(fuel: float)
signal barrier_changed(barrier: int)
signal flow_tier_changed(tier: int)
## Фактическая дельта топлива последнего вердикта (В.4.1: попап «+1.2с»/«−1.2с»
## у таймера Потока).
signal fuel_delta(delta: float)
## Причина последнего выхода (В.4.2: баннер причины живёт в UI после закрытия
## стойки; UI читает при переходе is_flowing true→false).
var last_exit_reason := ""

## ── Конфиг (ТЗ спеца, правится только здесь) ─────────────────────────────
const STANCE_SKILL_ID := "bard_flow"
const FUEL_START := 5.0
const FUEL_CAP := 14.0
const FUEL_PERFECT := 1.2
const FUEL_GOOD := 0.5
const FUEL_MISS := -0.5  # вердикт юзера 22.11.26: −1.5 убивало Поток за <1 с простоя
## Пустой пресс (вердикт спеца 09-ответ В.1.2): пресс без ноты СВОЕЙ дорожки
## в окне Good — штраф сильнее промаха: спам мышкой сжигает Поток за ~2 с.
## Вместе с ним −1 tier (у обработки ниже).
const FUEL_EMPTY := -1.2
const BARRIER_START := 100
const BARRIER_MAX := 120
const BARRIER_PERFECT := 14
## Пороги tier по числу удачных нот: 0 → T0, 2 → T1, 5 → T2, 8+ → T3.
const TIER_THRESHOLDS := [2, 5, 8]
## Tier-карта баффов: [защита, отражение, +скорость, множитель урона].
const DR := [0.15, 0.25, 0.35, 0.50]
const RR := [0.15, 0.25, 0.40, 0.60]
const SPEED_BONUS := [0.0, 0.10, 0.20, 0.25]
## Множитель урона под-приёмов по tier (ТЗ не задаёт — моё решение: линейно).
const TIER_POWER := [1.0, 1.1, 1.2, 1.3]
## Пул однотактовых фраз (вердикт спеца 09-ответ В.2): [b0..b3], L = harmony
## (ЛКМ-дорожка), R = chord (ПКМ), "." = пауза. ОДНА нота на долю —
## одновременных harmony+chord не бывает; ноты строго на четвертях (0.5 с),
## зазор same-lane ≥ 0.5 с. Фраза на каждый такт — случайная из пула
## текущего tier, БЕЗ повтора той же фразы 2 раза подряд.
const PHRASES := {
	0: ["L..R", "LL.R", ".LR.", "R.LL"],  # Tier 0–1: плавный вход, 2–3 ноты
	1: ["L..R", "LL.R", ".LR.", "R.LL"],
	2: ["LRL.", "LLRL", "RL.R", ".RLR"],  # Tier 2: живой разнобой, 3–4 ноты
	3: ["LRLR", "LLRR", "RLLR", "LRRL"],  # Tier 3 «РЕЗОНАНС»: драйв, 4 ноты
}
## Синкопы (В.2): только Tier 3, редкие, сдвиг последней доли на восьмую
## +0.25 с; гард — первая нота следующего такта не той же дорожки
## (зазор same-lane остаётся ≥ 0.5 с).
const SYNCOPA_CHANCE := 0.15
## Реген HP Tier 2+: каждые REGEN_PERIOD секунд — REGEN_AMOUNT HP.
## Жёсткий потолок суммарной длительности Потока (ТЗ: PvP-честность —
## даже 100% Perfect завершает Поток не позже 60 с — вердикт юзера
## 22.11.26, было 14 с по В.4).
const MAX_FLOW_DURATION := 60.0
const REGEN_PERIOD := 2.0
const REGEN_AMOUNT := 5
const REGEN_MIN_TIER := 2
## Звук срыва барьера (разбитый купол) — reuse miss-звука с понижением.
const SFX_BREAK := "res://Audio/Bard/note_miss.res"
## Пул снарядов (Нота-Рикошет) — const-preload, как в SpawnHomingProjectileEffect.
const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")
const LOOP_PATH := "res://Audio/Bard/bard_loop.res"
const RICOCHET_SCENE := "res://Scenes/ball_lightning.tscn"

## ── Состояние Потока ──────────────────────────────────────────────────────
var is_flowing := false
var fuel := 0.0
var barrier := 0
var tier := 0
var notes_hit := 0

var _stance: Node = null
var _hp: Node = null
var _player: Node = null
var _cond: Node = null
var _judge: Node = null
var _poly: AudioStreamPlayer = null
var _loop: AudioStreamPlayer = null
var _loop_pending := false
var _regen_t := 0.0
var _flow_elapsed := 0.0
var _last_loop_bar := -999
var _note_res := {}   # имя → AudioStreamWAV
const PENTA := ["d4", "f4", "g4", "a4", "c5", "d5"]
var _prev_phrase := ""   # фраза текущего такта (анти-повтор, В.2)
var _next_phrase := ""   # ЗАРАНЕЕ выбранная фраза следующего такта (гард синкоп)
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_stance = _sibling("StanceComponent")
	_hp = _sibling("HealthComponent")
	_player = get_parent()
	if _stance != null:
		_stance.stance_entered.connect(_on_stance_entered)
		_stance.stance_exited.connect(_on_stance_exited)

func _sibling(name: String) -> Node:
	return get_parent().get_node_or_null(name)

## ── Вход/выход Потока ─────────────────────────────────────────────────────
func _on_stance_entered(_overrides: Dictionary, stance_skill_id: String) -> void:
	if stance_skill_id != STANCE_SKILL_ID:
		return
	is_flowing = true
	fuel = FUEL_START
	barrier = BARRIER_START
	tier = 0
	notes_hit = 0
	_regen_t = 0.0
	_flow_elapsed = 0.0
	_last_loop_bar = -999
	_load_notes()
	_ensure_audio()
	_cond = get_node_or_null("/root/RhythmConductor")
	_judge = get_node_or_null("/root/RhythmJudge")
	if _cond != null and not _cond.is_running:
		_cond.start(120.0)
	if _judge != null:
		if _judge.conductor == null:
			_judge.conductor = _cond
		_judge.reset()
		_judge.note_judged.connect(_on_note_judged)
		_judge.empty_press.connect(_on_empty_press)
	# Судья — в стойку (гейт каста под-приёмов читает StanceComponent.judge).
	if _stance != null:
		_stance.judge = _judge
	_prev_phrase = ""
	_next_phrase = ""
	_rng.randomize()
	# Tier-множитель урона под-приёмов через provider (Expand StanceComponent).
	if _stance != null and "power_provider" in _stance:
		_stance.power_provider = Callable(self, "_tier_power")
	# Купол перехватывает урон вместо HP (Callable-хук в HealthComponent).
	if _hp != null and "damage_interceptor" in _hp:
		_hp.damage_interceptor = Callable(self, "_absorb_damage")
	_apply_buffs()
	# Фон карты приглушается на время Потока (ТЗ: −14 dB).
	var md = get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("set_bg_duck_db"):
		md.set_bg_duck_db(-14.0)
	_loop_pending = true
	_log("Поток Гармонии: вход (топливо %.1f, барьер %d)" % [fuel, barrier])
	fuel_changed.emit(fuel)
	barrier_changed.emit(barrier)
	flow_tier_changed.emit(tier)

func _on_stance_exited(reason: String) -> void:
	## Любой выход (fuel_out / barrier_break / bard_drop / cancel / timeout) —
	## полная очистка. Гард is_flowing: mana-стойки тоже эмитят exited.
	if not is_flowing:
		return
	is_flowing = false
	last_exit_reason = reason
	_loop_pending = false
	if _judge != null:
		if _judge.note_judged.is_connected(_on_note_judged):
			_judge.note_judged.disconnect(_on_note_judged)
		if _judge.empty_press.is_connected(_on_empty_press):
			_judge.empty_press.disconnect(_on_empty_press)
		_judge.reset()
	if _cond != null and _cond.is_running:
		_cond.stop()
	if _poly != null:
		_poly.stop()
	if _loop != null:
		_loop.stop()
	var md = get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("set_bg_duck_db"):
		md.set_bg_duck_db(0.0)
	# Баффы снять (клампы HealthComponent страхуют).
	if _hp != null:
		_hp.damage_reduction = 0.0
		_hp.reflect_ratio = 0.0
	if _player != null and "speed_mult" in _player:
		_player.speed_mult = 1.0
	if _stance != null and "power_provider" in _stance:
		_stance.power_provider = Callable()
	if _stance != null and "judge" in _stance:
		_stance.judge = null
	_prev_phrase = ""
	_next_phrase = ""
	if _hp != null and "damage_interceptor" in _hp:
		_hp.damage_interceptor = Callable()
	tier = 0
	fuel = 0.0
	barrier = 0
	notes_hit = 0
	_log("Поток Гармонии: выход (%s)" % reason)
	fuel_changed.emit(fuel)
	barrier_changed.emit(barrier)
	flow_tier_changed.emit(tier)

## Принудительное закрытие Потока (Бас-Дроп, срыв барьера, нулевое топливо).
func close_flow(reason: String) -> void:
	if _stance != null and _stance.is_active \
			and _stance.stance_skill_id == STANCE_SKILL_ID:
		_stance.exit_stance(reason)
		return
	# Стойка уже не активна (гонка) — чистим сами.
	_on_stance_exited(reason)

## ── Математика вердиктов ──────────────────────────────────────────────────
func _on_note_judged(_note_id: int, verdict: String, _kind: String = "") -> void:
	if not is_flowing:
		return
	var delta := 0.0
	match verdict:
		"perfect":
			var old := fuel
			fuel = minf(fuel + FUEL_PERFECT, FUEL_CAP)
			delta = fuel - old
			barrier = mini(barrier + BARRIER_PERFECT, BARRIER_MAX)
			notes_hit += 1
			tier = _tier_from_hits(notes_hit)
		"good":
			var old := fuel
			fuel = minf(fuel + FUEL_GOOD, FUEL_CAP)
			delta = fuel - old
			notes_hit += 1
			tier = _tier_from_hits(notes_hit)
		"miss":
			fuel = fuel + FUEL_MISS
			delta = FUEL_MISS
			tier = maxi(tier - 1, 0)  # откат tier, без выброса из Потока
			play_poly(SFX_BREAK, -3.0, 1.0)  # диссонанс промаха
	_after_fuel_change(delta)

## Пустой пресс (вердикт спеца В.1.2): пресс без ноты СВОЕЙ дорожки в окне
## Good. Штраф: −1.2 топлива, −1 tier (не ниже 0), фальшивая глухая струна.
## Анти-дребезг 0.18 с — на стороне судьи (чаще сигнал не придёт).
func _on_empty_press(_kind: String) -> void:
	if not is_flowing:
		return
	fuel = fuel + FUEL_EMPTY
	tier = maxi(tier - 1, 0)
	play_poly(SFX_BREAK, -4.0, 0.5)  # фальшивая глухая струна
	_after_fuel_change(FUEL_EMPTY)

## Общий хвост вердикта: сигналы (включая дельту для попапа у таймера),
## баффы, проверки срыва купола и нулевого топлива.
func _after_fuel_change(delta: float) -> void:
	fuel_delta.emit(delta)
	fuel_changed.emit(fuel)
	barrier_changed.emit(barrier)
	flow_tier_changed.emit(tier)
	_apply_buffs()
	if barrier <= 0:
		# Срыв купола: звук разбитого барьера + досрочный выход.
		play_poly(SFX_BREAK, -6.0, 0.8)
		close_flow("barrier_break")
		return
	if fuel <= 0.0:
		close_flow("fuel_out")

func _tier_from_hits(hits: int) -> int:
	var t := 0
	for th in TIER_THRESHOLDS:
		if hits >= int(th):
			t += 1
	return t

func _tier_power() -> float:
	return TIER_POWER[tier]

func max_duration_left() -> float:
	## Остаток жёсткого потолка Потока (В.4.1: таймер = min(fuel, это)).
	return maxf(MAX_FLOW_DURATION - _flow_elapsed, 0.0)

func _apply_buffs() -> void:
	if _hp != null:
		_hp.damage_reduction = DR[tier]
		_hp.reflect_ratio = RR[tier]
	if _player != null and "speed_mult" in _player:
		_player.speed_mult = 1.0 + SPEED_BONUS[tier]

## ── Кадр: топливо-таймер + реген + старт лупа на границе такта ───────────
func _process(delta: float) -> void:
	if not is_flowing:
		return
	_flow_elapsed += delta
	fuel = fuel - delta
	fuel_changed.emit(fuel)
	if fuel <= 0.0:
		close_flow("fuel_out")
		return
	if _flow_elapsed >= MAX_FLOW_DURATION:
		close_flow("max_duration")  # ТЗ: даже 100% Perfect ≤ 60 с (вердикт 22.11.26)
		return
	if tier >= REGEN_MIN_TIER and _hp != null:
		_regen_t += delta
		if _regen_t >= REGEN_PERIOD:
			_regen_t = 0.0
			_hp.heal(REGEN_AMOUNT)
	if _loop_pending and _cond != null:
		# Старт лупа на границе такта 2.0 с: пересечение индекса такта —
		# надёжнее fmod (кадр может перепрыгнуть границу).
		var b2 := int(floor(float(_cond.song_time) / 2.0))
		if b2 != _last_loop_bar:
			_last_loop_bar = b2
			_loop_pending = false
			if _loop != null:
				_loop.play()

## ── Ноты: пул фраз (В.2) + полифония ─────────────────────────────────────
func _on_subdivision_tick(bar: int, eighth: int) -> void:
	## Планировщик фраз (вердикт спеца 09-ответ В.2): на границе такта
	## (eighth == 0; тики conductor приходят с lookahead 1.5 с) выбирается
	## случайная фраза пула текущего tier и регистрируются её ноты — строго
	## на четвертях сетки, ОДНА нота на долю (без дублей harmony+chord).
	if not is_flowing or _judge == null:
		return
	if eighth != 0:
		return
	var pool: Array = PHRASES[mini(tier, 3)]
	var phrase := _next_phrase
	if phrase == "":
		phrase = _pick_phrase(pool)
	_prev_phrase = phrase
	# Фраза следующего такта — заранее (гард синкопы через границу такта).
	_next_phrase = _pick_phrase(pool)
	var bar_t := bar * 2.0
	for b in 4:
		var sym := phrase[b]
		if sym == ".":
			continue
		var kind := "harmony" if sym == "L" else "chord"
		var t := bar_t + b * 0.5
		# Синкопа: только Tier 3, редкая, на последней доле такта; гард —
		# первая нота СЛЕДУЮЩЕГО такта не той же дорожки (зазор ≥ 0.5 с).
		if tier >= 3 and b == 3 and _next_phrase[0] != sym \
				and _rng.randf() < SYNCOPA_CHANCE:
			t += 0.25
		_judge.register_note(kind, t)

func _pick_phrase(pool: Array) -> String:
	## Случайная фраза пула, не равная предыдущей (В.2: без повтора подряд).
	var p := ""
	for _i in 8:
		p = str(pool[_rng.randi() % pool.size()])
		if p != _prev_phrase:
			break
	return p

func _load_notes() -> void:
	for nm in PENTA:
		var path := "res://Audio/Bard/note_%s.res" % nm
		if ResourceLoader.exists(path):
			_note_res[nm] = load(path)
	if ResourceLoader.exists("res://Audio/Bard/note_miss.res"):
		_note_res["miss"] = load("res://Audio/Bard/note_miss.res")

## Случайная консонансная нота пентатоники в полифонию (bard_note).
func play_random_note(volume_db: float = 0.0) -> void:
	if _note_res.is_empty():
		return
	var keys := _note_res.keys()
	keys = keys.filter(func(k): return k != "miss")
	if keys.is_empty():
		return
	play_poly("res://Audio/Bard/note_%s.res" % keys[randi() % keys.size()], volume_db)

## Универсальный полифонический вызов: путь .res → голос на шине Bard.
func play_poly(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _poly == null or not _poly.playing:
		return
	var pb = _poly.get_stream_playback()
	if pb != null and pb.has_method("play_stream"):
		pb.play_stream(load(path), 0.0, volume_db, pitch)

## Аккорд: три РАЗНЫЕ ноты пентатоники одновременно (плейтест 22.11.26:
## у «Ударного Аккорда» не было звука вообще — только AoE-урон). Три голоса
## чуть тише одиночной ноты, чтобы не перекричать микс.
func play_chord(volume_db: float = -4.0) -> void:
	if _note_res.is_empty():
		return
	var keys := _note_res.keys()
	keys = keys.filter(func(k): return k != "miss")
	if keys.size() < 3:
		return
	keys.shuffle()
	for i in 3:
		play_poly("res://Audio/Bard/note_%s.res" % keys[i], volume_db)

func _ensure_audio() -> void:
	if _poly == null:
		_poly = AudioStreamPlayer.new()
		_poly.stream = AudioStreamPolyphonic.new()
		_poly.bus = "Bard"
		add_child(_poly)
	if _loop == null:
		_loop = AudioStreamPlayer.new()
		_loop.bus = "Bard"
		add_child(_loop)
	if _loop.stream == null and ResourceLoader.exists(LOOP_PATH):
		_loop.stream = load(LOOP_PATH)
	_poly.play()
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_flowing:
		return  # Поток закрылся за время await — тики не подключаем
	# Планировщик нот подключается ПОСЛЕ первого кадра полифонии (плеер жив).
	if _cond != null:
		if not _cond.subdivision_tick.is_connected(_on_subdivision_tick):
			_cond.subdivision_tick.connect(_on_subdivision_tick)

## ── Купол: перехват урона (Callable-хук HealthComponent) ─────────────────
func _absorb_damage(amount: int, impulse_dir: Vector3, attacker: Node,
		is_reflected: bool) -> bool:
	if not is_flowing:
		return false
	# Купол поглощает урон ПОСЛЕ tier-защиты: applied = raw × (1 − DR[tier]).
	var applied := int(round(float(amount) * (1.0 - float(DR[tier]))))
	barrier -= applied
	var hit_pos := Vector3.ZERO
	if _player != null and _player is Node3D:
		hit_pos = _player.global_position + Vector3(0, 1.9, 0)  # верх купола r1.9
	# Рябь по куполу (Шаг 7: AcousticBarrierVFX.notify_impact) — гард has_method.
	var abvfx = _player.get_node_or_null("AcousticBarrierVFX") if _player != null else null
	if abvfx != null and abvfx.has_method("notify_impact"):
		abvfx.notify_impact(hit_pos)
	# Цифра поглощённого урона (Graphics-автолоад; в -s-пробах отсутствует).
	var dn = get_node_or_null("/root/DamageNumbers")
	if dn != null:
		dn.spawn_at(hit_pos, applied, false)
	# Нота-Рикошет: raw × RR[tier] в атакующего (ТЗ: гвард пинг-понга —
	# is_reflected-удар купол поглощает, но рикошета не порождает).
	if attacker != null and not is_reflected and is_instance_valid(attacker) \
			and ResourceLoader.exists(RICOCHET_SCENE):
		var parent: Node = get_parent()
		var tree = get_tree()
		if tree != null and tree.current_scene != null:
			parent = tree.current_scene
		var proj = ProjectilePool.acquire(load(RICOCHET_SCENE), parent)
		if proj != null:
			var refl := int(round(float(amount) * float(RR[tier])))
			# Ровно raw × reflect_ratio (RR[tier] записан в hp.reflect_ratio).
			proj.set_meta("override_damage", refl)
			proj.set_meta("is_reflected", true)
			# Спавн 2 м к атакующему: снаряд, рождённый внутри купола/коллайдеров
			# владельца, мгновенно ловит его тело и умирает в момент рождения.
			var spawn_pos := hit_pos
			if attacker is Node3D and _player is Node3D:
				var dir: Vector3 = attacker.global_position - hit_pos
				dir.y = 0.0
				if dir.length() > 0.1:
					spawn_pos = _player.global_position \
							+ dir.normalized() * 2.0 + Vector3(0, 1.2, 0)
			proj.global_position = spawn_pos
			if proj.has_method("set_target"):
				proj.set_target(attacker)
			if proj.has_method("set_caster"):
				proj.set_caster(_player)
			play_random_note(-2.0)  # звонкий аккорд при рикошете
			_log("Нота-Рикошет → %s (урон %d)" % [attacker.name, refl])
	if barrier <= 0:
		play_poly(SFX_BREAK, -6.0, 0.6)  # хрустальный звон разбитого купола
		close_flow("barrier_break")
	return true

## Путь урона ИГРОКА (у игрока нет HealthComponent — PlayerController держит
## player_hp сам): купол-хук из PlayerController.take_damage. true — урон
## съеден куполом; false — Поток не активен, урон идёт как обычно.
func player_damage_hook(amount: int, attacker: Node) -> bool:
	return _absorb_damage(amount, Vector3.ZERO, attacker, false)

## ── Утилиты ───────────────────────────────────────────────────────────────
func _log(what: String) -> void:
	## Сессии юзера читаемы (плейтест 22.11.26): ВСЕГДА print — попадает в
	## godot.log и консоль. StallLogger — дополнительно (связь с фризами;
	## его буфер всплывает только при фризе, там бард-события терялись).
	print("BardFlow: " + what)
	var sl = get_node_or_null("/root/StallLogger")
	if sl != null and sl.has_method("event"):
		sl.event("BardFlow: " + what)
