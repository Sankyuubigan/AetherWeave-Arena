# Система стоек (Stance Override) — ССОТ

Компаньоны: [skill_system.md](skill_system.md) (сборка скиллов-кирпичиков),
[ui_input_rules.md](ui_input_rules.md) (мышь/UI), ТЗ спеца
(06-ответ.md, Поток: строки 178–240). Создан 22.11.26 по Q16 (PRP
`tasks/q16_stances_bard_prp.md`, шаги 0–9 закрыты, гейты зелёные).

## 1. Концепт: Stance Override

Стойка — это временная подмена слотов на время своей активности. Пока стойка
активна, нажатия перехваченных слотов кастуют **под-приёмы** стойки вместо
обычных скиллов слотов; после выхода обычные скиллы возвращаются.

Зачем: позволяет делать мощные режимные механики (зарядовая мана-стойка,
ритм-поток барда) **без «мёртвых скиллов»** — обычный арсенал не пропадает,
слоты просто переезжают на время — и **без клона DFJK** (без отдельной
второй панели и отдельного набора биндов).

Управление:
- **Q** — «Концентрация маны» (зарядовая стойка, 4 с).
- **R** — «Поток Гармонии» (ритм-стойка барда, до 60 с — вердикт юзера 22.11.26).
- Повторное нажатие клавиши стойки в стойке = приём `self` (для барда —
  «Финальный Бас-Дроп»); **Esc** отменяет стойку досрочно.

## 2. Контракт StanceComponent (`Logic/StanceComponent.gd`, Logic-only)

Поля:
- `is_active`, `stance_id`, `stance_skill_id` (id Skill-сборки стойки —
  ActionBar подменяет иконку self-слота), `duration`, `time_left`, `charge`,
  `tier` (Поток), `overrides` (Dictionary: слот-лейбл → sub_id),
  `power_provider: Callable` — внешняя карта мощности (Поток — tier),
  `exit_on_sub: bool` — приём разряжает стойку (мана: true, Поток: false;
  из `Skill.stance_exit_on_sub`, сериализатор Кузницы поле не пишет —
  user-стойки невозможны).

Сигналы (единственный канал к Graphics):
- `stance_entered(overrides: Dictionary, stance_skill_id: String)`
- `stance_updated(tier: int, charge: float)`
- `stance_exited(reason: String)`

API:
- `enter_stance(config) -> bool` — одна активная за раз (повтор игнор);
  `sub_skills` не пуст обязателен; `duration` клампится ≥ 0.5 с.
  Конфиг: `{stance_id, stance_skill_id, duration, sub_skills}`.
- `exit_stance(reason)` — гасит всё и эмитит `stance_exited(reason)`.
- `try_handle_slot(slot_label) -> bool` — ТОЧКА ПЕРЕХВАТА. Слот подменён →
  каст под-приёма через SpellCasterComponent с
  `context["stance_power"]` и `judge.submit_press()` (ритм-пресс); после
  успешного каста при `exit_on_sub` — немедленный `exit_stance("sub_used")`
  (вердикт юзера 22.11.26: приём = одноразовый заряд стойки); возвращает
  false → ActionBar ведёт обычный каст.
- `stance_power() -> float` — provider-ветка (Поток: TIER_POWER[tier]);
  иначе зарядовая лестница 1.0 / 1.3 / 1.6 (заряд 0–1.5 с).

Числа — ССОТ константы файлов (`StanceComponent.CHARGE_WINDOW`,
`BardFlowComponent` консты 15–65); в доке даны текущие значения.

## 3. Правила под-приёмов

- Под-приём = обычный Skill-сборка с флагом `is_sub_skill = true` —
  **не попадает в магазин** (`SkillDB.get_shop_skills()` фильтрует),
  выдаётся только вместе со стойкой-родителем (Кузница и продажа тоже
  фильтруют `is_sub_skill`).
- Skill-сборка стойки несёт `stance_sub_skills: [{id, label, default_slot}]`.
  `default_slot`: `"ЛКМ"` / `"ПКМ"` / `"self"` (self = слот самой стойки).
