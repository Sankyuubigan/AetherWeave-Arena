#!/usr/bin/env python3
# Q22 метод A (процедурный атлас): скелет ели + карточки хвои.
# Берём дерево "b" из pine_tree_01_4k_baked.gltf (3 дерева в одном gltf,
# узлы с translation -6/1/8), строим воксельное облако вершин веток
# (шаг 0.5м, y > 40% высоты), в каждом вокселе - кластер из 2 скрещённых
# квадов 0.45-0.75м (спец-спека: 200-350 карточек, UV случайный из 4
# тайлов атласа). Материал: alphaMode MASK 0.45, doubleSided, ORM.
# Выход: pine_tree_01_v2_foliage.gltf (+ _data.bin), БЕЗ бейка.
import json
import math
import os
import random
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
PROP = os.path.normpath(os.path.join(HERE, "..", "Graphics", "Environment",
                                     "Props", "pine_tree_01"))
SRC_GLTF = os.path.join(PROP, "pine_tree_01_4k_baked.gltf")
SRC_BIN = os.path.join(PROP, "pine_tree_01_4k_baked.bin")
# Q22-B (CC0-сток): переопределения через env — дефолты = метод A не тронут.
OUT_BASE = os.environ.get("TREE_OUT_BASE", "pine_tree_01_v2_foliage")
DIFF_PNG = os.environ.get("TREE_FOLIAGE_DIFF", "pine_tree_01_foliage_diff.png")
ORM_PNG = os.environ.get("TREE_FOLIAGE_ORM", "pine_tree_01_foliage_orm.png")
MAT_NAME = os.environ.get("TREE_MAT_NAME", "foliage_atlas_A")
TREE_KEY = "_b_"       # узел дерева b (единственного, ок для слота сравнения)
VOXEL = 0.32
Y_MIN_FRAC = 0.22      # крона ниже: голый низ = «мёртвое дерево»
MAX_CARDS = 550
CARD_MIN, CARD_MAX = 0.8, 1.3
UV_INSET = 0.008
RNG = random.Random(42424)
# Q22-FIX (вердикт юзера 20.11.26 «А и Б висят в воздухе, форма странная»):
# облако карточек унаследовано от скана 17М — крона с 25-30% высоты, внизу
# голая палка (AABB-проба: низ геометрии 0.089 = ствол касается земли, но
# видимая масса хвои стартует высоко — читается как «дерево на шпиле»).
# TREE_CONE=1: карточки на КОНУС-конверте вокруг ствола скана (профиль ели,
# как у одобренного Ц), радиус = максимальный разброс веток скана.
CONE = os.environ.get("TREE_CONE", "0") == "1"
CONE_Y0_FRAC = 0.08   # крона от 8% высоты (у одобренного Ц — от 12%)
CONE_POWER = 1.3      # профиль (1-y/H)^p — выпуклый конус ели
# Конус объёмом больше облака скана → 550 карт просвечивают интерьерный
# меш (растянутые QEM-треугольники скана видны сквозь крону). 900 карт
# закрывают интерьер; 900×4 + trim-ствол 677 = 4277 трис < хиро-нормы 5000.
CONE_CARDS = int(os.environ.get("TREE_CONE_CARDS", "900"))


def vsub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def vadd(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def vscale(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])
def vnorm(a):
    l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-8 else (0.0, 1.0, 0.0)


def read_positions(js, buf, mesh_idx):
    pts = []
    for p in js["meshes"][mesh_idx]["primitives"]:
        acc = js["accessors"][p["attributes"]["POSITION"]]
        bv = js["bufferViews"][acc["bufferView"]]
        off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        n = acc["count"]
        flat = struct.unpack_from("<%df" % (n * 3), buf, off)
        pts.extend([tuple(flat[i:i + 3]) for i in range(0, n * 3, 3)])
    return pts


def find_tree(js):
    for ni, n in enumerate(js["nodes"]):
        if "mesh" in n and TREE_KEY in n.get("name", ""):
            return ni, n["mesh"]
    raise SystemExit("ERROR: узел дерева '%s' не найден" % TREE_KEY)


