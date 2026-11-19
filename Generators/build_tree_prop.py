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
OUT_BASE = "pine_tree_01_v2_foliage"
TREE_KEY = "_b_"       # узел дерева b (единственного, ок для слота сравнения)
VOXEL = 0.32
Y_MIN_FRAC = 0.22      # крона ниже: голый низ = «мёртвое дерево»
MAX_CARDS = 550
CARD_MIN, CARD_MAX = 0.8, 1.3
UV_INSET = 0.008
RNG = random.Random(42424)


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
    centers, n_vox, ymax = build_cloud(pts)
    pos, nor, uvs, idx = [], [], [], []
    for c in centers:
        add_card(pos, nor, uvs, idx, c, ax, az)
    blob, views = pack_bin(pos, nor, uvs, idx)
    open(os.path.join(PROP, OUT_BASE + "_data.bin"), "wb").write(blob)

    n = len(pos)
    av = len(js["bufferViews"])
    js["bufferViews"].extend(views)
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
    js["images"].append({"uri": "pine_tree_01_foliage_diff.png"})
    img_o = len(js["images"])
    js["images"].append({"uri": "pine_tree_01_foliage_orm.png"})
    sam = len(js.get("samplers", []))
    js.setdefault("samplers", []).append(
        {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
    tex_d = len(js["textures"])
    js["textures"].append({"sampler": sam, "source": img_d})
    tex_o = len(js["textures"])
    js["textures"].append({"sampler": sam, "source": img_o})
    mat_i = len(js["materials"])
    js["materials"].append({
        "name": "foliage_atlas_A",
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
