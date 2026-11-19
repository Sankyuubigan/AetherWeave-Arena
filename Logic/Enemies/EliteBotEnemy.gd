extends "res://Logic/Enemies/BotEnemy.gd"
## ЭЛИТНЫЙ БОТ АДА (QUEUE Q38, заказ юзера 19.11.26): скин Whiteclown N Hallin,
## живёт ТОЛЬКО в HellArena (с мейн карты FFA-боты убраны). «Вражеские» —
## таргетят игрока как мобы ада, HP 450 (×3 обычного бота), урон скиллов ×2.5
## (damage_mult), размер ×1.4 («побольше чем остальные»). Переиспользует весь
## BotEnemy: FSM/патруль/касты/aim-риг/рэгдолл/респавн.

func _configure() -> void:
	max_health = 450
	move_speed = 3.6
	attack_range = 20.0 # каст-дистанция элиты: бьёт дальше обычного бота (16)
	attack_cooldown = 2.0
	damage_pct = 0 # урон наносится скиллами (×2.5 через damage_mult), не контактом
	aggro_range = 60.0
	patrol_radius = 10.0
	body_color = Color(0.55, 0.1, 0.55) # рэгдолл-труп элиты — тёмно-фиолетовый

func _ready() -> void:
	super._ready()
	# Урон ×2.5: SpellCasterComponent.damage_mult → context → снаряды
	# (fireball ProjectileComponent.damage и молния HomingProjectileComponent.damage).
	_sc.set("damage_mult", 2.5)
	# «Размером побольше чем остальные» — масштаб тела (капсула/аим-риг вместе).
	scale = Vector3(1.4, 1.4, 1.4)
