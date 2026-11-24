@echo off & setlocal & goto :inicio
r"""
===============================================================================
 FIRMADOR AUTOMATICO DE PLANOS  -  un solo archivo
-------------------------------------------------------------------------------
 Uso:   doble clic en firmar.bat, arrastre a la ventana los PDF o la carpeta
        (o pegue la ruta) y presione Enter.
        Tambien puede arrastrar los PDF / la carpeta sobre este archivo.

 Carpetas junto a este archivo (se crean solas):
   firmas\     una imagen por persona (JPG/PNG, cualquier fondo claro).
               El nombre del archivo debe contener nombre y apellido:
               "Christopher Coica.jpg", "Firma de Juan Alvarado.png"...
               Se reconoce por inicial + apellido: C. COICA, J. ALVARADO.
               Opcional: firmas\equivalencias.txt (ver ayuda en pantalla).
   firmados\   planos firmados + informe_firmas.csv + revision_firmas.png
   python\     Python portable (se descarga solo la primera vez, ~50 MB)

 Este archivo es a la vez script de Windows (esta parte) y programa Python
 (despues de las comillas). Windows ejecuta solo esta parte, que prepara
 Python y luego se ejecuta a si mismo con "python -x".
===============================================================================
:inicio
rem Se reabre dentro de una consola que no se cierra sola: si algo falla,
rem el mensaje queda en pantalla.
if "%FIRMADOR_CONSOLA%"=="1" goto :principal
set "FIRMADOR_CONSOLA=1"
cmd /k ""%~f0" %*"
exit /b

:principal
title Firmador de planos
set "AQUI=%~dp0"
set "PY=%AQUI%python\python.exe"
set "PYVER=3.12.7"
set "LIBS=pdfplumber pypdf reportlab pillow"
set "PYTHONUTF8=1"
echo Firmador de planos
echo Carpeta: %AQUI%
echo.

call :instalar || goto :fin

echo Iniciando el firmador...
rem Sin argumentos: el programa pide arrastrar o pegar las rutas en la ventana.
if "%~1"=="" (
  "%PY%" -x "%~f0"
  if errorlevel 1 goto :fin
  exit
)
rem Rutas arrastradas sobre el archivo (fuera de un bloque por si llevan parentesis).
"%PY%" -x "%~f0" %*

:fin
echo.
pause
exit

rem ---------------------------------------------------------------------------
rem Prepara un Python portable en "python\" (solo la primera vez).
rem No instala nada en Windows ni requiere permisos de administrador.
rem Si la carpeta quedo incompleta (archivos borrados), la vuelve a crear.
rem ---------------------------------------------------------------------------
:instalar
echo Comprobando Python...
if exist "%PY%" (
  "%PY%" -c "import pdfplumber, pypdf, reportlab, PIL" >nul 2>&1 && exit /b 0
  "%PY%" -c "pass" >nul 2>&1 || (
    echo La carpeta "python" esta incompleta o danada: se vuelve a instalar.
    rmdir /s /q "%AQUI%python"
  )
)
if exist "%AQUI%python\" if not exist "%PY%" rmdir /s /q "%AQUI%python"
echo Preparando Python %PYVER% portable y librerias (~50 MB, solo la primera vez).
echo.
set "ARQ=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARQ=arm64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "ARQ=win32"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -Command $ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12';"
if not exist "%PY%" (
  echo [1/3] Python %PYVER% [%ARQ%]...
  %PS% "$z=Join-Path $env:TEMP 'python-embed-firmador.zip'; Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/%PYVER%/python-%PYVER%-embed-%ARQ%.zip' -OutFile $z; Expand-Archive -Force -Path $z -DestinationPath '%AQUI%python'; Remove-Item $z; $f=Get-ChildItem '%AQUI%python\python*._pth' | Select-Object -First 1; (Get-Content $f.FullName) -replace '^#\s*import site','import site' | Set-Content $f.FullName" || goto :error_descarga
)
"%PY%" -c "pass" >nul 2>&1 || goto :error_bloqueado
"%PY%" -m pip --version >nul 2>&1 || (
  echo [2/3] pip...
  %PS% "Invoke-WebRequest -UseBasicParsing -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%AQUI%python\get-pip.py'" || goto :error_descarga
  "%PY%" "%AQUI%python\get-pip.py" --no-warn-script-location -q || goto :error_descarga
)
echo [3/3] Librerias...
"%PY%" -m pip install --no-warn-script-location --disable-pip-version-check -q %LIBS% || goto :error_descarga
"%PY%" -c "import pdfplumber, pypdf, reportlab, PIL" || goto :error_descarga
rem Solo python.exe es necesario: se borran los demas ejecutables.
del /q "%AQUI%python\pythonw.exe" "%AQUI%python\Scripts\*.exe" "%AQUI%python\get-pip.py" >nul 2>&1
echo Instalacion lista.
echo.
exit /b 0

:error_descarga
echo.
echo ERROR: no se pudo descargar o instalar Python.
echo  - Revise la conexion a internet.
echo  - Si hay proxy o bloqueo de descargas, pida acceso a www.python.org,
echo    bootstrap.pypa.io, pypi.org y files.pythonhosted.org
echo  - Para reintentar desde cero, borre la carpeta "python".
exit /b 1

:error_bloqueado
echo.
echo ERROR: Windows no permite ejecutar:
echo   %PY%
echo Suele ser el antivirus o una directiva de la empresa que bloquea
echo programas fuera de "Archivos de programa". Pida a TI que autorice ese
echo archivo, o mueva la carpeta del firmador a una ubicacion permitida.
exit /b 1
"""
# =============================================================================
#  Programa Python
# =============================================================================
from __future__ import annotations