- Пользовательские переназначения: `ActionBar.stance_binds =
  {stance_id: {sub_id: slot_label}}`.
  **КЛЮЧИ словаря биндов — sub_id, слоты живут в ЗНАЧЕНИЯХ** (гард занятости
  чужого слота — `values().has(slot_label)`, не get по ключу!).
- Swap двух под-приёмов — только внутри своей стойки; партнёр получает
  «эффективный старый» слот sub (явный бинд или его default_slot из SkillDB).
  Слот под-приёма ДРУГОЙ стойки занят → назначение отклонено (строкой-статусом
  в UI). Оба способа назначения сходятся в один
  `ActionBar.assign_stance_sub()`.
- UI-редактор (Шаг 8 + вердикты юзера 22.11.26): **⚙ в углу карточки стойки =
  кнопка открытия панели приёмов** (видна ТОЛЬКО у изученной стойки);
  **клик по самой карте = магазинные семантики** (на изученной — no-op,
  панель НЕ открывает; инверсия «карта открывала панель / ⚙ покупала»
  исправлена). Мини-панель «Приёмы внутри …»: drag приёма на подсвеченный
  ActionBar (режим «Слой стойки: <имя>», drag разрешён ТОЛЬКО в нём) или
  «Клик → слот» (следующее нажатие из 14 слотов; глотается
  `set_input_as_handled` — N не закрывает окно во время ловли). В режиме
  слоя слоты ActionBar показывают **превью назначенных приёмов** (иконка
  приёма на полную яркость, включая мышиные слоты; после закрытия —
  возврат как было).
- Пресеты: `stance_binds` едут в снапшоте
  (`SkillPresetsPanel._state_snapshot`) и восстанавливаются при загрузке
  (round-trip JSON, `user://skill_presets.json`).
- `_bind_overrides` на входе в стойку: дефолты `default_slot` +
  `stance_binds` поверх — свежие бинды входят в стойку сразу.

## 4. Мана-стойка «Концентрация» (Q)

- Вход: `EnterStanceEffect` duration 4.0 с. Заряд 0–1.5 с (держим Q) →
  мощность 1.0/1.3/1.6 через `stance_power()` (зарядовая лестница).
- Под-приёмы: Сокрушение (ЛКМ, `MeleeShoveEffect`: вблизи отбрасывает,
  damage 30, reach 2.5, radius 2.8, shove_force 9.0), Сгусток (ПКМ,
  `mana_bolt` снаряд), Серп (self, `CrescentWaveEffect`: radius 12,
  half_angle 60°, damage 22).
- **Приём разряжает стойку** (`stance_exit_on_sub = true`, вердикт юзера
  22.11.26): каждый успешный под-приём закрывает стойку (`sub_used`) —
  следующий приём требует повторного входа по Q (кулдауна нет, §10).
- VFX: `Graphics/ManaStanceVFX.gd` (заряд-свечение по stance_updated).

## 5. Поток Барда (R) — ритм-стойка

Вся математика — `Logic/BardFlowComponent.gd` (консты — ССОТ чисел):
- Топливо: старт 5.0, потолок 14.0; perfect +1.2, good +0.5, miss **−0.5**
  (тюнинг 22.11.26: было −1.5 — при восьмых-нотах простой жёг топливо и
  убивал Поток <1 с); пассивный дрейл −1/с в _process; деградация tier при
  промахе.
- Барьер: 100 → max 120; perfect +14; реген +5 / 2 с от Tier 2.
- Tier-пороги 2/5/8 → 4 ступени: DR защиты {0.15,0.25,0.35,0.50},
  RR отражения {0.15,0.25,0.40,0.60}, скорость {0,10,20,25}%, мощность
  урона TIER_POWER {1.0,1.1,1.2,1.3} через `StanceComponent.power_provider`.
