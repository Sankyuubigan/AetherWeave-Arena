# Каталог Эффектов Заклинаний (Lego Bricks) — ССОТ

Компаньон архитектурного ССОТ `docs/skill_system.md` (композиция вместо
наследования, Skill + массив Effect, сборка в SkillDB). Здесь описаны все
атомарные эффекты (`Effect`), из которых собираются умения.

**Обновлён 22.11.26 по коду `Logic/Skills/*.gd`** (16 эффектов + хелпер; Q16
добавил 12–16 — стоики/бард). Живые примеры сборки скиллов —
`Logic/Skills/SkillDB.gd`.

## 0. Поля скилла (`Skill.gd`) — уровень сборки

* `id`, `skill_name`, `description`, `icon` (путь-строка), `price` (1), `is_passive`.
* `is_sub_skill` (Q16) — под-приём стойки: НЕ в магазине, не продаётся,
  выдаётся только со стойкой-родителем (`get_shop_skills` и Кузница фильтруют).
* `stance_sub_skills` (Q16) — у Skill-сборки СТОЙКИ: массив
  `[{id, label, default_slot}]`, `default_slot` = «ЛКМ»/«ПКМ»/«self».
  Правила биндов/swap — [stance_system.md](stance_system.md) §3.
* `max_range` (200.0) — дальность штатного рейкаста прицела.
* `requires_target` + `target_type` (`"enemy"` / `"friendly"`) — скиллы с наведением.
* `effects: Array[Resource]` — кирпичики, исполняются по порядку в `execute()`.
* **Каст-конвейер:** `cast_anim` (имя клипа из shared_animations: `"Throw"`,
  `"Cast_Shoot"`), `cast_time > 0` = канал двумя руками (Cast_Enter → Cast_Loop
  до cast_time → Cast_Shoot + execute, движение заблокировано),
  `alternate_hands` (чередование рук на инста-касте, левая версия клипа =
  `<cast_anim>_L`), `cast_hand` (`"Right"`/`"Left"` — должна совпадать с рукой
  клипа; alternate_hands перекрывает), `shake` (тряска камеры в момент
  ИСПОЛНЕНИЯ; ударная тряска снаряда — отдельный `impact_shake` у
  SpawnProjectileEffect).
* **Паттерн «жест играет эффект»:** у Blade/Wings/Portals `cast_anim = ""` —
  у скилла разные режимы требуют разных жестов, поэтому клип играет сам
  эффект (см. грабли ниже).

## 0.1. Контекст каста (`context: Dictionary`) — что кладёт SpellCasterComponent

* `target_pos` — точка прицела (штатный рейкаст; отдельный рейкаст в эффектах
  НЕ делать — один луч на каст).
* `target_node` — цель под прицелом (для `requires_target`).
* `hit_normal` — нормаль поверхности в точке попадания.
* `hand` — `"Right"`/`"Left"` (решает кастер-компонент при alternate_hands).
* `cast_origin` — точка выброса из руки; при `spawn_delay` эффект сам
  обновляет её через `Effect.hand_pos()` (живая позиция кости кисти).
* `damage_mult` — множитель урона кастера (Q38 элита,
  `SpellCasterComponent @export damage_mult`); учитывают снарядные эффекты.
* `stance_power` (Q16) — множитель стойки: зарядовая лестница маны
  1.0/1.3/1.6 или TIER_POWER Потока через provider. Читают MeleeShove/
  CrescentWave/AoeDamage/SpawnProjectile; без стойки = 1.0 — поведение не меняется.
* `knockback_mult` (Q16) — множитель отброса AoE (Бас-Дроп: 1 + 0.25×tier),
  читает AoeDamageEffect.
* `groove_verdict` (22.11.26, «Пульс Битвы») — вердикт ритма
  («perfect»/«good»/«offbeat»), кладёт `SpellCasterComponent._groove_judge`
  при активной стойке bard_groove (в ОБЕИХ ветках cast_skill). Тот же хук
  умножает `damage_mult` на TIER_DAMAGE_MULT[tier] (пост-press, offbeat —
  НЕ меняет, скилл не блокируется). Читают GroovePulse/GrooveStep.

---

## 📦 Доступные строительные блоки (20, реализовано)

### 1. `SpawnProjectileEffect`
Классический летящий по прямой снаряд (урон тащит сам снаряд из tscn).
* `projectile_scene` (PackedScene): сцена снаряда (обязателен `set_direction(dir)`).
* `offset_y` (1.2): высота спавна от тела, когда `spawn_from_hand = false`.
* `impact_sound` (AudioStream): звук удара о цель/землю.
* `impact_shake` (float): тряска камеры при УДАРЕ (метеорит: канал 2 с, шейк в момент падения).
* `decal_scale` (1.0): множитель размера следа-декали при ударе (подпалина).
* `lava_pool` (bool): оставить эмиссивную лужу лавы в точке удара.
* `spawn_from_hand` (bool, false): true — спавн из `context.cast_origin`
  (кость кисти); false — старое поведение от тела+offset_y (метеор летит с неба).
