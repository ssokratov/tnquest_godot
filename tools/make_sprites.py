#!/usr/bin/env python3
"""Procedural pixel-art sprites for the tn2019quest Godot port.

Why code, not an image generator: one consistent indie style, transparent
backgrounds, and exact 3-frame animation (idle bob / walk) for every
character, which generated sheets never delivered reliably.

Canvas: 24x32 px, scaled x3 to 72x96 PNG. Frame 0 = standing, frame 1 =
bob up 1 px, frame 2 = feet apart. Fire is 32x32, 3 flame shapes.
Characters are one humanoid template with palette + accessories, so every
NPC is recognisable but clearly from the same game.
"""
from PIL import Image, ImageDraw
from pathlib import Path

OUT = Path.home() / "workspace/tn2019quest_port/project/assets/sprites"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 24, 32

SKIN = (255, 205, 170)
DARK = (40, 32, 40)

def px(d, x, y, w, h, color):
    if color is None:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)

def human(name, skin=SKIN, hair=(60, 40, 30), hair_style="short",
          shirt=(70, 130, 180), pants=(50, 50, 90), dress=False,
          hat=None, beard=None, glasses=False, badge=False,
          apron=False, bowtie=False, laptop=False):
    """Return 3 PIL frames."""
    frames = []
    for frame in range(3):
        dy = -1 if frame == 1 else 0
        spread = 1 if frame == 2 else 0
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # legs
        px(d, 8 - spread, 20 + dy, 4, 9, pants)
        px(d, 12 + spread, 20 + dy, 4, 9, pants)
        px(d, 7 - spread, 29 + dy, 5, 2, DARK)   # shoes
        px(d, 12 + spread, 29 + dy, 5, 2, DARK)
        # torso (dress widens it)
        tx0, tx1 = (6, 17) if dress else (7, 16)
        px(d, tx0, 10 + dy, tx1 - tx0 + 1, 10, shirt)
        if dress:
            px(d, tx0, 18 + dy, tx1 - tx0 + 1, 3, shirt)
        # arms
        px(d, 5, 11 + dy, 2, 8, shirt)
        px(d, 17, 11 + dy, 2, 8, shirt)
        px(d, 5, 19 + dy, 2, 2, skin)
        px(d, 17, 19 + dy, 2, 2, skin)
        # head
        px(d, 8, 2 + dy, 8, 8, skin)
        px(d, 10, 6 + dy, 2, 1, DARK)  # eyes
        px(d, 13, 6 + dy, 2, 1, DARK)
        px(d, 11, 8 + dy, 2, 1, (150, 60, 60))  # mouth
        # hair
        if hair_style == "short":
            px(d, 8, 2 + dy, 8, 2, hair)
            px(d, 8, 4 + dy, 1, 2, hair)
            px(d, 15, 4 + dy, 1, 2, hair)
        elif hair_style == "long":
            px(d, 8, 2 + dy, 8, 2, hair)
            px(d, 7, 4 + dy, 2, 10, hair)
            px(d, 15, 4 + dy, 2, 10, hair)
        elif hair_style == "bald":
            pass
        elif hair_style == "curly":
            px(d, 7, 1 + dy, 10, 3, hair)
        if beard:
            px(d, 8, 8 + dy, 8, 2, beard)
        if glasses:
            px(d, 9, 5 + dy, 3, 2, (220, 240, 255))
            px(d, 13, 5 + dy, 3, 2, (220, 240, 255))
        if hat == "cap":
            px(d, 8, 1 + dy, 8, 2, (30, 30, 120))
            px(d, 7, 3 + dy, 10, 1, (30, 30, 120))
        elif hat == "santa":
            px(d, 8, 1 + dy, 8, 2, (200, 30, 30))
            px(d, 8, 3 + dy, 8, 1, (240, 240, 240))
            px(d, 15, 0 + dy, 2, 2, (240, 240, 240))
        elif hat == "judge":
            px(d, 7, 1 + dy, 10, 2, (90, 40, 120))
            px(d, 6, 3 + dy, 12, 1, (90, 40, 120))
        elif hat == "bowler":
            px(d, 9, 1 + dy, 6, 2, (50, 40, 40))
            px(d, 7, 3 + dy, 10, 1, (50, 40, 40))
        if badge:
            px(d, 14, 13 + dy, 2, 2, (255, 220, 80))
        if apron:
            px(d, 10, 11 + dy, 4, 8, (230, 220, 200))
        if bowtie:
            px(d, 11, 10 + dy, 2, 1, (200, 30, 30))
        if laptop:
            px(d, 9, 16 + dy, 6, 4, (90, 90, 100))
            px(d, 10, 17 + dy, 4, 2, (170, 220, 255))
        im = im.resize((W * 3, H * 3), Image.NEAREST)
        frames.append(im)
    return frames

