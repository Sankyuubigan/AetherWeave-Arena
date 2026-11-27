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
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_PATH = os.path.join(ROOT, "Data", "skill_branches.json")
DUMP_PATH = os.path.join(ROOT, "temp", "skills_dump.json")
ANIM_DUMP_PATH = os.path.join(ROOT, "temp", "anim_library.json")
CANDS_PATH = os.path.join(ROOT, "admin", "candidates.json")
MANIFEST_PATH = os.path.join(ROOT, "Data", "animations_manifest.json")
NAME_MAX = 32
ICON_MAX = 8

# Белый список корней анимаций для /anim/api/list (единый каталог «Анимации»).
# Путь запроса mat'ится ТОЛЬКО по этому списку — защита от traversal.
# depth: рекурсивный скан на N уровней (паки UAL лежат в подпапках
# Unity/Unreal/Source — юзер их не находил); None = только корень папки.
ANIM_ROOTS = [
    {"id": "ual", "name": "UAL (касты, пистолет, меч...)", "dir": "tools/animation_catalog",
     "exts": (".glb",)},
    {"id": "ual_raw1", "name": "UAL1 [Standard] — ИСХОДНИКИ пака (fbx)",
     "dir": "Graphics/Animations/raw/Universal Animation Library[Standard]",
     "exts": (".fbx",), "depth": 3},
    {"id": "ual_raw2", "name": "UAL2 [Standard] — ИСХОДНИКИ пака (fbx)",
     "dir": "Graphics/Animations/raw/Universal Animation Library 2[Standard]",
     "exts": (".fbx",), "depth": 3},
    {"id": "mixamo", "name": "Mixamo (2317)", "dir": "Graphics/mixamo-lib/fbx", "exts": (".fbx",)},
    {"id": "raw_mixamo", "name": "Raw / mixamo (наши касты)", "dir": "Graphics/Animations/raw/mixamo",
     "exts": (".fbx",)},
    {"id": "raw", "name": "Raw / базовые (Idle, Run, Jump...)", "dir": "Graphics/Animations/raw",
     "exts": (".fbx",)},
    {"id": "cand", "name": "Кандидаты (GLB)", "dir": "tools/candidates_models", "exts": (".glb",)},
    {"id": "neuro", "name": "Нейро-касты (SOMA, .f32 — нет превью)", "dir": "Graphics/Animations/neuro_soma",
     "exts": (".f32",)},
]


def _url(path_rel: str) -> str:
    """Относительный путь файла → URL. quote обязателен: в паках UAL пробелы и
    квадратные скобки ([Standard]), urlencode их ломает (юзер не мог открыть)."""
    return "/" + quote(path_rel.replace(os.sep, "/"), safe="/")


def anim_list():
    """Сканирует белый список корней → {groups:[{id,name,items:[{name,url,preview,aka}]}]}.
    depth>0 — рекурсивный обход (файлы в подпапках получают относительный подпуть).
    aka — ИМЕНА КЛИПОВ В ИГРЕ для этого файла (из манифеста, temp/anim_library.json):
    юзер ищет «Wings_Fly»/«Tether_Hang», а файлы зовутся Flying.fbx/Hanging_Idle_2.fbx —
    без этого поиск по каталогу давал ноль совпадений (жалоба 26.11.26)."""
    by_file = (_read_json(ANIM_DUMP_PATH, "дамп анимаций") or {}).get("by_file") or {}
    groups = []
    for r in ANIM_ROOTS:
        base = os.path.join(ROOT, r["dir"].replace("/", os.sep))
        items = []
        if os.path.isdir(base):
            depth = int(r.get("depth", 0))
            for rel in _walk(base, depth):
                fn = os.path.basename(rel)
                if not fn.lower().endswith(r["exts"]) or fn.endswith(".import"):
                    continue
                full_rel = r["dir"] + "/" + rel.replace(os.sep, "/")
                items.append({
                    "name": fn if depth == 0 else full_rel[len(r["dir"]) + 1:],
                    "url": _url(full_rel),
                    # .f32 (neuro) — без браузер-превью; glb/fbx — грузим в центре.
                    "preview": not fn.lower().endswith(".f32"),
                    "aka": by_file.get(fn, []),
                })
            items.sort(key=lambda it: it["name"].lower())
        groups.append({"id": r["id"], "name": r["name"], "items": items})
    return {"groups": groups}