- Выходы: `fuel_out` (топливо кончилось), `barrier_break` (барьер разбит),
  `bard_drop` (self-приём), `max_duration` (14 с), Esc-отмена.
- **Купол dual-path**: у игрока НЕТ HealthComponent → поглощение урона
  подключено двумя хуками: `HealthComponent.damage_interceptor` (враги,
  true = урон съеден куполом) и `PlayerController.player_damage_hook`
  (сам игрок, гард `has_method`). Отражение: купол сам спавнит
  `ball_lightning` через ProjectilePool с метами `override_damage = raw ×
  RR[tier]` и `is_reflected = true` (гвард пинг-понга: reflected-удар
  поглощается без нового рикошета); спавн 2 м от атакующего.
- Ноты судьи: «Ноты Гармонии» (ЛКМ) планируются на ЧЕТВЕРТЯХ
  (eighth % 2 == 0), «Ударный Аккорд» (ПКМ) — на сильных долях (beat % 2 ==
  0); тюнинг 22.11.26: восьмые давили 4 промаха/с при простое.
- Аудио: полифония нот пентатоники на шине Bard + луп по пересечению
  индекса такта (не fmod), duck фона −14 dB на время Потока.
- **Раунд 3 (22.11.26, вердикт спеца 09+10)**: окна судьи Perfect −55..+70 мс /
  Good −110..+130 мс, miss после +130; **каст под-приёма только perfect/good**
  (×1.25/×0.85 через `stance_power`); empty_press −1.2 топлива и tier −1,
  анти-дребезг 0.18 с; пул однотактовых фраз по tier БЕЗ повтора подряд,
  одна нота на долю, синкопа +0.25 только T3 (гард зазора ≥0.45); выход
  Потока закрывается баннером BardFlowUI 2.0 с (`EXIT_BANNERS`, живёт после
  закрытия стойки); КД 2.0 с на вход стоек (Skill.cooldown); поза-боб
  `sin(beat_phase·TAU)·0.04` в стойке + T3-левитация +0.18 м
  (`PlayerController._process`); купол: fresnel pow 3.0, base alpha 0.03,
  тонкие eq-волны от MusicSpectrum вместо широких поясов, орбитальные
  частицы — процедурная 64×64 острая искра; иконки под-приёмов на ВСЕХ
  подменённых слотах ActionBar (мышиные тоже).

## 5.1 «Пульс Битвы» (bard_groove) — вторая стойка Барда (T, 22.11.26)

Вся математика — `Logic/BardGrooveComponent.gd` (консты — ССОТ чисел). ТЗ
спеца 11-ответ (Блоки 2–3). **БЕЗ падающих нот**: ритм судится на ВСЕ
действия (Hi-Fi Rush-стиль), метроном — пульс-кольца вокруг прицела.
- Грув: старт 25, спад 11%/с (на 75+ — 14%/с); tier по 40/70/95 → DR
  {0.15,0.28,0.40,0.50}, RR {0.15,0.30,0.45,0.55}, скорость {0,12,20,25}%,
  множитель урона скиллов в бит {1.0,1.15,1.25,1.35}. Жёсткий потолок
  стойки **16 с** (`MAX_DURATION`, «ПУЛЬС ЗАВЕРШЁН»).
- **Судья `evaluate_action(source)`**: dt до ближайшей доли (четверть 0.5 с
  при 120 BPM / восьмая при 72 — `fraction_len` = beat_len≤0.6 ? beat_len :
  ×0.5). Окна: |dt|≤0.075 perfect / ≤0.135 good / else offbeat. Заряд:
  скилл/саб +18/+10 (perfect ещё купол +10, кап 120), движение +12/+6;
  **1 бит = 1 заряд** (`last_charged_beat`, вердикт возвращается всегда —
  анти-абуз не блокирует). Спам сабами мимо бита чаще 0.30 с → −6 + глухой
  звук. Сигнал `groove_hit(verdict, source, delta)` → попапы UI.