def build_cloud(pts):
    ymax = max(p[1] for p in pts)
    ythr = ymax * Y_MIN_FRAC
    vox = {}
    for p in pts:
        if p[1] < ythr:
            continue
        k = (int(math.floor(p[0] / VOXEL)),
             int(math.floor(p[1] / VOXEL)),
             int(math.floor(p[2] / VOXEL)))
        s, c = vox.get(k, ((0.0, 0.0, 0.0), 0))
        vox[k] = (vadd(s, p), c + 1)
    centers = [vscale(s, 1.0 / c) for s, c in vox.values()]
    if len(centers) > MAX_CARDS:
        centers = RNG.sample(centers, MAX_CARDS)
    return centers, len(vox), ymax


def build_cone(pts):
    """Карточки на конус-конверте: объёмная выборка (r ~ sqrt(u) * профиль)
    — плотность равномерная по сечению, у вершины сгущение на оси."""
    ax, az = axis_xz(pts)
    ymax = max(p[1] for p in pts)
    rmax = 0.0
    for p in pts:
        if p[1] < ymax * 0.2:
            continue
        rmax = max(rmax, math.hypot(p[0] - ax, p[2] - az))
    y0 = ymax * CONE_Y0_FRAC
    centers = []
    for _ in range(CONE_CARDS):
        y = y0 + (ymax - y0) * RNG.random()
        prof = (1.0 - y / ymax) ** CONE_POWER
        r = rmax * prof * math.sqrt(RNG.random())
        a = RNG.uniform(0.0, 2.0 * math.pi)
        centers.append((ax + math.cos(a) * r,
                        y + RNG.uniform(-0.12, 0.12),
                        az + math.sin(a) * r))
    return centers, rmax, ymax


def axis_xz(pts):
    n = len(pts)
    ax = sum(p[0] for p in pts) / n
    az = sum(p[2] for p in pts) / n
    return ax, az


def add_card(pos, nor, uvs, idx, center, ax, az):
    dx, dz = center[0] - ax, center[2] - az
    d = math.hypot(dx, dz)
    if d < 0.2:
        a = RNG.uniform(0.0, 2.0 * math.pi)
        dx, dz = math.cos(a), math.sin(a)
    else:
        dx, dz = dx / d, dz / d
    drop = RNG.uniform(0.35, 0.75)      # висячая хвоя (v2: 0.15-0.35 = столбики)
    face = vnorm((dx * math.cos(drop), -math.sin(drop), dz * math.cos(drop)))
    right = vnorm(vcross((0.0, 1.0, 0.0), face))
    upA = vcross(face, right)
    gam = RNG.uniform(0.0, math.pi)     # случайный поворот креста вокруг face
    rr = vnorm(vadd(vscale(right, math.cos(gam)), vscale(upA, math.sin(gam))))
    up_r = vcross(face, rr)
    s = RNG.uniform(CARD_MIN, CARD_MAX)
    h = s / 2.0
    tile = RNG.randrange(4)
    tx, ty = tile % 2, tile // 2
    u0 = tx * 0.5 + UV_INSET
    v0 = ty * 0.5 + UV_INSET
    usz = 0.5 - 2.0 * UV_INSET
    corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
    for plane_r, plane_u in ((right, upA), (rr, up_r)):
        base = len(pos)
        for su, sv in corners:
            pos.append(vadd(center, vadd(vscale(plane_r, h * su),
                                         vscale(plane_u, h * sv))))
            nor.append(face)
            uvs.append((u0 + (su + 1.0) / 2.0 * usz,
                        v0 + (sv + 1.0) / 2.0 * usz))
        idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])


def read_acc_f(js, buf, acc_idx):
    acc = js["accessors"][acc_idx]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"]
    comps = 3 if acc["type"] == "VEC3" else 2
    flat = struct.unpack_from("<%df" % (n * comps), buf, off)
    return [tuple(flat[i:i + comps]) for i in range(0, n * comps, comps)]


