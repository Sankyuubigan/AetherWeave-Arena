extends Node

## «Пульс Битвы» (bard_groove) — вторая стойка Барда (ТЗ спеца 11-ответ,
## Блоки 2–3). БЕЗ падающих нот: ритм на ВСЕ действия (Hi-Fi Rush-стиль).
## Шкала Грува 0–100 (старт 25, спад 11%/с, на 75+ — 14%/с); ЛЮБОЕ действие
## в бит заряжает её (1 бит = 1 заряд, анти-абуз last_charged_beat); tier
## по порогам 40/70/95 даёт ЗАЩ/ОТР/скорость/урон скиллов в бит. Выходы:
## гров-угас / потолок 16 с / разбит купол / Крещендо / Esc. Купол и
## Нота-Рикошет — та же dual-path связка, что у Потока (BardFlowComponent):
## HealthComponent.damage_interceptor + PlayerController.player_damage_hook.
## ССЫЛКИ: docs/stance_system.md, файл-план 22.11.26 (groove).

signal groove_changed(groove: float)
signal groove_tier_changed(tier: int)
signal barrier_changed(barrier: int)
## (verdict, source, delta) — попапы «В БИТ! +18%» / «+10%» в BardGrooveUI.
signal groove_hit(verdict: String, source: String, delta: float)

## Причина последнего выхода (баннер причины живёт в UI после закрытия).
var last_exit_reason := ""

## ── Конфиг (ТЗ спеца 11-ответ, Блоки 2–3; правится только здесь) ──────────
const STANCE_SKILL_ID := "bard_groove"
const GROOVE_START := 25.0
const GROOVE_DECAY := 11.0         # %/с; на 75+ — 14/с (на пике держи темп!)
const GROOVE_DECAY_HIGH := 14.0
const TIER_THRESHOLDS := [40.0, 70.0, 95.0]
## Tier-карта: [защита, отражение, +скорость, множитель урона скиллов в бит].
const DR := [0.15, 0.28, 0.40, 0.50]
const RR := [0.15, 0.30, 0.45, 0.55]
const SPEED_BONUS := [0.0, 0.12, 0.20, 0.25]
const TIER_DAMAGE_MULT := [1.0, 1.15, 1.25, 1.35]
## Жёсткий PvP-потолок стойки (ТЗ: честно, как max_duration Потока).
const MAX_DURATION := 16.0
const BARRIER_START := 100
const BARRIER_MAX := 120
const BARRIER_PERFECT := 10        # perfect-скилл в бит подпитывает купол
const CHARGE_SKILL_PERFECT := 18.0
const CHARGE_SKILL_GOOD := 10.0
const CHARGE_MOVE_PERFECT := 12.0
const CHARGE_MOVE_GOOD := 6.0
## Окна бита: |dt| ≤ 0.075 — perfect, ≤ 0.135 — good (ТЗ Блок 3.1).
const PERFECT_WIN := 0.075
const GOOD_WIN := 0.135
## Анти-абуз: 1 бит = максимум 1 заряд (last_charged_beat, ТЗ Блок 2.3).
## Спам сабскиллами мимо бита чаще 0.30 с → мягкий штраф −6 + глухой звук.
const OFFBEAT_SPAM_DT := 0.30
const OFFBEAT_SPAM_PENALTY := 6.0
const SFX_BREAK := "res://Audio/Bard/note_miss.res"
const LOOP_PATH := "res://Audio/Bard/bard_loop.res"
const RICOCHET_SCENE := "res://Scenes/ball_lightning.tscn"
const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

## ── Состояние ─────────────────────────────────────────────────────────────
var is_active := false
var groove := 0.0
var tier := 0
var barrier := 0
var last_charged_beat := -1

