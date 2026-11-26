extends "res://Logic/Skills/Effect.gd"
## Энергетический клинок (Q19): одно действие на кнопке — если клинка нет,
## материализация (жест Throw), если есть — взмах (Blade_Swing_A, урон).
## Анимации играет ЭФФЕКТ: у скилла cast_anim="" — cast_skill не играет
## ничего сам, разные режимы требуют разных жестов.
##
## 26.11.26 (вердикт юзера «не отменять удары, а ставить в очередь»): режим
## ВЗМАХА передан скиллу — Skill.cast_anim="Blade_Swing_A",
## next_cast_anim="Blade_Swing_B". Каст-слой играет A→B→A по окну отмены, а
## эффект только наносит урон (раньше эффект САМ звал play_cast_anim и обрывал
## очередь: A игрался один раз, спам рестартил клип). Жест МАТЕРИАЛИЗАЦИИ
## (Throw) по-прежнему у эффекта — у этого режима своего cast_anim нет.

const BLADE_SCRIPT := "res://Graphics/EnergyBladeComponent.gd"
const MATERIALIZE_ANIM := "Throw"
const SWING_ANIM := "Blade_Swing_A"
## Ударная точка свинга: клип Sword_Regular_A 0.43 с, контакт ≈ середина замаха.
const SWING_HIT_DELAY := 0.18

## Режим клинка по состоянию: нет клинка → материализация (Throw), есть →
## очередь взмахов (Skill.cast_anim/next_cast_anim: A→B→A). Вызывается
## SpellCasterComponent ДО выбора клипа, поэтому окно отмены и очередь
## работают как у обычного инста-каста (вердикт юзера: «в очередь, не отменять»).
func pick_cast_anim(caster: Node, _skill) -> String:
	var blade = caster.get_node_or_null("EnergyBlade")
	if blade == null or not bool(blade.call("is_active")):
		return MATERIALIZE_ANIM
	return ""   # взмах — имя берёт Skill.cast_anim (A), очередь двигает каст-слой

func apply(caster: Node, context: Dictionary) -> void:
	var blade = caster.get_node_or_null("EnergyBlade")
	if blade == null:
		blade = Node3D.new()
		blade.name = "EnergyBlade"
		blade.set_script(load(BLADE_SCRIPT))
		caster.add_child(blade)
	var anim_comp = caster.get_node_or_null("PlayerAnimationComponent")
	if blade.is_active():
		# Клип взмаха играет каст-слой (очередь A/B). Здесь — только фолбэк-жест,
		# если клип не был сыгран каст-слоем (скилл без cast_anim).
		if str(context.get("cast_anim", "")) == "" \
				and anim_comp and anim_comp.has_method("play_cast_anim") \
				and anim_comp.has_method("has_cast_anim") \
				and anim_comp.has_cast_anim(SWING_ANIM):
			anim_comp.play_cast_anim(SWING_ANIM)
		# Урон по ударной точке клипа (до конца корутины effect'а — execute()
		# не ждёт, остальные эффекты не блокируются).
		await caster.get_tree().create_timer(SWING_HIT_DELAY).timeout
		if is_instance_valid(blade) and blade.is_active():
			blade.swing(context)
	else:
		if anim_comp and anim_comp.has_method("play_cast_anim"):
			anim_comp.play_cast_anim(MATERIALIZE_ANIM)
		blade.materialize()
