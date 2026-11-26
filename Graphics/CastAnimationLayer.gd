extends Node
## Единый слой каст-анимаций (вердикт спеца 23.11.26, Ф2.1/2.2).
## Фасад над AnimationPlayer (CastPlayer) с UB-клипами: инста-касты,
## канал Enter→Loop→Shoot, capture-блендинг из ТЕКУЩЕЙ позы (без рывка через
## rest). Публичный API (has_cast_anim/play_cast_anim/cast_clip_length/
## play_channel/end_channel) сохранён — эффекты скиллов не меняются.
## ВНУТРЕННИЙ механизм — CastPlayer (проверен 5 плейтестами, одобрен юзером);
## объединённое дерево OneShot/Blend2 (идеал спеца) отложено: визуально не
## верифицируется в headless, а своп рискует регрессом одобренных кастов.
## Фасад локализует будущую замену в одном файле.

const USE_UAL_CASTS := true
const UAL_CASTS_LIB := "res://Graphics/Animations/ual_casts_test.res"
## Каст-имена игры, которых нет в UAL, → ближайший UAL-клип.
const UAL_CAST_ALIASES := {
	"Cast_Shoot_L": "Pistol_Shoot",
}

var cast_player: AnimationPlayer = null
## ЧТО реально играет и как долго (26.11.26). Окно отмены инста-каста в
## SpellCasterComponent считает прогресс по ФАКТИЧЕСКОМУ клипу: стоя играется
## full-body (короче UB на хвост 0.2 с), в бегу — UB. Без этого окно открывалось
## бы не в тот момент, что видит игрок.
var last_clip: String = ""
var last_len: float = 0.0
## Темп текущего каста (Skill.cast_speed). Длины, которые отдаём наружу
## (cast_clip_length / last_len), делятся на него: окно отмены и IK считаются
## в РЕАЛЬНОМ времени, а не в длине клипа. Иначе при cast_speed=2 окно отмены
## открывалось бы вдвое позже конца клипа (оно бы просто не наступало).
var _speed := 1.0
var _channel := false
## Канал играет СВОЙ клип скилла (не Enter→Loop→Shoot): тогда end_channel
## не подмешивает Cast_Shoot — выброс уже внутри клипа.
var _channel_custom := false
## Клип-СОСТОЯНИЕ (крылья, гитара барда): имя UB-клипа, играющего по кругу.
## "" = нет. Владелец (WingsComponent / StanceComponent) гасит через
## stop_cast_loop; разовый каст поверх состояния не снимает владение —
## по завершении клип-состояние возвращается (_on_finished).
var _loop_clip := ""
var _finished_cb: Callable

## Создать CastPlayer рядом с anim_player, загрузить UB-библиотеку.
## finished_cb(anim_name) — уведомление о конце клипа (канал Enter→Loop).
func setup(anim_player: AnimationPlayer, finished_cb: Callable) -> void:
	_finished_cb = finished_cb
	cast_player = AnimationPlayer.new()
	anim_player.get_parent().add_child(cast_player)
	cast_player.root_node = anim_player.root_node
	cast_player.animation_finished.connect(_on_finished)
	if USE_UAL_CASTS and ResourceLoader.exists(UAL_CASTS_LIB):
		var ual = load(UAL_CASTS_LIB)
		if ual is AnimationLibrary:
			var clib := AnimationLibrary.new()
			for anim_name in ual.get_animation_list():
				# Грузим И _UB (верх тела, бег), И базовые Full-Body (стоит:
				# Hips+ноги+шаг — ноги не «забетонированы», ступни на полу).
				clib.add_animation(anim_name, ual.get_animation(anim_name))
			for alias in UAL_CAST_ALIASES:
				var target: String = UAL_CAST_ALIASES[alias] + "_UB"
				var alias_ub: String = alias + "_UB"
				if clib.has_animation(target) and not clib.has_animation(alias_ub):
					clib.add_animation(alias_ub, clib.get_animation(target))
			cast_player.add_animation_library("", clib)
		else:
			print("CastAnimationLayer: ", UAL_CASTS_LIB, " не AnimationLibrary")
	else:
		print("CastAnimationLayer: UB-библиотека не найдена: ", UAL_CASTS_LIB)

func has_cast_anim(anim_name: String) -> bool:
	return cast_player != null and anim_name != "" \
			and cast_player.has_animation(anim_name + "_UB")

## Full-Body каст (СТОЯ): база без _UB — с Hips+ногами (шаг, присед, ступни
## на полу). Бегущий каст играет UB (верх тела) через play_cast_anim.
## speed — темп (Skill.cast_speed): 2.0 = вдвое быстрее.
func play_full_body(anim_name: String, speed: float = 1.0) -> void:
	if cast_player == null or not cast_player.has_animation(anim_name):
		return
	_apply_speed(speed)
	cast_player.stop()
	cast_player.play(anim_name, 0.1)
	cast_player.capture(anim_name, 0.1)
	_note_playing(anim_name)

## Инста-каст: UB поверх текущего состояния локомоции. stop()→play()→capture()
## (capture блендит из ТЕКУЩЕЙ позы; stop рестартует с нуля — спам не копится).
func play_cast_anim(anim_name: String, speed: float = 1.0) -> void:
	var ub := anim_name + "_UB"
	if cast_player == null or not cast_player.has_animation(ub):
		return
	_apply_speed(speed)
	cast_player.stop()
	cast_player.play(ub, 0.1)
	cast_player.capture(ub, 0.1)
	_note_playing(ub)