var _stance: Node = null
var _hp: Node = null
var _player: Node = null
var _cond: Node = null
var _poly: AudioStreamPlayer = null
var _loop: AudioStreamPlayer = null
var _loop_pending := false
var _last_loop_bar := -999
var _elapsed := 0.0
var _last_offbeat_sub_usec := 0
var _note_res := {}
const PENTA := ["d4", "f4", "g4", "a4", "c5", "d5"]

func _ready() -> void:
	_stance = _sibling("StanceComponent")
	_hp = _sibling("HealthComponent")
	_player = get_parent()
	if _stance != null:
		_stance.stance_entered.connect(_on_stance_entered)
		_stance.stance_exited.connect(_on_stance_exited)

func _sibling(nm: String) -> Node:
	return get_parent().get_node_or_null(nm)

## ── Вход/выход стойки ─────────────────────────────────────────────────────
func _on_stance_entered(_overrides: Dictionary, stance_skill_id: String) -> void:
	if stance_skill_id != STANCE_SKILL_ID:
		return
	is_active = true
	groove = GROOVE_START
	tier = 0
	barrier = BARRIER_START
	last_charged_beat = -1
	_elapsed = 0.0
	_last_offbeat_sub_usec = 0
	_last_loop_bar = -999
	_load_notes()
	_ensure_audio()
	_cond = get_node_or_null("/root/RhythmConductor")
	if _cond != null and not _cond.is_running:
		_cond.start(120.0)
	# Provider = плоская 1.0: урон в бит масштабирует damage_mult-хук
	# (TIER_DAMAGE_MULT в SpellCasterComponent), чтобы не удвоить множитель.
	if _stance != null and "power_provider" in _stance:
		_stance.power_provider = Callable(self, "_flat_power")
	# Купол перехватывает урон вместо HP (та же dual-path связка, что у Потока).
	if _hp != null and "damage_interceptor" in _hp:
		_hp.damage_interceptor = Callable(self, "_absorb_damage")
	_apply_buffs()
	var md = get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("set_bg_duck_db"):
		md.set_bg_duck_db(-14.0)
	_loop_pending = true
	_log("Пульс Битвы: вход (грув %.0f%%, купол %d)" % [groove, barrier])
	groove_changed.emit(groove)
	groove_tier_changed.emit(tier)
	barrier_changed.emit(barrier)

func _on_stance_exited(reason: String) -> void:
	if not is_active:
		return  # mana-стойки тоже эмитят exited
	is_active = false
	last_exit_reason = reason
	_loop_pending = false
	if _poly != null:
		_poly.stop()
	if _loop != null:
		_loop.stop()
	var md = get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("set_bg_duck_db"):
		md.set_bg_duck_db(0.0)
	if _hp != null:
		_hp.damage_reduction = 0.0
		_hp.reflect_ratio = 0.0
	if _player != null and "speed_mult" in _player:
		_player.speed_mult = 1.0
	if _stance != null and "power_provider" in _stance:
		_stance.power_provider = Callable()
	if _hp != null and "damage_interceptor" in _hp:
		_hp.damage_interceptor = Callable()
	tier = 0
	groove = 0.0
	barrier = 0
	last_charged_beat = -1
	_log("Пульс Битвы: выход (%s)" % reason)
	groove_changed.emit(groove)
	groove_tier_changed.emit(tier)
	barrier_changed.emit(barrier)

## Принудительное закрытие (Крещендо, срыв купола, угас, потолок).
func close(reason: String) -> void:
	if _stance != null and _stance.is_active \
			and _stance.stance_skill_id == STANCE_SKILL_ID:
		_stance.exit_stance(reason)
		return
	_on_stance_exited(reason)  # стойка уже не активна (гонка) — чистим сами

