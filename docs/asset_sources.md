# Источники бесплатных 3D-ассетов — ССОТ

> Статус: ССОТ (v1, 19.11.26). База — заготовки юзера. Любой скачанный ассет
> регистрируется в разделе «Журнал ассетов» внизу (лицензия / источник / где
> используется). Вопрос «откуда это?» решается одним поиском по этому файлу.

## Правило лицензий (читать перед КАЖДОЙ скачкой)

| Лицензия | Что можно | Что требует |
|---|---|---|
| **CC0** | всё, в т.ч. в коммерческую игру | ничего (даже имя автора) |
| **CC-BY 4.0** | всё | указать автора (строка в кредитах игры) |
| Sketchfab **Free Standard** | использовать в игре | НЕ перераспространять файлы, ссылка на автора в кредитах |
| GPL (OpenGameArt) | использовать в игре | исходники, если что-то из ассета попадает в дистрибутив как код — для арт-ассетов обычно не критично, читать лицензию конкретного пака |

Предпочтение всегда: CC0 → CC-BY → Free Standard. «Лицензия не указана» = не
скачивать. Коммерческое использование проверять на странице каждого пака.

> **ВЕРДИКТ ЮЗЕРА 19.11.26: используем ТОЛЬКО CC0.** CC-BY и прочие «с
> указанием авторства» не проходят. Пункты этого дока с не-CC0 лицензиями
> оставлены справочно, в проект их НЕ брать (ABO-glb = CC-BY-4.0 и
> Megascans = Fab Standard — вне правила). Нейро-генерация через
> plugin-mesh-engine (trellis) — основной путь уникальных пропов: результат
> наш, лицензия не нужна вообще.

## 1. Локации / меши / рельеф

### Только рельеф (Heightmaps)
1. **Tangram Heightmapper** — бесплатная карта всего мира. Находишь Альпы или
   Гранд-Каньон, «Export» → готовая карта высот для движка. Реальный рельеф,
   без копирайтов.
2. **Terrain.party** — вытаскивает рельеф реальной Земли (использовался для
   Cities: Skylines, подходит для всего).
3. **Генераторы рельефа**: Gaea, World Machine, процедурные плагины внутри
   движков — горы любого вида с нуля, результат на 100% твой.

### Сканы и локации с текстурами
4. **Sketchfab.com** (нужна регистрация):
   - поиск: `arena`, `ruins`; галочка **Downloadable**;
   - формат скачивания — **glTF** (Godot 4 грузит его идеально вместе с
     текстурами; наш пайплайн пропов построен на glTF);
   - для блокгаутов/заготовок арен искать слова: **Blockout, Whitebox,
     Greybox, Untextured**;
   - лицензии: CC0 и Free Standard (см. таблицу выше);
   - полезные категории для сканов природы/локаций:
     - **Places & Travel** — отсканированные реальные куски земли, скалы,
       овраги, руины;
     - **Nature & Plants** — куски леса, поляны, камни;
     - **Cultural Heritage & History** — сканы храмов, раскопок, замков
       (референсы).

### Готовые паки пропов (легальные «Лего»)
5. **Kenney.nl** — база инди-разработчика. Раздел Assets → 3D:
   - **Prototype Textures** — сетчатые текстуры стен/пола (приятные, разных
     цветов);
   - **Nature Kit** — low-poly деревья, камни, земля;
   - вся графика мультяшная (low poly) — для прототипов идеально.
6. **OpenGameArt.org** — выглядит как из 2005, но тонны ресурсов. Фильтр:
   3D Art + лицензия **CC0** (GPL тоже приемлем).
7. **Itch.io** — раздел Game Assets. Поиски: `3d environment CC0`,
   `3d modular CC0`, `low poly environment`, фильтр **Free**. Сотни арен,
   подземелий и лесов.
8. **PolyHaven.com** → Models — фотографически реалистичные камни, деревья,
   объекты. Всё CC0.
9. **AmbientCG.com** → 3D Models — вторая большая база моделей, CC0.
10. *(добавлено агентом 19.11.26)* **Quaternius.com** — большие паки фэнтези/
    природы (Ultimate series), CC0. **Poly Pizza** — агрегатор low-poly
    моделей с фильтром CC0. Для «кузницы/стола зачарований/манекена» искать
    в первую очередь тут и в Kenney.

