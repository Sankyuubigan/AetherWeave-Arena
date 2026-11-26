extends "res://Logic/Skills/Effect.gd"
## Крылья-скилл (Q20): материализация светящихся крыльев на 10 с + ускорение
## x1.35 на всё окно активности. Жест каста (Cast_Enter) играет ЭФФЕКТ — у
## скилла cast_anim="", чтобы cast_skill не вешал IK-доводку руки на крылья.
##
## 26.11.26: если скилл ЗАДАЛ клип (Skill.cast_anim="Wings_Fly",
## cast_anim_loop=true), клип играет каст-слой — эффект свой жест НЕ играет
## (контракт одного владельца анимации: context["cast_anim"]).

const WINGS_SCRIPT := "res://Graphics/WingsComponent.gd"
const CAST_GESTURE := "Cast_Enter"

func apply(caster: Node, context: Dictionary) -> void:
	var wings = caster.get_node_or_null("Wings")
	if wings == null:
		wings = Node3D.new()
		wings.name = "Wings"
		wings.set_script(load(WINGS_SCRIPT))
		caster.add_child(wings)
	# Жест материализации играем ТОЛЬКО если клип не взят каст-слоем (иначе
	# Cast_Enter рвёт Wings_Fly: крылья «дёргались» при каждом касте).
	if str(context.get("cast_anim", "")) == "":
		var anim_comp = caster.get_node_or_null("PlayerAnimationComponent")
		if anim_comp and anim_comp.has_method("play_cast_anim") \
				and anim_comp.has_method("has_cast_anim") \
				and anim_comp.has_cast_anim(CAST_GESTURE):
			anim_comp.play_cast_anim(CAST_GESTURE)
	wings.call("activate")