def _walk(base: str, depth: int):
    """Относительные пути файлов. depth=0 → только корень папки (не рекурсия)."""
    if depth <= 0:
        for fn in os.listdir(base):
            if os.path.isfile(os.path.join(base, fn)):
                yield fn
        return
    for dirpath, dirnames, filenames in os.walk(base):
        rel_dir = os.path.relpath(dirpath, base)
        level = 0 if rel_dir == "." else rel_dir.count(os.sep) + 1
        if level > depth:
            dirnames[:] = []
            continue
        for fn in filenames:
            yield fn if rel_dir == "." else os.path.join(rel_dir, fn)


def _read_json(path: str, what: str):
    """JSON-файл или None (лог причины). Битый файл не валит сервер."""
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as ex:
        print("[admin] %s битый (%s): %s" % (what, ex, path))
        return None


def anim_skills():
    """Скиллы для правой панели страницы «Анимации» = ДАМП ИГРЫ ⨝ кандидаты ⨝
    библиотека ⨝ манифест. Только чтение, ничего не пишет.

    Схема ответа:
      legend  — расшифровка статусов (рисует вьюер)
      library — {casts_count, loco_count, generated} (из temp/anim_library.json)
      skills  — [{id, name, phase, branch, price, current:{clip,cast_time,
                 cast_hand,alternate_hands,cancel_at,in_lib,in_manifest,file},
                 cands:[{clip, src, url, v, note, approved, in_manifest, file}],
                 warn}] — warn = человекочитаемая проблема («клип не найден в
                 библиотеке» и т.п.), чтобы дыры были видны без переписки.
    """
    dump = _read_json(DUMP_PATH, "дамп скиллов") or {}
    cands_raw = _read_json(CANDS_PATH, "candidates.json") or {}
    anim = _read_json(ANIM_DUMP_PATH, "дамп анимаций") or {}
    manifest = anim.get("manifest") or {}
    casts = anim.get("casts") or {}
    by_file = anim.get("by_file") or {}
    if not manifest:
        manifest = _manifest_min()  # дампа нет — читаем манифест напрямую

    by_id = {}
    for c in cands_raw.get("skills", []):
        if isinstance(c, dict) and c.get("id"):
            by_id[str(c["id"])] = c

    skills = []
    seen = set()
    for s in dump.get("skills", []):
        if not isinstance(s, dict):
            continue
        sid = str(s.get("id", ""))
        seen.add(sid)
        skills.append(_skill_row(s, by_id.pop(sid, {}), manifest, casts, by_file))
    # Кандидаты, которых нет в дампе игры (не заведены/без скилла) — показываем
    # отдельной секцией, чтобы ничего не терялось молча.
    for sid, c in by_id.items():
        row = _skill_row({"id": sid, "name": c.get("name", sid)}, c, manifest, casts, by_file)
        # Секция кандидатов, которой нет в игре как скилла (враги, будущие
        # умения). Это НЕ ошибка данных — «скилла нет в дампе» только для тех,
        # что заявлены реальными (virtual=true помечает «кандидаты без скилла»).
        if not bool(c.get("virtual", False)):
            row["warn"] = (row.get("warn") or "") + " скилла нет в дампе игры (temp/skills_dump.json)"
        skills.append(row)

    return {
        "legend": {
            "game": "стоит в игре сейчас (cast_anim из дампа)",
            "ok": "кандидат проверен и одобрен",
            "alt": "альтернатива (не проверена вживую)",
            "warn": "требует проверки зрением",
            "no": "не годится",
            "lib": "клип есть в каст-библиотеке ual_casts_test.res",
            "manifest": "имя есть в Data/animations_manifest.json (файл источника)",
            "missing": "клипа нет в библиотеке — НЕ заиграет, пока не импортирован",
        },
        "library": {
            "casts_count": len(casts),
            "loco_count": len(_read_json(ANIM_DUMP_PATH, "дамп анимаций").get("loco", {})) if anim else 0,
            "generated": anim.get("generated", ""),
            "dump_missing": not anim,
        },
        "skills": skills,
        "generated": dump.get("generated", ""),
    }