- **Выходы**: `groove_empty` / `max_duration` / `barrier_break` /
  `crescendo` (Крещендо: self-саб, порог ≥60%, AoE 20–100 ∝ groove, сам
  закрывает стойку) / `cancel`.
- **Хуки (универсальный ритм)**: `SpellCasterComponent._groove_judge` в
  ОБЕИХ ветках cast_skill (инста после merge; канал после re-aim) ставит
  `context["groove_verdict"]` и умножает `context["damage_mult"]` на
  TIER_DAMAGE_MULT **пост-press tier** (tier растёт синхронно внутри
  evaluate_action — как у Потока); offbeat НИЧЕГО не меняет — скилл НИКОГДА
  не блокируется. `PlayerController._physics_process`: новые нажатия
  WASD/стрелок/Space → `evaluate_action("move")` (снапшот-битмаска прошлого
  кадра — `Input.is_key_just_pressed` НЕ существует). Скорость — через
  `speed_mult` из `_apply_buffs` (стойка УСКОРЯЕТ; stance_mult 0.5 только
  bard_flow). Купол у игрока — через `player_damage_hook`: flow ИЛИ groove
  (кто активен).
- **Купол + Нота-Рикошет**: та же dual-path связка, что у Потока
  (`damage_interceptor` + `player_damage_hook`), карта DR/RR — groove;
  рикошет через ProjectilePool с метами `override_damage`/`is_reflected`.
- **UI `Graphics/BardGrooveUI.gd`** (layer 4, IGNORE, ~204 строки, 4
  пробела): БЕЗ дорожек; два сходящихся полукольца-пульса r44→16 px по доле
  бита (`RhythmConductor.filtered_time`); дуга Грува + крупная цифра % +
  мелкий остаток лимита + 3 ромба Tier + ЗАЩ/ОТР 16px над прицелом
  (STATUS-паттерн Потока, «не на голове героя»); попапы
  «В БИТ! +18%»/«+10%» + золотая вспышка прицела; баннер причины 2.0 с
  ПОСЛЕ закрытия (`EXIT_BANNERS`, текст max_duration строится из консты).
- **AcousticBarrierVFX — единый источник**: `_active_bard()` возвращает
  BardGrooveComponent (is_active) ИЛИ BardFlowComponent (is_flowing) ИЛИ
  null — купол/кольцо/ноты живут в ОБОИХ стойках от одного кода.
- Сабы (SkillDB): groove_pulse «Нота-пуля» ЛКМ (КД 0.25), groove_step
  «Ритм-выпад» ПКМ (КД 0.45), groove_crescendo «Крещендо» self —
  `is_sub_skill`, без judge_kind (судья сам). КД входа стойки 2.0 с.
- **Квирки**: полный cast_skill в пробе двигает song_time на СВЕЖИЙ бит —
  анти-абуз съедает второй заряд в том же бите; probe RhythmConductor
  get-or-make (автолоады при -s ненадёжны, паттерн probe_bard_flow).

## 6. Инварианты (нарушать = регресс)

- **Logic-only**: вся математика стоек/топлива/барьера/tier — в Logic
  (headless-runnable); Graphics читает сигналы или опрашивает (`is_flowing`,
  `tier`).
- **Единая точка перехвата**: любой каст под-приёма — только через
  `StanceComponent.try_handle_slot()`. Новый UI-вход (другой биндер слотов)
  обязан идти через ActionBar/try_handle_slot, а не кастовать мимо.
- **Ритм-время** — только `RhythmConductor.song_time` (PLL-часы), никогда
  `Time.get_ticks_msec()`. Пресс мапится к ближайшей ноте по 1€-сглаженному
  времени (`Logic/OneEuroFilter.gd`).
- **note_id детерминирован**: `register_note(kind, grid_time) -> int`,
  вердикт уходит сигналом `note_judged(note_id, verdict)`.
- **Клампы**: `duration ≥ 0.5`, топливо/барьер в границах конст,
  `audio_offset_ms` ±150 (SettingsMenu/AudioManager).

## 7. Чек-лист новой стойки / меню стойки (30 секунд)

