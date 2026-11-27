"""E2E чек-листа (шаг 1 PRP): живой сервер на тест-порту + все HTTP-маршруты.

Поднимает admin/server.py на ADMIN_PORT (по умолчанию 8199) с временным
CHECKLIST_PATH в temp/ — боевые admin/checklist.json и админку юзера на 8181
не трогает. EXIT 0 = PASS.

  python -I admin/checklist_e2e.py
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

PASS = 0
FAIL = 0


def ck(cond, label):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS  %s" % label)
    else:
        FAIL += 1
        print("  FAIL  %s" % label)


def http(port, method, path, body=None):
    """(код, json|None, сырой текст). Соединение закрываем всегда."""
    url = "http://127.0.0.1:%d%s" % (port, path)
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read().decode("utf-8", "replace")
            code = r.status
    except urllib.error.HTTPError as ex:
        raw = ex.read().decode("utf-8", "replace")
        code = ex.code
    try:
        js = json.loads(raw)
    except ValueError:
        js = None
    return code, js, raw


def free_port(start=8199, tries=30):
    for p in range(start, start + tries):
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    raise RuntimeError("нет свободного порта в диапазоне %d..%d" % (start, start + tries))


def wait_up(port, seconds=20.0):
    end = time.time() + seconds
    while time.time() < end:
        try:
            code, js, _ = http(port, "GET", "/checklist/api/list")
            if code == 200 and js and js.get("ok"):
                return True
        except OSError:
            pass
        time.sleep(0.25)
    return False


def main():
    tmpdir = tempfile.mkdtemp(prefix="checklist_e2e_", dir=os.path.join(ROOT, "temp"))
    path = os.path.join(tmpdir, "checklist.json")
    port = free_port()
    env = dict(os.environ)
    env["ADMIN_PORT"] = str(port)
    env["CHECKLIST_PATH"] = path
    env["PYTHONIOENCODING"] = "utf-8"

    print("=== E2E: чек-лист HTTP (порт %d) ===" % port)
    print("  файл: %s" % path)

    log = open(os.path.join(tmpdir, "server.log"), "w", encoding="utf-8")
    proc = subprocess.Popen([sys.executable, os.path.join(HERE, "server.py")],
                            cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        ck(wait_up(port), "сервер поднялся и отвечает на /checklist/api/list")

        # --- пустой список
        code, js, _ = http(port, "GET", "/checklist/api/list")
        ck(code == 200 and js["ok"] and js["items"] == [], "пустой список")
        ck(js["counts"] == {"pending": 0, "done": 0}, "counts 0/0")
        ck(js["file"].replace("\\", "/").endswith("checklist.json"), "API отдаёт путь файла")

        # --- наполнение через CLI (тот же файл через env) — путь агента
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "checklist_cli.py"),
                            "add", "--title", "Первый", "--date", "27.11.26"],
                           capture_output=True, text=True, encoding="utf-8", env=env)
        ck(r.returncode == 0, "CLI add в тот же файл (%s)" % r.stdout.strip()[:50])
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "checklist_cli.py"),
                        "add", "--title", "Второй", "--kind", "decision"],
                       capture_output=True, text=True, encoding="utf-8", env=env)

        code, js, _ = http(port, "GET", "/checklist/api/list")
        ck(code == 200 and len(js["items"]) == 2, "сервер видит 2 пункта")
        ck(js["items"][0]["title"] == "Второй", "порядок: новые сверху")
        ck(js["counts"]["pending"] == 2, "counts pending=2")
        first_id = js["items"][0]["id"]
        second_id = js["items"][1]["id"]

        # --- done / undo
        code, js, _ = http(port, "POST", "/checklist/api/done", {"id": first_id})
        ck(code == 200 and js["ok"] and js["item"]["status"] == "done", "POST done")
        ck(js["counts"] == {"pending": 1, "done": 1}, "counts 1/1 после done")
        code, js, _ = http(port, "POST", "/checklist/api/undo", {"id": first_id})
        ck(code == 200 and js["ok"] and js["item"]["status"] == "pending", "POST undo")
        ck(js["item"]["done_at"] is None, "undo снял done_at")

        # --- ошибки
        code, js, _ = http(port, "POST", "/checklist/api/done", {"id": "нет-такого"})
        ck(code == 400 and js and js["ok"] is False and js["error"], "неизвестный id → 400 + error")
        req = urllib.request.Request("http://127.0.0.1:%d/checklist/api/done" % port,
                                     data=b"\x7b\xd0\xb1\xd0\xb8\xd1\x82\xd1\x8b\xd0\xb9",
                                     method="POST",
                                     headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=10)
            ck(False, "битый JSON → 400")
        except urllib.error.HTTPError as ex:
            ck(ex.code == 400, "битый JSON → 400")
        code, js, _ = http(port, "POST", "/checklist/api/nope", {})
        ck(code == 404 and js["ok"] is False, "неизвестный маршрут → 404")

        # --- done_all / prune
        code, js, _ = http(port, "POST", "/checklist/api/done_all", {})
        ck(code == 200 and js["changed"] == 2, "done_all отметил 2")
        code, js, _ = http(port, "GET", "/checklist/api/list")
        ck(js["counts"] == {"pending": 0, "done": 2}, "после done_all pending=0")
        code, js, _ = http(port, "POST", "/checklist/api/prune", {})
        ck(code == 200 and js["removed"] == 2, "prune удалил 2")
        code, js, _ = http(port, "GET", "/checklist/api/list")
        ck(js["items"] == [], "после prune список пуст")

        # --- статика: страница отдаётся, чужие маршруты живы
        code, _, raw = http(port, "GET", "/admin/viewer_hub.html")
        ck(code == 200 and "Админка проекта" in raw, "хаб отдаётся (статика не сломана)")
        code, _, _ = http(port, "GET", "/skills/api/data")
        ck(code == 200, "старый маршрут /skills/api/data жив")
        code, _, raw = http(port, "GET", "/checklist/api/list?x=1")
        ck(code == 200, "query-строка не ломает маршрут")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        log.close()

    # лог сервера: ни одного трейсбека
    try:
        with open(os.path.join(tmpdir, "server.log"), "r", encoding="utf-8") as f:
            srv_log = f.read()
    except OSError:
        srv_log = ""
    ck("Traceback" not in srv_log, "в логе сервера нет трейсбеков")
    shutil.rmtree(tmpdir, ignore_errors=True)

    print("=== ИТОГ: %d PASS / %d FAIL ===" % (PASS, FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