CHARS = {
    "toshik": dict(shirt=(70, 130, 180), pants=(50, 50, 90), hair=(60, 40, 30)),
    "nastya": dict(shirt=(220, 90, 140), pants=(60, 40, 80), hair=(40, 25, 15),
                   hair_style="long", dress=True),
    "zags": dict(shirt=(110, 60, 150), pants=(50, 40, 70), hair=(120, 120, 120),
                 hair_style="long", hat="judge", dress=True),
    "jacob": dict(shirt=(200, 30, 30), pants=(60, 60, 60), hair=(240, 240, 240),
                  hair_style="bald", beard=(240, 240, 240), hat="santa"),
    "kolyan": dict(shirt=(120, 110, 90), pants=(70, 60, 50), hair=(50, 40, 30),
                   hat="cap"),
    "sedosh": dict(shirt=(40, 70, 160), pants=(40, 40, 80), hair=(30, 30, 30),
                   hat="cap", badge=True),
    "sokrat": dict(shirt=(90, 180, 120), pants=(50, 50, 70), hair=(30, 30, 30),
                   glasses=True, laptop=True),
    "bartender": dict(shirt=(200, 200, 200), pants=(40, 40, 40), hair=(20, 20, 20),
                      apron=True),
    "policeman": dict(shirt=(30, 60, 140), pants=(30, 30, 70), hair=(30, 30, 30),
                      hat="cap", badge=True),
    "crowd": dict(shirt=(180, 120, 40), pants=(70, 50, 40), hair=(80, 50, 20),
                  hair_style="curly"),
    "genich": dict(shirt=(40, 40, 40), pants=(30, 30, 30), hair=(90, 90, 90),
                   bowtie=True),
    "repa": dict(shirt=(20, 20, 20), pants=(20, 20, 20), hair=(10, 10, 10),
                 bowtie=True),
    "okusheva": dict(shirt=(240, 200, 90), pants=(80, 60, 40), hair=(150, 90, 30),
                     hair_style="long", dress=True),
}

def fire_frames():
    frames = []
    for f in range(3):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        w = [13, 11, 14][f]
        h = [26, 22, 28][f]
        x0, y0 = 16 - w // 2, 30 - h
        d.ellipse([x0, y0, x0 + w, 30], fill=(230, 90, 20, 255))
        d.polygon([(16, y0 - 2), (x0 + 2, 28), (x0 + w - 2, 28)], fill=(240, 140, 30, 255))
        d.ellipse([16 - w // 4, 30 - h // 2, 16 + w // 4, 30], fill=(255, 210, 60, 255))
        frames.append(im.resize((96, 96), Image.NEAREST))
    return frames

def item(name, draw):
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw(ImageDraw.Draw(im))
    im.resize((96, 96), Image.NEAREST).save(OUT / f"{name}_0.png")

def main():
    for name, kw in CHARS.items():
        for i, fr in enumerate(human(name, **kw)):
            fr.save(OUT / f"{name}_{i}.png")
    for i, fr in enumerate(fire_frames()):
        fr.save(OUT / f"fire_{i}.png")
    # static items (single frame; engine treats 1-frame sets as static)
    item("monocle", lambda d: (d.ellipse([6, 6, 26, 26], outline=(210, 170, 60), width=3),
                               d.ellipse([10, 10, 22, 22], fill=(170, 220, 255))))
    item("extinguisher", lambda d: (d.rectangle([11, 8, 21, 28], fill=(200, 40, 40)),
                                    d.rectangle([14, 4, 18, 8], fill=(180, 180, 190)),
                                    d.arc([18, 6, 28, 16], 270, 90, fill=(30, 30, 30), width=2)))
    item("boots", lambda d: (d.rectangle([8, 6, 18, 26], fill=(120, 70, 30)),
                             d.rectangle([8, 24, 26, 28], fill=(80, 45, 20))))
    item("key", lambda d: (d.ellipse([7, 7, 15, 15], outline=(220, 180, 60), width=3),
                           d.rectangle([13, 12, 26, 15], fill=(220, 180, 60)),
                           d.rectangle([22, 15, 24, 20], fill=(220, 180, 60)),
                           d.rectangle([18, 15, 20, 18], fill=(220, 180, 60))))
    item("shoe", lambda d: (d.polygon([(6, 24), (8, 12), (14, 12), (26, 24), (26, 27), (6, 27)],
                                      fill=(140, 40, 60)),
                            d.rectangle([22, 24, 25, 30], fill=(140, 40, 60))))
    item("taxofon", lambda d: (d.rectangle([8, 4, 24, 28], fill=(40, 80, 160)),
                               d.rectangle([11, 7, 21, 15], fill=(170, 220, 255)),
                               d.rectangle([11, 18, 21, 25], fill=(220, 220, 220))))
    print(f"wrote {len(list(OUT.glob('*.png')))} PNGs to {OUT}")

if __name__ == "__main__":
    main()
