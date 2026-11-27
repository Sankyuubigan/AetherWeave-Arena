"""Selftest чек-листа (шаг 0 PRP): store + CLI, БЕЗ сервера.

Гоняется на временном файле в temp/ (env CHECKLIST_PATH), боевой
admin/checklist.json не трогает. EXIT 0 = PASS.

  python -I admin/checklist_selftest.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# Консоль Windows (cp1251) не держит стрелки/эмодзи — вывод в UTF-8.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

_pass = 0
_fail = 0


def ck(cond, label):
    global _pass, _fail
    if cond:
        _pass += 1
        print("  PASS  %s" % label)
    else:
        _fail += 1
        print("  FAIL  %s" % label)


def expect_err(fn, label):
    """Проверка отказа: fn обязана бросить ChecklistError."""
    try:
        fn()
    except store.ChecklistError:
        ck(True, label)
    except Exception as ex:  # noqa: BLE001 — любой другой тип = провал гейта
        ck(False, label + " (исключение другого типа: %s)" % ex)
    else:
        ck(False, label + " (исключения не было)")


def run_cli(*args, env):
    return subprocess.run(
        [sys.executable, "-I", os.path.join(HERE, "checklist_cli.py"), *args],
        capture_output=True, text=True, encoding="utf-8", env=env,
    )


def main():
    tmpdir = tempfile.mkdtemp(prefix="checklist_selftest_", dir=os.path.join(ROOT, "temp")
                              if os.path.isdir(os.path.join(ROOT, "temp"))
                              else tempfile.gettempdir())
    path = os.path.join(tmpdir, "checklist.json")
    os.environ["CHECKLIST_PATH"] = path

    print("=== SELFTEST: чек-лист store+CLI ===")
    print("  файл: %s" % path)

    # --- пустое состояние
    d = store.load()
    ck(d == {"version": 1, "items": []}, "нет файла → пустой список (не ошибка)")
    ck(store.counts(d) == {"pending": 0, "done": 0}, "counts пустого = 0/0")

    # --- add / порядок / round-trip
    a = store.add("Пункт A", body="тело **A**", date="27.11.26")
    b = store.add("Пункт B", kind="decision")
    ck(os.path.exists(path), "файл записан после add")
    d = store.load()
    ck([x["title"] for x in d["items"]] == ["Пункт B", "Пункт A"], "новые пункты в НАЧАЛО")
    ck(d["items"][1]["body"] == "тело **A**", "body переживает round-trip")
    ck(d["items"][0]["kind"] == "decision", "kind=decision сохраняется")
    ck(all(x["status"] == "pending" for x in d["items"]), "новые = pending")
    ck(a["id"] != b["id"], "id уникальны")

    # --- валидация
    expect_err(lambda: store.add(""), "пустой title — отказ")
    bad = json.loads(json.dumps(d))
    bad["items"][0]["status"] = "maybe"
    expect_err(lambda: store.validate(bad), "плохой status — отказ")
    bad2 = json.loads(json.dumps(d))
    bad2["items"].append(dict(bad2["items"][0]))
    expect_err(lambda: store.validate(bad2), "дубликат id — отказ")
    bad3 = json.loads(json.dumps(d))
    bad3["items"][0]["kind"] = "wat"
    expect_err(lambda: store.validate(bad3), "плохой kind — отказ")

    # --- done / undo
    it = store.set_done(b["id"], True)
    ck(it["status"] == "done" and it["done_at"], "done ставит статус и done_at")
    it = store.set_done(b["id"], False)
    ck(it["status"] == "pending" and it["done_at"] is None, "undo снимает done_at")
    store.set_done(a["id"], True)
    ck(store.counts() == {"pending": 1, "done": 1}, "counts 1/1 после отметки")

    # --- префикс id
    pre = a["id"][:5]
    it = store.set_done(pre, True)
    ck(it["id"] == a["id"], "done по префиксу id")

    # --- remove / prune (состояние на входе: [C, B, A], done только A)
    store.add("Пункт C")
    n = store.prune()
    ck(n == 1 and [x["title"] for x in store.load()["items"]] == ["Пункт C", "Пункт B"],
       "prune удаляет только done (%d)" % n)
    first = store.load()["items"][0]
    store.remove(first["id"])
    ck([x["title"] for x in store.load()["items"]] == ["Пункт B"], "remove удаляет пункт")

    # --- CLI через subprocess (python -I: папка скрипта не в sys.path — проверяем, что работает)
    # Чистый лист: store-секция оставила «Пункт B», для CLI нужен предсказуемый счётчик.
    os.unlink(path)
    env = dict(os.environ)
    r = run_cli("add", "--title", "CLI пункт", "--body", "из CLI", "--kind", "decision",
                "--date", "01.01.27", env=env)
    ck(r.returncode == 0 and "OK" in r.stdout, "CLI add OK (%s)" % r.stdout.strip()[:60])
    r = run_cli("list", env=env)
    ck(r.returncode == 0 and "CLI пункт" in r.stdout and "К ПРОВЕРКЕ (1)" in r.stdout,
       "CLI list показывает пункт")
    cid = store.load()["items"][0]["id"]
    r = run_cli("done", cid[:6], env=env)
    ck(r.returncode == 0 and store.load()["items"][0]["status"] == "done", "CLI done по префиксу")
    r = run_cli("list", env=env)
    ck("К ПРОВЕРКЕ (0)" in r.stdout, "CLI list: done скрыт без --all")
    r = run_cli("list", "--all", env=env)
    ck("[done]" in r.stdout, "CLI list --all показывает [done]")
    r = run_cli("remove", "нет-такого", env=env)
    ck(r.returncode == 1 and "ОШИБКА" in r.stderr, "CLI remove неизвестного → EXIT 1")
    r = run_cli("prune", env=env)
    ck(r.returncode == 0 and store.load()["items"] == [], "CLI prune очистил")

    # --- битый файл: честная ошибка, не падение трейсбеком
    with open(path, "w", encoding="utf-8") as f:
        f.write("{битый json")
    expect_err(lambda: store.load(), "битый файл → ChecklistError с текстом")

    # --- уборка
    try:
        os.unlink(path)
        os.rmdir(tmpdir)
    except OSError:
        pass

    print("=== ИТОГ: %d PASS / %d FAIL ===" % (_pass, _fail))
    return 0 if _fail == 0 else 1


if __name__ == "__main__":
    import checklist_store as store  # noqa: E402  (после sys.path.insert)
    sys.exit(main())
