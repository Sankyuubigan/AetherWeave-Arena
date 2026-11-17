extends Resource

@export var id: String
@export var skill_name: String
@export var description: String = ""
@export var icon: String
@export var price: int = 1
@export var is_passive: bool = false
@export var max_range: float = 200.0

@export var requires_target: bool = false
@export var target_type: String = "enemy" # "enemy" или "friendly"

@export var effects: Array[Resource] = []

## Каст-анимация (план 17.11.26): имя клипа из shared_animations
## ("Throw", "Cast_Shoot"). Играется при касте, эффекты срабатывают сразу.
@export var cast_anim: String = ""
## >0 — длительный каст двумя руками: Cast_Enter → Cast_Loop до cast_time →
## Cast_Shoot + execute (канал, движение заблокировано).
@export var cast_time: float = 0.0
## Чередование рук при инста-касте (сердечко: лево/право, вердикт 17.11.26).
## Левая версия анимации = <cast_anim>_L (зеркало генерит retarget_ual_anims).
@export var alternate_hands: bool = false
## Рука каста ("Right"/"Left"): откуда вылетает снаряд. Должна совпадать с
## рукой cast_anim (Cast_Shoot — левая, Throw — правая). alternate_hands
## перекрывает это поле (попеременно Л/П).
@export var cast_hand: String = "Right"

func execute(caster: Node, context: Dictionary) -> void:
    for eff in effects:
        if eff.has_method("apply"):
            eff.apply(caster, context)