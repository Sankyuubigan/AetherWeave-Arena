"""Чек-лист проверки игры — SSOT-хранилище (admin/checklist.json).

ЕДИНСТВЕННЫЙ код доступа к списку проверки: HTTP-API (checklist_api.py) и CLI
(checklist_cli.py) работают только через этот модуль. Править JSON руками
запрещено (docs/checklist.md) — иначе теряются валидация и атомарность.

Схема файла:
    {"version": 1,
     "items": [{"id", "title", "body", "date", "kind", "status", "done_at"}]}

Путь: env CHECKLIST_PATH (абсолютный или относительно корня проекта; для
тестов/e2e), иначе admin/checklist.json. Запись атомарная (tmp + os.replace),
мутации — под threading.Lock (сервер многопоточный).
"""
import json
import os
import tempfile
import threading
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATH = os.path.join(ROOT, "admin", "checklist.json")

KINDS = ("check", "decision")
STATUSES = ("pending", "done")
TITLE_MAX = 200
DATE_MAX = 12

_lock = threading.Lock()


class ChecklistError(Exception):
    """Ошибка данных/операции чек-листа (текст — для UI/CLI/лога)."""


def path() -> str:
    """Активный путь файла: env CHECKLIST_PATH или admin/checklist.json."""
    p = os.environ.get("CHECKLIST_PATH", "").strip()
    if not p:
        return DEFAULT_PATH
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def _empty() -> dict:
    return {"version": 1, "items": []}


def _validate_item(it, idx: int) -> dict:
    """Нормализует и проверяет один пункт; ChecklistError при нарушении схемы."""
    if not isinstance(it, dict):
        raise ChecklistError("пункт #%d: не словарь" % idx)
    iid = str(it.get("id", "")).strip()
    if not iid:
        raise ChecklistError("пункт #%d: пустой id" % idx)
    title = str(it.get("title", "")).strip()
    if not title:
        raise ChecklistError("пункт '%s': пустой title" % iid)
    if len(title) > TITLE_MAX:
        raise ChecklistError("пункт '%s': title длиннее %d симв." % (iid, TITLE_MAX))
    kind = str(it.get("kind", "check") or "check")
    if kind not in KINDS:
        raise ChecklistError("пункт '%s': kind '%s' не из %s" % (iid, kind, KINDS))
    status = str(it.get("status", "pending") or "pending")
    if status not in STATUSES:
        raise ChecklistError("пункт '%s': status '%s' не из %s" % (iid, status, STATUSES))
    date = str(it.get("date", "") or "")
    if len(date) > DATE_MAX:
        raise ChecklistError("пункт '%s': date длиннее %d симв." % (iid, DATE_MAX))
    done_at = it.get("done_at")
    return {
        "id": iid,
        "title": title,
        "body": str(it.get("body", "") or ""),
        "date": date,
        "kind": kind,
        "status": status,
        "done_at": None if done_at is None else str(done_at),
    }


def validate(data) -> None:
    """Проверяет и НОРМАЛИЗУЕТ data на месте (items — список словарей схемы)."""
    if not isinstance(data, dict):
        raise ChecklistError("корень: не словарь")
    items = data.get("items")
    if not isinstance(items, list):
        raise ChecklistError("items: не массив")
    out = []
    ids = set()
    for i, it in enumerate(items):
        v = _validate_item(it, i)
        if v["id"] in ids:
            raise ChecklistError("дубликат id '%s'" % v["id"])
        ids.add(v["id"])
        out.append(v)
    data["version"] = 1
    data["items"] = out


def load() -> dict:
    """Читает и валидирует файл. Нет файла → пустой список (не ошибка)."""
    p = path()
    if not os.path.exists(p):
        return _empty()
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as ex:
        raise ChecklistError("файл чек-листа не читается (%s): %s" % (ex, p))
    validate(data)
    return data


def _save_unlocked(data: dict) -> None:
    """Атомарная запись (tmp в той же папке + os.replace). Вызывать под _lock."""
    validate(data)
    p = path()
    d = os.path.dirname(p)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".checklist_", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, p)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def save(data: dict) -> None:
    with _lock:
        _save_unlocked(data)


def counts(data: dict = None) -> dict:
    """{pending, done} по данным (или читает файл)."""
    d = load() if data is None else data
    pend = sum(1 for it in d["items"] if it["status"] == "pending")
    return {"pending": pend, "done": len(d["items"]) - pend}


def _new_id(items) -> str:
    """Короткий случайный id (8 hex) — удобно копировать из CLI/UI и набирать
    префиксом. Коллизия перегенерируется (практически не случается)."""
    ids = {it["id"] for it in items}
    while True:
        cand = os.urandom(4).hex()
        if cand not in ids:
            return cand


def _find(items, key: str) -> dict:
    """Пункт по полному id или однозначному префиксу (CLI-удобство)."""
    key = str(key or "").strip()
    if not key:
        raise ChecklistError("пустой id")
    for it in items:
        if it["id"] == key:
            return it
    pref = [it for it in items if it["id"].startswith(key)]
    if len(pref) == 1:
        return pref[0]
    if len(pref) > 1:
        raise ChecklistError("id '%s' неоднозначен (%d совпадений)" % (key, len(pref)))
    raise ChecklistError("пункт не найден: %s" % key)


def add(title: str, body: str = "", kind: str = "check", date: str = "") -> dict:
    """Новый пункт в НАЧАЛО списка. Возвращает созданную запись."""
    item = {
        "id": "",
        "title": str(title or "").strip(),
        "body": str(body or ""),
        "date": str(date or ""),
        "kind": kind or "check",
        "status": "pending",
        "done_at": None,
    }
    if not item["title"]:
        raise ChecklistError("title не может быть пустым")
    with _lock:
        data = load()
        item["id"] = _new_id(data["items"])
        _validate_item(item, 0)  # полная проверка до записи
        data["items"].insert(0, item)
        _save_unlocked(data)
    return item


def set_done(item_id: str, done: bool = True) -> dict:
    """Ставит/снимает отметку «Проверено» (done_at пишется только при done)."""
    with _lock:
        data = load()
        it = _find(data["items"], item_id)
        it["status"] = "done" if done else "pending"
        it["done_at"] = datetime.now().isoformat(timespec="seconds") if done else None
        _save_unlocked(data)
        return dict(it)


def done_all() -> int:
    """Отмечает ВСЕ ожидающие пункты проверенными. Возвращает число изменённых."""
    with _lock:
        data = load()
        stamp = datetime.now().isoformat(timespec="seconds")
        changed = 0
        for it in data["items"]:
            if it["status"] == "pending":
                it["status"] = "done"
                it["done_at"] = stamp
                changed += 1
        if changed:
            _save_unlocked(data)
        return changed


def remove(item_id: str) -> dict:
    """Удаляет пункт (возвращает удалённую запись)."""
    with _lock:
        data = load()
        it = _find(data["items"], item_id)
        data["items"] = [x for x in data["items"] if x["id"] != it["id"]]
        _save_unlocked(data)
        return dict(it)


def prune() -> int:
    """Удаляет ВСЕ отмеченные пункты (чистка в начале сессии агентом)."""
    with _lock:
        data = load()
        kept = [it for it in data["items"] if it["status"] != "done"]
        removed = len(data["items"]) - len(kept)
        if removed:
            data["items"] = kept
            _save_unlocked(data)
        return removed
