extends Node

@export var max_health: int = 100
var current_health: int = 100

func _ready():
    current_health = max_health

func take_damage(amount: int):
    current_health -= amount
    if current_health < 0:
        current_health = 0
    print("Манекен получил урон! Осталось ХП: ", current_health)
