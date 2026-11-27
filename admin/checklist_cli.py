"""CLI чек-листа — единственный путь агента к списку проверки.

Правила (docs/checklist.md): агент добавляет пункты и чистит сделанные ТОЛЬКО
этими командами, руками JSON не правит. Юзер отмечает «Проверено» в админке.

  python -I admin/checklist_cli.py add --title "..." [--body "..." | --body-file F]
                                       [--kind check|decision] [--date ДД.ММ.ГГ]
  python -I admin/checklist_cli.py list [--all]
  python -I admin/checklist_cli.py done <id|префикс>... [--all]
  python -I admin/checklist_cli.py remove <id|префикс>...
  python -I admin/checklist_cli.py prune

Коды выхода: 0 = ок, 1 = ошибка (текст в stderr).
"""
import argparse
import os
import sys
from datetime import datetime

# python -I не кладёт папку скрипта в sys.path — добавляем явно.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import checklist_store as store  # noqa: E402

# Консоль Windows (cp1251) не держит «→»/тире — вывод в UTF-8.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def _fmt(it: dict, show_status: bool = False) -> str:
    title = it["title"] if len(it["title"]) <= 110 else it["title"][:107] + "…"
    parts = ["  %s" % it["id"]]
    if it["date"]:
        parts.append(it["date"])
    if show_status:
        parts.append("[done]" if it["status"] == "done" else "[ ]")
    if it["kind"] == "decision":
        parts.append("(решение)")
    parts.append(title)
    return "  ".join(parts)


def cmd_add(a) -> int:
    body = a.body or ""
    if a.body_file:
        with open(a.body_file, "r", encoding="utf-8") as f:
            body = f.read()
    date = a.date if a.date is not None else datetime.now().strftime("%d.%m.%y")
    it = store.add(a.title, body=body, kind=a.kind, date=date)
    print("OK %s — %s" % (it["id"], it["title"]))
    return 0


def cmd_list(a) -> int:
    data = store.load()
    items = data["items"] if a.all else [x for x in data["items"] if x["status"] == "pending"]
    c = store.counts(data)
    print("К ПРОВЕРКЕ (%d) · ПРОВЕРЕНО (%d)" % (c["pending"], c["done"]))
    for it in items:
        print(_fmt(it, show_status=a.all))
    return 0


def cmd_done(a) -> int:
    if a.all:
        n = store.done_all()
        print("OK отмечено: %d" % n)
        return 0
    if not a.ids:
        raise store.ChecklistError("укажи id (или --all)")
    for key in a.ids:
        it = store.set_done(key, True)
        print("OK %s — %s" % (it["id"], it["title"]))
    return 0


def cmd_remove(a) -> int:
    if not a.ids:
        raise store.ChecklistError("укажи id")
    for key in a.ids:
        it = store.remove(key)
        print("OK удалён %s — %s" % (it["id"], it["title"]))
    return 0


def cmd_prune(a) -> int:
    n = store.prune()
    print("OK удалено отмеченных: %d" % n)
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Чек-лист проверки игры (admin/checklist.json)")
    sub = p.add_subparsers(dest="cmd", required=True)

    pa = sub.add_parser("add", help="добавить пункт")
    pa.add_argument("--title", required=True)
    pa.add_argument("--body", default="")
    pa.add_argument("--body-file", default="")
    pa.add_argument("--kind", default="check", choices=list(store.KINDS))
    pa.add_argument("--date", default=None, help="ДД.ММ.ГГ (по умолчанию сегодня)")
    pa.set_defaults(fn=cmd_add)

    pl = sub.add_parser("list", help="показать список")
    pl.add_argument("--all", action="store_true", help="включая отмеченные")
    pl.set_defaults(fn=cmd_list)

    pd = sub.add_parser("done", help="отметить проверенным")
    pd.add_argument("ids", nargs="*")
    pd.add_argument("--all", action="store_true")
    pd.set_defaults(fn=cmd_done)

    pr = sub.add_parser("remove", help="удалить пункт")
    pr.add_argument("ids", nargs="+")
    pr.set_defaults(fn=cmd_remove)

    pp = sub.add_parser("prune", help="удалить все отмеченные")
    pp.set_defaults(fn=cmd_prune)

    a = p.parse_args(argv)
    try:
        return a.fn(a)
    except store.ChecklistError as ex:
        print("ОШИБКА: %s" % ex, file=sys.stderr)
        return 1
    except OSError as ex:
        print("ОШИБКА: %s" % ex, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
