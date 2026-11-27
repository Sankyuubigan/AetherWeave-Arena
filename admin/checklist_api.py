"""HTTP-API чек-листа (шаг 1 PRP): маршруты /checklist/api/*.

Вынесено из server.py отдельным модулем (лимит 500 строк на файл).
Единственный код данных — checklist_store.py; здесь только разбор запроса
и коды ответа. Контракт:

  GET  /checklist/api/list    -> {ok, items, counts:{pending,done}, generated}
  POST /checklist/api/done    {id}     -> {ok, item}
  POST /checklist/api/undo    {id}     -> {ok, item}
  POST /checklist/api/done_all {}      -> {ok, changed}
  POST /checklist/api/remove  {id}     -> {ok, item}
  POST /checklist/api/prune   {}       -> {ok, removed}

Ошибки данных/JSON -> {ok:false, error} с кодом 400. Чужие маршруты не трогаем:
handle() возвращает False, если путь не наш — server.py идёт дальше по статике.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import checklist_store as store  # noqa: E402

PREFIX = "/checklist/api/"


def _payload(handler):
    """Тело POST как dict; ValueError при битом JSON."""
    length = int(handler.headers.get("Content-Length", 0) or 0)
    raw = handler.rfile.read(length) if length else b"{}"
    data = json.loads(raw.decode("utf-8") or "{}")
    if not isinstance(data, dict):
        raise ValueError("ожидался JSON-объект")
    return data


def handle(handler, method: str) -> bool:
    """Обрабатывает наш маршрут. True = ответ отправлен, False = не наш путь."""
    route = handler.path.split("?", 1)[0].rstrip("/")
    if not route.startswith(PREFIX.rstrip("/")):
        return False
    name = route[len(PREFIX):].strip("/")

    try:
        if method == "GET" and name == "list":
            data = store.load()
            handler._send_json({
                "ok": True,
                "items": data["items"],
                "counts": store.counts(data),
                "file": store.path(),
            })
            return True
        if method == "POST" and name in ("done", "undo", "done_all", "remove", "prune"):
            body = _payload(handler)
            if name == "done_all":
                changed = store.done_all()
                handler._send_json({"ok": True, "changed": changed,
                                    "counts": store.counts()})
                print("[admin] checklist done_all: %d" % changed)
                return True
            if name == "prune":
                removed = store.prune()
                handler._send_json({"ok": True, "removed": removed,
                                    "counts": store.counts()})
                print("[admin] checklist prune: %d" % removed)
                return True
            item_id = str(body.get("id", "")).strip()
            if name == "done":
                item = store.set_done(item_id, True)
            elif name == "undo":
                item = store.set_done(item_id, False)
            else:  # remove
                item = store.remove(item_id)
            handler._send_json({"ok": True, "item": item, "counts": store.counts()})
            print("[admin] checklist %s: %s" % (name, item["id"]))
            return True
    except store.ChecklistError as ex:
        handler._send_json({"ok": False, "error": str(ex)}, 400)
        return True
    except (ValueError, OSError) as ex:
        handler._send_json({"ok": False, "error": "битый запрос: %s" % ex}, 400)
        return True

    handler._send_json({"ok": False, "error": "нет такого маршрута: %s" % name}, 404)
    return True