import argparse
import csv
import io
import os
import re
import sys
import traceback
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import pdfplumber
from PIL import Image, ImageDraw, ImageOps
from pypdf import PdfReader, PdfWriter, Transformation
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

# -----------------------------------------------------------------------------
#  Configuración (puntos PDF; 1 pt = 0,353 mm)
# -----------------------------------------------------------------------------
CARGOS = ("DIBUJADO", "REVISADO", "DISEÑADO", "DIS. APRO", "PROY. APRO")
COLUMNAS_REVISION = ("POR", "REV", "ING", "APRO")
CELDA_VACIA = {"", ".", "-"}

ALTO_FIRMA_CAJETIN = 11.0      # alto máximo junto al nombre
FRACCION_FILA_CAJETIN = 0.42   # ... o esta fracción del alto de la fila (lo menor)
MARGEN_CAJETIN = 1.5           # separación mínima con el cargo y con el nombre
ALTO_FIRMA_REVISION = 10.0     # alto máximo en la tabla de revisiones
FRACCION_FILA_REVISION = 0.8   # ... dentro de una fila vacía
FRACCION_COLUMNA_REVISION = 0.85
SEPARACION_SOBRE_TABLA = 3.0   # cuando se firma encima de la tabla
TOLERANCIA_LINEA = 4.0         # diferencia vertical para "misma línea de texto"
LARGO_MINIMO_LINEA = 20.0      # trazos más cortos no son líneas de la grilla

