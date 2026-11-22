extends "res://Logic/Skills/Effect.gd"

## «Финальный Бас-Дроп» (Q16 Шаг 6, self-слот Потока): закрытие Потока
## AoE вокруг барда. Урон × stance_power (tier-карта, приходит в context
## из StanceComponent.try_handle_slot), отброс × tier. Поток закрывается
## ПОСЛЕ взрыва (close_flow → exit_stance → снятие баффов/аудио).

func apply(caster: Node, context: Dictionary) -> void:
	var flow = caster.get_node_or_null("BardFlowComponent")
	if flow == null or not flow.is_flowing:
		# Поток не активен — дроп не летит (под-приём живёт только в Потоке).
		return
	context["knockback_mult"] = 1.0 + 0.25 * float(flow.tier)
	var aoe = load("res://Logic/Skills/AoeDamageEffect.gd").new()
	aoe.radius = 6.0
	aoe.damage = 45
	aoe.center_on_caster = true
	aoe.apply(caster, context)
	flow.close_flow("bard_drop")
