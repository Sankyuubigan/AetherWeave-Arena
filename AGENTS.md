# AI Agent Workflow Rules (CRITICAL)

Ты — Lead-разработчик на Godot 4 (GDScript). Пользователь выступает только как тестировщик и геймдизайнер. Пользователь НЕ использует графический интерфейс редактора Godot. Твоя задача — писать весь код, генерировать сцены и запускать игру через терминал.

## 0. Решение проблем (Troubleshooting)
* Если на каком-либо этапе возникли проблемы — сразу ищи в интернете документацию по ошибкам. Не пытайся гадать или патчить наугад. Ошибка → поиск в Google/GitHub Issues → чтение документации → только потом исправление.

## 0.1. Сначала читай docs
* Прежде чем начинать любую работу, **ОБЯЗАТЕЛЬНО** прочитай файлы из `res://docs/`. Там лежит ключевая информация о проекте: фичи, архитектура, стек технологий и troubleshooting.

## 1. Запрет на ручное редактирование сцен
* **НИКОГДА** не пытайся создавать, писать или редактировать файлы `.tscn` напрямую как текст. Это ломает структуру и ID файлов Godot.

## 2. Как создавать сцены (Генераторы)
* Чтобы создать или обновить сцену (`.tscn`), ты должен написать временный скрипт-генератор на GDScript (например, `build_player.gd`), который наследуется от `SceneTree`.
* Внутри скрипта (в `_init()` или `_process()`):
  1. Создай узлы (например, `var root = CharacterBody3D.new()`).
  2. Выстрой иерархию (`root.add_child(camera)`).
  3. **ОБЯЗАТЕЛЬНО** назначь `owner` для всех дочерних узлов на `root` (иначе они не сохранятся в файл: `camera.owner = root`).
  4. Упакуй сцену: `var packed = PackedScene.new(); packed.pack(root)`.
  5. Сохрани: `ResourceSaver.save(packed, "res://Scenes/player.tscn")`.
  6. Вызови `quit()`.
* Запусти этот скрипт через терминал:
  `& "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/build_player.gd`

## 3. Файловая структура
Сразу создай и поддерживай строгую иерархию:
* `res://Logic/` (Скрипты компонентов логики, сети и математики)
* `res://Graphics/` (Скрипты для UI, визуальных эффектов и анимаций)
* `res://Scenes/` (Сгенерированные `.tscn` файлы)
* `res://Generators/` (Временные скрипты, которые ты пишешь для создания `.tscn` файлов)

## 4. Запуск для пользователя
Когда ты закончил генерацию и хочешь, чтобы пользователь протестировал игру, запусти главную сцену через терминал:
`& "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" res://Scenes/MainArena.tscn`

## 5. Путь к движку
Godot 4.8-beta3 находится по пути: `D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe` (откат на 4.7: `D:\Programs\Godot\Godot_v4.7-stable\Godot_v4.7-stable_win64_console.exe`)

## 6. Контроль размера файлов и Clean Code
* **Размер кода:** Перед внесением исправлений проверяй количество строк в файле. Старайся не превышать предел в **300-500 строк кода** на один файл. 
* **Разделение логики:** Если файл слишком разросся или класс превращается в "God Object", выноси часть логики в новые модули или отдельные файлы компонентов. Это критически важно для упрощения поддержки проекта в будущем.

## 6.5. Конвейер декормации (Decimate pipeline)

### Правило: никогда без `delimit`
При декормации photogrammetry-мешей через Blender DECIMATE modifier **ОБЯЗАТЕЛЬНО** используй:
```python
mod.delimit = {'NORMAL', 'UV', 'SEAM', 'SHARP'}
mod.use_collapse_triangulate = False
```

Без `delimit` DECIMATE коллапсит рёбра поперёк UV-швов и границ нормалей, создавая растянутые треугольники с битыми нормалями. В Godot это выглядит как «прозрачность» модели (артефакты normal map из-за растянутых UV).

### Режимы декормации
- **REMESH (VOXEL)** — для одиночных больших мешей (boulder 66K→13.5K): `--remesh`. Voxel Remesh + Smart UV Project + Normal Bake + **Diffuse Bake (обязателен!)**. Лучшее качество на одиночных мешах.
  REMESH строит НОВЫЕ UV → старое альбедо невалидно. Без `bake_diffuse_map` материал
  получается белым (tex_diff=None): так «поседели» камни карты 2 (17.11.26 — вердикт
  юзера «белые камни выглядят ужасно пиксельно»). Нормал-бейк без диффуз-бейка не спасает.
