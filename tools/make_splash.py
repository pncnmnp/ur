"""Boot splash: the full painting (icons/icon_1024.png, pixel-for-pixel, no resampling)
over the game's title in the game's own font (Copperplate Bold, cream with a dark shadow).

Canvas is 3200x1800: twice the 1600x900 window, so on a Retina screen the painting is
shown at its native 1024 px. Written as lossless PNG to icons/splash.png.

    venv/bin/python tools/make_splash.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "icons" / "icon_1024.png"
OUT = ROOT / "icons" / "splash.png"
FONT = "/System/Library/Fonts/Supplemental/Copperplate.ttc"
FONT_BOLD_INDEX = 2  # Copperplate.ttc faces: 0 Regular, 1 Light, 2 Bold

W, H = 3200, 1800
BG = (22, 13, 7)  # dark warm brown, a step above the title's shadow colour
CREAM = (250, 230, 184)  # Color(0.98, 0.9, 0.72) from main.gd
SHADOW = (31, 15, 5, 179)  # Color(0.12, 0.06, 0.02, 0.7)
FRAME = (150, 112, 58)  # thin gilt line around the painting
TITLE = "The Royal Game of Ur"
FONT_SIZE = 128
GAP = 110


def main() -> None:
    logo = Image.open(LOGO).convert("RGB")
    font = ImageFont.truetype(FONT, FONT_SIZE, index=FONT_BOLD_INDEX)
    tx0, ty0, tx1, ty1 = font.getbbox(TITLE)
    text_w, text_h = tx1 - tx0, ty1 - ty0

    block_h = logo.height + GAP + text_h
    top = (H - block_h) // 2
    lx = (W - logo.width) // 2

    canvas = Image.new("RGB", (W, H), BG)

    # soft drop shadow under the painting
    shade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shade).rectangle(
        [lx + 10, top + 18, lx + logo.width + 10, top + logo.height + 18], fill=170
    )
    shade = shade.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), shade)

    # gilt frame, then the painting pasted 1:1
    d = ImageDraw.Draw(canvas)
    d.rectangle([lx - 8, top - 8, lx + logo.width + 7, top + logo.height + 7], outline=FRAME, width=3)
    canvas.paste(logo, (lx, top))

    # title: blurred shadow (offset like the in-game label, doubled for the 2x canvas), then text
    tx = (W - text_w) // 2 - tx0
    ty = top + logo.height + GAP - ty0
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx + 4, ty + 6), TITLE, font=font, fill=SHADOW)
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    ImageDraw.Draw(canvas).text((tx, ty), TITLE, font=font, fill=CREAM)

    canvas.convert("RGB").save(OUT, optimize=True)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
