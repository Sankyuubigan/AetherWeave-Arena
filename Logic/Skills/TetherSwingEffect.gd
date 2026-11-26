extends "res://Logic/Skills/Effect.gd"
## Эфирный захват (Q48, ТЗ 21.11.26 / PRP tasks/tether_swing_prp.md): два режима
## на одной кнопке — паттерн Blade. Троса нет → жест Cast_Shoot + зацеп
## (activate(context)); трос активен → срыв с бустом (release(true)).
## Вся физика и стейт-машина — в TetherSwingComponent; эффект только конфиг.

const TETHER_SCRIPT := "res://Logic/Skills/TetherSwingComponent.gd"
const CAST_GESTURE := "Cast_Shoot"  # леворукий выброс ладони (как beam/ball_lightning)

## Дальность зацепа (штатный рейкаст прицела ведёт Skill.max_range; здесь
## граница валидации точки — ТЗ §2).
@export var max_tether_range: float = 45.0
## Зацеп за «пустое небо»: спавн эфирного якоря в воздухе (ТЗ §2).
@export var allow_air_anchor: bool = true
## Цвет нити/свечения (фиолет-бирюзовая палитра vfx_guidelines).
@export var thread_color: Color = Color(0.62, 0.42, 1.0)

func apply(caster: Node, context: Dictionary) -> void:
	var tether = caster.get_node_or_null("TetherSwing")
	if tether == null:
		tether = Node.new()
		tether.name = "TetherSwing"
		tether.set_script(load(TETHER_SCRIPT))
		caster.add_child(tether)
	# Конфигурация скилла → компонент (exports скилла — границы данных).
	tether.set("max_range", max_tether_range)
	tether.set("allow_air_anchor", allow_air_anchor)
	tether.set("thread_color", thread_color)

	if tether.is_active():
		# Повторный каст в полёте = быстрый срыв с бустом (ТЗ §1).
		tether.call("release", true)
		return

	# Жест выброса ладони к якорю (гварды как у Blade — скины без клипа молчат).
	# 26.11.26: клип задан скиллом (ether_tether → Tether_Hang) → его играет
	# каст-слой, свой жест не играем (контракт одного владельца анимации).
	if str(context.get("cast_anim", "")) == "":
		var anim_comp = caster.get_node_or_null("PlayerAnimationComponent")
		if anim_comp and anim_comp.has_method("play_cast_anim") \
				and anim_comp.has_method("has_cast_anim") \
				and anim_comp.has_cast_anim(CAST_GESTURE):
			anim_comp.play_cast_anim(CAST_GESTURE)

	tether.call("activate", context)