def read_acc_idx(js, buf, acc_idx):
    acc = js["accessors"][acc_idx]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"]
    fmt = "<%dH" if acc["componentType"] == 5123 else "<%dI"
    return list(struct.unpack_from(fmt % n, buf, off))


def trim_tree(js, buf, node_i, rmax, ymax):
    """CONE-режим: ветки скана торчат из-под конус-конверта карточек
    («антенны» на рендере v4-пробы). Треугольники дерева b остаются только
    внутри конверта (r <= profile(y) + 0.15) или у оси (ствол). Новые
    индексы кладутся во второй буфер (_data.bin) — POSITION/NORMAL/UV
    не дублируются, примитивы лишь перепривязываются на новый accessor."""
    y0 = ymax * CONE_Y0_FRAC
    TOL = 0.15
    blobs = []
    views = []
    off = 0
    mesh = js["meshes"][js["nodes"][node_i]["mesh"]]
    for pi, p in enumerate(mesh["primitives"]):
        pts_p = read_acc_f(js, buf, p["attributes"]["POSITION"])
        indices = read_acc_idx(js, buf, p["indices"])
        assert len(pts_p) <= 65535, "uint16 индексы против count>65535"
        kept = []
        for t in range(0, len(indices), 3):
            # точки проверки: вершины + середины рёбер (длинный пролёт ветки
            # с вершинами внутри конверта вылезал «треугольником коры»)
            vs = [pts_p[indices[t + k]] for k in range(3)]
            check = list(vs)
            for k in range(3):
                a, b = vs[k], vs[(k + 1) % 3]
                check.append(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2))
            ok = True
            for v in check:
                r = math.hypot(v[0], v[2])
                if r < 0.35:
                    continue  # ствол у оси — всегда остаётся
                prof = rmax * (1.0 - min(1.0, max(0.0, v[1] / ymax))) ** CONE_POWER
                limit = prof + TOL if v[1] >= y0 else min(prof, 1.2) + TOL
                if r > limit:
                    ok = False
                    break
            if ok:
                kept.extend(indices[t:t + 3])
        data = struct.pack("<%dH" % len(kept), *kept)
        bv_i = len(js["bufferViews"])
        # тот же dict в локальный views И в js — shift в main мутирует оба
        v = {"buffer": 1, "byteOffset": off,
             "byteLength": len(data), "target": 34963}
        js["bufferViews"].append(v)
        views.append(v)
        a_i = len(js["accessors"])
        js["accessors"].append({"bufferView": bv_i, "componentType": 5123,
                                "count": len(kept), "type": "SCALAR"})
        p["indices"] = a_i
        blobs.append(data)
        off += len(data)
        print("TREE TRIM: prim %d: %d -> %d idx" % (pi, len(indices), len(kept)))
    return b"".join(blobs), views


def pack_bin(pos, nor, uvs, idx):
    blobs = []
    views = []
    off = 0
    for flat, fmt, target in (
            ([c for p in pos for c in p], "<%df", 34962),
            ([c for p in nor for c in p], "<%df", 34962),
            ([c for u in uvs for c in u], "<%df", 34962),
            (idx, "<%dI", 34963)):
        data = struct.pack(fmt % len(flat), *flat)
        blobs.append(data)
        views.append({"buffer": 1, "byteOffset": off,
                      "byteLength": len(data), "target": target})
        off += len(data)
    return b"".join(blobs), views


