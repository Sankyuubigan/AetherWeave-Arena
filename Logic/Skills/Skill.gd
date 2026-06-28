extends Resource

@export var id: String
@export var skill_name: String
@export var icon: String
@export var price: int = 1
@export var is_passive: bool = false
@export var max_range: float = 200.0

# ИСПРАВЛЕНИЕ: Используем Array[Resource] вместо Array[Effect], 
# чтобы избежать падения движка из-за проблем с глобальным кэшем классов
@export var effects: Array[Resource] = []

func execute(caster: Node, context: Dictionary) -> void:
    for eff in effects:
        # Утиная типизация GDScript сама найдет метод apply у ресурса
        if eff.has_method("apply"):
            eff.apply(caster, context)