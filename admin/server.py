"""ЕДИНАЯ админка проекта (Q51, PRP tasks/q50_q51_admin_branches.md).

Один сервер на localhost:8181 (docroot = корень проекта):
  * статика: admin/ (страницы админки) + tools/ (каталоги 3D/врагов/анимаций
    отдаются БЕЗ правок viewer'ов — относительные пути сохраняются);
  * API скиллов:
      GET  /skills/api/data  -> {branches, overrides, skills, generated, error}
                                  skills = temp/skills_dump.json (регенерит
                                  start_admin.bat при каждом старте);
      POST /skills/api/save  -> валидация + запись Data/skill_branches.json.
Границы зеркалят SkillBranchDB.gd (ССОТ-правила): имя <= 32, иконка <= 8,
неизвестная ветка -> отказ сохранения. Логика скиллов через админку
неизменяема (код-ССОТ SkillDB.gd). Запуск: admin/start_admin.bat.
"""
import json
import os
import re
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_PATH = os.path.join(ROOT, "Data", "skill_branches.json")
DUMP_PATH = os.path.join(ROOT, "temp", "skills_dump.json")
NAME_MAX = 32
ICON_MAX = 8


def load_current() -> dict:
    if os.path.exists(DATA_PATH):
        try:
            with open(DATA_PATH, "r", encoding="utf-8") as f:
                d = json.load(f)
            if isinstance(d, dict):
                return d
        except (OSError, ValueError):
            pass
    return {"branches": [], "overrides": {}}


def validate(data: dict):
    """Возвращает None или строку ошибки; нормализует записи на месте."""
    branches = data.get("branches")
    if not isinstance(branches, list):
        return "branches: не массив"
    ids = set()
    for b in branches:
        if not isinstance(b, dict):
            return "ветка: не словарь"
        bid = str(b.get("id", "")).strip()
        if not re.match(r"^[a-z0-9_]+$", bid):
            return "ветка: плохой id '%s' (разрешены a-z0-9_)" % bid
        if bid in ids:
            return "ветка: дубликат id '%s'" % bid
        ids.add(bid)
        b["name"] = str(b.get("name", ""))[:NAME_MAX]
        b["icon"] = str(b.get("icon", ""))[:ICON_MAX]
        try:
            b["order"] = int(b.get("order", 100))
        except (TypeError, ValueError):
            return "ветка '%s': order не число" % bid
    misc = data.get("misc")
    if misc is not None:
        if not isinstance(misc, dict):
            return "misc: не словарь"
        data["misc"] = {"name": str(misc.get("name", ""))[:NAME_MAX],
                        "icon": str(misc.get("icon", ""))[:ICON_MAX]}
    ov = data.get("overrides")
    if not isinstance(ov, dict):
        return "overrides: не словарь"
    out = {}
    for sid, o in ov.items():
        if not isinstance(o, dict):
            return "override '%s': не словарь" % sid
        e = {}
        if "skill_name" in o:
            e["skill_name"] = str(o["skill_name"])[:NAME_MAX]
        if "icon" in o:
            e["icon"] = str(o["icon"])[:ICON_MAX]
        if "branch" in o:
            bid = str(o["branch"])
            if bid and bid not in ids:
                return "override '%s': неизвестная ветка '%s'" % (sid, bid)
            e["branch"] = bid  # '' = «Разное» — сохраняем явно, не выбрасываем
        if e:
            out[str(sid)] = e
    data["overrides"] = out
    return None


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def _send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.path = "/admin/viewer_hub.html"  # корень = хаб админки (Q51)
        if self.path.rstrip("/") == "/skills/api/data":
            cur = load_current()
            payload = {
                "branches": cur.get("branches", []),
                "overrides": cur.get("overrides", {}),
                "misc": cur.get("misc"),
                "skills": [],
                "generated": "",
                "error": None,
            }
            if os.path.exists(DUMP_PATH):
                try:
                    with open(DUMP_PATH, "r", encoding="utf-8") as f:
                        dump = json.load(f)
                    payload["skills"] = dump.get("skills", [])
                    payload["generated"] = dump.get("generated", "")
                except (OSError, ValueError) as ex:
                    payload["error"] = "Дамп битый (%s) — перезапустите start_admin.bat" % ex
            else:
                payload["error"] = (
                    "Дамп не найден — перезапустите admin\\start_admin.bat "
                    "(он регенерит temp/skills_dump.json перед стартом сервера)"
                )
            print("[admin] GET data: %d скиллов, %d веток" % (
                len(payload["skills"]), len(payload["branches"])))
            self._send_json(payload)
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.rstrip("/") != "/skills/api/save":
            self._send_json({"ok": False, "error": "нет такого маршрута"}, 404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, OSError) as ex:
            self._send_json({"ok": False, "error": "битый JSON: %s" % ex}, 400)
            return
        err = validate(data)
        if err:
            print("[admin] SAVE отказ: %s" % err)
            self._send_json({"ok": False, "error": err}, 400)
            return
        with open(DATA_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("[admin] SAVE ok: %d веток, %d оверрайдов -> Data/skill_branches.json" % (
            len(data["branches"]), len(data["overrides"])))
        self._send_json({"ok": True, "written": DATA_PATH})

    def log_request(self, code="-", size="-"):
        # Статику не спамим в консоль; API-запросы показываем. Ошибки (404 и
        # пр.) идут через log_error -> log_message без правок — не трогаем.
        try:
            if "/skills/api/" in str(self.path or ""):
                super().log_request(code, size)
        except Exception:
            pass


def main():
    port = 8181
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("[admin] ЕДИНАЯ админка: http://localhost:%d/  (docroot=%s)" % (port, ROOT))
    print("[admin] Данные скиллов: %s" % DATA_PATH)
    print("[admin] Ctrl+C — остановить сервер (окно можно закрыть).")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("[admin] остановлено.")


if __name__ == "__main__":
    main()