def main():
    js = json.load(open(SRC_GLTF, encoding="utf-8"))
    buf = open(SRC_BIN, "rb").read()
    node_i, mesh_i = find_tree(js)
    pts = read_positions(js, buf, mesh_i)
    ax, az = axis_xz(pts)
    if CONE:
        centers, rmax, ymax = build_cone(pts)
        n_vox = len(centers)
        print("TREE CONE: rmax=%.1f y0=%.1f cards=%d" % (rmax, ymax * CONE_Y0_FRAC, n_vox))
    else:
        centers, n_vox, ymax = build_cloud(pts)
    pos, nor, uvs, idx = [], [], [], []
    for c in centers:
        add_card(pos, nor, uvs, idx, c, ax, az)
    blob, views = pack_bin(pos, nor, uvs, idx)
    # av ДО extend: pack-вьюхи лягут ровно здесь (trim допишет свои после)
    av = len(js["bufferViews"])
    js["bufferViews"].extend(views)
    if CONE:
        tb, tv = trim_tree(js, buf, node_i, rmax, ymax)
        shift = len(blob)
        for v in tv:
            v["byteOffset"] += shift
        blob += tb
    open(os.path.join(PROP, OUT_BASE + "_data.bin"), "wb").write(blob)

    n = len(pos)
    # glTF: новые данные — ВТОРОЙ буфер. Ловушка: bufferViews с buffer:1
    # валидны, но если сам буфер не добавить в buffers[], Godot падает
    # «Index buffer = 1 is out of bounds» (поймано на сборке ели-v2).
    js["buffers"].append({
        "uri": OUT_BASE + "_data.bin",
        "byteLength": len(blob)})
    a_pos = len(js["accessors"])
    js["accessors"].append({"bufferView": av, "componentType": 5126,
        "count": n, "type": "VEC3",
        "max": [max(p[i] for p in pos) for i in range(3)],
        "min": [min(p[i] for p in pos) for i in range(3)]})
    a_nor = a_pos + 1
    js["accessors"].append({"bufferView": av + 1, "componentType": 5126,
        "count": n, "type": "VEC3"})
    a_uv = a_pos + 2
    js["accessors"].append({"bufferView": av + 2, "componentType": 5126,
        "count": n, "type": "VEC2"})
    a_idx = a_pos + 3
    js["accessors"].append({"bufferView": av + 3, "componentType": 5125,
        "count": len(idx), "type": "SCALAR"})
    img_d = len(js["images"])
    js["images"].append({"uri": DIFF_PNG})
    img_o = len(js["images"])
    js["images"].append({"uri": ORM_PNG})
    sam = len(js.get("samplers", []))
    js.setdefault("samplers", []).append(
        {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
    tex_d = len(js["textures"])
    js["textures"].append({"sampler": sam, "source": img_d})
    tex_o = len(js["textures"])
    js["textures"].append({"sampler": sam, "source": img_o})
    mat_i = len(js["materials"])
    js["materials"].append({
        "name": MAT_NAME,
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": tex_d},
            "metallicFactor": 0.0,
            "roughnessFactor": 1.0,
            "metallicRoughnessTexture": {"index": tex_o},
        },
        "occlusionTexture": {"index": tex_o},
        "alphaMode": "MASK",
        "alphaCutoff": 0.45,
        "doubleSided": True})
    mesh_i_new = len(js["meshes"])
    js["meshes"].append({"name": "FoliageCards", "primitives": [{
        "attributes": {"POSITION": a_pos, "NORMAL": a_nor, "TEXCOORD_0": a_uv},
        "indices": a_idx, "material": mat_i, "mode": 4}]})
    fol_i = len(js["nodes"])
    js["nodes"].append({"name": "FoliageCards", "mesh": mesh_i_new})
    js["nodes"][node_i]["translation"] = [0.0, 0.0, 0.0]  # дерево b к origin
    js["scenes"][0]["nodes"] = [node_i, fol_i]
    out_gltf = os.path.join(PROP, OUT_BASE + ".gltf")
    json.dump(js, open(out_gltf, "w", encoding="utf-8"), indent=1)
    print("TREE OK: verts=%d voxels=%d(>%.1fm) cards=%d tris=%d "
          "bin=%d KB -> %s" % (n, n_vox, ymax * Y_MIN_FRAC, len(centers),
                               len(idx) // 3, len(blob) // 1024, out_gltf))


if __name__ == "__main__":
    main()
