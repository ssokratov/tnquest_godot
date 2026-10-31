#!/usr/bin/env python3
"""Slice AI sprite sheets into game sprites, with background removal.

Sheets are wide images with characters/items in one row on white (or
already transparent) background. Steps per sheet:
  1. Build an alpha channel: near-white background components that touch
     the image border become transparent (scipy connected components).
     Interior white (shirts, coat trim, monocle glass) stays opaque
     because its white region never touches the border.
  2. Split the row into characters by column gaps in the foreground mask
     (falls back to equal split if the group count is wrong).
  3. Trim, resize to a common height (characters 512, items/fire 384),
     save as <name>_0.png; characters also get bob frames _1 (shifted
     up) and _2 (same as _0) so the existing 3-frame animation code
     just works. Items get only _0 (static).
"""
import numpy as np
from PIL import Image
from pathlib import Path
from scipy import ndimage

SRC = Path.home() / "workspace/tn2019quest_port/sprites_ai"
OUT = Path.home() / "workspace/tn2019quest_port/project/assets/sprites_ai"
OUT.mkdir(parents=True, exist_ok=True)


def add_alpha(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    arr = np.array(im)
    if (arr[..., 3] < 250).any():
        # Already has transparency (Toshik, Nastya): keep it as-is.
        return im
    rgb = arr[..., :3].astype(np.int16)
    # Near-white background (min channel > 215 is safely above skin tones).
    bg = (rgb.min(axis=2) > 215)
    labels, _n = ndimage.label(bg)
    border_labels = set(np.unique(np.concatenate([
        labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1],
    ]))) - {0}
    alpha = np.where(np.isin(labels, list(border_labels)), 0, 255).astype(np.uint8)
    arr[..., 3] = alpha
    return Image.fromarray(arr, "RGBA")


def decontaminate(im: Image.Image) -> Image.Image:
    """Remove the white fringe left by background removal.

    Edge pixels blended with the white sheet background stay opaque and
    whitish, which reads as white specks on the game's dark scene. For
    each opaque near-white pixel that touches transparency, copy the
    colour of the nearest opaque non-white pixel — but only when that
    pixel is within 2.5 px, so large genuinely white areas (shirts,
    coat trim) keep their colour apart from a thin rim at most.
    """
    arr = np.array(im).copy()
    alpha = arr[..., 3]
    opaque = alpha > 128
    if not opaque.any():
        return im
    rgb = arr[..., :3].astype(np.int16)
    near_white = (rgb.min(axis=2) > 200) & ((rgb.max(axis=2) - rgb.min(axis=2)) < 40)
    near_transp = ndimage.binary_dilation(~opaque, iterations=1)
    cand = opaque & near_white & near_transp
    keep = opaque & ~near_white
    if not keep.any() or not cand.any():
        return im
    dist, inds = ndimage.distance_transform_edt(~keep, return_indices=True)
    ys, xs = np.where(cand & (dist <= 2.5))
    for y, x in zip(ys, xs):
        ny, nx = inds[0][y, x], inds[1][y, x]
        arr[y, x, :3] = arr[ny, nx, :3]
    return Image.fromarray(arr, "RGBA")


def clear_gap_strips(im: Image.Image) -> Image.Image:
    """Make trapped background strips transparent.

    Background removal only clears white that touches the image
    border, so a background strip closed off inside the silhouette
    survives: between the legs, between arm and torso, a coat slit.
    On the dark scene it reads as a bright white bar. Clear a
    near-white component only when it is tall and narrow, large
    enough not to be a lace or button, thin, and in the lower part
    of the sprite. The lower-part guard is load-bearing: chest-level
    strips of the same shape are shirt fronts (genich's shirt left
    of his tie, repa's dress-shirt front) and must survive.
    """
    arr = np.array(im).copy()
    alpha = arr[..., 3]
    opaque = alpha > 128
    if not opaque.any():
        return im
    rgb = arr[..., :3].astype(np.int16)
    near_white = opaque & (rgb.min(axis=2) > 200) & ((rgb.max(axis=2) - rgb.min(axis=2)) < 40)
    if not near_white.any():
        return im
    lab, n = ndimage.label(near_white, structure=np.ones((3, 3), int))
    thick = ndimage.distance_transform_edt(~(opaque & ~near_white))
    h_img = arr.shape[0]
    for i in range(1, n + 1):
        comp = lab == i
        if int(comp.sum()) < 150:
            continue
        ys, xs = np.where(comp)
        w = xs.max() - xs.min() + 1
        h = ys.max() - ys.min() + 1
        if (w <= 16 and h >= 3 * w and thick[comp].max() <= 6.5
                and ys.min() >= 0.45 * h_img):
            arr[comp, 3] = 0
    return Image.fromarray(arr, "RGBA")