- [ ] Под-приёмы: `is_sub_skill = true` (не в магазине, не продаются).
- [ ] Skill-сборка стойки: заполненный `stance_sub_skills` (id/label/default_slot).
- [ ] `EnterStanceEffect.stance_id` заполнен; SkillDB пре-лоадит эффект —
  внутри эффекта `load()`, не preload (цикл preload ломается).
- [ ] ActionBar: ВСЕ подменённые слоты (key И мышиные ЛКМ/ПКМ) показывают
  иконку под-приёма + фиолет-подсветку (В.7, вердикт 09 — как в превью
  редактора; старое «mouse без иконки» отменено).
- [ ] `_try_stance` подключён И в key-ветке `_unhandled_input`, И в
  mouse-ветке `_input`.
- [ ] ⚙-панель: открытие включает «Слой стойки», закрытие (и N-закрытие
  книги) — выключает; бинды едут в пресет.
- [ ] VFX/UI слушают сигналы, не пишут в Logic.
- [ ] Новый `probe_*.gd` с чеками enter/exit/intercept/exit-reason + смоук
  сцены: EXIT=0, 0 SCRIPT ERROR.

## 8. История регрессий (не повторять)

- **Ключи vs значения биндов**: словарь биндов — ключи = sub_id; проверка
  «слот занят» = `values().has(slot_label)`. `get(slot_label)` по ключу
  ловил пустоту — гард чужой стойки молча не срабатывал (probe_binds_ui
  прогон 3).
- **Типизированные поля UI**: `var player: CharacterBody3D` в SkillMenu/
  SkillPresetsPanel — стаб игрока в пробах ОБЯЗАН быть CharacterBody3D,
  иначе SCRIPT ERROR в _ready и дерево не строится (прогон 2, висел до
  таймаута).
- **`var x := untyped.method()`** — Parse Error «Cannot infer the type»;
  явные типы (`var snap: Dictionary = ...`).
- **SCRIPT ERROR в probe `_run` абортирует `_run`** → quit() не доходит →
  прогон висит до таймаута. Каждый чек — через `_ck()`, никаких «прямых»
  обращений, могущих упасть.
- **Двойной уход из Потока**: close_flow → exit_stance → гонка со вторым
  close_flow; лечится гардом `is_flowing` и веткой `_on_stance_exited`.
- **Частицы орбиты остаются после выхода** (probe_bard_vfx прогон 1):
  при переходе flowing→false выключать не только купол, но и
  `_notes.emitting`.
- **Инверсия карта/⚙** (плейтест 22.11.26): клик по КАРТЕ стойки открывал
  панель приёмов, а ⚙-кнопка — «покупала». Исправлено: ⚙ = кнопка панели
  (`_on_gear_input` + `accept_event`), карта = магазин (no-op на изученной);
  без `MOUSE_FILTER_STOP` на ⚙ клик доходит до карточки-магазина.
- **Каскад exit_on_sub в probe-ах** (22.11.26): после «приём = разряд
  стойки» probe_mana краснел каскадом (ступени 2/3 заряда в ОДНОЙ стойке
  недостижимы — charge не копится в закрытой стойке) — probe перестроен:
  повторный вход по Q между ступенями + чеки `sub_used` (49 чеков).
  probe_bard_flow: чек «Miss −1.5 → 5.2» → «Miss −0.5 → 6.2» (83).