* `spawn_delay` (0.0): задержка спавна от нажатия (с) — снаряд рождается в
  момент хлыста/выброса руки в клипе из ЖИВОЙ позиции кисти.
* **Пул:** снаряд не бьёт кастера (мета `cast_caster`), урон × `damage_mult`.
* **Применение:** огненный шар, метеор (канал + `impact_*` + `lava_pool`), ледяные стрелы.

### 2. `SpawnHomingProjectileEffect`
Самонаводящийся враждебный снаряд (`set_target` + `set_caster`).
* `projectile_scene`, `offset_y`, `spawn_from_hand`, `spawn_delay` — как выше.
* **Примечание:** скиллу нужны `requires_target = true` + `target_type = "enemy"`.
* Урон × `damage_mult`; самонаведение не бьёт кастера.
* **Меты пула (Q16 рикошет Потока):** `override_damage` (= raw × RR[tier],
  урон переопределён куполом барда) и `is_reflected` (гвард пинг-понга)
  читаются в `HomingProjectileComponent._on_body_entered`, сбрасываются в
  `pooled_reset` — не хранить в снаряде между жизнями.
* **Применение:** шаровые молнии, магические ракеты, духи-преследователи.

### 3. `SpawnHomingHealProjectileEffect`
Самонаводящийся снаряд-лечение: не наносит урон, вызывает `heal()` у цели.
* `projectile_scene`, `offset_y`, `spawn_from_hand`, `spawn_delay`.
* **Примечание:** `requires_target = true` + `target_type = "friendly"`.
* **Применение:** саппортские скиллы, лечение союзников.

### 4. `AoeDamageEffect`
Мгновенный урон всем целям в радиусе от точки прицела (сфера intersect_shape,
кастер исключён). Урон с отбросом рэгдолла от центра взрыва.
* `radius` (5.0, м), `damage` (30), `vfx_scene` (опц., GPUParticles3D в точке взрыва).
* `center_on_caster` (false): true — сфера вокруг КАСТЕРА, а не точки прицела
  (Бас-Дроп барда).
* Урон × `damage_mult` × `stance_power`; отброс × `knockback_mult` (Q16).
* Встроено: кольцо ударной волны на полу под точкой (аним. декаль,
  диаметр = 2×radius) — внешних ассетов не требует.
* **Применение:** гранаты, взрывы, заклинания по площади.

### 5. `TeleportEffect`
Перемещение кастера в точку прицела. Для игрока — стремительный СВИП-полёт
A→B 0.45 с (дуга smoothstep + подпрыг 0.4 м в начале, «падение» в конце,
коллизии в полёте глушатся, поза Jump→Falling→Landing); для прочих кастеров —
мгновенный телепорт. Повторный каст в полёте игнорируется.
* `vfx_scene` (опц.): вспышка в точке старта и прибытия.
* Встроено: кольца варпа на полу (уход — сжимается, приход — расширяется).
* **Применение:** блинки, рывки сквозь пространство.

### 6. `SpawnHitscanEffect`
Хитскан: мгновенный луч от кастера к точке прицела. Свой рейкаст НЕ делает —
берёт готовый `target_pos`/`hit_normal`/`target_node` из контекста.
Урон `take_damage(damage, направление)`. Вся геометрия процедурная:
светящийся луч (висит `beam_lifetime` с) + вспышка с OmniLight в точке
попадания + анимированный прожог-декаль. Внешних ассетов нет.
* `damage` (30), `beam_color`, `beam_width` (0.06), `beam_lifetime` (0.12, 0.03–0.5).
* `offset_y` (1.2), `spawn_from_hand`, `spawn_delay` — как у снарядных.
* `leave_decal` (true), `decal_size` (0.7).
* **Применение:** лазеры, снайперские выстрелы, молния-взгляд.

### 7. `SpawnBladeEffect`
Энергетический клинок (Q19): два режима на одной кнопке — нет клинка →
материализация (жест Throw) + спавн `EnergyBladeComponent`; есть → взмах
(Blade_Swing_A) с урон по ударной точке клипа (0.18 с).
* Экспортных свойств нет (константы внутри).
* **Примечание:** у скилла `cast_anim = ""` — жесты играет эффект.

### 8. `SpawnWingsEffect`
Крылья (Q20): материализация светящихся крыльев на 10 с + ускорение ×1.35
на всё окно активности (`WingsComponent`).
* Экспортных свойств нет; жест Cast_Enter играет эффект.
* **Примечание:** у скилла `cast_anim = ""`.

