#!/usr/bin/env python3
# Q22 метод B (CC0-сток): атлас хвои из фотоскана пучков иголок.
# Источник: ambientCG PineNeedles001 (CC0 1.0, https://ambientcg.com/view?id=PineNeedles001)
# — 2048² scan: 8 отдельных пучков иголок на чёрном фоне + Opacity-маска.
# Из него: 4 лучших пучка → тайлы 512² (alpha из Opacity, tint в хвойный
# зелёный для 3 тайлов + 1 «сухой» коричневый для разнообразия), dilation
# 16px, ORM (R=AO 255, G=rough 220, B=0). Выход в Props/pine_tree_01/:
# pine_tree_01_foliage_diff_B.png + pine_tree_01_foliage_orm_B.png.
# Превью для визуальной проверки — tasks/<sess>/stock_atlas_preview.png.
import os
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
PROP = os.path.normpath(os.path.join(HERE, "..", "Graphics", "Environment",
                                     "Props", "pine_tree_01"))
SESS = os.path.normpath(os.path.join(HERE, "..", "tasks", "261117_2355-089dca89"))
SRC = os.path.join(SESS, "stock", "ambientcg_pine_needles_001",
                   "PineNeedles001_2K-JPG_Color.jpg")
SRC_OP = os.path.join(SESS, "stock", "ambientcg_pine_needles_001",
                      "PineNeedles001_2K-JPG_Opacity.jpg")
DIFF_OUT = os.path.join(PROP, "pine_tree_01_foliage_diff_B.png")
ORM_OUT = os.path.join(PROP, "pine_tree_01_foliage_orm_B.png")
TILE = 512
PAD = 24          # поля тайла — запас под dilation
DILATE = 16
MIN_BLOB = 3000   # пучки иголок крупные; мелочь = пыль

def _bundle_images(ca, oa):
    """Пучки (RGBA-спрайты) из scan по связным компонентам opacity."""
    mask = oa > 100
    lab, n = ndimage.label(mask)
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    out = []
    for k in np.argsort(sizes)[::-1][:8]:
        if sizes[k] < MIN_BLOB:
            continue
        ys, xs = np.where(lab == k + 1)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        crop = ca[y0:y1 + 1, x0:x1 + 1]
        a = oa[y0:y1 + 1, x0:x1 + 1].astype(np.float32) / 255.0
        alpha = np.clip((a - 0.22) / 0.20, 0, 1)
        # Иголки скана 1-3px — VRAM (DXT) моет тонкие линии в бледность.
        # Толщина +2px: линии переживают сжатие и видны издалека.
        alpha = ndimage.grey_dilation(alpha, size=(5, 5)) * 1.0
        alpha = np.clip(alpha, 0, 1)
        rgba = np.dstack([crop, (alpha * 255).astype(np.uint8)])
        out.append(Image.fromarray(rgba))
    if len(out) < 4:
        raise SystemExit("пучков меньше 4 — атлас не собирать")
    return out

def _tint(im, green: bool):
    if not green:
        return im
    # RGBA-сохраняющий tint: HSV по RGB-каналам, альфа остаётся.
    a = im.split()[3]
    rgb = im.convert("RGB")
    hsv = np.asarray(rgb.convert("HSV"), dtype=np.float32)
    h, s2, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    h = ((h + 70.0 * 255.0 / 360.0)) % 255.0
    s2 = np.clip(s2 * 1.7, 0, 255)
    v = np.clip(v * 0.50, 0, 255)
    tinted = Image.fromarray(np.dstack([h, s2, v]).astype(np.uint8), "HSV").convert("RGB")
    out = tinted.convert("RGBA")
    out.putalpha(a)
    return out

