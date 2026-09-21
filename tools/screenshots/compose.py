#!/usr/bin/env python3
"""Impagina gli screenshot grezzi (asc/screenshots/raw/) in pagine da vetrina
App Store 1320×2868: titolo, sottotitolo, sfondo sfumato, iPhone con cornice.
Uscita: asc/screenshots/<it|en-US>/NN.png

    python3 tools/screenshots/compose.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent.parent
RAW = ROOT / "asc" / "screenshots" / "raw"
OUT = ROOT / "asc" / "screenshots"
W, H = 1320, 2868
FONT = "/System/Library/Fonts/SFNS.ttf"

# (file grezzo, colore alto, colore basso)
SLIDES = [
    ("1_list",   "#0A5BD6", "#1FB36B"),
    ("2_detail", "#3B2FC9", "#0A84FF"),
    ("3_add",    "#E0561B", "#FF9F0A"),
    ("4_stats",  "#7B2FC9", "#D63A8E"),
]

COPY = {
    "it": [
        ("Dividi le spese.\nSenza account.", "Si sincronizza con il tuo iCloud:\ni dati restano tuoi"),
        ("Chi paga chi,\nal centesimo", "I rimborsi li calcola l'app"),
        ("Una spesa in\npochi secondi", "Scegli chi ha pagato e per chi è"),
        ("Sai dove vanno\ni soldi", "Totali, medie e categorie"),
    ],
    "en": [
        ("Split expenses.\nNo account.", "Syncs through your iCloud:\nyour data stays yours"),
        ("Who owes whom,\nto the cent", "Settle-ups worked out for you"),
        ("Add an expense\nin seconds", "Pick who paid and who it's for"),
        ("See where the\nmoney goes", "Totals, averages and categories"),
    ],
}
LOCALE_DIR = {"it": "it", "en": "en-US"}


def font(size, weight, opsz):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([100, opsz, 400, weight])  # larghezza, dim. ottica, grad, peso
    return f


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def background(top, bottom):
    a, b = hex_rgb(top), hex_rgb(bottom)
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    img = grad.resize((W, H), Image.BICUBIC)

    # Alone chiaro dietro il telefono: dà profondità senza distrarre.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-200, 1100, W + 200, 3300), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    img.paste(Image.new("RGB", (W, H), "white"), (0, 0), glow)
    return img


def fit(draw, text, size, weight, opsz, max_w):
    while True:
        f = font(size, weight, opsz)
        widest = max(draw.textlength(line, font=f) for line in text.split("\n"))
        if widest <= max_w or size < 60:
            return f
        size -= 4


def draw_text(img, title, subtitle):
    d = ImageDraw.Draw(img)
    max_w = W - 2 * 90
    tf = fit(d, title, 124, 760, 96, max_w)
    sf = fit(d, subtitle, 54, 500, 28, max_w)
    y = 190
    for line in title.split("\n"):
        d.text((W / 2, y), line, font=tf, fill="white", anchor="ma")
        y += int(tf.size * 1.12)
    y += 34
    for line in subtitle.split("\n"):
        d.text((W / 2, y), line, font=sf, fill=(255, 255, 255, 225), anchor="ma")
        y += int(sf.size * 1.3)
    return y


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return m


def place_phone(img, shot, top):
    dw = 1030
    dh = round(shot.height * dw / shot.width)
    screen = shot.convert("RGB").resize((dw, dh), Image.LANCZOS)
    r = round(dw * 0.125)  # raggio degli angoli dello schermo di un iPhone Pro Max
    bezel, rim = 24, 5

    fw, fh = dw + 2 * (bezel + rim), dh + 2 * (bezel + rim)
    x, y = (W - fw) // 2, top

    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 40, x + fw, y + fh + 40), radius=r + bezel + rim, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(55))
    img.paste(Image.new("RGB", (W, H), (10, 10, 30)), (0, 0), shadow)

    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x, y, x + fw, y + fh), radius=r + bezel + rim, fill=(58, 58, 64))
    d.rounded_rectangle((x + rim, y + rim, x + fw - rim, y + fh - rim), radius=r + bezel, fill=(8, 8, 10))
    img.paste(screen, (x + rim + bezel, y + rim + bezel), rounded_mask((dw, dh), r))


def main():
    for lang, copy in COPY.items():
        out_dir = OUT / LOCALE_DIR[lang]
        out_dir.mkdir(parents=True, exist_ok=True)
        for i, ((name, top, bottom), (title, subtitle)) in enumerate(zip(SLIDES, copy), 1):
            img = background(top, bottom)
            text_bottom = draw_text(img, title, subtitle)
            place_phone(img, Image.open(RAW / lang / f"{name}.png"), max(text_bottom + 70, 720))
            dest = out_dir / f"{i:02d}.png"
            img.save(dest, optimize=True)
            print(f"  {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
