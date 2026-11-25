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
var _channel := false
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
func play_full_body(anim_name: String) -> void:
	if cast_player == null or not cast_player.has_animation(anim_name):
		return
	cast_player.stop()
	cast_player.play(anim_name, 0.1)
	cast_player.capture(anim_name, 0.1)

## Инста-каст: UB поверх текущего состояния локомоции. stop()→play()→capture()
## (capture блендит из ТЕКУЩЕЙ позы; stop рестартует с нуля — спам не копится).
func play_cast_anim(anim_name: String) -> void:
	var ub := anim_name + "_UB"
	if cast_player == null or not cast_player.has_animation(ub):
		return
	cast_player.stop()
	cast_player.play(ub, 0.1)
	cast_player.capture(ub, 0.1)

func cast_clip_length(anim_name: String) -> float:
	if cast_player == null or not cast_player.has_animation(anim_name + "_UB"):
		return 0.0
	return cast_player.get_animation(anim_name + "_UB").length

## Старт канала: Enter (0.53с) → сигнал сам подхватит Loop.
func play_channel() -> void:
	if not cast_player:
		return
	_channel = true
	for ub in ["Cast_Enter_UB", "Cast_Loop_UB"]:
		if cast_player.has_animation(ub):
			cast_player.stop()
			cast_player.play(ub, 0.1)
			cast_player.capture(ub, 0.1)
			break

## Конец канала: выброс (Cast_Shoot_UB). Локомоция не трогается.
func end_channel() -> void:
	if not _channel:
		return
	_channel = false
	if cast_player and cast_player.has_animation("Cast_Shoot_UB"):
		cast_player.stop()
		cast_player.play("Cast_Shoot_UB", 0.1)
		cast_player.capture("Cast_Shoot_UB", 0.1)

func _on_finished(anim_name: StringName) -> void:
	if _channel and String(anim_name) == "Cast_Enter_UB" \
			and cast_player and cast_player.has_animation("Cast_Loop_UB"):
		cast_player.play("Cast_Loop_UB", 0.1)
		cast_player.capture("Cast_Loop_UB", 0.1)
	if _finished_cb.is_valid():
		_finished_cb.call(anim_name)