- **DECIMATE (Collapse + delimit)** — для мульти-мешей (rock_moss 63K→15K, 6 объектов): режим по умолчанию. Single-pass с `delimit = {'NORMAL', 'UV', 'SEAM', 'SHARP'}`.
- **Двухстадийный (гиганты >5М трис)** — стадия A: `predecimate_raw.py` воксель-ремеш
  без weld/UV (ель 17.18М→2.8М за 50 с), стадия B: `optimize_triangles.py --target N`
  с work-копии. Напрямую 17М не декимировать: weld/QEM на 17М = 25+ мин и 35 ГБ РАМ
  (инцидент 18.11.26). Итог двух стадий: ~4.5 мин, РАМ в разы ниже.
- **Multi-pass** (устарел): итеративные проходы — не нужны.
- **Растительность (хвоя/листва) — ОТКРЫТАЯ ПРОБЛЕМА**: воксель-ремеш съедает иглы
  (мм-геометрия тоньше вокселя), UV-атлас таких сканов занят на 0–4% → бейк в кляксы,
  проп выглядит как сухостой (ель, 19.11.26 — отправлено спецу, §13 меш-отчёта).
  Не декимировать растительность этим конвейером до решения.

### v2-пайплайн сборки пропа (19.11.26 — камни одобрены юзером)
1. Бейки: samples=64 (дефолт 4096 = 25 мин!), OPTIX→CUDA-фолбэк (в headless GPU молча
   падает на CPU), `use_clear=False` + heal-заливка незапечённых текселей (иначе фон
   атласа = чёрные осколки), диффуз-бейк обязателен всегда.
2. Выход: diffuse+normal+ORM (R=AO,G=Rough,B=Metal) → `build_env_prop.gd` собирает
   ORMMaterial3D. Флоу текстур: `--import` → sed `compress/mode=2` + `mipmaps/generate=true`
   (+`compress/normal_map=1` нормалям) → `--import` снова → и ТОЛЬКО ПОТОМ
   `build_env_prop.gd` (без .import load() даёт pathless-фолбэк, ResourceSaver
   вкомпывает текстуры в .res → 25–38 МБ/меш, 576 МБ VRAM).
3. После перегенерации текстур ОБЯЗАТЕЛЕН повторный `--import`: load() отдаёт старый
   .ctex из кэша (два «не сработавших» фикса из-за этого).
4. Коллизия пропа: `mesh.create_convex_shape(true, true)` — НЕ trimesh: упор
   CharacterBody3D в trimesh = депенетрация 5–11 мс на КАЖДЫЙ тик физики
   (фризы 100–400 мс у валуна; convex 32 точек — worst 1.7 мс).

### Важные ограничения
- DECIMATE НЕЛЬЗЯ использовать на одиночных мешах >20K — creates stretched triangles с битыми нормалями ("прозрачность")
- REMESH(voxel) теряет UV и материалы — нужно пересоздавать их через Smart UV Project + сборку материала
- ARM текстуры (AO/Roughness/Metallic) экспортируются в glTF через `ShaderNodeSeparateColor` (mode=RGB)
- Blender 5.1: `ShaderNodeSeparateRGB` переименован в `ShaderNodeSeparateColor`

### Запуск
```
& "D:\Programs\Blender Foundation\Blender 5.1\blender.exe" --background --python res://Generators/optimize_triangles.py -- <path_to_gltf> [--no-bake] [--no-decimate]
```

## 7. Конвейер сборки анимаций (Animation pipeline)

### Нейро-анимации кастов (SOMA30 / kimodo.cpp) — ССОТ `docs/animation_generation.md`
Канон, правила промптов и реестр ошибок — там же. Генерация одной командой —
тул `D:\Projects\cross-app-plugins\bin\agent-tools.exe anim --name <clip>
(--prompt "..." | --prompt-file F) [--type cast_push]`: промпт → параллельные
сиды kmd-generate → численный гейт probe_hand_path.gd → победитель в
`Graphics/Animations/neuro_soma/<clip>/`. Без PASS гейта в проект ничего не
попадает (EXIT≠0). Ретаргет (`retarget_soma_anims.gd`), тесты и смоук — по §2 ССОТ.

