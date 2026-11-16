#!/usr/bin/env python3
"""Convierte escaneos o fotos de firmas en PNG listos para el firmador.

Para cada imagen (PNG, JPG, TIFF, BMP) de la carpeta de entrada:
  - vuelve transparente el fondo claro (papel blanco o grisáceo),
  - conserva el color del trazo,
  - recorta al trazo y lo escala a un ancho estándar,
  - guarda <NOMBRE>.png en la carpeta de salida.

El nombre de salida se toma del nombre del archivo, normalizado al formato del
cajetín: "a callupe.jpg" o "A. CALLUPE.png" -> "A_CALLUPE.png".

Uso:
    python preparar_firmas.py escaneos/ firmas/ [--umbral 200] [--ancho 600]
"""
from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

EXTENSIONES = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp"}


def nombre_archivo(stem: str) -> str:
    s = "".join(c for c in unicodedata.normalize("NFD", stem.upper()) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^A-Z0-9]+", "_", s).strip("_") + ".png"


def preparar(origen: Path, destino: Path, umbral: int, ancho: int) -> tuple[int, int]:
    img = ImageOps.exif_transpose(Image.open(origen)).convert("RGBA")
    a = np.asarray(img).astype(float)
    rgb, alfa_orig = a[..., :3], a[..., 3]
    lum = rgb @ [0.299, 0.587, 0.114]
    # Transparencia gradual: papel (>= umbral) invisible, trazo oscuro opaco, bordes suaves.
    alfa = np.clip((umbral - lum) / max(umbral - 60, 1), 0, 1) * 255
    alfa = np.minimum(alfa, alfa_orig)
    # Eliminar motas sueltas muy tenues.
    alfa[alfa < 25] = 0
    out = Image.fromarray(np.dstack([rgb, alfa]).astype("uint8"), "RGBA")
    caja = out.getbbox()
    if caja is None:
        raise ValueError("no se detectó trazo (pruebe con un --umbral más alto)")
    margen = 4
    caja = (max(caja[0] - margen, 0), max(caja[1] - margen, 0),
            min(caja[2] + margen, out.width), min(caja[3] + margen, out.height))
    out = out.crop(caja)
    if out.width != ancho:
        out = out.resize((ancho, max(1, round(out.height * ancho / out.width))), Image.LANCZOS)
    destino.parent.mkdir(parents=True, exist_ok=True)
    out.save(destino, optimize=True)
    return out.size


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Prepara imágenes de firma (fondo transparente, recortadas).")
    ap.add_argument("entrada", type=Path, help="carpeta con escaneos o fotos de firmas")
    ap.add_argument("salida", type=Path, help="carpeta donde guardar los PNG (la que usa el firmador)")
    ap.add_argument("--umbral", type=int, default=200,
                    help="0-255: más alto quita menos fondo; bájelo si queda sombra del papel (defecto 200)")
    ap.add_argument("--ancho", type=int, default=600, help="ancho final en píxeles (defecto 600)")
    args = ap.parse_args(argv)

    archivos = sorted(p for p in args.entrada.iterdir() if p.suffix.lower() in EXTENSIONES)
    if not archivos:
        ap.error(f"no hay imágenes en {args.entrada}")
    errores = 0
    for p in archivos:
        destino = args.salida / nombre_archivo(p.stem)
        try:
            w, h = preparar(p, destino, args.umbral, args.ancho)
            print(f"{p.name:30s} -> {destino.name} ({w}x{h})")
        except Exception as e:
            errores += 1
            print(f"{p.name:30s} ERROR: {e}")
    return 1 if errores else 0


if __name__ == "__main__":
    sys.exit(main())