EXTENSIONES_IMAGEN = {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp", ".gif"}
PALABRAS_IGNORADAS = {"FIRMA", "FIRMAS", "DE", "DEL", "LA", "ING", "ARQ", "PNG", "JPG", "JPEG"}
ANCHO_MAXIMO_FIRMA_PX = 800
ARCHIVO_EQUIVALENCIAS = "equivalencias.txt"


# -----------------------------------------------------------------------------
#  Texto
# -----------------------------------------------------------------------------
def normalizar(texto: str) -> str:
    """Mayúsculas, espacios simples, NFC (conserva tildes para comparar cargos)."""
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", texto)).strip().upper()


def sin_tildes(texto: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")


def decodificar_nombre(nombre: str) -> str:
    """Repara nombres de ZIP con caracteres escapados: 'Luis #U00d1ope' -> 'Luis Ñope'."""
    return re.sub(r"#U([0-9A-Fa-f]{4})", lambda m: chr(int(m.group(1), 16)), nombre)


def palabras_de(nombre: str) -> list[str]:
    """'Firma de Juan_Alvarado 1' -> ['JUAN', 'ALVARADO']."""
    limpio = sin_tildes(decodificar_nombre(nombre)).upper()
    return [p for p in re.findall(r"[A-Z]+", limpio) if p not in PALABRAS_IGNORADAS]


def clave_persona(nombre: str) -> tuple[str, str] | None:
    """('C', 'COICA') para 'C. COICA' o 'Christopher Coica'."""
    p = palabras_de(nombre)
    return (p[0][0], p[-1]) if len(p) >= 2 else None


def iniciales_de(nombre: str) -> str:
    clave = clave_persona(nombre)
    return clave[0] + clave[1][0] if clave else ""


# -----------------------------------------------------------------------------
#  Firmas
# -----------------------------------------------------------------------------
def limpiar_firma(ruta: Path) -> Image.Image:
    """Abre una firma y devuelve RGBA con fondo transparente, recortada al trazo."""
    with Image.open(ruta) as original:
        img = ImageOps.exif_transpose(original).convert("RGBA")
    alfa = img.getchannel("A")
    if alfa.getextrema()[0] > 250:
        # Sin transparencia: el papel se estima con el tono claro dominante.
        gris = img.convert("L")
        hist = gris.histogram()
        total, acumulado, papel = sum(hist), 0, 255
        for tono in range(255, -1, -1):          # percentil 70 desde el lado claro
            acumulado += hist[tono]
            if acumulado >= total * 0.3:
                papel = tono
                break
        umbral = max(min(papel - 30, 235), 110)
        rango = max(umbral - 40, 1)
        alfa = gris.point(lambda v: 0 if v >= umbral else min(255, int((umbral - v) * 255 / rango)))
    alfa = alfa.point(lambda v: 0 if v < 25 else v)   # quita motas tenues
    # Firmas tenues: se refuerza la opacidad para que el trazo más fuerte quede opaco.
    hist = alfa.histogram()
    trazo = sum(hist[25:])
    if trazo:
        acumulado, fuerte = 0, 255
        for nivel in range(255, 24, -1):                  # percentil 95 del trazo
            acumulado += hist[nivel]
            if acumulado >= trazo * 0.05:
                fuerte = nivel
                break
        if fuerte < 230:
            alfa = alfa.point(lambda v: min(255, round(v * 255 / fuerte)))
    img.putalpha(alfa)
    caja = alfa.getbbox()
    if caja is None:
        raise ValueError("no se detectó trazo")
    m = 4
    img = img.crop((max(caja[0] - m, 0), max(caja[1] - m, 0),
                    min(caja[2] + m, img.width), min(caja[3] + m, img.height)))
    if img.width > ANCHO_MAXIMO_FIRMA_PX:
        alto = round(img.height * ANCHO_MAXIMO_FIRMA_PX / img.width)
        img = img.resize((ANCHO_MAXIMO_FIRMA_PX, alto), Image.LANCZOS)
    return img


class RegistroFirmas:
    """Encuentra la firma de cada persona en la carpeta de firmas.

    Reglas, en orden:
      1. equivalencias.txt:  "A. CALLUPE = Alex Callupe.png"  o  "JQ = J. QUISPE"
      2. archivo cuyo nombre coincide exactamente con la persona
      3. archivo con la misma inicial y el mismo apellido:
         "C. COICA" -> "Christopher Coica.jpg", "Firma de Carlos Coica.png"
    """

    def __init__(self, carpeta: Path):
        self.carpeta = carpeta
        self.archivos = sorted(p for p in carpeta.iterdir()
                               if p.is_file() and p.suffix.lower() in EXTENSIONES_IMAGEN)
        self.equivalencias = self._leer_equivalencias(carpeta / ARCHIVO_EQUIVALENCIAS)
        self._busquedas: dict[str, Path | None] = {}
        self._imagenes: dict[Path, Image.Image] = {}
        self._lectores: dict[Path, ImageReader] = {}

    @staticmethod
    def _leer_equivalencias(ruta: Path) -> dict[str, str]:
        if not ruta.exists():
            return {}
        datos = {}
        for linea in ruta.read_text(encoding="utf-8-sig").splitlines():
            linea = linea.split("#", 1)[0].strip()
            if "=" in linea:
                clave, valor = (s.strip() for s in linea.split("=", 1))
                if clave and valor:
                    datos[normalizar(clave)] = valor
        return datos

    def personas_por_iniciales(self) -> dict[str, str]:
        """Equivalencias del tipo 'JQ = J. QUISPE' (claves de 2-3 letras)."""
        return {k: normalizar(v) for k, v in self.equivalencias.items() if re.fullmatch(r"[A-ZÑ]{2,3}", k)}

    def buscar(self, persona: str) -> Path | None:
        if persona not in self._busquedas:
            self._busquedas[persona] = self._buscar(persona)
        return self._busquedas[persona]

    def _buscar(self, persona: str) -> Path | None:
        objetivo = self.equivalencias.get(normalizar(persona), persona)
        directo = self.carpeta / objetivo
        if directo.is_file():
            return directo
        exactos = [p for p in self.archivos if palabras_de(p.stem) == palabras_de(objetivo)]
        if exactos:
            return exactos[0]
        clave = clave_persona(objetivo)
        if clave is None:
            return None
        inicial, apellido = clave
        candidatos = [p for p in self.archivos
                      if (pal := palabras_de(p.stem)) and len(pal) >= 2
                      and pal[0][0] == inicial and apellido in pal[1:]]
        distintos = {p.read_bytes() for p in candidatos}
        if len(distintos) > 1:
            print(f"AVISO varias firmas posibles para {persona}: {', '.join(p.name for p in candidatos)}; "
                  f"se usa {candidatos[0].name} (defina cuál en {ARCHIVO_EQUIVALENCIAS})")
        return candidatos[0] if candidatos else None

    def imagen(self, ruta: Path) -> Image.Image:
        if ruta not in self._imagenes:
            self._imagenes[ruta] = limpiar_firma(ruta)
        return self._imagenes[ruta]

    def lector(self, ruta: Path) -> ImageReader:
        if ruta not in self._lectores:
            self._lectores[ruta] = ImageReader(self.imagen(ruta))
        return self._lectores[ruta]


# -----------------------------------------------------------------------------
#  Geometría y lectura de la página
# -----------------------------------------------------------------------------
@dataclass(frozen=True)
class Caja:
    x0: float
    top: float
    x1: float
    bottom: float

    @property
    def ancho(self) -> float:
        return self.x1 - self.x0

    @property
    def alto(self) -> float:
        return self.bottom - self.top

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) / 2

    @property
    def cy(self) -> float:
        return (self.top + self.bottom) / 2


@dataclass
class Casilla:
    """Lugar donde debe ir una firma."""
    pagina: int
    zona: str             # "cajetín" o "revisión"
    etiqueta: str         # cargo o columna
    persona: str
    hueco: Caja           # espacio disponible
    alto_max: float
    anclar_abajo: bool = False   # True: la firma se apoya en el borde inferior del hueco

    def ubicar(self, ancho_img: int, alto_img: int) -> Caja:
        """Caja final de la firma, conservando proporción, dentro del hueco."""
        proporcion = ancho_img / alto_img
        alto = self.alto_max
        ancho = alto * proporcion
        if ancho > self.hueco.ancho:
            ancho, alto = self.hueco.ancho, self.hueco.ancho / proporcion
        cx = self.hueco.cx
        if self.anclar_abajo:
            return Caja(cx - ancho / 2, self.hueco.bottom - alto, cx + ancho / 2, self.hueco.bottom)
        cy = self.hueco.cy
        return Caja(cx - ancho / 2, cy - alto / 2, cx + ancho / 2, cy + alto / 2)


@dataclass
class Palabra:
    texto: str
    caja: Caja


class Pagina:
    """Texto y líneas de grilla de una página."""

    def __init__(self, numero: int, pagina):
        self.numero = numero
        self.palabras = [
            Palabra(normalizar(w["text"]), Caja(w["x0"], w["top"], w["x1"], w["bottom"]))
            for w in pagina.extract_words(keep_blank_chars=True, x_tolerance=2)
        ]
        bordes = pagina.edges
        self.horizontales = [e for e in bordes if e["orientation"] == "h" and e["x1"] - e["x0"] >= LARGO_MINIMO_LINEA]
        self.verticales = [e for e in bordes if e["orientation"] == "v" and e["bottom"] - e["top"] >= LARGO_MINIMO_LINEA]

    def buscar(self, texto: str) -> list[Palabra]:
        return [p for p in self.palabras if p.texto == texto]

    def en_linea(self, y: float) -> list[Palabra]:
        return [p for p in self.palabras if abs(p.caja.cy - y) < TOLERANCIA_LINEA]

    def limites_fila(self, x: float, y: float, alto_defecto: float) -> tuple[float, float]:
        """Líneas horizontales inmediatamente encima y debajo del punto (x, y)."""
        ys = [e["top"] for e in self.horizontales if e["x0"] - 0.5 <= x <= e["x1"] + 0.5]
        arriba = [t for t in ys if t < y - 1]
        abajo = [t for t in ys if t > y + 1]
        return (max(arriba) if arriba else y - alto_defecto / 2,
                min(abajo) if abajo else y + alto_defecto / 2)

    def columna(self, x: float, y: float) -> Caja | None:
        """Celda vertical (entre dos líneas) que contiene el punto (x, y)."""
        cruzan = [e for e in self.verticales if e["top"] - 1 <= y <= e["bottom"] + 1]
        izq = [e for e in cruzan if e["x0"] < x]
        der = [e for e in cruzan if e["x0"] > x]
        if not izq or not der:
            return None
        a = max(izq, key=lambda e: e["x0"])
        b = min(der, key=lambda e: e["x0"])
        return Caja(a["x0"], min(a["top"], b["top"]), b["x0"], max(a["bottom"], b["bottom"]))


# -----------------------------------------------------------------------------
#  Detección de casillas
# -----------------------------------------------------------------------------
def casillas_cajetin(pag: Pagina) -> list[Casilla]:
    """Cajetín de responsables: firma a la izquierda del nombre."""
    casillas = []
    for cargo in CARGOS:
        for etiqueta in pag.buscar(cargo):
            derecha = [p for p in pag.en_linea(etiqueta.caja.cy)
                       if etiqueta.caja.x1 < p.caja.x0 < etiqueta.caja.x1 + 90 and p.texto not in CELDA_VACIA]
            if not derecha:
                continue
            nombre = min(derecha, key=lambda p: p.caja.x0)
            arriba, abajo = pag.limites_fila(nombre.caja.x0, nombre.caja.cy, alto_defecto=28.35)
            hueco = Caja(etiqueta.caja.x1 + MARGEN_CAJETIN, arriba, nombre.caja.x0 - MARGEN_CAJETIN, abajo)
            alto = min(ALTO_FIRMA_CAJETIN, FRACCION_FILA_CAJETIN * (abajo - arriba))
            casillas.append(Casilla(pag.numero, "cajetín", cargo, nombre.texto, hueco, alto))
    return casillas


def casillas_revision(pag: Pagina, por_iniciales: dict[str, str]) -> tuple[list[Casilla], list[str]]:
    """Tabla de revisiones: firma la revisión más reciente (POR, REV, ING, APRO).

    Si encima de esa revisión hay una fila vacía, la firma va en esa fila;
    si la revisión ocupa la primera fila, va encima del borde de la tabla.
    """
    cabecera_por = [p for p in pag.buscar("POR") if any(q.texto == "FECHA" for q in pag.en_linea(p.caja.cy))]
    if not cabecera_por:
        return [], ["no se encontró la tabla de revisiones"]
    y_cabecera = cabecera_por[0].caja.cy
    cabecera = {p.texto: p for p in pag.en_linea(y_cabecera) if p.texto in COLUMNAS_REVISION + ("NO",)}
    columnas = {k: pag.columna(p.caja.cx, p.caja.cy) for k, p in cabecera.items()}

    col_no = columnas.get("NO")
    if col_no is None:
        return [], ["no se encontró la columna 'No' de la tabla de revisiones"]
    numeros = sorted((p for p in pag.palabras
                      if col_no.x0 < p.caja.cx < col_no.x1 and col_no.top < p.caja.cy < y_cabecera - TOLERANCIA_LINEA),
                     key=lambda p: p.caja.top)
    ultima = next((p for p in numeros if p.texto not in CELDA_VACIA), None)
    if ultima is None:
        return [], ["la tabla de revisiones está vacía"]

    casillas, avisos = [], []
    for nombre_col in COLUMNAS_REVISION:
        col = columnas.get(nombre_col)
        if col is None:
            avisos.append(f"columna {nombre_col} no encontrada")
            continue
        celda = [p for p in pag.en_linea(ultima.caja.cy) if col.x0 < p.caja.cx < col.x1]
        iniciales = celda[0].texto if celda else ""
        if iniciales in CELDA_VACIA:
            continue
        persona = por_iniciales.get(iniciales)
        etiqueta = f"{nombre_col} rev {ultima.texto}"
        if persona is None:
            avisos.append(f"{etiqueta}: iniciales '{iniciales}' sin persona asociada")
            continue

        ancho = col.ancho * FRACCION_COLUMNA_REVISION
        arriba_fila, _ = pag.limites_fila(col.cx, ultima.caja.cy, alto_defecto=14.17)
        if arriba_fila - col.top > 2:      # hay una fila encima: firmar dentro de ella
            arriba_ant, _ = pag.limites_fila(col.cx, arriba_fila - 2, alto_defecto=14.17)
            arriba_ant = max(arriba_ant, col.top)
            hueco = Caja(col.cx - ancho / 2, arriba_ant, col.cx + ancho / 2, arriba_fila)
            alto = min(ALTO_FIRMA_REVISION, FRACCION_FILA_REVISION * hueco.alto)
            casillas.append(Casilla(pag.numero, "revisión", etiqueta, persona, hueco, alto))
        else:                              # primera fila: firmar sobre la tabla
            base = col.top - SEPARACION_SOBRE_TABLA
            hueco = Caja(col.cx - ancho / 2, base - ALTO_FIRMA_REVISION, col.cx + ancho / 2, base)
            casillas.append(Casilla(pag.numero, "revisión", etiqueta, persona, hueco,
                                    ALTO_FIRMA_REVISION, anclar_abajo=True))
    return casillas, avisos


# -----------------------------------------------------------------------------
#  Firma de un PDF
# -----------------------------------------------------------------------------
@dataclass
class Opciones:
    solo_cajetin: bool = False
    simular: bool = False
    personas: set[str] | None = None


class Informe:
    CAMPOS = ("plano", "pagina", "zona", "casilla", "persona", "archivo_firma", "estado")

    def __init__(self):
        self.filas: list[dict] = []

    def agregar(self, plano: str, estado: str, casilla: Casilla | None = None,
                archivo: Path | None = None, pagina: int | None = None):
        numero = casilla.pagina if casilla else pagina
        self.filas.append({
            "plano": plano,
            "pagina": numero + 1 if numero is not None else "",
            "zona": casilla.zona if casilla else "",
            "casilla": casilla.etiqueta if casilla else "",
            "persona": casilla.persona if casilla else "",
            "archivo_firma": archivo.name if archivo else "",
            "estado": estado,
        })

    def guardar(self, ruta: Path):
        ruta.parent.mkdir(parents=True, exist_ok=True)
        with open(ruta, "w", newline="", encoding="utf-8-sig") as f:   # utf-8-sig: Excel lee bien las tildes
            escritor = csv.DictWriter(f, fieldnames=self.CAMPOS, delimiter=";")
            escritor.writeheader()
            escritor.writerows(self.filas)


def detectar(entrada: Path, firmas: RegistroFirmas, op: Opciones, informe: Informe) -> dict[int, list[tuple[Casilla, Path, Caja]]]:
    """Devuelve, por página, las firmas a estampar: (casilla, archivo, caja)."""
    plan: dict[int, list[tuple[Casilla, Path, Caja]]] = {}
    with pdfplumber.open(entrada) as pdf:
        for numero, pagina_pdf in enumerate(pdf.pages):
            pag = Pagina(numero, pagina_pdf)
            casillas = casillas_cajetin(pag)
            if not casillas:
                print(f"  pág {numero + 1}: sin cajetín de responsables")
                informe.agregar(entrada.name, "sin cajetín", pagina=numero)
                continue
            if not op.solo_cajetin:
                por_iniciales = {iniciales_de(c.persona): c.persona for c in casillas}
                por_iniciales.update(firmas.personas_por_iniciales())
                revision, avisos = casillas_revision(pag, por_iniciales)
                casillas += revision
                for aviso in avisos:
                    print(f"  pág {numero + 1}: AVISO {aviso}")
                    informe.agregar(entrada.name, f"aviso: {aviso}", pagina=numero)
            if op.personas is not None:
                casillas = [c for c in casillas if c.persona in op.personas]

            for c in casillas:
                archivo = firmas.buscar(c.persona)
                if archivo is None:
                    print(f"  pág {numero + 1}: FALTA firma de {c.persona} ({c.zona} {c.etiqueta})")
                    informe.agregar(entrada.name, "falta firma", c)
                    continue
                try:
                    img = firmas.imagen(archivo)
                except Exception as e:
                    print(f"  pág {numero + 1}: ERROR en la imagen {archivo.name}: {e}")
                    informe.agregar(entrada.name, f"imagen inválida: {e}", c, archivo)
                    continue
                caja = c.ubicar(*img.size)
                plan.setdefault(numero, []).append((c, archivo, caja))
                informe.agregar(entrada.name, "simulado" if op.simular else "firmado", c, archivo)
                print(f"  pág {numero + 1}: {c.zona:8s} {c.etiqueta:12s} {c.persona:14s} <- {archivo.name}")
    return plan


def estampar(entrada: Path, salida: Path, plan: dict[int, list[tuple[Casilla, Path, Caja]]], firmas: RegistroFirmas):
    """Agrega las firmas como una capa sobre cada página; el resto no se toca."""
    lector = PdfReader(str(entrada))
    escritor = PdfWriter(clone_from=lector)
    for numero, firmas_pagina in plan.items():
        pagina = escritor.pages[numero]
        mb = pagina.mediabox
        ancho, alto = float(mb.width), float(mb.height)
        buffer = io.BytesIO()
        lienzo = canvas.Canvas(buffer, pagesize=(ancho, alto))
        for _, archivo, caja in firmas_pagina:
            lienzo.drawImage(firmas.lector(archivo), caja.x0, alto - caja.bottom,
                             caja.ancho, caja.alto, mask="auto")
        lienzo.save()
        capa = PdfReader(buffer).pages[0]
        if float(mb.left) or float(mb.bottom):
            capa.add_transformation(Transformation().translate(float(mb.left), float(mb.bottom)))
        pagina.merge_page(capa)
    salida.parent.mkdir(parents=True, exist_ok=True)
    with open(salida, "wb") as f:
        escritor.write(f)


def lamina_de_firmas(firmas: RegistroFirmas, destino: Path):
    """Imagen con todas las firmas ya limpias, para revisarlas de un vistazo."""
    filas = []
    for archivo in firmas.archivos:
        try:
            filas.append((archivo, firmas.imagen(archivo)))
        except Exception:
            filas.append((archivo, None))
    if not filas:
        return
    celda_w, celda_h, texto_w = 320, 110, 330
    hoja = Image.new("RGB", (texto_w + celda_w + 20, celda_h * len(filas) + 10), "white")
    dibujo = ImageDraw.Draw(hoja)
    for i, (archivo, img) in enumerate(filas):
        y = 5 + i * celda_h
        clave = clave_persona(archivo.stem)
        cajetin = f"{clave[0]}. {clave[1]}" if clave else "(sin apellido)"
        dibujo.text((10, y + 35), sin_tildes(decodificar_nombre(archivo.name)), fill="black")
        dibujo.text((10, y + 55), f"cajetin: {sin_tildes(cajetin)}", fill=(90, 90, 90))
        dibujo.rectangle((texto_w, y + 5, texto_w + celda_w, y + celda_h - 5), outline=(210, 210, 210))
        if img is None:
            dibujo.text((texto_w + 10, y + 45), "ERROR: no se pudo leer", fill="red")
            continue
        miniatura = img.copy()
        miniatura.thumbnail((celda_w - 10, celda_h - 15))
        hoja.paste(miniatura, (texto_w + 5, y + 8), miniatura)
    destino.parent.mkdir(parents=True, exist_ok=True)
    hoja.save(destino)


# -----------------------------------------------------------------------------
#  Programa principal
# -----------------------------------------------------------------------------
def recolectar(rutas: list[str], excluir: Path) -> list[tuple[Path, Path]]:
    """(pdf, ruta relativa para la salida); busca en subcarpetas."""
    pdfs = []
    for texto in rutas:
        ruta = Path(texto)
        if ruta.is_dir():
            for p in sorted(ruta.rglob("*")):
                if (p.suffix.lower() == ".pdf" and not p.stem.endswith("_firmado")
                        and excluir not in p.resolve().parents):
                    pdfs.append((p, p.relative_to(ruta)))
        elif ruta.is_file() and ruta.suffix.lower() == ".pdf":
            pdfs.append((ruta, Path(ruta.name)))
        else:
            print(f"AVISO: se ignora {texto}")
    return pdfs


def abrir_carpeta(ruta: Path):
    if os.name == "nt":
        os.startfile(ruta)  # type: ignore[attr-defined]


def rutas_de_texto(linea: str) -> list[str]:
    """Rutas arrastradas o pegadas en la consola.

    Windows pone entre comillas las rutas con espacios: "C:\\a b\\x.pdf" C:\\c.pdf
    Una ruta pegada sin comillas (con espacios) se acepta si existe tal cual.
    """
    linea = linea.strip()
    if not linea:
        return []
    if Path(linea.strip('"')).exists():
        return [linea.strip('"')]
    return [a or b for a, b in re.findall(r'"([^"]+)"|(\S+)', linea)]


def firmar_lote(entradas: list[str], firmas: RegistroFirmas, salida: Path, op: Opciones,
                informe: Informe | None = None) -> int:
    """Firma un lote. El informe se acumula si se pasa uno (modo interactivo)."""
    pdfs = recolectar(entradas, excluir=salida)
    if not pdfs:
        print("No se encontraron planos PDF en lo indicado.")
        return 2

    informe = informe if informe is not None else Informe()
    previas = len(informe.filas)
    firmados = 0
    for pdf, relativa in pdfs:
        print(f"\n== {relativa}")
        try:
            plan = detectar(pdf, firmas, op, informe)
            if plan and not op.simular:
                estampar(pdf, salida / relativa.parent / f"{pdf.stem}_firmado.pdf", plan, firmas)
            firmados += bool(plan)
        except Exception as e:   # un plano dañado no detiene el lote
            print(f"  ERROR: {e}")
            informe.agregar(pdf.name, f"error: {e}")

    informe.guardar(salida / "informe_firmas.csv")
    lamina_de_firmas(firmas, salida / "revision_firmas.png")

    print("\n" + "=" * 70)
    print(f"{firmados}/{len(pdfs)} plano(s) {'revisados' if op.simular else 'firmados'} -> {salida}")
    faltan = sorted({f["persona"] for f in informe.filas[previas:] if f["estado"] == "falta firma"})
    if faltan:
        print("Faltan firmas de: " + ", ".join(faltan))
        print(f'Agregue la imagen en "firmas" o una línea en firmas\\{ARCHIVO_EQUIVALENCIAS}, p. ej.:')
        print(f"    {faltan[0]} = Nombre Apellido.png")
    print("Detalle en informe_firmas.csv; firmas reconocidas en revision_firmas.png")
    print("=" * 70)
    return 0 if firmados == len(pdfs) and not faltan else 1


def modo_interactivo(firmas: RegistroFirmas, salida: Path, op: Opciones) -> int:
    """Pide rutas en la consola hasta que se presione Enter sin escribir nada."""
    resultado, hubo_lote, informe = 0, False, Informe()
    while True:
        print("\nArrastre aquí los PDF o la carpeta de planos (o pegue la ruta) y presione Enter.")
        print("Enter sin nada para salir.")
        try:
            linea = input("> ")
        except KeyboardInterrupt:
            break
        except EOFError:
            print("No se pudo leer lo escrito en la ventana.")
            return 1
        entradas = rutas_de_texto(linea)
        if not entradas:
            break
        resultado = firmar_lote(entradas, firmas, salida, op, informe)
        hubo_lote = True
    if hubo_lote:
        abrir_carpeta(salida)
    return resultado


def main(argv: list[str] | None = None) -> int:
    base = Path(sys.argv[0]).resolve().parent
    ap = argparse.ArgumentParser(prog="firmar.bat", description="Firma automática de planos PDF.")
    ap.add_argument("entradas", nargs="*", help="carpetas o PDFs a firmar (sin nada: se piden en la ventana)")
    ap.add_argument("--firmas", type=Path, default=base / "firmas", help="carpeta de imágenes de firma")
    ap.add_argument("--salida", type=Path, default=base / "firmados", help="carpeta de salida")
    ap.add_argument("--persona", action="append", metavar="NOMBRE",
                    help='firmar solo las casillas de esta persona, p. ej. --persona "A. CALLUPE"')
    ap.add_argument("--solo-cajetin", action="store_true", help="no firmar la tabla de revisiones")
    ap.add_argument("--simular", action="store_true", help="solo informar, sin generar PDFs")
    args = ap.parse_args(argv)

    args.firmas.mkdir(parents=True, exist_ok=True)
    firmas = RegistroFirmas(args.firmas)
    if not firmas.archivos:
        print(f"No hay imágenes en la carpeta de firmas:\n  {args.firmas}\n"
              "Copie ahí una imagen por persona, con nombre y apellido en el nombre del archivo\n"
              '(p. ej. "Christopher Coica.jpg") y vuelva a ejecutar.')
        abrir_carpeta(args.firmas)
        if not args.entradas:
            input("Presione Enter para salir.")
        return 2
    salida = args.salida.resolve()
    op = Opciones(solo_cajetin=args.solo_cajetin, simular=args.simular,
                  personas={normalizar(p) for p in args.persona} if args.persona else None)
    if not args.entradas:
        return modo_interactivo(firmas, salida, op)
    resultado = firmar_lote(args.entradas, firmas, salida, op)
    abrir_carpeta(salida)
    return resultado


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        print("\nError inesperado. Envíe una captura de esta ventana.")
        sys.exit(1)