### Как работает `build_animations.gd`
Скрипт конвертирует исходные FBX анимации в сжатый `.res` файл, который используют все скины:
1. Загружает каждый FBX через `FBXDocument`
2. Извлекает анимации (с исправлением пути `mixamorig1_` → `mixamorig_`)
3. Сохраняет как `Graphics/Animations/shared_animations.res` (один файл на все скины)

Запуск (выполняется **один раз** после добавления новых FBX анимаций в `raw/`):
```
& "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/build_animations.gd
```

### Структура папок для анимаций
```
res://Graphics/Animations/
  shared_animations.res   # Скомпилированные анимации (используется в игре)
  raw/                     # Исходники FBX (не связаны с игрой напрямую)
    Idle.fbx
    Running.fbx
    Jumping.fbx
```

### Порядок добавления новой анимации:
1. Положить FBX файл в `res://Graphics/Animations/raw/<name>.fbx`
2. Добавить запись `"<Name>": RAW_DIR + "<Name>.fbx"` в `build_animations.gd`
3. Запустить `build_animations.gd` — он пересоберет `shared_animations.res`
4. Запустить `rebuild_player_from_skin.gd <skin>` — он подхватит новую анимацию
5. Запустить игру для проверки

## 8. Конвейер сборки скинов (Skin pipeline)

### Как работает `rebuild_player_from_skin.gd`
Скрипт автоматизирует создание `player.tscn` из FBX модели:
1. Загружает FBX напрямую через `FBXDocument` (без Editor-импорта)
2. Извлекает встроенные текстуры из FBX, сохраняет как **WebP lossy q=95**
3. Запускает Editor (`--import`), чтобы WebP были импортированы
4. Перезагружает FBX — теперь текстуры подхватываются нормально
5. Строит `player.tscn` с моделью, анимациями, SpringArm/Camera, UI

Запуск:
```
& "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/rebuild_player_from_skin.gd <skin_name>
```

### Структура папок для нового скина
```
res://Graphics/PlayerModel/
  .gdignore                # Чтобы Editor не переимпортил raw/
  raw/
    <skin_name>.fbx        # Сырой FBX (единственный источник)
  <skin_name>/             # Создаётся скриптом
    <skin_name>_tex_0.webp # Извлечённые текстуры
    <skin_name>_tex_1.webp
    <skin_name>_tex_2.webp
    <skin_name>_tex_3.webp
    *.webp.import          # Создаются Editor при --import
```

Порядок добавления нового скина:
1. Положить FBX в `res://Graphics/PlayerModel/raw/<skin>.fbx`
2. Запустить `rebuild_player_from_skin.gd <skin>` — он сам сделает всё
3. Запустить игру для проверки

### Важные правила
* **Не копировать FBX** — скрипт загружает из `raw/` напрямую
* **Не редактировать .tscn** вручную — всё генерируется
* **Не удалять .gdignore** из `raw/` — иначе Godot расплодит PNG мусор при импорте FBX
* Если нужно принудительно перестроить скин — удалить папку `<skin_name>/` и перезапустить скрипт

## 9. Конвейер сборки пропов (Prop pipeline)

### Как работает `build_env_prop.gd`
Скрипт конвертирует baked glTF (из `optimize_triangles.py`) в компактный `.tscn` префаб пропа:
1. Загружает glTF через `GLTFDocument`
2. Читает `images` из glTF JSON, для каждой текстуры вызывает `load(webp_path)` — получает `CompressedTexture2D` (если есть `.import`) или `ImageTexture` (если нет)
3. Заменяет текстуры в материалах на загруженные — теперь у них есть `resource_path`
4. `ResourceSaver.save(mesh)` → текстуры сохраняются как внешние ссылки, не встраиваются
5. Создаёт `StaticBody3D` + `CollisionShape3D` + Graphics, сохраняет `.tscn`

**Ключевая идея:** без `--import`. В Godot 4.8 `load("file.webp")` БЕЗ `.import` падает
«No loader found» (png работает) — поэтому `build_env_prop.gd` грузит текстуры через
`Image.load_from_file(globalize_path)` + `generate_mipmaps()` + `ImageTexture.create_from_image`.
Сырая картинка без мипмапов даёт пиксельную рябь в 3D — генерация мипмапов обязательна.
`ResourceSaver` сохраняет меш с внешними ссылками на текстуры — префаб компактный (KB вместо MB).

