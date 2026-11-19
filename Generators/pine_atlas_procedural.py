#!/usr/bin/env python3
# Q22 метод A: процедурный атлас хвои 1024^2, 4 тайла 512^2 (заказ юзера
# «начнем с процедурного атласа»). Тайл = веточка-основа (изогнутый стебель)
# + пучки иголок (изогнутые линии, вариации цвета/длины/угла). Alpha — для
# gltf alphaMode MASK (cutoff 0.45). ORM: R=AO 255, G=rough 230, B=0.
# Dilation 16px: RGB растекается под прозрачные пиксели — мипмапы без
# чёрной каймы (спец-спека Q22, SSOT).
import colorsys
import math
import os
import random

import numpy as np
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "Graphics", "Environment", "Props", "pine_tree_01")
SIZE = 1024
TILE = 512
RNG = random.Random(20261119)
DILATE_PX = 16


def lerp(a, b, t):
    return a + (b - a) * t


def hsv(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1.0, s), min(1.0, v))
    return (int(r * 255), int(g * 255), int(b * 255))


def stamp(tile, x, y, r, col):
    # круглая печать: alpha=255 в ядре, без софт-края (MASK режет чисто)
    x0 = int(math.floor(x - r)); x1 = int(math.ceil(x + r))
    y0 = int(math.floor(y - r)); y1 = int(math.ceil(y + r))
    H, W = tile.shape[:2]
    r2 = r * r
    for yy in range(max(0, y0), min(H, y1 + 1)):
        for xx in range(max(0, x0), min(W, x1 + 1)):
            d2 = (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2
            if d2 <= r2:
                tile[yy, xx, 0:3] = col
                tile[yy, xx, 3] = 255


def draw_needle(tile, x0, y0, ang, length, width, col_base, tip_boost):
    # изогнутая иголка: параметрическая линия, прогиб по перпендикуляру,
    # сужение к кончику, высветление к кончику
    bend = RNG.uniform(0.06, 0.2) * length * RNG.choice([-1, 1])
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx
    steps = max(8, int(length / 1.4))  # шаг штампа <= радиуса — линия без пунктира
    for i in range(steps + 1):
        t = i / steps
        x = x0 + dx * length * t + px * bend * t * t
        y = y0 + dy * length * t + py * bend * t * t
        r = (width * (1.0 - 0.55 * t)) / 2.0
        v = col_base[2] + tip_boost * t
        col = hsv(col_base[0], col_base[1], v)
        stamp(tile, x, y, max(0.8, r), col)


def make_tile():
    tile = np.zeros((TILE, TILE, 4), dtype=np.uint8)
    # стебель-веточка: снизу-центра вверх, лёгкий изгиб, кора-цвет
    bx, by = TILE / 2.0, TILE - 30.0
    ang0 = -math.pi / 2.0 + RNG.uniform(-0.15, 0.15)
    stem_len = TILE * 0.72
    bend = RNG.uniform(-60.0, 60.0)
    dx, dy = math.cos(ang0), math.sin(ang0)
    px, py = -dy, dx
    steps = 90
    stem_pts = []
    for i in range(steps + 1):
        t = i / steps
        x = bx + dx * stem_len * t + px * bend * t * t
        y = by + dy * stem_len * t + py * bend * t * t
        stem_pts.append((x, y))
        r = lerp(4.5, 1.8, t)
        col = hsv(0.07 + RNG.uniform(-0.01, 0.01), 0.42,
                  0.28 + RNG.uniform(0.0, 0.1))
        stamp(tile, x, y, r, col)
    return tile, stem_pts, ang0, stem_len, steps


def make_tile_needles(tile, stem_pts, ang0, stem_len, steps):
    # пучки иголок вдоль стебля: у каждого узла 14-22 иголки веером
    n_whorls = RNG.randint(12, 16)
    tint = RNG.uniform(-0.03, 0.03)  # оттенок тайла (4 варианта)
    for w in range(n_whorls):
        t = (w + 1) / (n_whorls + 1.0)
        idx = int(t * steps)
        sx, sy = stem_pts[idx]
        # Радиальный пучок (v2 после рендер-пробы: вертикальные «стержни»
        # выглядели мусорно): иголки во ВСЕ стороны, bias вниз (в image y+ —
        # вниз), короткая «подпушь» + длинные наружные.
        n = RNG.randint(24, 34)
        for k in range(n):
            ang = RNG.uniform(0.0, 2.0 * math.pi)
            down = (math.sin(ang) + 1.0) / 2.0  # 1 = вниз
            length = RNG.uniform(55.0, 110.0) * (1.0 - 0.2 * t)                 * (0.75 + 0.45 * down)
            width = RNG.uniform(3.5, 5.5)
            hue = 0.26 + tint + RNG.uniform(-0.02, 0.03)
            sat = RNG.uniform(0.42, 0.62)
            val = RNG.uniform(0.2, 0.52) + 0.1 * down
            draw_needle(tile, sx, sy, ang, length, width, (hue, sat, val), 0.32)
        for k in range(RNG.randint(10, 16)):
            ang = RNG.uniform(0.0, 2.0 * math.pi)
            length = RNG.uniform(28.0, 50.0)
            width = RNG.uniform(3.0, 4.4)
            hue = 0.26 + tint + RNG.uniform(-0.02, 0.03)
            sat = RNG.uniform(0.4, 0.58)
            val = RNG.uniform(0.16, 0.38)
            draw_needle(tile, sx, sy, ang, length, width, (hue, sat, val), 0.32)
    return tile


def dilate(arr, iters):
    # RGB растекается в прозрачные пиксели (alpha не трогаем) — bleed от
    # чёрной каймы мипмапов; 16 проходов 3x3
    rgb = arr[..., 0:3]
    for _ in range(iters):
        filled = arr[..., 3] > 0
        grew = filled.copy()
        src_rgb = rgb.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                m = np.roll(np.roll(filled, dy, axis=0), dx, axis=1)
                c = np.roll(np.roll(src_rgb, dy, axis=0), dx, axis=1)
                touch = m & ~grew
                rgb[touch] = c[touch]
                grew |= m
        if (grew == filled).all():
            break


def main():
    atlas = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    for ti in range(4):
        tile, stem_pts, ang0, stem_len, steps = make_tile()
        make_tile_needles(tile, stem_pts, ang0, stem_len, steps)
        tx = (ti % 2) * TILE
        ty = (ti // 2) * TILE
        atlas[ty:ty + TILE, tx:tx + TILE] = tile
    dilate(atlas, DILATE_PX)
    os.makedirs(OUT_DIR, exist_ok=True)
    diff_p = os.path.join(OUT_DIR, "pine_tree_01_foliage_diff.png")
    orm_p = os.path.join(OUT_DIR, "pine_tree_01_foliage_orm.png")
    Image.fromarray(atlas, "RGBA").save(diff_p)
    orm = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    orm[..., 0] = 255   # AO=1.0
    orm[..., 1] = 230   # roughness 0.9
    orm[..., 2] = 0     # metallic 0
    Image.fromarray(orm, "RGB").save(orm_p)
    print("ATLAS OK: diff %s orm %s (dilation %dpx)" % (diff_p, orm_p, DILATE_PX))


if __name__ == "__main__":
    main()
