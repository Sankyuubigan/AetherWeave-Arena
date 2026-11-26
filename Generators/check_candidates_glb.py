"""ГЕЙТ КАНДИДАТОВ АДМИНКИ (26.11.26) — GLB в tools/candidates_models.

ПОЧЕМУ СУЩЕСТВУЕТ: юзер увидел в админке GLB в T-позе. Причин было ДВЕ, и обе
тихие:
  1) бейк сопоставлял кости по точному имени (mixamorig:Hips vs mixamorig1:Hips)
     → 0 совпадений → запеклась rest-поза;
  2) в файле лежали ДВА экшена (старый rest-поза + запечённый), а вьюер играет
     clips[0] → показывал rest-позу даже при корректном клипе внутри.
Данные выглядели здоровыми (файл валидный GLB, анимация есть, каналы есть).
Поэтому гейт меряет ФАКТ, а не наличие: сколько клипов, сколько ключей, сколько
каналов реально меняется между кадрами.

Правила (нарушение = EXIT≠0):
  * в GLB РОВНО один клип (иначе вьюер может сыграть не тот);
  * клип не короче MIN_KEYS ключей (2 ключа = начало+конец = статичная поза);
  * не меньше MIN_VARIED каналов различаются между кадрами;
  * имя клипа не служебное («ArmatureAction», «Armature.001|mixamo.com|Layer0»).

Запуск: python -I Generators/check_candidates_glb.py [--dir tools/candidates_models]
EXIT: 0 = все кандидаты здоровы, 1 = есть битые (перепечь bake_anim_glb.py).
"""
import json
import os
import struct
import sys

MIN_KEYS = 4        # настоящий клип 24 fps даёт десятки ключей; 2 = rest-поза
MIN_VARIED = 20     # каналов, обязанных различаться между кадрами
BAD_NAMES = ("ArmatureAction",)


def read_glb_json(path):
    """JSON-чанк GLB (без зависимостей: триангуляция не нужна)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise ValueError("не GLB: " + path)
    json_len = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + json_len])


def read_glb_bin(path):
    with open(path, "rb") as f:
        data = f.read()
    json_len = struct.unpack("<I", data[12:16])[0]
    off = 20 + json_len
    bin_len = struct.unpack("<I", data[off:off + 4])[0]
    return data[off + 8:off + 8 + bin_len]


COMPS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor_floats(j, blob, idx):
    a = j["accessors"][idx]
    bv = j["bufferViews"][a["bufferView"]]
    n = a["count"]
    c = COMPS[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return n, c, struct.unpack_from("<%df" % (n * c), blob, start)


def check_file(path):
    """Возвращает список проблем (пустой = файл здоров)."""
    problems = []
    try:
        j = read_glb_json(path)
        blob = read_glb_bin(path)
    except Exception as e:
        return ["не читается как GLB: %s" % e]
    anims = j.get("animations") or []
    if not anims:
        return ["в GLB нет анимации"]
    if len(anims) != 1:
        problems.append("клипов %d, должен быть 1 (вьюер играет clips[0]): %s"
                        % (len(anims), [a.get("name") for a in anims]))
    a = anims[0]
    name = str(a.get("name", ""))
    if not name or any(name.startswith(b) for b in BAD_NAMES) or "|" in name:
        problems.append("служебное имя клипа: %r" % name)
    max_keys = 0
    varied = 0
    channels = a.get("channels") or []
    for ch in channels:
        s = a["samplers"][ch["sampler"]]
        n, _c, _ = accessor_floats(j, blob, s["input"])
        max_keys = max(max_keys, n)
        n2, c2, vals = accessor_floats(j, blob, s["output"])
        if vals and (max(vals) - min(vals)) > 1e-4:
            varied += 1
    if max_keys < MIN_KEYS:
        problems.append("ключей %d (<%d) — статичная поза / T-поза" % (max_keys, MIN_KEYS))
    if varied < MIN_VARIED:
        problems.append("меняется %d/%d каналов (<%d) — анимация не перенесена"
                        % (varied, len(channels), MIN_VARIED))
    return problems


def main():
    # Консоль Windows = cp1251: без этого print с «→»/кириллицей валит
    # UnicodeEncodeError уже ПОСЛЕ проверок и маскирует результат гейта.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, "tools", "candidates_models")
    args = sys.argv[1:]
    if "--dir" in args:
        target = args[args.index("--dir") + 1]
    files = sorted(f for f in os.listdir(target) if f.lower().endswith(".glb"))
    if not files:
        print("ГЕЙТ: нет GLB в", target)
        return 1
    bad = 0
    for f in files:
        p = os.path.join(target, f)
        problems = check_file(p)
        if problems:
            bad += 1
            print("FAIL %-38s %s" % (f, "; ".join(problems)))
        else:
            print("OK   %s" % f)
    print("")
    print("ГЕЙТ КАНДИДАТОВ: %d файлов, битых %d%s" % (
        len(files), bad, "" if bad == 0 else " → перепечь: bake_anim_glb.py"))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
