# Локальная оффлайн-библиотека Mixamo (ССОТ)

**Статус:** библиотека скачана полностью (9.0 ГБ, 0 ошибок), Adobe/Mixamo-сайт больше не нужен.
**Обновлено:** 25.11.26.

Это единственный источник правды по локальной библиотеке Mixamo. Раздел про
сторонние источники в `docs/asset_sources.md` §4 ссылается сюда.

---

## 1. Что это и зачем

Оффлайн-копия **всех 2 317 движущихся анимаций Mixamo** и **всех 114 персонажей
Mixamo** (скины), скачанная с открытых HF-датасетов. Рядом лежат:

- **готовые VLM-описания каждого движения** (что реально происходит в клипе, 7–19
  слов) — искать анимацию можно **по смыслу**, а не по кривым именам Mixamo;
- **MP4-превью каждого клипа** (512×512, 30 fps, Y-Bot; в датасете 4 ракурса,
  локально лежат 2 — фронт `v000` и профиль `v002`) — клип можно **посмотреть
  глазами** через `agent-tools vision` до того, как тащить его в проект;
- **T-pose картинки-сетки 2×2 всех 114 скинов** — скин тоже можно подобрать глазами.

Итог: цикл «нашёл → посмотрел → взял» занимает секунды и не требует ни логина на
Adobe, ни капчи, ни интернета.

## 2. Где лежит

```
D:\Projects\3d_game\Graphics\mixamo-lib\      <- внутри проекта, в .gitignore
```

Библиотека лежит **внутри проекта**, но целиком в `.gitignore`
(`/Graphics/mixamo-lib/`) — 9 ГБ ассетов в git не коммитятся. В папке стоит
`.gdignore`, поэтому Godot НЕ импортирует 2 317 FBX и 114 GLB (иначе Editor
уйдёт в многочасовой импорт).

Путь можно переопределить переменной окружения `MIXAMO_LIB_DIR`.

### Структура

| Путь | Что | Кол-во |
| :--- | :--- | :---: |
| `fbx/<Clip>.fbx` | анимации, скелет 65 костей `mixamorig:`, 30 fps, без меша | 2 317 |
| `previews/<Clip>/v000.mp4` | превью **фронт** | 2 317 |
| `previews/<Clip>/v002.mp4` | превью **левый профиль** | 2 317 |
| `character_refined/<Name>.fbx` | 114 скинов в T-pose, **bone-неймспейс починен** | 114 |
| `character_refined_glb/<Name>.glb` | те же скины в `.glb` (для Godot/Blender) | 114 |
| `character_tpose/<Name>.png` | сетка 2×2 (спереди/сзади/слева/справа) | 114 |
| `_meta/` | JSON-индексы, captions, `filtered_clips.txt` | ~1.3 МБ |
| `_tools/mixamo_search.py` | оффлайн-поиск по библиотеке | 1 |

`_meta/` — что внутри:

- `animation_motion_prompts.json` — имя Mixamo + описание на каждый клип;
- `animation_motion_frames.json` — кол-во кадров (длительность = кадры / 30);
- `motion_captions.json` / `_generic.json` / `_detail.json` — VLM-описания движения
  (1 предложение / ~6 слов / пошаговое 7–19 слов);
- `filtered_clips.txt` — 7 бракованных клипов (персонаж висит в воздухе / «едет»
  корнем);
- `characters.csv` — 114 скинов: `bone_count`, `covers_animation_rig`;
- `animation_bones.json`, `character_bones.json`, `character_nonstandard_rig.txt`.

## 3. Как искать анимацию

### 3.1 Основной способ — смысловой поиск

```bash
python -I D:/Projects/3d_game/Graphics/mixamo-lib/_tools/mixamo_search.py "jump forward overhead slash" --max-sec 3.5 --limit 8
```

Что делает: ищет по VLM-описаниям (вес x3), общим captions (x2.5), описанию Mixamo
(x2) и имени файла (x1.5), расширяет запрос геймдев-синонимами
(`slash→swing/strike/cleave`, `cast→spell/magic`, `dodge→evade/roll`, …),
скрывает 7 битых клипов и печатает для каждого кандидата:

```
19.05  Forward_Jump    2.47s ( 74f)
       An object crouches with its arms swung back, springs forward swinging them ahead, then lands and stands.
       fbx: D:\Projects\3d_game\Graphics\mixamo-lib\fbx\Forward_Jump.fbx
       mp4: ...\previews\Forward_Jump\v000.mp4 | ...\v002.mp4
```

Флаги:

| Флаг | Смысл |
| :--- | :--- |
| `--limit N` | сколько кандидатов (дефолт 10) |
| `--min-sec F` / `--max-sec F` | фильтр по длительности (кадры / 30) |
| `--include-flagged` | показать 7 бракованных клипов |
| `--json` | машинный вывод (stem, seconds, frames, caption, пути) |

**Правило:** сначала 1–3 слова запроса, потом уже уточнять. Длинный запрос
размывает веса.

### 3.2 Быстрый поиск по имени (без скрипта)

```bash
ls D:/Projects/3d_game/Graphics/mixamo-lib/fbx | grep -i "sword"
grep -i "sword" D:/Projects/3d_game/Graphics/mixamo-lib/_meta/animation_motion_prompts.json | head -20
```

### 3.3 Поиск по смыслу без скрипта (grep по captions)

```bash
grep -i -C0 "jump" D:/Projects/3d_game/Graphics/mixamo-lib/_meta/motion_captions_detail.json | head -40
```

## 4. Проверка глазами через `agent-tools vision` (обязательный шаг)

Найденные кандидаты **нельзя брать вслепую** — имя Mixamo врёт, а caption может
не заметить разворот/прыжок. Смотрим MP4-превью:

```bash
D:/Projects/cross-app-plugins/bin/agent-tools.exe vision \
  --video "D:/Projects/3d_game/Graphics/mixamo-lib/previews/Forward_Jump/v000.mp4" \
  --prompt "Опиши точно траекторию движения: есть ли прыжок/разворот, на какой секунде пик удара/каста, подходит ли для скилла 'рывок с ударом сверху'?"
```

- `--video` — 6 равномерных кадров, таймкоды уходят в промт (timeout bash-тула
  **300000** мс: живой инференс + загрузка модели).
- Важен выпад вперёд/назад — добавь второй ракурс `--video .../v002.mp4`.
- Нужна поза/меш — `--image character_tpose/<Name>.png`.
- Промт с кириллицей надёжнее передавать через `--prompt-file F` или stdin
  (`--prompt -`), кавычки в `--prompt "..."` на Windows ломаются.
- Коды: `0` ответ · `2` нет медиа · `3` бэкенд/таймаут · `4` внутренняя.

**Что снимать через vision:** момент пика удара / выпуска спелла (секунды) — он
идёт в привязку хитбокса и VFX в коде скилла.

## 5. Как забрать клип в проект

1. Выбрать клип (`mixamo_search.py` → `vision`).
2. Скопировать FBX в `res://Graphics/Animations/raw/<Name>.fbx`
   (имя — латиница, без пробелов и `:`).
3. Добавить запись `"<Name>": RAW_DIR + "<Name>.fbx"` в `Generators/build_animations.gd`.
4. Пересобрать `shared_animations.res`:
   ```bash
   & "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/build_animations.gd
   ```
5. Пересобрать скин: `rebuild_player_from_skin.gd <skin>` (AGENTS §8).
6. Запустить игру, проверить.

Файлы в `raw/` под `.gdignore` — Editor их не импортирует (AGENTS §7).

### Про root motion

Клипы в `fbx/` экспортированы **с root motion** (переносится `mixamorig:Hips`).
Если скиллу нужен `in-place` — обнулить смещение Hips по X/Z при импорте.
Обратное восстановить невозможно, поэтому брать «с движением» безопаснее.

## 6. Скины (114 персонажей)

- `character_refined/` — T-pose с мешем и текстурами, **имена костей уже починенные**
  (на Mixamo у 27 персонажей неймспейс `mixamorig1:` — анимации на них молча
  ломаются; здесь это вылечено).
- **97 из 114 полностью покрывают 65 костей** анимаций (`covers_animation_rig=true`
  в `characters.csv`) — любая из 2 317 анимаций садится **без ретаргетинга**.
- `character_refined_glb/` — то же в `.glb` (Godot/Blender).
- `character_tpose/<Name>.png` — сетка 2×2, подбор скина глазами:
  ```bash
  D:/Projects/cross-app-plugins/bin/agent-tools.exe vision --image "D:/Projects/3d_game/Graphics/mixamo-lib/character_tpose/Knight_D_Pelegrini.png" \
    --prompt "Опиши персонажа для подбора ассета: архетип, одежда/броня, стиль, цвета. 1-2 предложения."
  ```

## 7. Грабли и ограничения

- **7 битых клипов** (`filtered_clips.txt`): `Falling_3`, `Falling_Into_Pool`,
  `Falling_Into_Pool_2`, `Flying`, `Being_Carried`, `Being_Carried_2` — персонаж
  висит в воздухе или едет корнем. Скрыты по умолчанию, не брать без нужды.
- **30 fps**, скелет 65 костей с префиксом `mixamorig:` — в `build_animations.gd`
  уже есть фикс `mixamorig1_` → `mixamorig_`.
- **Лицензия:** FBX и рендеры — под условиями Adobe Mixamo (бесплатно для игр,
  нельзя перепродавать/раздавать сырые паки отдельно). Описания `UniML3D` — `ODC-BY 1.0`.
- **Не коммитить** библиотеку в git: ~10 ГБ.

## 8. Обновление / докачка

Скрипт идемпотентный (существующие файлы >0 байт пропускаются), качает curl-ом
в 16 потоков:

```bash
python -I "D:/Projects/3d_game/tasks/261125_0121-1883b78e/download_mixamo.py" --jobs 16
```

Флаги: `--limit N` (быстрый смоук), `--only-meta` (только индексы).
Источники: `Linzhan/Mixamo-Animations-Characters` + `Linzhan/UniML3D` (Hugging Face,
без логина). Качается всё, **кроме 3 папок-дубликатов** `animation/`, `character/`,
`animation_motion_ybot/` (~18 ГБ мусора).

**Про rate limit HF:** анонимный IP режется после ~5 ГБ за burst — HF отдаёт
`429 Too Many Requests` телом на 189 байт. Скрипт это ловит (проверяет первые
200 байт ответа, а не только код curl) и уходит в backoff 120 с, докачка
идемпотентна. Если лимит держится долго — работаем на уже скачанном (первые
~1 000 клипов есть всегда) либо качаем с токеном `HF_TOKEN`.

## 9. Чек-лист «нужна анимация под скилл»

- [ ] Разложить идею скилла на 2–3 английских описания движения.
- [ ] `mixamo_search.py "<запрос>" --max-sec <лимит> --limit 8`.
- [ ] Топ-3 проверить `agent-tools vision --video v000.mp4` (+ `v002.mp4` для выпада).
- [ ] Выбрать, снять таймкод пика удара/каста.
- [ ] `cp` FBX → `Graphics/Animations/raw/`, запись в `build_animations.gd`.
- [ ] Пересборка `shared_animations.res` → `rebuild_player_from_skin.gd` → смоук.
- [ ] Хитбокс/VFX привязать к снятому таймкоду.