### Грабли проп-пайплайна (все пойманы на практике)
* **bin-файл НЕ переименовывать**: gltf ссылается на буфер ПО ИМЕНИ файла в `buffers[0].uri`;
  переименовал bin → «no nodes» каскадом. Нужно другое имя — правь uri в gltf или дублируй.
* **«:» в имени файла запрещено**: Windows превращает хвост в NTFS Alternate Data Stream —
  файл обрезается/теряется (ловили на именах планов). Замена — «—».
* **Порядок «новый проп»:**optimize → **check_polycount.gd (обязательный гейт)** →
  build_env_prop → render_prop_check (посмотреть PNG самому) → build_main_arena → смоук.
  Нормы полигонажа: фон 50–300 трис, средний 300–1500, хиро 1000–5000 (AAA до 10K с нормал-бейком).
* **MultiMesh-скаттер не коллизится сам по себе** (ProceduralArena): один StaticBody3D на
  группу + per-instance CylinderShape3D из AABB пропа. Без него юзер ходит сквозь деревья/камни.
* **AABB origin в центре меша** (origin не в подошве) → скаттер обязан поднимать инстанс за
  низ AABB (`-minf(aabb.position.y, 0)`) минус 10% высоты на врытие — иначе пропы утонут,
  тем глубже, чем больше масштаб.

### Запуск
```
& "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/build_env_prop.gd <prop_name>
```

### Структура папок
```
res://Graphics/Environment/Props/
  <prop_name>/
    <prop_name>_4k_baked.gltf   # Выход optimize_triangles.py
    <prop_name>_4k_baked.bin
    <texture>.webp              # Текстуры (из glTF или отдельно)
    <texture>.webp.import       # Создаются Editor при --import (опционально)
    <prop_name>_mesh_0.res      # Меш с внешними текстурными ссылками (маленький)
    <prop_name>_mesh_1.res      # Для multi-mesh пропов
    <prop_name>.tscn            # Готовый префаб
```

### Порядок добавления нового пропа
1. Положить baked glTF в `res://Graphics/Environment/Props/<prop_name>/` (через `optimize_triangles.py`)
2. Запустить `build_env_prop.gd <prop_name>`
3. Добавить запись в `build_main_arena.gd`
4. Запустить `build_main_arena.gd` для обновления главной сцены
5. Запустить игру для проверки

### Про `--import` (актуально 19.11.26)
* `--import` безопасен, пока ВСЕ `raw/` папки защищены `.gdignore` (Editor их не видит;
  без защиты сканирование = 15-30 минут).
* v2-путь (ORM-материалы) ТРЕБУЕТ `.import`-флоу до build_env_prop — см. §6.5.
* Если `.import` нет — `load()` вернёт pathless-фолбэк, и ResourceSaver ВКОМПЫВАЕТ
  текстуры в .res (ель 25–38 МБ/меш) — не допускать, править флоу, а не лечить вес.

## 10. Живая очередь задач (ССОТ): tasks/QUEUE.md
* Единый список текущих задач проекта — `tasks/QUEUE.md`. Любая одобренная юзером
  в чате задача → СРАЗУ запись в QUEUE.md, потом код. Не одобренное — в раздел
  «ЖДЁТ ОДОБРЕНИЯ», код не писать (шлюз coding_modes.md).
* Порядок работы: сверху вниз — лёгкие/быстрые (или базовые, от которых зависят
  другие) первыми; независимые можно параллелить сабагентом.
* Сделанное из QUEUE.md УДАЛЯЕТСЯ сразу (факт «выполнено» остаётся в handoff
  сессии и коммитах) — список не должен забивать контекст.
* Автопоток: если активной работы нет — сам бери верхнюю одобренную задачу из
  QUEUE.md и делай без простоев, не дожидаясь команды юзера.

## 11. МЫШЬ И UI — ССОТ: docs/ui_input_rules.md
* Захват мыши (CAPTURED) — ровно два легальных места: клик по пустому миру
  (`PlayerController._unhandled_input`) и ЗАКРЫТИЕ любого окна UI (авто-возврат
  курсора в игру — вердикт юзера 19.11.26). Открытие UI → VISIBLE. Блокировка
  захвата при открытом UI — флаг в `_gui_blocks_capture()`, страховка-гард
  `_process` в самом окне. Чек-лист нового меню и история регрессий —
  в `docs/ui_input_rules.md`. Нарушать = снова ловить «мышь не фокусится».