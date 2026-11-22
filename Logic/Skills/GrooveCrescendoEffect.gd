extends "res://Logic/Skills/Effect.gd"

## «Крещендо» (groove_crescendo, self-слот стойки «Пульс Битвы» — повторное
## нажатие кнопки стойки, ТЗ Блок 2 п.2.3): финальный AoE-взрыв-волна
## с отбрасыванием, урон ∝ текущему Груву (60% → 68 урона, 100% → 100),
## доступен при Груве ≥ 60%. Стойка закрывается ПОСЛЕ взрыва (reason
## "crescendo" → баннер «КРЕЩЕНДО!» в UI). Self-защита 0.45 с от дабл-клика
## живёт в StanceComponent.

@export var radius: float = 5.5
@export var damage_min: float = 20.0
@export var damage_max: float = 100.0
@export var min_groove: float = 60.0

func apply(caster: Node, context: Dictionary) -> void:
    var groove = caster.get_node_or_null("BardGrooveComponent")
    if groove == null or not bool(groove.is_active):
        return  # под-приём живёт только в стойке
    if float(groove.groove) < min_groove:
        # Вердикт В.6.3: никаких тихих отказов — тост в HUD.
        var ab = caster.get_node_or_null("ActionBar")
        if ab != null and ab.has_method("show_toast"):
            ab.show_toast("Крещендо: нужно ≥60% Грува")
        if groove.has_method("play_poly"):
            groove.play_poly("res://Audio/Bard/note_miss.res", -8.0, 0.8)
        return
    var g := clampf(float(groove.groove), 0.0, 100.0) / 100.0
    # Отброс ∝ Груву (карта knockback_mult AoeDamageEffect, Шаг 6 Q16).
    context["knockback_mult"] = 1.0 + 0.8 * g
    var aoe = load("res://Logic/Skills/AoeDamageEffect.gd").new()
    aoe.radius = radius
    aoe.damage = int(round(lerpf(damage_min, damage_max, g)))
    aoe.center_on_caster = true
    if ResourceLoader.exists("res://Scenes/thunder_effect.tscn"):
        aoe.vfx_scene = load("res://Scenes/thunder_effect.tscn")
    aoe.apply(caster, context)
    groove.close("crescendo")