- **Урок купола — «пробы зелёные, рантайм кривой»** (вердикт 11, 22.11.26):
  AcousticBarrierVFX единственный в проекте считал `player.global_position.y`
  «полом», а покой игрока в MainArena — **y=1.0** (капсула r0.5 h2.0 origin —
  низ на 0.0) → весь купол уезжал на +1.0 м (кольцо на поясе, сфера висит).
  Пробы-стабы стояли на y=0 — код совпадал с пробой, не с рантаймом. Фикс:
  `_cache_feet` (низ коллайдера один раз: capsule/cyl position.y−h·0.5,
  box −size.y·0.5; нет шейпа → fallback −1.0), центр = feet_y+0.95, ground_y
  = raycast вниз 2.6 м (Array[RID] exclude, маска 1), кольцо ground_y+0.02,
  scale.x/z = sqrt(R²−dy²)/base_fit (сечение сферы полом), скрыть при
  dy≥1.8. **Урок: высотные якоря мерить в реальной сцене с физикой**
  (probe_bard_dome_real_scene — MainArena + CharacterBody3D), не в стабе.
  Плюс Vulkan-квирк шейдера: DEPTH через NDC не работает на Compatibility —
  `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` ветка.
- **Input.is_key_just_pressed НЕ существует** (4.8): только
  `is_key_pressed`; just-pressed для WASD/стрелок/Space в PlayerController —
  снапшот-битмаска прошлого кадра (`_groove_prev_keys`).

## 9. Гейты (все headless, EXIT=0, 0 SCRIPT ERROR)

Раунд 3 (22.11.26, вербатим): `probe_bard_antispam` (19) ·
`probe_bard_patterns` (11, seed-скан T3-синкопы) ·
`probe_skillmenu_await_slot` (30) · `probe_bard_exit_reason` (37) ·
`parse_check_r3` (13) — плюс обновлённые под новые окна/семантику:
`probe_stance_input` (33) · `probe_stance_contracts` (23) ·
`probe_stance_mana` (52) · `probe_health_buffs` (16) ·
`probe_rhythm_conductor` (15) · `probe_rhythm_judge` (28) ·
`probe_audio_bard` (31) · `probe_bard_flow` (100) · `probe_bard_vfx` (34) ·
`probe_binds_ui` (37) + регрессия `test_skill_forge` (52) + смоуки
MainArena/ProceduralArena/HellArena/Rotmarsh. ПОЛНЫЙ прогон после В.7 —
22.11.26: все EXIT=0, 0 FAIL, 0 SCRIPT ERROR. Рендер-проб купола/дуг:
`_tmp_probe/render_bard_check.ps1` → PNG просмотрен агентом.

Стойка groove (22.11.26, 11-ответ): `probe_bard_groove_mechanics` (37) ·
`probe_bard_dome_real_scene` (18) · `probe_parse_check_groove` (10) —
полный прогон 18 проб + смоуки MainArena/Rotmarsh EXIT=0, 0 FAIL, 0 SCRIPT
ERROR; render_bard_check PNG a/b просмотрены (кольцо на полу в обеих
стойках — единый `_active_bard()`).

## 10. Честные оговорки (edges)

- **Рикошет не летит от снарядов**: ProjectileComponent/HellFireball не
  передают `attacker` в `take_damage` — купол поглощает урон снаряда, но
  нот-рикошет в стрелявшего не возвращается (нет атакующего для спавна).
- **Бард-duck vs боевой fade**: MusicDirector глушит фон своим
  неотслеживаемым `_fade`-твином при бое — может перебить duck −14 dB
  Потока. В пробах гасится (`_combat_stream = null`); полировка после
  плейтеста.
- **Кулдаун**: КД 2.0 с на вход стоек реализован (В.6.4, Skill.cooldown +
  SpellCaster CD, цифры отката на слоте); «откат ~15 с» из старого ТЗ спеца
  НЕ реализован — решение за юзером после плейтеста.
- **Баннер Потока = переход**: BardFlowUI ставит баннер причины в `_process`
  ТОЛЬКО на переходе is_flowing true→false — если стойка вошла и закрылась
  в одном синхронном блоке (проба!), баннера НЕТ: между входом и закрытием
  обязателен `await process_frame`.
- **Headless-дисплей глотает CAPTURED**: `set_mouse_mode` в headless — no-op;
  пробы проверяют захват через гард `DisplayServer.get_name() == "headless"`.
- Хитстоп «Сокрушения», наезд камеры, эпичный лид на T3 — опциональная
  полировка, только по вердикту юзера (раздел 5 PRP).