## ── Судья «действие в бит» (ТЗ Блок 3.1) ──────────────────────────────────
func evaluate_action(source: String) -> String:
	## Универсальная оценка «действие прямо сейчас в бит». ВЕРДИКТ возвращается
	## ВСЕГДА (действия мимо бита НИКОГДА не блокируются, ТЗ Блок 2.3); заряд
	## начисляется только за perfect/good и только 1 на бит (last_charged_beat).
	if not is_active or _cond == null:
		return ""
	var fl := _fraction_len()
	var st := float(_cond.song_time)
	var frac := fposmod(st, fl)
	var dt := minf(frac, fl - frac)
	var beat_idx := int(round(st / fl))
	var verdict := "perfect" if dt <= PERFECT_WIN \
			else ("good" if dt <= GOOD_WIN else "offbeat")
	if verdict == "offbeat":
		if source == "sub":
			# Спам сабами мимо бита: чаще раз в 0.30 с → −6 + тихий звук.
			var now := Time.get_ticks_usec()
			if _last_offbeat_sub_usec > 0 \
					and now - _last_offbeat_sub_usec < int(OFFBEAT_SPAM_DT * 1000000.0):
				groove = maxf(0.0, groove - OFFBEAT_SPAM_PENALTY)
				play_poly(SFX_BREAK, -8.0, 0.7)
				groove_hit.emit("offbeat_spam", source, -OFFBEAT_SPAM_PENALTY)
				groove_changed.emit(groove)
				_check_exits()
			_last_offbeat_sub_usec = now
		return verdict
	if beat_idx == last_charged_beat:
		return verdict  # анти-абуз: этот бит уже заряжен
	last_charged_beat = beat_idx
	var delta := 0.0
	if source == "move":
		delta = CHARGE_MOVE_PERFECT if verdict == "perfect" else CHARGE_MOVE_GOOD
	else:
		delta = CHARGE_SKILL_PERFECT if verdict == "perfect" else CHARGE_SKILL_GOOD
		if verdict == "perfect":
			barrier = mini(barrier + BARRIER_PERFECT, BARRIER_MAX)
			barrier_changed.emit(barrier)
	_grow(delta)
	play_random_note(-2.0)  # красивая нота пентатоники D minor (шина Bard)
	groove_hit.emit(verdict, source, delta)
	return verdict

## Доля такта для сетки бита: четверть при 120 BPM (0.5 с), восьмая при 72
## (0.4167 с) — ТЗ Блок 3.1; иначе шаг ≈ 0.4–0.6 с.
func _fraction_len() -> float:
	if _cond == null:
		return 0.5
	return _cond.beat_len if float(_cond.beat_len) <= 0.6 else float(_cond.beat_len) * 0.5

func _grow(delta: float) -> void:
	groove = minf(groove + delta, 100.0)
	groove_changed.emit(groove)
	var t := _tier_from_groove()
	if t != tier:
		tier = t
		_apply_buffs()
		groove_tier_changed.emit(tier)

func _tier_from_groove() -> int:
	var t := 0
	for th in TIER_THRESHOLDS:
		if groove >= float(th):
			t += 1
	return t

func _check_exits() -> void:
	if barrier <= 0:
		play_poly(SFX_BREAK, -6.0, 0.6)
		close("barrier_break")
		return
	if groove <= 0.0:
		close("groove_empty")

func max_duration_left() -> float:
	## Остаток жёсткого потолка (UI: мелкая цифра под шкалой Грува).
	return maxf(MAX_DURATION - _elapsed, 0.0)

func _apply_buffs() -> void:
	if _hp != null:
		_hp.damage_reduction = DR[tier]
		_hp.reflect_ratio = RR[tier]
	if _player != null and "speed_mult" in _player:
		_player.speed_mult = 1.0 + SPEED_BONUS[tier]

func _flat_power() -> float:
	return 1.0