def _manifest_min():
    """Манифест напрямую (если temp/anim_library.json ещё не сгенерирован)."""
    m = _read_json(MANIFEST_PATH, "манифест анимаций") or {}
    out = {}
    for e in m.get("entries", []):
        if isinstance(e, dict) and e.get("name"):
            out[str(e["name"])] = {
                "source": str(e.get("source", "")),
                "layer": str(e.get("layer", "")),
                "status": str(e.get("status", "missing")),
            }
    return out


def _clip_info(name: str, manifest: dict, casts: dict) -> dict:
    """Инфо по имени клипа игры: есть ли в библиотеке/манифесте, файл источника."""
    if not name:
        return {"clip": "", "in_lib": False, "in_manifest": False, "file": ""}
    m = manifest.get(name) or {}
    src = str(m.get("source", ""))
    fname = src.split("://", 1)[1] if "://" in src else ""
    return {
        "clip": name,
        "in_lib": name in casts,
        "ub": bool((casts.get(name) or {}).get("ub", False)) or (name + "_UB") in casts,
        "in_manifest": bool(m),
        "file": fname,
        "source": src,
        "len": (casts.get(name) or {}).get("len", 0.0),
    }


def _skill_row(s: dict, c: dict, manifest: dict, casts: dict, by_file: dict) -> dict:
    """Строка скилла: текущий клип из ДАМПА ИГРЫ + кандидаты из candidates.json."""
    clip = str(s.get("cast_anim", "") or "")
    is_channel = float(s.get("cast_time", 0.0) or 0.0) > 0.0
    # Клип-СОСТОЯНИЕ (26.11.26): у крыльев cast_anim играет по кругу, у стоек
    # клип лежит в stance_loop_anim. Без этих двух полей админка врала
    # «анимация не задана» на здоровых скиллах — ровно та «чушь», на которую
    # жаловался юзер.
    is_loop = bool(s.get("cast_anim_loop", False))
    stance_clip = str(s.get("stance_loop_anim", "") or "")
    # Показываем ТО, что реально играет: каст-клип важнее позы стойки.
    shown = clip if clip else stance_clip
    cur = _clip_info(shown, manifest, casts)
    cur.update({
        "cast_anim": clip,
        "stance_loop_anim": stance_clip,
        "loop": is_loop,
        "next_cast_anim": str(s.get("next_cast_anim", "") or ""),
        "cast_time": float(s.get("cast_time", 0.0) or 0.0),
        "cast_hand": str(s.get("cast_hand", "") or ""),
        "alternate_hands": bool(s.get("alternate_hands", False)),
        "cancel_at": float(s.get("cancel_at", 0.0) or 0.0),
        "channel": is_channel,
    })
    warns = []
    if shown and not cur["in_lib"]:
        warns.append("текущий клип «%s» НЕ найден в каст-библиотеке — каст не заиграет" % shown)
    # «Анимация не задана» — предупреждение ТОЛЬКО для скиллов, которым клип
    # положен по контракту. Ложные тревоги (жалоба юзера «чушь в кандидатах»):
    #  * под-приёмы стоек (is_sub_skill) играют позу стойки, своего клипа нет;
    #  * скиллы, у которых клип принадлежит ЭФФЕКТУ/компоненту (трос: Tether_Hang
    #    включает TetherSwingComponent в момент зацепа) — в candidates.json
    #    объявлено полем anim_owned_by;
    #  * скиллы движения (двойной прыжок) — анимация не нужна по конструкции.
    owned_by = str(c.get("anim_owned_by", "") or "")
    is_sub = bool(s.get("is_sub_skill", False))
    if not shown and not is_channel and not is_sub and not owned_by:
        warns.append("анимация не задана (ни cast_anim, ни stance_loop_anim)")

    cands = []
    for cc in (c.get("cands") or []):
        if not isinstance(cc, dict):
            continue
        cn = str(cc.get("clip", ""))
        url = _cand_url(cc)
        # Имя в игре: у кандидатов из Mixamo имя ФАЙЛА совпадает со стемом файла
        # источника из манифеста (Flying.fbx → Wings_Fly), поэтому ищем по
        # by_file для ЛЮБОГО src — включая GLB-кандидатов (tools/candidates_models
        # /Standing_1H_Magic_Attack_01.glb = файл клипа Cast_1H_Magic_01).
        game_names = by_file.get(cn + ".fbx", [])
        in_lib = cn in casts or any(n in casts for n in game_names)
        cands.append({
            "clip": cn,
            "src": str(cc.get("src", "mixamo")),
            "url": url,
            "v": str(cc.get("v", "alt")),
            "note": str(cc.get("note", "")),
            # «одобрен» = этот кандидат и есть текущий клип игры.
            "approved": bool(clip) and (cn == clip or clip in game_names),
            "game_names": game_names,
            "in_lib": in_lib,
        })
    return {
        "id": str(s.get("id", "")),
        "name": str(s.get("name") or s.get("skill_name") or ""),
        "phase": str(c.get("phase", "")),
        "branch": str(s.get("branch", "")),
        "price": int(s.get("price", 0) or 0),
        "current": cur,
        "cands": cands,
        "warn": "; ".join(warns),
    }


