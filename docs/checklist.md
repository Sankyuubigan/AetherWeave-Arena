# Чек-лист проверки игры (ССОТ)

Единственный источник истины по списку «что сделано и ждёт вердикта юзера».
Система живёт в админке (`admin/`), к игре не подключена.

## 1. Где что лежит

| Слой | Файл | Роль |
|---|---|---|
| Данные | `admin/checklist.json` | Список пунктов (committed, как `candidates.json`) |
| Код данных | `admin/checklist_store.py` | load/save/validate/add/set_done/done_all/remove/prune |
| HTTP | `admin/checklist_api.py` | `/checklist/api/*`, вызывается из `admin/server.py` |
| UI | `admin/viewer_checklist.html` | Страница «✅ Проверка» + карточка в хабе со счётчиком |
| CLI | `admin/checklist_cli.py` | Путь агента: add/list/done/remove/prune |
| Гейты | `admin/checklist_selftest.py`, `admin/checklist_e2e.py` | store+CLI; живой сервер + HTTP |

**Правило SSOT:** писать в `admin/checklist.json` можно ТОЛЬКО через
`checklist_store.py` (HTTP-API или CLI). Правка JSON руками запрещена — теряются
валидация, атомарность записи и уникальность id.

## 2. Схема данных

```json
{"version": 1,
 "items": [{"id": "8 hex", "title": "…", "body": "markdown-lite",
            "date": "ДД.ММ.ГГ", "kind": "check|decision",
            "status": "pending|done", "done_at": "ISO|null"}]}
```

* `id` — 8 hex, генерируется store; CLI/API принимают однозначный префикс.
* `title` ≤ 200 симв., непустой. `date` ≤ 12 симв. (группировка карточек в UI;
  пустая = «без даты», показывается последней).
* `kind`: `check` — «сделано, проверь в игре» (кнопка «✅ Проверено»);
  `decision` — нужно РЕШЕНИЕ юзера (кнопка «✅ Решено», синяя полоса).
* `body` — markdown-lite: `**жирный**`, `` `код` ``, `[текст](url)`, переносы строк,
  списки «- ». Таблицы/картинки не поддерживаются (показываются сырым текстом).
* Порядок массива = порядок показа; новые пункты вставляются в НАЧАЛО.
  UI группирует по `date`, свежие даты сверху.
* Путь переопределяется env `CHECKLIST_PATH` (тесты/e2e — временный файл).

## 3. HTTP API (порт админки, по умолчанию 8181)

```
GET  /checklist/api/list                -> {ok, items, counts:{pending,done}, file}
POST /checklist/api/done      {id}      -> {ok, item, counts}
POST /checklist/api/undo      {id}      -> {ok, item, counts}
POST /checklist/api/done_all  {}        -> {ok, changed, counts}
POST /checklist/api/remove    {id}      -> {ok, item, counts}
POST /checklist/api/prune     {}        -> {ok, removed, counts}
```

Ошибки данных/JSON → `{ok:false, error}` + код 400; неизвестный маршрут → 404.

## 4. CLI (единственный путь агента)

```
python -I admin/checklist_cli.py add --title "…" [--body "…" | --body-file F]
                                   [--kind check|decision] [--date ДД.ММ.ГГ]
python -I admin/checklist_cli.py list [--all]
python -I admin/checklist_cli.py done <id|префикс>… | --all
python -I admin/checklist_cli.py remove <id|префикс>…
python -I admin/checklist_cli.py prune
```

`--date` по умолчанию — сегодня. Длинные тела удобнее писать в файл `temp/*.md`
и передавать `--body-file` (кавычки/переносы в `--body` на Windows капризны).

## 5. Правила работы (обязательны для агента)

1. **Работа, ждущая проверки, СРАЗУ попадает в чек-лист** — CLI-командой `add`
   в том же ходе, где закончена работа. Не «потом», не в чат «на словах».
2. **Пункт пишется для человека:** заголовок — суть («СЕРДЕЧКО — ждёт плейтеста»),
   тело — что сделано + **что именно нажать/посмотреть** в игре.
3. **В начале сессии — `prune`**: удалить отмеченные юзером пункты; факт
   «проверено юзером» зафиксировать в handoff сессии (список не архив).
4. **При каждом запуске игры** — напоминание юзеру: «📋 Чек-лист:
   `admin\start_admin.bat` → ✅ Проверка (N)».
5. **Не дублировать список в md/чате.** `tasks/QUEUE.md` — только планы.
6. Вердикт юзера «не ок» → пункт НЕ удаляется: агент чинит и обновляет тело
   (или `remove` + новый `add`, если суть изменилась).

## 6. Гейты (прогонять после правок системы)

```
python -I admin/checklist_selftest.py    # store + CLI, без сервера (26 проверок)
python -I admin/checklist_e2e.py         # живой сервер на свободном порту + все маршруты
```

Оба EXIT 0 = PASS. E2E берёт временный файл (`temp/`) и свободный порт 8199+ —
запущенную админку юзера на 8181 и боевой `admin/checklist.json` не трогает.

## 7. Реестр ошибок (поймано на практике)

* **cp1251-консоль Windows:** любой `print` с «→», «—», эмодзи падает
  `UnicodeEncodeError`. В CLI/selftest/e2e обязателен
  `sys.stdout.reconfigure(encoding="utf-8", errors="replace")`.
* **`python -I` в 3.12** (= `-E -P -s`) не кладёт папку скрипта в `sys.path` —
  модули-соседи импортируются только после
  `sys.path.insert(0, dirname(abspath(__file__)))`. `server.py` запускается
  батником БЕЗ `-I`, поэтому там обычный импорт.
* **Перезапись `textContent` контейнера** стирает вложенные элементы: заголовок
  «Проверено (N)» со `<span id="done_n">` ломался на следующем рендере
  («Cannot set properties of null»). Стрелку/счётчик менять только в своих span.
* **IAB-браузер (агент):** Playwright-клик по кнопкам этой страницы таймаутится
  при живом элементе (квирк бэкенда). Проверка UI — `evaluate(() => btn.click())`
  + скриншот; не тратить раунды на повторные locator-клики.