def main():
    col = Image.open(SRC).convert("RGB")
    op = Image.open(SRC_OP).convert("L")
    ca = np.asarray(col, dtype=np.uint8)
    oa = np.asarray(op, dtype=np.uint8)
    bundles = _bundle_images(ca, oa)
    print("bundles: %d" % len(bundles))

    # Атлас 2×2×512: КАЖДЫЙ тайл = плотная упаковка 5 пучков (позиции
    # решёткой 2×2+центр со сдвигами, случайные повороты/зеркала) —
    # карточка видит сплошной ворс иголок, а не одиночную дугу на пустоте.
    rng = np.random.RandomState(777)
    atlas = Image.new("RGBA", (TILE * 2, TILE * 2), (0, 0, 0, 0))
    for tile_i in range(4):
        tx, ty = (tile_i % 2) * TILE, (tile_i // 2) * TILE
        slots = [(0.40, 0.38), (0.62, 0.34), (0.36, 0.62), (0.64, 0.66),
                 (0.50, 0.50), (0.50, 0.30), (0.30, 0.50), (0.70, 0.50)]
        for si, (fx, fy) in enumerate(slots):
            b = bundles[(tile_i * 2 + si) % len(bundles)]
            if rng.rand() < 0.5:
                b = b.transpose(Image.FLIP_LEFT_RIGHT)
            if rng.rand() < 0.5:
                b = b.transpose(Image.FLIP_TOP_BOTTOM)
            ang = rng.uniform(-25, 25)
            b = b.rotate(ang, expand=True, resample=Image.BICUBIC)
            w, h = b.size
            sc = min((TILE * 0.85) / w, (TILE * 0.85) / h, 1.0)
            b = b.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
            # Тонкие иголки при даунсеймпле теряют альфу (LANCZOS усредняет
            # 1-3px линии) — буст, иначе MASK 0.45 отрезает хвою в штрихи.
            bb = np.asarray(b).astype(np.float32)
            bb[..., 3] = np.clip(bb[..., 3] * 1.7, 0, 255)
            b = Image.fromarray(bb.astype(np.uint8))
            w, h = b.size
            cx, cy = tx + int(fx * TILE), ty + int(fy * TILE)
            # Все тайлы зелёные (v3): «сухой» тайл давал розовые пятна кроны
            # (25% карточек) — юзер такое не одобрил бы даже как «разнообразие».
            atlas.alpha_composite(_tint(b, True), (cx - w // 2, cy - h // 2))
        # Второй слой мелких пучков — заполнение окон между большими:
        # карточка не должна видеть сквозь хвою пустоту тайла.
        for si in range(4):
            b = bundles[(tile_i * 3 + si) % len(bundles)]
            if rng.rand() < 0.5:
                b = b.transpose(Image.FLIP_LEFT_RIGHT)
            b = b.rotate(rng.uniform(-40, 40), expand=True, resample=Image.BICUBIC)
            w, h = b.size
            sc = min((TILE * 0.45) / w, (TILE * 0.45) / h, 1.0)
            b = b.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
            bb = np.asarray(b).astype(np.float32)
            bb[..., 3] = np.clip(bb[..., 3] * 1.7, 0, 255)
            b = Image.fromarray(bb.astype(np.uint8))
            cx, cy = tx + int(rng.uniform(0.3, 0.7) * TILE), ty + int(rng.uniform(0.3, 0.7) * TILE)
            atlas.alpha_composite(_tint(b, True), (cx - w // 2, cy - h // 2))
    atlas_np = np.asarray(atlas).copy()

    # Dilation RGB за границы alpha (мипмапы без тёмных кантов).
    am = atlas_np[:, :, 3] > 0
    grown = ndimage.binary_dilation(am, iterations=DILATE)
    for c in range(3):
        ch = atlas_np[:, :, c].astype(np.float32)
        w = atlas_np[:, :, 3].astype(np.float32) / 255.0
        fill = ndimage.grey_dilation(ch, size=(DILATE * 2 + 1, DILATE * 2 + 1))
        ch = ch * w + fill * (1.0 - w) * grown
        atlas_np[:, :, c] = np.clip(ch, 0, 255).astype(np.uint8)
    Image.fromarray(atlas_np).save(DIFF_OUT)
    print("DIFF:", DIFF_OUT, atlas_np.shape)

    orm = np.zeros((TILE * 2, TILE * 2, 3), dtype=np.uint8)
    orm[..., 0] = 255
    orm[..., 1] = 220
    Image.fromarray(orm).save(ORM_OUT)
    print("ORM:", ORM_OUT)

    px = np.zeros((TILE * 2, TILE * 2, 3), dtype=np.uint8)
    for yy in range(0, TILE * 2, 32):
        for xx in range(0, TILE * 2, 32):
            px[yy:yy + 32, xx:xx + 32] = 90 if ((xx // 32 + yy // 32) % 2) else 60
    pv = Image.fromarray(px)
    pv.paste(Image.fromarray(atlas_np), (0, 0), Image.fromarray(atlas_np))
    pv.save(os.path.join(SESS, "stock_atlas_preview.png"))
    print("PREVIEW ok")

if __name__ == "__main__":
    main()