### 9. `SpawnPortalsEffect` (v1)
Пара порталов-колец (Q21): вход ВСЕГДА за спиной кастера (1.7 м), выход —
точка прицела. Вертикальные кольца, точка ставится на пол вниз-рейкастом +
подъём над склоном. Повторный каст переносит пару (старая сносится).
* Экспортных свойств нет; цвета синий/оранжевый; `PortalNode` (телепорт по входу).
* **Примечание:** у скилла `cast_anim = ""`.

### 10. `SpawnPortals2Effect` (v2 «живое окно», Q44)
Отдельный скилл, независимая пара от v1. Постановка как v1 (за спиной +
прицел, пол-рейкаст, склон), но `PortalNode2`: проскок через мембрану,
живое окно-вид на партнёра, lifetime 30 с.
* Экспортных свойств нет; цвета бирюза/фиолет (отличать от v1 в игре).
* **Примечание:** у скилла `cast_anim = ""`.

### 11. `PlaySoundEffect`
Звук каста через `AudioManager.play_sfx`.
* `audio_stream` (AudioStream): звук (.ogg/.wav).
* `audio_streams` (Array): пул рандомной ротации — если непуст, каждый каст
  играет случайный вариант, `audio_stream` игнорируется. Нетипизированный
  Array: литерал из SkillDB нельзя присвоить типизированному свойству.
* `volume_db` (0.0).
* **Применение:** озвучка кастов, боевые крики, сердечко-дзынь.

### 12. `EnterStanceEffect`
Атомарный вход в стойку (Q16): находит `StanceComponent` кастера и входит
с конфигом; под-приёмы берёт у Skill-сборки стойки из SkillDB.
* `stance_id` (обязателен — id Skill-сборки стойки), `duration` (4.0).
* **Грабля:** SkillDB пре-лоадит эффект — внутри `load()`, НЕ preload
  (цикл preload SkillDB↔EnterStanceEffect ломает загрузку).
* **Применение:** «Концентрация маны» (Q, 4 с), «Поток Гармонии» (R, 99 с
  — страховка; реальные выходы fuel_out/barrier_break/bard_drop/max_duration).
* **КД входа** (раунд 3, В.6.4): Skill.cooldown 2.0 с на обе стойки через
  SpellCasterComponent CD — числовой таймер отката на слоте ActionBar
  (тост «Идёт другой каст» при попытке во время КД).

### 13. `MeleeShoveEffect`
Сокрушение (Q16, ЛКМ в мана-стойке): урон+отброс вблизи (конус/сфера у руки).
* `damage` (30), `reach` (2.5), `radius` (2.8), `shove_force` (9.0).
* Урон × `stance_power` (заряд Q). Направление — `context.forward_dir`
  или назад-вектор кастера.

### 14. `CrescentWaveEffect`
Серп (Q16, self мана-стойки): плоская дуга-волна перед кастером.
* `radius` (12.0), `half_angle_deg` (60.0), `damage` (22), `wave_color`.
* Урон × `stance_power`. Направление — как у MeleeShove.

### 15. `BardNoteEffect`
Ноты Гармонии (Q16, ЛКМ в Потоке): случайная нота пентатоники в полифонию
Потока (уровень через `BardFlowComponent.play_random_note`). Урона НЕТ —
суть приёма ритм-пресс и вердикт судьи (топливо/барьер/tier).
* Экспортных свойств нет; вне Потока не звучит.
* **judge_kind = "harmony"** (SkillDB, раунд 3): ритм-гейт судьи — каст
  только perfect/good (×1.25/×0.85), miss/empty_press не кастует. У
  «Ударного Аккорда» `judge_kind = "chord"`; Бас-Дроп без ритма (kind "").

### 16. `BardDropEffect`
Финальный Бас-Дроп (Q16, self Потока): закрытие Потока AoE вокруг барда.
* Экспортных свойств нет (radius 6, damage 45, knockback_mult = 1 + 0.25×tier).
* Порядок: взрыв → `close_flow("bard_drop")` (снятие баффов/аудио после).
* Вне Потока не летит.

### 17. `Effect.hand_pos()` — статический хелпер (не эффект)
Позиция кости кисти кастера (`mixamorig_RightHand`/`LeftHand`) для спавна
из руки; фолбэк — центр тела +1.2 м. У ботов/врагов скелет ищется по всему
поддереву (скин не всегда под `GraphicsWrapper/PlayerModel`).

### 18. `GroovePulseEffect` (22.11.26, «Пульс Битвы»)
«Нота-пуля» (ЛКМ в bard_groove): mana_bolt урон 14, КД 0.25 — ритм-масштаб
по `context["groove_verdict"]`.
* perfect/good: урон ×1.25 (СВЕРХ tier-множителя, уже лежащего в
  `damage_mult`), скорость ×1.6, материал снаряда — золото (emission).
