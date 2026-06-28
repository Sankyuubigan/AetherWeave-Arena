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

func execute(caster: Node, context: Dictionary) -> void:
    for eff in effects:
        if eff.has_method("apply"):
            eff.apply(caster, context)