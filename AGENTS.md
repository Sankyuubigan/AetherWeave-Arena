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
- **REMESH (VOXEL)** — для одиночных больших мешей (boulder 66K→13.5K): `--remesh`. Voxel Remesh + Smart UV Project + Normal Bake. Лучшее качество на одиночных мешах.
- **DECIMATE (Collapse + delimit)** — для мульти-мешей (rock_moss 63K→15K, 6 объектов): режим по умолчанию. Single-pass с `delimit = {'NORMAL', 'UV', 'SEAM', 'SHARP'}`.
- **Multi-pass** (устарел): итеративные проходы — не нужны.

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

**Ключевая идея:** без `--import`. `load("file.webp")` в Godot 4 возвращает `ImageTexture` даже без `.import` файла. `ResourceSaver` видит `resource_path` и сохраняет компактно.

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

### Запрет на `--import` (важно)
* `--import` на весь проект сканирует все папки, включая `raw/` с тысячами файлов → 15-30 минут
* Все `raw/` папки защищены `.gdignore` — Editor их не видит
* `build_env_prop.gd` не требует `--import` вообще — использует runtime `load()` для WebP
* Если текстуры уже имеют `.import` файлы (были импортированы ранее), `load()` вернёт `CompressedTexture2D` (лучше)
* Если `.import` нет — `load()` вернёт `ImageTexture` (тоже работает, чуть дольше загрузка)