def split_columns(fg: np.ndarray, count: int, min_gap: int = 40) -> list:
    """Return x-intervals of `count` foreground groups, or equal split."""
    col_has = fg.any(axis=0)
    groups = []
    start = None
    for x, has in enumerate(col_has):
        if has and start is None:
            start = x
        elif not has and start is not None:
            groups.append((start, x))
            start = None
    if start is not None:
        groups.append((start, len(col_has)))
    # Merge groups separated by less than min_gap (e.g. a character's
    # arm separated from its body by a few background pixels).
    merged = []
    for g in groups:
        if merged and g[0] - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], g[1])
        else:
            merged.append(g)
    if len(merged) == count:
        return merged
    w = fg.shape[1]
    return [(i * w // count, (i + 1) * w // count) for i in range(count)]


def process(im: Image.Image, names: list, height: int, animated: bool):
    im = decontaminate(add_alpha(im))
    arr = np.array(im)
    fg = arr[..., 3] > 10
    intervals = split_columns(fg, len(names))
    for name, (x0, x1) in zip(names, intervals):
        pad = 6
        crop = im.crop((max(0, x0 - pad), 0, min(im.width, x1 + pad), im.height))
        a = np.array(crop)
        f = a[..., 3] > 10
        ys, xs = np.where(f)
        if len(ys) == 0:
            raise SystemExit(f"empty sprite: {name}")
        crop = crop.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        scale = height / crop.height
        crop = crop.resize((max(1, round(crop.width * scale)), height), Image.NEAREST)
        crop = clear_gap_strips(crop)
        crop.save(OUT / f"{name}_0.png")
        if animated:
            up = Image.new("RGBA", crop.size, (0, 0, 0, 0))
            up.paste(crop, (0, -12))
            up.save(OUT / f"{name}_1.png")
            crop.save(OUT / f"{name}_2.png")
        print(f"  {name}: {crop.size}")


def main():
    print("characters:")
    process(Image.open(SRC / "media-generation-toshik-0-6f0eb2d5-81d2-4c50-90e3-f5ddb6464530.png"),
            ["toshik"], 512, True)
    process(Image.open(SRC / "media-generation-nastya-0-a5e44cd7-d875-4b05-b268-963f1ca04a5b.png"),
            ["nastya"], 512, True)
    process(Image.open(SRC / "media-generation-jacob-0-6b43b61b-f594-4c3e-9bae-6bb0726297ab.png"),
            ["jacob"], 512, True)
    process(Image.open(SRC / "media-generation-sheet-npc1-0-e6c55f37-2b9e-4dac-b71e-b20ac9958a6d.png"),
            ["zags", "kolyan", "sedosh", "sokrat"], 512, True)
    process(Image.open(SRC / "media-generation-sheet-npc2-0-67c3fa2e-20cf-4ee9-be99-db3f0d625112.png"),
            ["bartender", "policeman", "crowd", "genich"], 512, True)
    process(Image.open(SRC / "media-generation-sheet-npc3-0-ab954f4a-b46a-46ef-9649-805590489090.png"),
            ["repa", "okusheva"], 512, True)
    print("items:")
    process(Image.open(SRC / "media-generation-sheet-items-0-313fc9cb-fd90-4228-bf3d-70835cdef586.png"),
            ["monocle", "extinguisher", "boots", "key", "shoe", "taxofon"], 384, False)
    print("fire (sheet frames are the animation, no bob copies):")
    im = decontaminate(add_alpha(Image.open(SRC / "media-generation-fire-sheet-0-dedcf309-9658-4a1a-9df0-638808fd4352.png")))
    arr = np.array(im)
    fg = arr[..., 3] > 10
    for name, (x0, x1) in zip(["fire_0", "fire_1", "fire_2"], split_columns(fg, 3)):
        crop = im.crop((max(0, x0 - 6), 0, min(im.width, x1 + 6), im.height))
        a = np.array(crop)
        f = a[..., 3] > 10
        ys, xs = np.where(f)
        crop = crop.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        scale = 384 / crop.height
        crop = crop.resize((max(1, round(crop.width * scale)), 384), Image.NEAREST)
        crop = clear_gap_strips(crop)
        crop.save(OUT / f"{name}.png")
        print(f"  {name}: {crop.size}")
    print(f"total: {len(list(OUT.glob('*.png')))} PNGs in {OUT}")


if __name__ == "__main__":
    main()