## Темп проигрывания. ВСЕГДА выставляется перед play(): пул скиллов разный,
## иначе ускоренный клип «прилипнет» к следующему нормальному касту.
## Замер Generators/probe_cast_speed.gd: speed_scale=2 → 2.30с клип за 1.16с.
func _apply_speed(speed: float) -> void:
	_speed = clampf(speed, 0.25, 4.0)
	if cast_player:
		cast_player.speed_scale = _speed

## Запомнить играющий клип и его длину (для окна отмены инста-каста).
## last_len — в РЕАЛЬНОМ времени (длина клипа ÷ темп).
func _note_playing(clip: String) -> void:
	last_clip = clip
	var raw: float = cast_player.get_animation(clip).length if cast_player.has_animation(clip) else 0.0
	last_len = raw / _speed

func cast_clip_length(anim_name: String) -> float:
	if cast_player == null or not cast_player.has_animation(anim_name + "_UB"):
		return 0.0
	return cast_player.get_animation(anim_name + "_UB").length / _speed

## Длина клипа КАК ЗАПИСАН (без деления на текущий темп). Нужна, чтобы
## посчитать темп подгонки в окно канала: cast_clip_length тут не годится —
## он делит на темп ПРОШЛОГО каста, и подгонка съезжала бы от каста к касту.
func cast_raw_length(anim_name: String) -> float:
	if cast_player == null or not cast_player.has_animation(anim_name + "_UB"):
		return 0.0
	return cast_player.get_animation(anim_name + "_UB").length

## Старт канала: Enter (0.53с) → сигнал сам подхватит Loop.
## clip — СВОЙ клип канала (26.11.26: метеор/гром). Пусто = классический
## Enter→Loop→Cast_Shoot. Свой клип играет ОДИН раз на всё окно канала и
## растягивается под cast_time (fit_speed), чтобы выброс в конце клипа совпал
## с моментом execute() — иначе снаряд рождается после того, как руки вернулись.
func play_channel(clip: String = "", fit_speed: float = 1.0) -> void:
	if not cast_player:
		return
	_channel = true
	_channel_custom = false
	if clip != "" and cast_player.has_animation(clip + "_UB"):
		_channel_custom = true
		_apply_speed(fit_speed)
		cast_player.stop()
		cast_player.play(clip + "_UB", 0.1)
		cast_player.capture(clip + "_UB", 0.1)
		_note_playing(clip + "_UB")
		return
	for ub in ["Cast_Enter_UB", "Cast_Loop_UB"]:
		if cast_player.has_animation(ub):
			cast_player.stop()
			cast_player.play(ub, 0.1)
			cast_player.capture(ub, 0.1)
			_note_playing(ub)
			break

## Конец канала: выброс (Cast_Shoot_UB). Локомоция не трогается.
## Свой клип канала уже содержит выброс — его не перебиваем.
func end_channel() -> void:
	if not _channel:
		return
	_channel = false
	if _channel_custom:
		_channel_custom = false
		return
	if cast_player and cast_player.has_animation("Cast_Shoot_UB"):
		cast_player.stop()
		cast_player.play("Cast_Shoot_UB", 0.1)
		cast_player.capture("Cast_Shoot_UB", 0.1)
		_note_playing("Cast_Shoot_UB")

## ── Клип-СОСТОЯНИЕ (26.11.26) ──────────────────────────────────────────────
## Крылья и гитара барда — не удар, а поза: играет по кругу, пока эффект
## активен. Всегда UB (ноги — локомотива), окна отмены НЕТ: это не инста-каст,
## повторный каст того же скилла идёт своей логикой (эффект-владелец).
func play_cast_loop(clip: String) -> void:
	var ub := clip + "_UB"
	if cast_player == null or not cast_player.has_animation(ub):
		return
	_loop_clip = ub
	_apply_speed(1.0)
	cast_player.stop()
	cast_player.play(ub, 0.15)
	cast_player.capture(ub, 0.15)
	_note_playing(ub)

## Снять клип-состояние. clip пусто = снять любое (владелец не помнит имя).
## Разовый каст поверх состояния (удар) — не отменяет владение: _loop_clip
## остаётся, и _on_finished вернёт позу, когда удар доиграет.
func stop_cast_loop(clip: String = "") -> void:
	if _loop_clip.is_empty():
		return
	if clip != "" and _loop_clip != clip + "_UB" and _loop_clip != clip:
		return   # чужое состояние не трогаем (два владельца не конфликтуют)
	_loop_clip = ""
	if _channel:
		return   # канал важнее — не рвём его посреди выброса
	if cast_player and last_clip == _loop_clip:
		cast_player.stop()
		last_clip = ""
		last_len = 0.0

func has_loop_state() -> bool:
	return not _loop_clip.is_empty()

func _on_finished(anim_name: StringName) -> void:
	if _channel and String(anim_name) == "Cast_Enter_UB" \
			and cast_player and cast_player.has_animation("Cast_Loop_UB"):
		cast_player.play("Cast_Loop_UB", 0.1)
		cast_player.capture("Cast_Loop_UB", 0.1)
	# Разовый каст поверх клипа-состояния доиграл → вернуть позу-состояние.
	elif not _loop_clip.is_empty() and not _channel \
			and String(anim_name) != _loop_clip \
			and cast_player and cast_player.has_animation(_loop_clip):
		cast_player.play(_loop_clip, 0.2)
		cast_player.capture(_loop_clip, 0.2)
		_note_playing(_loop_clip)
	if _finished_cb.is_valid():
		_finished_cb.call(anim_name)