def _cand_url(c: dict) -> str:
    """URL кандидата по полю src (glb/raw/mixamo/neuro/lib) — как в старой странице.

    src="lib" — клип СОБРАН в каст-библиотеку, но отдельного файла-превью нет
    (нейро/UAL-клипы вроде Blade_Swing_A: retarget_ual_anims собрал их из UAL2,
    исходного .glb/.fbx с таким именем на диске не существует). Пустой URL =
    «превью нет»: страница показывает честную надпись вместо 404-ошибки.
    """
    clip = str(c.get("clip", ""))
    src = str(c.get("src", "mixamo"))
    if src == "lib":
        return ""
    if src == "glb":
        return "/tools/candidates_models/" + quote(clip + ".glb")
    if src == "raw":
        return "/Graphics/Animations/raw/mixamo/" + quote(clip + ".fbx")
    if src == "neuro":
        # Нейро-касты: .f32 в подпапке с именем клипа (нет браузер-превью, но
        # ссылка полезна — файл открывается/скачивается из админки).
        return "/Graphics/Animations/neuro_soma/" + quote(clip) + "/" + quote(clip) + ".f32"
    return "/Graphics/mixamo-lib/fbx/" + quote(clip + ".fbx")


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
        if self.path.rstrip("/") == "/anim/api/list":
            self._send_json(anim_list())
            return
        if self.path.rstrip("/") == "/anim/api/skills":
            payload = anim_skills()
            print("[admin] GET anim/skills: %d скиллов (библиотека %d клипов)" % (
                len(payload["skills"]), payload["library"]["casts_count"]))
            self._send_json(payload)
            return
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
            if "/skills/api/" in str(self.path or "") or "/anim/api/" in str(self.path or ""):
                super().log_request(code, size)
        except Exception:
            pass


def main():
    # Порт можно переопределить (ADMIN_PORT) — для проверок агента на своём порту,
    # когда у юзера уже запущена админка на 8181. Прод-путь (батник) — 8181.
    port = int(os.environ.get("ADMIN_PORT", "8181"))
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
