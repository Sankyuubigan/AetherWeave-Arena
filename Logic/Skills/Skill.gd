extends Resource

@export var id: String
@export var skill_name: String
@export var description: String = ""
@export var icon: String
## Ветка умений (Q50): id из Data/skill_branches.json (SkillBranchDB). ""
## = секция «Разное». Метаданные поверх кода — админка меняет только это
## поле, id и логика не трогаются.
@export var branch: String = ""
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
## Окно отмены ИНСТА-каста, доля длины клипа (стандарт проекта 55–60 %,
## docs/animation_generation.md §14.3). Пока инста-клип не дошёл до этой доли,
## повторный каст ТОГО ЖЕ скилла не перебивает его: ввод копится в буфере
## (input buffering 150 мс, SpellCasterComponent) и играет на открытии окна —
## так спам сердечка даёт плавное чередование рук вместо рваных рестартов.
## Чужой скилл перебивает сразу (приоритеты слоёв §14.4). Канал (cast_time>0)
## не отменяется вовсе. 0.0 = отменять сразу (старое поведение).
@export var cancel_at: float = 0.6
## Рука каста ("Right"/"Left"): откуда вылетает снаряд. Должна совпадать с
## рукой cast_anim (Cast_Shoot — левая, Throw — правая). alternate_hands
## перекрывает это поле (попеременно Л/П).
@export var cast_hand: String = "Right"

## Темп проигрывания каст-клипа: 1.0 = как записан, 2.0 = вдвое быстрее.## Нужен, когда клип Mixamo длинноват для игры (фаербол Cast_1H_Magic_01 2.30 с —
## вердикт юзера 26.11.26 «долго кастует, ускорить раза в 2»).
## Реализация — AnimationPlayer.speed_scale на CastPlayer (проверено зондом
## Generators/probe_cast_speed.gd: клип 2.30 с доигрывает за 1.16 с при 2.0).
## spawn_delay и cancel_at задаются в СЕКУНДАХ РЕАЛЬНОГО ВРЕМЕНИ и НЕ
## масштабируются автоматически — при ускорении уменьшать их вручную
## (иначе снаряд родится после того, как рука уже вернулась).
@export var cast_speed: float = 1.0

## Следующий клип ОЧЕРЕДИ того же скилла (26.11.26, энергоклинок).
## Пусто — скилл не очередной (повторный каст перезапускает cast_anim).
## Заполнено — повторный каст внутри окна отмены играет ЭТОТ клип вместо
## рестарта cast_anim, и дальше очередь идёт по кругу: A → B → A → B…
## Реализация — SpellCasterComponent: буфер ввода уже есть (_buffered_skill),
## очередь — просто выбор имени клипа в момент каста. Не канал: скилл не
## блокирует движение и не рвёт каст чужого скилла.
## Вердикт юзера 26.11.26: «не отменять удары, а ставить в очередь» —
## Blade_Swing_A игрался один раз и обрывался спамом.
@export var next_cast_anim: String = ""

## cast_anim — КЛИП-СОСТОЯНИЕ (26.11.26, крылья): играет по кругу, пока эффект
## активен, и НЕ даёт окна отмены (это не удар, а поза). Владелец останавливает
## клип сам (WingsComponent.deactivate → stop_cast_loop), поэтому клип не может
## «прилипнуть» навсегда. Всегда UB: ноги остаются локомоции.
@export var cast_anim_loop: bool = false

## Только у скиллов-стоек: клип-состояние стойки (26.11.26, бард: гитара).
## Играет по кругу, пока стойка активна; StanceComponent останавливает его на
## выходе. Отдельное поле, а НЕ cast_anim: у стойки нет каста-удара, и
## SpellCasterComponent не должен играть клип одноразово.
@export var stance_loop_anim: String = ""

## Тряска камеры в момент ИСПОЛНЕНИЯ заклинания (19.11.26, верб. юзера:
## громовой раскат — земля взрывается под ногами). 0 = нет. Ударная тряска
## снарядов (метеорит падает ПОСЛЕ канала) — отдельный impact_shake у
## SpawnProjectileEffect: там момент удара, а не каста.
@export var shake: float = 0.0

## --- Система стоек (Q16, ТЗ спеца 06-ответ.md 22.11.26) ---
## true — под-приём стойки: не продаётся в магазине (SkillDB.get_shop_skills),
## не создаётся в Кузнице (сериализатор поля не знает), выдаётся игроку только
## вместе с родительской стойкой через EnterStanceEffect.
@export var is_sub_skill: bool = false
## Только у скиллов-стоек: декларация под-приёмов для UI/биндов — элементы
## {id: String, label: String, default_slot: String}. Сериализатор Кузницы
## и магазин это поле игнорируют.
@export var stance_sub_skills: Array[Dictionary] = []
## Только у скиллов-стоек: любой удачный под-приём ЗАКРЫВАЕТ стойку
## (вердикт юзера 22.11.26: под-приём = одноразовый заряд стойки —
## мана-стойка). Кузница поле не сериализует — user-стойки невозможны.
@export var stance_exit_on_sub: bool = false
## Только у скиллов-стоек: под-приём с judge_kind (в stance_sub_skills) кастуется
## ТОЛЬКО за попадание в ритм (вердикт спеца 09-ответ В.1.3): perfect → ×1.25,
## good → ×0.85, miss/empty_press → каста нет. Мана-стойка — false.
@export var stance_rhythm_gate: bool = false
## Кулдаун скилла, с (вердикт спеца В.6.4: 2.0 с на стойки для тестов, 0 = нет).
## Отсчёт от начала каста; отказ = тост + цифры отката на слоте ActionBar.
@export var cooldown: float = 0.0

func execute(caster: Node, context: Dictionary) -> void:
    for eff in effects:
        if eff.has_method("apply"):
            eff.apply(caster, context)
    if shake > 0.0:
        var cs = caster.get_node_or_null("/root/CameraShake")
        if cs:
            cs.add_trauma(shake)