### Датасеты / библиотеки сканов (массовые базы)

11. *(добавлено 19.11.26, заказ юзера)* **Amazon Berkeley Objects (ABO) в GLB** —
    huggingface.co/datasets/codepawl/abo-glb:
    - **7 953 модели** предметов быта и мебели (кресла, диваны, столы, лампы,
      ковры) с реальными размерами в метрах; лицензия **CC-BY-4.0** (указать
      «Amazon Berkeley Objects Dataset» в кредитах; repack от CodePawl, Amazon
      не аффилирован);
    - **вход для Godot без конверсий**: папка `engine/` (~16.6 ГБ, без
      meshopt-сжатия, «for engines like Godot»), плюс `lods/` (3 уровня),
      `collision/` (готовые выпуклые коллизии — наш стандарт после инцидента
      с trimesh!), `metadata.jsonl` (треугольники/размеры до скачивания);
    - форматы glb с WebP/KTX2-текстурами; масштаб Y-вверх — совместим с Godot;
    - профиль применения: ИНТЕРЬЕРЫ и бытовые объекты (не уличные пропы
      природы — для них PolyHaven/сканы).
12. *(добавлено 19.11.26, заказ юзера)* **Quixel Megascans** —
    fab.com/sellers/Quixel%20Megascans (нужен аккаунт Epic):
    - фотограмметрия-сканы высшего качества (камни, скалы, растительность,
      поверхности — то же семейство, что наши юзерские сканы);
    - **лицензия Fab Standard**: можно в коммерческую игру, НЕЛЬЗЯ
      перераспространять сырые файлы (не выкладывать в наш публичный git);
    - история бесплатности (важно проверять на момент скачки): промо «весь
      libры бесплатны» кончилось в 2024 — всё, что «клеймнули» тогда,
      остаётся бесплатным навсегда; в 2025 платно, ~1500 стартовых бесплатных
      осталось; Epic анонсировал возврат полной библиотеки к бесплатности с
      12.11.2026 — статус на момент скачки проверять на Fab напрямую;
    - формат скачки — GLTF/FBX под наш пайплайн; полигоны у сканов большие →
      обязательный гейт декимации (AGENTS §6.5).

## 2. Текстуры

1. **PolyHaven.com** — лучшие реалистичные текстуры, всё CC0.
2. **AmbientCG.com** — огромная база текстур земли, дерева, камня (CC0).
   *(В проекте уже используется: пол MainArena/ProceduralArena
   `forrest_ground_01` — именование ambientCG, точная запись о скачке не
   сохранилась; считать ambientCG, при следующей скачке зафиксировать в
   журнале.)*

## 3. Звуки / SFX

- **Freesound.org** (нужна регистрация) — в фильтрах справа ставить лицензию
  **Creative Commons 0** (автора указывать не нужно). Поисковые запросы:
  | Событие | Ключевые слова |
  |---|---|
  | Огненный шар (каст/полёт) | Fire whoosh, Flame burst, Fire spell |
  | Огненный взрыв (импакт) | Fire explosion, Magic impact, Boom |
  | Лечение / Телепорт | Magic chime, Sparkle magic, Fairy dust, Synth zap |
  | Молния | Electric zap, Thunder strike, Static shock |
  | Шаги | Footstep dirt, Footstep stone, Run boots |
  | Удар мечом (на будущее) | Sword swing, Blade whoosh, Flesh hit |
