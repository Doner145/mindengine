#!/usr/bin/env python3
"""Firma automática de planos PDF (cajetín Ausenco / Compañía Minera Ares).

Coloca la imagen de firma de cada persona en dos lugares:

1. Cajetín de responsables (DIBUJADO, REVISADO, DISEÑADO, DIS. APRO,
   PROY. APRO): a la izquierda del nombre, centrada en el hueco entre el
   cargo y el nombre.
2. Tabla de revisiones: para la revisión más reciente, en las columnas POR,
   REV, ING y APRO según las iniciales escritas en esa fila (CC -> C. COICA,
   AC -> A. CALLUPE, ...). La firma va en la fila vacía ("." ) justo encima de
   esa revisión; si la revisión ocupa la primera fila, va encima de la tabla.

Las posiciones se calculan buscando el texto del PDF, no con coordenadas
fijas, así que tolera pequeños desplazamientos del cajetín.

Uso:
    python firmar_planos.py PLANO.pdf [MAS.pdf | CARPETA ...] --firmas firmas/ \
        [--salida firmados/] [--solo-cajetin] [--dry-run]
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

import pdfplumber
from pypdf import PdfReader, PdfWriter
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

CARGOS = ["DIBUJADO", "REVISADO", "DISEÑADO", "DIS. APRO", "PROY. APRO"]
COLUMNAS_REV = ["POR", "REV", "ING", "APRO"]
VACIO = {"", ".", "-"}

# Geometría (puntos PDF; 1 pt = 0,353 mm). Medida sobre el ejemplo aprobado.
NOMBRE_ALTO_MAX = 11.0      # alto máximo de la firma junto al nombre
NOMBRE_ALTO_FRAC = 0.42     # ... o esta fracción del alto de fila, lo menor
NOMBRE_MARGEN = 1.5         # separación mínima con el cargo y con el nombre
REV_ALTO_MAX = 10.0         # alto máximo de la firma sobre la tabla de revisiones
REV_ANCHO_FRAC = 0.85       # ancho máximo como fracción del ancho de columna
REV_SEPARACION = 3.0        # distancia entre la firma y el borde superior de la tabla
REV_ALTO_FILA_FRAC = 0.8    # alto máximo dentro de una fila vacía de la tabla de revisiones
TOL_LINEA = 4.0             # tolerancia vertical para "misma línea de texto"
LARGO_MIN_LINEA = 20.0      # largo mínimo de un trazo para considerarlo línea de la grilla


# --------------------------------------------------------------------------- #
# Utilidades de texto
# --------------------------------------------------------------------------- #
def normalizar(texto: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", texto)).strip().upper()


def sin_tildes(texto: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")


def iniciales_de(nombre: str) -> str:
    """'C. COICA' -> 'CC', 'J. ALVARADO' -> 'JA'."""
    partes = re.findall(r"[A-ZÑ]+", sin_tildes(normalizar(nombre)))
    if not partes:
        return ""
    return (partes[0][0] + partes[-1][0]) if len(partes) > 1 else partes[0][:2]


def archivo_por_defecto(nombre: str) -> str:
    """'C. COICA' -> 'C_COICA.png'."""
    return re.sub(r"[^A-Z0-9]+", "_", sin_tildes(normalizar(nombre))).strip("_") + ".png"


# --------------------------------------------------------------------------- #
# Registro de firmas
# --------------------------------------------------------------------------- #
class Firmas:
    """Resuelve nombre o iniciales -> archivo de imagen de firma.

    Por defecto busca <carpeta>/<NOMBRE_CON_GUIONES>.png (p. ej. C_COICA.png).
    Un archivo opcional <carpeta>/personas.json permite otros nombres de
    archivo o iniciales adicionales:
        {"C. COICA": {"firma": "coica.png", "iniciales": ["CC"]}}
    """

    def __init__(self, carpeta: Path):
        self.carpeta = carpeta
        self.config: dict[str, dict] = {}
        cfg = carpeta / "personas.json"
        if cfg.exists():
            datos = json.loads(cfg.read_text(encoding="utf-8"))
            self.config = {normalizar(k): v for k, v in datos.items()}
        self._cache: dict[Path, ImageReader] = {}

    def iniciales_extra(self) -> dict[str, str]:
        return {
            normalizar(ini): nombre
            for nombre, datos in self.config.items()
            for ini in datos.get("iniciales", [])
        }

    def ruta(self, nombre: str) -> Path | None:
        nombre = normalizar(nombre)
        archivo = self.config.get(nombre, {}).get("firma") or archivo_por_defecto(nombre)
        ruta = self.carpeta / archivo
        return ruta if ruta.exists() else None

    def imagen(self, ruta: Path) -> ImageReader:
        if ruta not in self._cache:
            self._cache[ruta] = ImageReader(str(ruta))
        return self._cache[ruta]


# --------------------------------------------------------------------------- #
# Detección
# --------------------------------------------------------------------------- #
@dataclass
class Caja:
    x0: float
    top: float
    x1: float
    bottom: float

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) / 2

    @property
    def cy(self) -> float:
        return (self.top + self.bottom) / 2


@dataclass
class Ubicacion:
    pagina: int
    zona: str            # "cajetin" o "revision"
    etiqueta: str        # cargo o columna
    persona: str
    hueco: Caja          # espacio disponible donde se centra la firma
    alto_max: float
    ruta: Path | None = None
    caja_final: Caja | None = field(default=None)


def _palabras(pagina) -> list[dict]:
    ws = pagina.extract_words(keep_blank_chars=True, x_tolerance=2, use_text_flow=False)
    for w in ws:
        w["norm"] = normalizar(w["text"])
        w["cy"] = (w["top"] + w["bottom"]) / 2
        w["cx"] = (w["x0"] + w["x1"]) / 2
    return ws


def _bordes(pagina):
    # Solo líneas de grilla: se descartan trazos cortos (letras vectorizadas, sombreados).
    h = [e for e in pagina.edges if e["orientation"] == "h" and e["x1"] - e["x0"] >= LARGO_MIN_LINEA]
    v = [e for e in pagina.edges if e["orientation"] == "v" and e["bottom"] - e["top"] >= LARGO_MIN_LINEA]
    return h, v


def _limites_fila(hs, x: float, y: float, alto_defecto: float = 28.35) -> tuple[float, float]:
    cruzan = [e["top"] for e in hs if e["x0"] - 0.5 <= x <= e["x1"] + 0.5]
    arriba = [t for t in cruzan if t < y - 1]
    abajo = [t for t in cruzan if t > y + 1]
    sup = max(arriba) if arriba else y - alto_defecto / 2
    inf = min(abajo) if abajo else y + alto_defecto / 2
    return sup, inf


def detectar_cajetin(nro: int, ws, hs) -> tuple[list[Ubicacion], dict[str, str]]:
    ubic: list[Ubicacion] = []
    nombres: dict[str, str] = {}
    for cargo in CARGOS:
        for lab in (w for w in ws if w["norm"] == cargo):
            candidatos = [
                w for w in ws
                if abs(w["cy"] - lab["cy"]) < TOL_LINEA and lab["x1"] < w["x0"] < lab["x1"] + 90
                and w["norm"] not in VACIO
            ]
            if not candidatos:
                continue
            nom = min(candidatos, key=lambda w: w["x0"])
            sup, inf = _limites_fila(hs, nom["x0"], nom["cy"])
            hueco = Caja(lab["x1"] + NOMBRE_MARGEN, sup, nom["x0"] - NOMBRE_MARGEN, inf)
            alto = min(NOMBRE_ALTO_MAX, NOMBRE_ALTO_FRAC * (inf - sup))
            ubic.append(Ubicacion(nro, "cajetin", cargo, nom["norm"], hueco, alto))
            nombres[nom["norm"]] = cargo
    return ubic, nombres


def detectar_revision(nro: int, ws, hs, vs, por_iniciales: dict[str, str]) -> tuple[list[Ubicacion], list[str]]:
    avisos: list[str] = []
    # La cabecera es el "POR" que comparte línea con "FECHA" (descarta "POR" de las notas).
    cab_por = [
        w for w in ws if w["norm"] == "POR"
        and any(f["norm"] == "FECHA" and abs(f["cy"] - w["cy"]) < TOL_LINEA for f in ws)
    ]
    if not cab_por:
        return [], ["no se encontró la tabla de revisiones (cabecera POR)"]
    cab_y = cab_por[0]["cy"]
    cabecera = {w["norm"]: w for w in ws if abs(w["cy"] - cab_y) < TOL_LINEA and w["norm"] in COLUMNAS_REV + ["NO"]}

    def columna(w) -> Caja | None:
        cruzan = [e for e in vs if e["top"] - 1 <= w["cy"] <= e["bottom"] + 1]
        izq = [e for e in cruzan if e["x0"] < w["cx"]]
        der = [e for e in cruzan if e["x0"] > w["cx"]]
        if not izq or not der:
            return None
        ei = max(izq, key=lambda e: e["x0"])
        ed = min(der, key=lambda e: e["x0"])
        return Caja(ei["x0"], min(ei["top"], ed["top"]), ed["x0"], max(ei["bottom"], ed["bottom"]))

    cols = {k: columna(w) for k, w in cabecera.items()}
    if "NO" not in cols or cols["NO"] is None:
        return [], ["no se encontró la columna 'No' de la tabla de revisiones"]

    col_no = cols["NO"]
    filas = sorted(
        (w for w in ws if col_no.x0 < w["cx"] < col_no.x1 and col_no.top < w["cy"] < cab_y - TOL_LINEA),
        key=lambda w: w["top"],
    )
    ultima = next((w for w in filas if w["norm"] not in VACIO), None)
    if ultima is None:
        return [], ["la tabla de revisiones está vacía"]

    ubic: list[Ubicacion] = []
    for nombre_col in COLUMNAS_REV:
        col = cols.get(nombre_col)
        if col is None:
            avisos.append(f"columna {nombre_col} no encontrada")
            continue
        celda = [
            w for w in ws
            if col.x0 < w["cx"] < col.x1 and abs(w["cy"] - ultima["cy"]) < TOL_LINEA
        ]
        ini = celda[0]["norm"] if celda else ""
        if ini in VACIO:
            continue
        persona = por_iniciales.get(ini)
        if persona is None:
            avisos.append(f"rev {ultima['norm']}, columna {nombre_col}: iniciales '{ini}' sin persona asociada")
            continue
        ancho = (col.x1 - col.x0) * REV_ANCHO_FRAC
        etiqueta = f"{nombre_col} (rev {ultima['norm']})"
        # Fila de la última revisión y, si existe, la fila (vacía) inmediatamente encima.
        sup, _ = _limites_fila(hs, col.cx, ultima["cy"], alto_defecto=14.17)
        if sup - col.top > 2:
            sup_ant, _ = _limites_fila(hs, col.cx, sup - 2, alto_defecto=2 * (ultima["cy"] - sup))
            sup_ant = max(sup_ant, col.top)
            alto = min(REV_ALTO_MAX, REV_ALTO_FILA_FRAC * (sup - sup_ant))
            hueco = Caja(col.cx - ancho / 2, sup_ant, col.cx + ancho / 2, sup)
            u = Ubicacion(nro, "revision", etiqueta + " fila sup.", persona, hueco, alto)
        else:
            # La última revisión ocupa la primera fila: se firma encima de la tabla.
            fondo = col.top - REV_SEPARACION
            hueco = Caja(col.cx - ancho / 2, fondo - REV_ALTO_MAX, col.cx + ancho / 2, fondo)
            u = Ubicacion(nro, "revision", etiqueta + " sobre tabla", persona, hueco, REV_ALTO_MAX)
            u.anclar_abajo = True  # type: ignore[attr-defined]
        ubic.append(u)
    return ubic, avisos


def encajar(ubic: Ubicacion, img: ImageReader) -> Caja:
    ancho_img, alto_img = img.getSize()
    proporcion = ancho_img / alto_img
    disp_w = max(ubic.hueco.x1 - ubic.hueco.x0, 1.0)
    h = ubic.alto_max
    w = h * proporcion
    if w > disp_w:
        w, h = disp_w, disp_w / proporcion
    cx = ubic.hueco.cx
    if getattr(ubic, "anclar_abajo", False):
        bottom = ubic.hueco.bottom
        return Caja(cx - w / 2, bottom - h, cx + w / 2, bottom)
    cy = ubic.hueco.cy
    return Caja(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)


# --------------------------------------------------------------------------- #
# Proceso
# --------------------------------------------------------------------------- #
def firmar(entrada: Path, salida: Path, firmas: Firmas, solo_cajetin: bool, dry_run: bool,
           personas: set[str] | None = None, informe: list[dict] | None = None) -> bool:
    """Firma un PDF. `personas` limita la firma a esas personas (None = todas)."""
    informe = informe if informe is not None else []

    def anotar(pag, zona, etiqueta, persona, estado):
        informe.append({"plano": entrada.name, "pagina": pag, "zona": zona, "casilla": etiqueta,
                        "persona": persona, "estado": estado})

    print(f"\n== {entrada.name}")
    planes: list[tuple[int, list[Ubicacion]]] = []
    hubo_firmas = False
    with pdfplumber.open(entrada) as pdf:
        for nro, pagina in enumerate(pdf.pages):
            ws = _palabras(pagina)
            hs, vs = _bordes(pagina)
            ubic, nombres = detectar_cajetin(nro, ws, hs)
            if not ubic:
                print(f"  pág {nro + 1}: no se encontró el cajetín de responsables")
                anotar(nro + 1, "", "", "", "sin cajetín")
                continue
            por_iniciales = {iniciales_de(n): n for n in nombres}
            por_iniciales.update(firmas.iniciales_extra())
            if not solo_cajetin:
                rev, avisos = detectar_revision(nro, ws, hs, vs, por_iniciales)
                ubic += rev
                for a in avisos:
                    print(f"  pág {nro + 1}: AVISO {a}")
                    anotar(nro + 1, "revision", "", "", "aviso: " + a)
            if personas is not None:
                ubic = [u for u in ubic if u.persona in personas]
            for u in ubic:
                u.ruta = firmas.ruta(u.persona)
                if u.ruta is None:
                    print(f"  pág {nro + 1}: FALTA firma de {u.persona} "
                          f"(se esperaba {firmas.carpeta / archivo_por_defecto(u.persona)}) -> {u.etiqueta} sin firmar")
                    anotar(nro + 1, u.zona, u.etiqueta, u.persona, "falta imagen de firma")
                    continue
                anotar(nro + 1, u.zona, u.etiqueta, u.persona, "a firmar" if dry_run else "firmado")
                u.caja_final = encajar(u, firmas.imagen(u.ruta))
                c = u.caja_final
                print(f"  pág {nro + 1}: {u.zona:8s} {u.etiqueta:16s} {u.persona:14s} "
                      f"x={c.x0:7.1f}-{c.x1:7.1f} y={c.top:7.1f}-{c.bottom:7.1f}  [{u.ruta.name}]")
                hubo_firmas = True
            planes.append((nro, ubic))

    if dry_run or not hubo_firmas:
        if not hubo_firmas:
            print("  nada que firmar; no se genera archivo")
        return hubo_firmas

    lector = PdfReader(str(entrada))
    escritor = PdfWriter()
    planes_por_pag = dict(planes)
    for nro, pagina in enumerate(lector.pages):
        ubic = [u for u in planes_por_pag.get(nro, []) if u.caja_final]
        if ubic:
            if int(pagina.get("/Rotate", 0) or 0) % 360:
                print(f"  pág {nro + 1}: AVISO página rotada; revise la posición de las firmas")
            mb = pagina.mediabox
            ancho, alto = float(mb.width), float(mb.height)
            buf = io.BytesIO()
            cv = canvas.Canvas(buf, pagesize=(ancho, alto))
            for u in ubic:
                c = u.caja_final
                cv.drawImage(firmas.imagen(u.ruta), c.x0, alto - c.bottom,
                             c.x1 - c.x0, c.bottom - c.top, mask="auto")
            cv.save()
            capa = PdfReader(buf).pages[0]
            if float(mb.left) or float(mb.bottom):
                from pypdf import Transformation
                capa.add_transformation(Transformation().translate(float(mb.left), float(mb.bottom)))
            pagina.merge_page(capa)
        escritor.add_page(pagina)
    if lector.metadata:
        escritor.add_metadata(dict(lector.metadata))
    salida.parent.mkdir(parents=True, exist_ok=True)
    with open(salida, "wb") as f:
        escritor.write(f)
    print(f"  -> {salida}")
    return True


def recolectar(rutas: list[str]) -> list[tuple[Path, Path]]:
    """Devuelve (pdf, ruta relativa) buscando también en subcarpetas."""
    pdfs: list[tuple[Path, Path]] = []
    for r in rutas:
        p = Path(r)
        if p.is_dir():
            pdfs += [(x, x.relative_to(p)) for x in sorted(p.rglob("*"))
                     if x.suffix.lower() == ".pdf" and not x.stem.endswith("_firmado")]
        elif p.suffix.lower() == ".pdf" and p.exists():
            pdfs.append((p, Path(p.name)))
        else:
            print(f"AVISO: se ignora {r}")
    return pdfs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Firma automática de planos PDF junto al nombre.")
    ap.add_argument("entradas", nargs="+", help="PDF(s) o carpeta(s) con PDFs")
    ap.add_argument("--firmas", required=True, type=Path, help="carpeta con las imágenes PNG de firma")
    ap.add_argument("--salida", type=Path, help="carpeta de salida (por defecto, junto al original)")
    ap.add_argument("--solo-cajetin", action="store_true", help="no firmar la tabla de revisiones")
    ap.add_argument("--dry-run", action="store_true", help="solo mostrar dónde se firmaría")
    ap.add_argument("--persona", action="append", metavar="NOMBRE",
                    help='firmar solo las casillas de esta persona, tal como figura en el cajetín '
                         '(p. ej. --persona "A. CALLUPE"); se puede repetir')
    ap.add_argument("--informe", type=Path,
                    help="ruta del informe CSV (por defecto informe_firmas.csv en la carpeta de salida)")
    args = ap.parse_args(argv)

    if not args.firmas.is_dir():
        ap.error(f"no existe la carpeta de firmas: {args.firmas}")
    firmas = Firmas(args.firmas)
    pdfs = recolectar(args.entradas)
    if not pdfs:
        ap.error("no se encontraron PDFs")
    personas = {normalizar(p) for p in args.persona} if args.persona else None
    informe: list[dict] = []
    ok = 0
    for pdf, rel in pdfs:
        destino = (args.salida / rel.parent if args.salida else pdf.parent) / f"{pdf.stem}_firmado.pdf"
        try:
            ok += firmar(pdf, destino, firmas, args.solo_cajetin, args.dry_run, personas, informe)
        except Exception as e:  # sigue con el resto del lote
            print(f"  ERROR en {pdf.name}: {e}")
            informe.append({"plano": pdf.name, "pagina": "", "zona": "", "casilla": "",
                            "persona": "", "estado": f"error: {e}"})

    ruta_informe = args.informe or (args.salida or Path(".")) / "informe_firmas.csv"
    ruta_informe.parent.mkdir(parents=True, exist_ok=True)
    with open(ruta_informe, "w", newline="", encoding="utf-8-sig") as f:  # utf-8-sig: Excel abre bien las tildes
        w = csv.DictWriter(f, fieldnames=["plano", "pagina", "zona", "casilla", "persona", "estado"], delimiter=";")
        w.writeheader()
        w.writerows(informe)

    faltan = sorted({r["persona"] for r in informe if r["estado"] == "falta imagen de firma"})
    print(f"\n{ok}/{len(pdfs)} plano(s) {'analizados' if args.dry_run else 'firmados'}")
    if faltan:
        print("Faltan imágenes de firma de: " + ", ".join(faltan))
    print(f"Informe: {ruta_informe}")
    return 0 if ok == len(pdfs) and not faltan else 1


if __name__ == "__main__":
    sys.exit(main())