* offbeat: ×0.4 «фальшивый плевок» (5 урона), глухая нота note_miss.
* **Пул-безопасность:** damage/speed/material_override перезаписываются
  КАЖДЫЙ каст (ProjectilePool шарит узлы между жизнями).
* **Применение:** образец «урон зависит от ритма без блокировки каста».

### 19. `GrooveStepEffect` (22.11.26)
«Ритм-выпад» (ПКМ в bard_groove): рывок 3.5 м (в бит 4.5) по WASD-вектору
(фолбэк `forward_dir` из context), КД 0.45.
* Raycast-гард стены: дистанция до hit −0.6 (мин 0.5);
  `reset_physics_interpolation` после сдвига.
* Шлейф: `AnimatedDecalComponent.ground_hit_below` + DecalFrames.warp_ring
  (золото в бит / фиолет мимо); в бит — вторая декаль на финише.
* **Применение:** мобильность, управляемая ритмом игрока.

### 20. `GrooveCrescendoEffect` (22.11.26)
«Крещендо» (self в bard_groove, повторное нажатие кнопки стойки): взрыв,
растущий от шкалы Грува.
* Гард: groove < 60 → тост «Крещендо: нужно ≥60% Грува» + глухая нота,
  стойка НЕ закрывается.
* При ≥60: AoeDamageEffect radius 5.5, урон lerp(20, 100, g),
  `center_on_caster`, `knockback_mult` 1 + 0.8g, VFX thunder_effect;
  после apply — `groove.close("crescendo")`.
* **Применение:** «накопил — выпустил», выход из стойки с уроном.

---

## 🧱 Как собрать скилл (кратко; полная ССОТ — `skill_system.md`)

```gdscript
var meteor = Skill.new()
meteor.id = "meteor"
meteor.skill_name = "Метеор"
meteor.cast_anim = "Cast_Enter"
meteor.cast_time = 2.0            # канал двумя руками
meteor.shake = 0.4                # тряска в момент исполнения

var rock = SpawnProjectileEffect.new()
rock.projectile_scene = load("res://Scenes/fireball.tscn")  # пул шарит tscn
rock.spawn_from_hand = false      # метеор летит с неба, не из руки
rock.impact_sound = load("res://Audio/SFX/huge_explosion.ogg")
rock.impact_shake = 0.6           # шейк при УДАРЕ (не при касте)
rock.decal_scale = 2.0
rock.lava_pool = true
meteor.effects.append(rock)

var boom = AoeDamageEffect.new()
boom.radius = 6.0
boom.damage = 100
boom.vfx_scene = load("res://Scenes/thunder_effect.tscn")
meteor.effects.append(boom)

_skills["meteor"] = meteor
```

Никакого нового кода для `SpellCasterComponent` — только кирпичики из каталога.

## 🛠 Грабли / паттерны (пойманы на практике)

* **Пул снарядов шарит tscn между скиллами** (fireball = огненный шар И
  метеор): impact-меты ставятся/стираются КАЖДЫЙ каст — не хранить состояние
  в снаряде между жизнями узла.
* **`cast_anim = ""` у Blade/Wings/Portals** — жест играет сам эффект, иначе
  двойной жест / IK-доводка руки вешается на крылья.
* **`spawn_delay`** — после await обязательна проверка
  `is_instance_valid(caster)`/`target`: за время задержки они могли умереть.
* **Новый атомарный эффект** = скрипт-наследник `Effect.gd`; наследование
  писать ЯВНО по пути файла (`extends "res://Logic/Skills/Effect.gd"`) —
  спасает от бага кэша Godot.
* **Кузница (user_скиллы, §4 skill_system.md):** кастомные скиллы юзера
  строятся только из MVP-набора эффектов и путей из белых списков
  `SkillSerializer`; Blade/Wings/Portals/SoftAim при сериализации
  пропускаются — новые встроенные кирпичики в кузнице недоступны, пока их
  не добавят в сериализатор.

## 🚧 Список желаемого (что предстоит создать)

Если нужной детальки тут нет — это новый скрипт-наследник `Effect.gd`.
* `BuffEffect` / `DebuffEffect` — изменение статов на время (потребует системы баффов в `HealthComponent`).
* `ShieldEffect` — щит, блокирующий снаряды.
* `ChainLightningEffect` — прыжки молнии по ближайшим врагам.
* `SpawnSummonEffect` — спавн союзного AI-помощника в точке прицела.

*(Сделано из старого вишлиста: RaycastDamageEffect → `SpawnHitscanEffect`
19.11.26; порталы → v1+v2 19–20.11.26.)*

*(Q16, 22.11.26: кирпичи 12–16 — стойки/бард; контекст-множители
`stance_power`/`knockback_mult`; ССОТ стоек — [stance_system.md](stance_system.md).)*
