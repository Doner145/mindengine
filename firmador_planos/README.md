# Firmador automático de planos

Firma en lote planos PDF (cajetín Ausenco / Compañía Minera Ares). El programa lee los nombres
escritos en el cajetín y coloca la firma de cada persona en sus casillas. No hay que indicar
quién firma cada plano.

## Dónde firma

1. **Cajetín de responsables** (DIBUJADO, REVISADO, DISEÑADO, DIS. APRO, PROY. APRO): a la izquierda
   del nombre, centrada en el hueco entre el cargo y el nombre.
2. **Tabla de revisiones**: en la revisión más reciente (la fila superior que no sea `.`), en las
   columnas POR, REV, ING y APRO, según las iniciales de esa fila:
   - si encima de esa revisión hay una fila vacía (`.`), la firma va dentro de esa fila;
   - si la revisión ocupa la primera fila de la tabla, la firma va encima del borde superior de la tabla.

   Las iniciales se deducen de los nombres del cajetín: `C. COICA` → `CC`, `A. CALLUPE` → `AC`,
   `Y. SILVA` → `YS`. Para iniciales que no aparecen en el cajetín, vea `personas.json` más abajo.

Las posiciones se calculan leyendo el texto del PDF; no se usan coordenadas fijas. El plano no se
modifica: la firma se agrega como una capa encima. Requisito: el PDF debe conservar el texto. Use
*Capture fonts used in the drawing* en AutoCAD, nunca *Convert all text to geometry*.

## Instalación (Windows)

No hay que instalar nada. Descomprima la carpeta y haga **doble clic en `firmar.bat`**.

La primera vez, el programa descarga un Python portable (unos 60 MB) en la subcarpeta `python\`
junto con las librerías. No toca la instalación de Windows ni pide permisos de administrador.
Las siguientes veces arranca directo.

- Si Windows muestra *"Windows protegió su PC"*, pulse **Más información → Ejecutar de todas formas**
  (ocurre con los `.bat` descargados de internet).
- Si la empresa usa proxy, la descarga necesita acceso a `www.python.org`, `bootstrap.pypa.io`,
  `pypi.org` y `files.pythonhosted.org`.
- Para reinstalar desde cero, borre la carpeta `python\`.

## Estructura de carpetas

```
firmador_planos/
  firmar_planos.py
  preparar_firmas.py
  firmar.bat           <- doble clic para firmar
  preparar_firmas.bat  <- doble clic para preparar las firmas desde escaneos
  instalar.bat         <- lo llaman los anteriores (descarga Python la primera vez)
  python/              <- Python portable (se crea solo)
  escaneos/            <- escaneos o fotos de firmas (entrada de preparar_firmas)
  firmas/              <- un PNG por trabajador (no se sube al repositorio)
    A_CALLUPE.png
    C_COICA.png
    J_ALVARADO.png
    Y_SILVA.png
    personas.json      (opcional)
  firmados/            <- aquí quedan los planos firmados y el informe
```

## 1. Preparar las firmas (una sola vez)

Copie los escaneos o fotos de las firmas (JPG o PNG, en papel blanco) en la carpeta `escaneos\`.
Nombre cada archivo **como aparece el nombre en el cajetín**: `A. CALLUPE.jpg`, `C. COICA.png`, etc.
Después haga doble clic en **`preparar_firmas.bat`**. Desde la terminal, el equivalente es:

```
python preparar_firmas.py escaneos/ firmas/
```

El programa quita el fondo, recorta al trazo y guarda `firmas/A_CALLUPE.png`, etc. Si queda sombra
del papel, use `--umbral 180`. Si el trazo sale cortado o muy tenue, use `--umbral 220`.

### personas.json (opcional)

Úselo cuando el archivo de firma tenga otro nombre o cuando en la tabla de revisiones aparezcan
iniciales que no salen de un nombre del cajetín (por ejemplo `JQ` o `EN`):

```json
{
  "C. COICA":  {"firma": "coica.png"},
  "J. QUISPE": {"firma": "J_QUISPE.png", "iniciales": ["JQ"]}
}
```

## 2. Firmar

**Doble clic en `firmar.bat`:** se abre una ventana para elegir la carpeta con los planos.
También puede arrastrar una carpeta o varios PDF sobre `firmar.bat`. Las firmas se toman de
`firmas\`, los resultados quedan en `firmados\` y esa carpeta se abre al terminar.

**Desde la terminal:**

```bash
# revisar sin escribir nada: muestra qué se firmaría y dónde
python firmar_planos.py planos/ --firmas firmas/ --dry-run

# firmar en lote (incluye subcarpetas; respeta la estructura en la salida)
python firmar_planos.py planos/ --firmas firmas/ --salida firmados/

# firmar solo las casillas de una persona (p. ej. cuando cada uno firma lo suyo)
python firmar_planos.py planos/ --firmas firmas/ --salida firmados/ --persona "A. CALLUPE"

# solo el cajetín, sin la tabla de revisiones
python firmar_planos.py planos/ --firmas firmas/ --salida firmados/ --solo-cajetin
```

Cada plano se guarda como `<nombre>_firmado.pdf`. Además se genera `informe_firmas.csv`, que se
abre en Excel, con una fila por casilla: plano, casilla, persona y estado (`firmado`,
`falta imagen de firma`, aviso o error). Al terminar, el programa también lista en pantalla las
personas a las que les falta la imagen de firma.

Los tamaños (alto máximo de la firma, separación sobre la tabla, etc.) están al inicio de
`firmar_planos.py`.