- **Zapsplat.com** — вторая библиотека (проверять лицензию на каждый звук).
- **Генераторы**: Bfxr, sfxr — ретро/8-бит звуки для прототипов.
- **Нейро-SFX** — наш основной путь (Audio/Gen/neural/*, ССОТ:
  docs/features.md / MusicDirector); сторонние библиотеки — фолбэк/пополнение
  пула.

## 4. Анимации

- **Mixamo.com** — огромная бесплатная библиотека анимаций под Humanoid Rig.
  Ключевые слова: `sword attack`, `magic cast`, `spell cast`, `hit reaction`,
  `death`, `dodge`. Скачивание — FBX.
- **Наш конвейер** (не Mixamo-путь, а свой): FBX → `Graphics/Animations/raw/` →
  `build_animations.gd` → `shared_animations.res` (AGENTS §7; фикс пути
  `mixamorig1_` → `mixamorig_`). Нейро-касты — через тул `anim` (ССОТ
  docs/animation_generation.md).
- **Магия в руке персонажа (паттерн Godot 4):**
  1. Импорт модели/анимации.
  2. На Skeleton3D создаётся **BoneAttachment3D** на кости кисти (RightHand).
  3. В BoneAttachment3D кладётся система частиц (GPUParticles3D с фаерболом)
     — эффект следует за рукой.
  4. В AnimationPlayer на нужном кадре броска — Call Method Track / Property
     Track: отцепить частицы и запустить в цель, либо `emitting = true`.
  *(В проекте это уже реализовано: SpawnProjectileEffect.spawn_from_hand +
  CastIKComponent — см. docs/skill_system.md.)*

## 5. VFX

- **itch.io** — поиски `VFX`, `Spell effects`, `free particles`,
  `free magic effects`.
- **Kenney.nl** — пак **Particle Pack**: текстуры огня, искр, звёзд для
  сборки магии.
- **Godot Asset Library** (вкладка AssetLib в движке).
- **Генераторы спрайтовых последовательностей** — текстуры для частиц,
  собираются в систему частиц вручную.
- **Effekseer** (effekseer.github.io) — open-source редактор игровых эффектов
  (магия/удары/взрывы, аниме/JRPG-стиль). Официальный плагин Godot 4:
  github.com/effekseer/EffekseerForGodot4.
  Рабочий процесс с ИИ: юзер сам скачивает .efkefc → кладёт в проект →
  агент пишет GDScript-логику (EffekseerEmitter3D + загрузка файла + проигрыш).
  Сам эффект ИИ создать не может — только подключить.
  *(В проекте пока НЕ используется: VFX — процедурные GPUParticles3D, ССОТ
  docs/vfx_guidelines.md. Effekseer — запасной вариант, если процедурных
  станет мало.)*

## 6. Прочее

- Список бесплатного для геймдева:
  github.com/ripienaar/free-for-dev (раздел Game Development).
- Краткая шпаргалка: Itch.io (звуки, VFX, модели), Sketchfab (модели),
  Mixamo (анимации), Kenney.nl (всё для прототипов), Freesound.org (аудио),
  Quixel Megascans (фотограмметрия-сканы), ABO-glb (мебель/быт, датасет).

## 7. Справка: Unity-путь (не для этого проекта)

Хранится по просьбе юзера как референс (если будет портирование/другой проект):

- Mixamo: загрузить FBX модели → Rig = Humanoid → скачать клипы
  («FBX for Unity») → извлечь клипы → Animator Controller + переходы.
- Каст умения (временное решение): проигрывать часть анимации атаки или
  короткий фриз в Idle; получение урона — «спотыкание»/дёрганье назад кодом.

## 8. Интеграция в ЭТОТ проект (гейты, обязательные для скачанных мешей)

1. Формат — **glTF (+bin)** → наш v2-пайплайн пропов (AGENTS §6.5, §9):
   optimize_triangles.py → check_polycount.gd (ГЕЙТ) → build_env_prop.gd →
   render-проба PNG → build_main_arena.gd → смоук.
2. Нормы полигонажа: фон 50–300 трис, средний 300–1500, хиро 1000–5000.
3. Сырье кладётся в отдельную папку; папки `raw/` защищать `.gdignore`.
4. bin-файл НЕ переименовывать (gltf ссылается по имени, AGENTS §9).
5. Текстуры из glTF — через `--import`-флоу v2 (compress/mode=2 + mipmaps),
   иначе ResourceSaver вкомпывает их в .res (25–38 МБ/меш).
6. **Журнал ассетов** (раздел ниже) — запись СРАЗУ после скачки.

## 9. Журнал ассетов (SSOT-учёт: скачал → записал)

| Дата | Ассет | Источник | Лицензия | Куда положен | Где используется |
|---|---|---|---|---|---|
| — | forrest_ground_01 (текстура пола) | ambientCG (по именованию; точная скачка не зафиксирована) | CC0 | Graphics/Environment | пол MainArena + рельеф ProceduralArena |
| — | photogrammetry-сканы юзера (boulder, rock_moss, ель и пр.) | собственные сканы | собственные | Graphics/Environment/Props | пропы карт 1–2 |
| 19.11.26 | training_dummy (нейро-проп, 5000 трис) | собственная генерация: Blender-концепт → trellis-cli image→3D → optimize_triangles v2 | своя (лицензия не нужна) | Graphics/Environment/Props/training_dummy/ | стоячие мишени MainArena (Q37) |
| 19.11.26 | enchant_table (нейро-проп, 4999 трис) | собственная генерация: Blender-концепт → trellis-cli image→3D → optimize_triangles v2 | своя (лицензия не нужна) | Graphics/Environment/Props/enchant_table/ | стол зачарований MainArena (Q37, объект Q36) |
| 20.11.26 | PineNeedles001 (Color/Opacity/Normal/Roughness 2K) | [ambientCG](https://ambientcg.com/view?id=PineNeedles001) | CC0 | tasks/261117_2355-089dca89/stock/ambientcg_pine_needles_001/ → Graphics/Environment/Props/pine_tree_01/foliage_diff_B.png + _orm_B.png (атлас 1024², pine_atlas_stock.py) | ель B «CC0-фотоскан иголок» у спавна MainArena (Q22-B, слот TreeB_StockScanCards) |
| 20.11.26 | modular_tree (MTree) 5.6.0 — Blender-аддон генерации деревьев | [GoodPie/modular_tree](https://github.com/GoodPie/modular_tree) | GPL-3.0 (ИНСТРУМЕНТ: выходной меш наш, лицензия аддона на генерат не распространяется) | tasks/261117_2355-089dca89/stock/modular_tree_560/ → Generators/build_mtree_spruce_cards2.py | ель C «MTree живой скелет» (Q22-C, слот TreeC_MTree, 3830 трис) |
| 20.11.26 | moon_rock_02 (diff/nor_gl/arm 4K) | [polyhaven.com/models/moon_rock_02](https://polyhaven.com/models/moon_rock_02) | CC0 | Graphics/Environment/Props/moon_rock_02/ (v2-пайплайн, 1200 трис, --scale-to 1.0) | скаттер камней карты 2, группа Rocks_2 (Q11) |
| 20.11.26 | moon_rock_03 (diff/nor_gl/arm 4K) | [polyhaven.com/models/moon_rock_03](https://polyhaven.com/models/moon_rock_03) | CC0 | Graphics/Environment/Props/moon_rock_03/ (v2-пайплайн, 1200 трис, --scale-to 0.8) | скаттер камней карты 2, группа Rocks_3 (Q11) |
| 20.11.26 | rock_07 (diff/nor_gl/arm 4K) | [polyhaven.com/models/rock_07](https://polyhaven.com/models/rock_07) | CC0 | Graphics/Environment/Props/rock_07/ (v2-пайплайн, 1200 трис, --scale-to 1.2) | скаттер камней карты 2, группа Rocks_4 (Q11) |
| 20.11.26 | stone_01 (diff/nor_gl/arm 4K) | [polyhaven.com/models/stone_01](https://polyhaven.com/models/stone_01) | CC0 | Graphics/Environment/Props/stone_01/ (v2-пайплайн, 1200 трис, --scale-to 0.9) | скаттер камней карты 2, группа Rocks_5 (Q11) |
| 20.11.26 | namaqualand_boulder_04 (diff/nor_gl/arm 4K) | [polyhaven.com/models/namaqualand_boulder_04](https://polyhaven.com/models/namaqualand_boulder_04) | CC0 | Graphics/Environment/Props/namaqualand_boulder_04/ (v2-пайплайн, 1200 трис, без scale-to, 2.5 м) | скаттер камней карты 2, группа Rocks_6 (Q11) |

*(Новая строка на каждый скачанный файл. Пример: `19.11.26 | anvil.glb |
polyhaven.com/models/anvil | CC0 | Graphics/Environment/Props/forge/ | кузница MainArena`)*
