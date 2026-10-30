"""Genera assets/branding/nuvora_foreground.png a partir del logo.

El ícono adaptativo de Android pone su propio fondo (#10121B) y recorta la
forma (círculo, squircle…). Este script deja solo el contenido del logo
(corchetes, hoja y brillo) sobre transparente: quita el recuadro oscuro y su
filo claro para que no se vean sobre el fondo del sistema.

Uso:  python3 tool/make_adaptive_foreground.py
Luego: dart run flutter_launcher_icons
"""

import math

from PIL import Image, ImageChops, ImageDraw

SRC = "assets/branding/nuvora.png"
DST = "assets/branding/nuvora_foreground.png"
BG = (16, 18, 27)  # color del recuadro del logo
RIM_SHRINK = 24  # px que se recortan del recuadro para quitar su filo claro
CORNER_RADIUS = 230


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    px = src.load()
    w, h = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    po = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            # Solo cuenta lo más claro que el fondo; lo cercano al fondo se vuelve transparente.
            dr, dg, db = max(0, r - BG[0]), max(0, g - BG[1]), max(0, b - BG[2])
            k = max(0.0, min(1.0, (math.sqrt(dr * dr + dg * dg + db * db) - 10) / 45))
            if k <= 0:
                continue
            # "Des-mezcla" el color con el fondo para no dejar un halo oscuro.
            c = [int(max(0, min(255, (v - bgv * (1 - k)) / k))) for v, bgv in zip((r, g, b), BG)]
            po[x, y] = (c[0], c[1], c[2], int(a * k))

    x0, y0, x1, y1 = src.split()[3].getbbox()
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (x0 + RIM_SHRINK, y0 + RIM_SHRINK, x1 - RIM_SHRINK, y1 - RIM_SHRINK),
        radius=CORNER_RADIUS - RIM_SHRINK,
        fill=255,
    )
    r, g, b, a = out.split()
    Image.merge("RGBA", (r, g, b, ImageChops.multiply(a, mask))).save(DST)


if __name__ == "__main__":
    main()