## ── Кадр: спад Грува + потолок 16 с + старт лупа на границе такта ─────────
func _process(delta: float) -> void:
	if not is_active:
		return
	_elapsed += delta
	if groove > 0.0:
		var decay := GROOVE_DECAY_HIGH if groove >= 75.0 else GROOVE_DECAY
		groove = maxf(0.0, groove - decay * delta)
		groove_changed.emit(groove)
		var t := _tier_from_groove()
		if t != tier:
			tier = t
			_apply_buffs()
			groove_tier_changed.emit(tier)
		if groove <= 0.0:
			close("groove_empty")
			return
	if _elapsed >= MAX_DURATION:
		close("max_duration")
		return
	if _loop_pending and _cond != null:
		var b2 := int(floor(float(_cond.song_time) / 2.0))
		if b2 != _last_loop_bar:
			_last_loop_bar = b2
			_loop_pending = false
			if _loop != null:
				_loop.play()

## ── Аудио (полифония + ритм-луп — та же схема, что у Потока) ──────────────
func _load_notes() -> void:
	for nm in PENTA:
		var path := "res://Audio/Bard/note_%s.res" % nm
		if ResourceLoader.exists(path):
			_note_res[nm] = load(path)
	if ResourceLoader.exists("res://Audio/Bard/note_miss.res"):
		_note_res["miss"] = load("res://Audio/Bard/note_miss.res")

func play_random_note(volume_db: float = 0.0) -> void:
	if _note_res.is_empty():
		return
	var keys := _note_res.keys()
	keys = keys.filter(func(k): return k != "miss")
	if keys.is_empty():
		return
	play_poly("res://Audio/Bard/note_%s.res" % keys[randi() % keys.size()], volume_db)

func play_poly(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _poly == null or not _poly.playing:
		return
	var pb = _poly.get_stream_playback()
	if pb != null and pb.has_method("play_stream"):
		pb.play_stream(load(path), 0.0, volume_db, pitch)

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

## ── Купол: перехват урона (зеркало Потока, карта DR/RR — groove) ──────────
func _absorb_damage(amount: int, impulse_dir: Vector3, attacker: Node,
		is_reflected: bool) -> bool:
	if not is_active:
		return false
	var applied := int(round(float(amount) * (1.0 - float(DR[tier]))))
	barrier -= applied
	var hit_pos := Vector3.ZERO
	if _player != null and _player is Node3D:
		hit_pos = _player.global_position + Vector3(0, 1.9, 0)
	var abvfx = _player.get_node_or_null("AcousticBarrierVFX") if _player != null else null
	if abvfx != null and abvfx.has_method("notify_impact"):
		abvfx.notify_impact(hit_pos)
	var dn = get_node_or_null("/root/DamageNumbers")
	if dn != null:
		dn.spawn_at(hit_pos, applied, false)
	# Нота-Рикошет: raw × RR[tier] в атакующего (гвард пинг-понга is_reflected).
	if attacker != null and not is_reflected and is_instance_valid(attacker) \
			and ResourceLoader.exists(RICOCHET_SCENE):
		var parent: Node = get_parent()
		var tree = get_tree()
		if tree != null and tree.current_scene != null:
			parent = tree.current_scene
		var proj = ProjectilePool.acquire(load(RICOCHET_SCENE), parent)
		if proj != null:
			var refl := int(round(float(amount) * float(RR[tier])))
			proj.set_meta("override_damage", refl)
			proj.set_meta("is_reflected", true)
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
			play_random_note(-2.0)
			_log("Нота-Рикошет → %s (урон %d)" % [attacker.name, refl])
	if barrier <= 0:
		play_poly(SFX_BREAK, -6.0, 0.6)
		close("barrier_break")
	return true

## Путь урона ИГРОКА (PlayerController.take_damage → player_damage_hook).
func player_damage_hook(amount: int, attacker: Node) -> bool:
	return _absorb_damage(amount, Vector3.ZERO, attacker, false)

## ── Утилиты ───────────────────────────────────────────────────────────────
func _log(what: String) -> void:
	print("BardGroove: " + what)
	var sl = get_node_or_null("/root/StallLogger")
	if sl != null and sl.has_method("event"):
		sl.event("BardGroove: " + what)
