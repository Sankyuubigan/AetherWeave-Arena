extends "res://Logic/Enemies/HellEnemyBase.gd"
## Враг ближнего боя ада (19.11.26, верб. юзера): подходит вплотную, мили-удар
## 5% макс HP игрока, кулдаун 3 с. Вся логика — в базе, тут только статы.

func _configure() -> void:
	max_health = 100
	move_speed = 4.0
	attack_range = 2.2
	attack_cooldown = 3.0
	damage_pct = 5
	body_color = Color(0.55, 0.08, 0.06) # багровый
