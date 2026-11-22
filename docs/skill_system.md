# Архитектура Системы Навыков (Data-Driven & Composition)

Все скиллы и умения в проекте строятся по принципу **"Композиция вместо наследования" (Composition over Inheritance)**, как детали конструктора Лего.

## 1. Базовые принципы
* Мы **КАТЕГОРИЧЕСКИ НЕ** создаем отдельный скрипт под каждый новый скилл (никаких `FireballSkill.gd` или `IceBoltSkill.gd`).
* Вместо этого используется класс-контейнер `Skill`, который содержит массив независимых микро-эффектов `Effect`.
* Каждый скилл — это сборка из готовых кусочков данных, создаваемых в `SkillDB` (Data-Driven Design).
* Любой новый скилл должен быть просто комбинацией уже существующих эффектов, либо потребуется написать новый атомарный `Effect`.

## 2. Основные классы (`res://Logic/Skills/`)
* **`Skill`** — ресурс-контейнер. Хранит иконку, цену, дистанцию каста и массив эффектов.
* **`Effect`** — абстрактный базовый класс для любого эффекта. Имеет единый метод `apply(caster: Node, context: Dictionary)`.
* **Наследники `Effect`** (например, `SpawnProjectileEffect`, `TeleportEffect`) содержат изолированную и атомарную логику (только выпустить снаряд, только переместить игрока и т.д.).

## 3. Как добавить новый скилл?
Все навыки регистрируются программно в Синглтоне `SkillDB.gd`. 

Пример сборки "Огненного Телепорта" (наносит урон вокруг при старте и перемещает игрока):
```gdscript
var fire_blink = Skill.new()
fire_blink.id = "fire_blink"
fire_blink.skill_name = "Огненный Скачок"

# Деталька 1: Взрыв на старте (допустим, у нас есть такой эффект)
var aoe = AoeDamageEffect.new()
aoe.radius = 5.0
fire_blink.effects.append(aoe)

# Деталька 2: Перемещение
var tel = TeleportEffect.new()
tel.vfx_scene = load("res://Scenes/teleport_effect.tscn")
fire_blink.effects.append(tel)

skills["fire_blink"] = fire_blink
```
Таким образом, `SpellCasterComponent` больше никогда не нуждается в дописывании кода при добавлении новых заклинаний!

## 4. Пользовательские скиллы (Кузница, Q36 — 19.11.26)
Стол зачарований на арене (35.5, 0, 35.5) — точка входа: подход → подсказка
«[Z] — Кузница скиллов» → окно-конструктор (`Graphics/SkillForgeWindow.gd`,
автолоад `/root/SkillForgeWindow`). Z открывает в зоне и закрывает ВСЕГДА
(даже с фокусом на контроле), уход от стола закрывает окно автоматически.

**Конвейер данных:** форма окна → `Dictionary` JSON-схемы →
`UserSkillDB.save_skill` (валидация через `SkillSerializer`, запись в
`user://custom_skills.json`, обёртка `{"skills": [...]}`) →
`SkillDB.register(id, skill)` — и скилл сразу виден магазину (SkillMenu),
ActionBar и касту: всё работает по `id` без дописывания кода.

**Правила:**
* id пользовательских скиллов ВСЕГДА с префиксом `user_` — `SkillDB.register/
  replace/unregister` и `UserSkillDB` отклоняют всё остальное; конфликт id с
  встроенным скиллом = отказ (встроенные не перезаписываются).
* Загрузка: `SkillDB.get_skills()` в конце ленивой инициализации вызывает
  `UserSkillDB.load_all()` — битая запись JSON пропускается с логом, файл
  целиком не валим; повторный вызов load_all идемпотентен (флаг).
* Границы данных — ССОТ: ползунки окна импортируют те же `CLAMP_*` константы
  `SkillSerializer`, что и валидатор при загрузке (UI-граница == граница данных).
* Пути ассетов — только белые списки сериализатора (3 сцены снарядов, 3 VFX,
  8 звуков); каждый путь дополнительно проверяется `ResourceLoader.exists`.
  Произвольные пути из JSON невозможны. Эффекты вне MVP-набора (Blade/Wings/
  Portals/SoftAim) при сериализации пропускаются.
* Правка скилла: кнопка ✎ в списке «Мои скиллы» кладёт его в форму
  (`load_from_dict`) и сохраняет под тем же id (replace, без дублей).
* Удаление: ✖ → `UserSkillDB.delete_skill` + `SkillDB.unregister` +
  `notify_deleted` окну.
* Захват мыши: открытое окно Кузницы блокирует клик-захват в мире — флаг
  `is_open` проверяется в `PlayerController._gui_blocks_capture` (ССОТ
  docs/ui_input_rules.md; гейт — Generators/probe_mouse_gate.gd).

**Гейты (все headless, EXIT=0, 0 SCRIPT ERROR):**
* `Generators/test_skill_forge.gd` — контракт данных: round-trip, клампы,
  белые списки, register-гейты, JSON-персист (52 чека).
* `Generators/probe_skill_forge_zone.gd` — зона стола: подход/подсказка/Z/
  авто-закрытие (11 чеков).
* `Generators/probe_skill_forge_ui.gd` — окно: open/close, создание/правка/
  удаление через форму, JSON на диске, живой реестр (21 чек).
* `Generators/probe_skill_forge_execute.gd` — сквозной: user-скилл
  «снаряд+взрыв» кастуется по манекену — AoE снимает ровно свой урон,
  fireball летит и долетает (13 чеков).

## 5. Система стоек (Stance Override, Q16 — 22.11.26)

Стойка временно подменяет слоты под-приёмами: пока активна — нажатия
перехваченных слотов кастуют под-приёмы, после выхода обычные скиллы
возвращаются. Контракт `StanceComponent`, правила `is_sub_skill`/
`stance_sub_skills`/`stance_binds`/swap, Поток Барда и инварианты —
**ССОТ: [docs/stance_system.md](stance_system.md)** (дочитай перед правкой
перехвата слотов — там чек-лист новой стойки и история регрессий).
Кирпичи стоек — `EnterStanceEffect`/`MeleeShoveEffect`/`CrescentWaveEffect`/
`BardNoteEffect`/`BardDropEffect` в [skill_effects_catalog.md](skill_effects_catalog.md).