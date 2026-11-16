# Firmador automático de planos

Un solo archivo: **`firmar.bat`**. Firma en lote los planos PDF (cajetín Ausenco / Compañía Minera Ares):
lee los nombres del cajetín y coloca la firma de cada persona en sus casillas.

## Uso

1. Ponga `firmar.bat` en una carpeta y, junto a él, una carpeta `firmas\` con una imagen por persona.
2. Haga doble clic en `firmar.bat` y elija la carpeta con los planos. También puede arrastrar una
   carpeta o varios PDF sobre el archivo.
3. El resultado queda en `firmados\` y esa carpeta se abre al terminar.

La primera vez descarga un Python portable (unos 50 MB) en `python\`. No instala nada en Windows
ni pide permisos de administrador. Si Windows muestra *"Windows protegió su PC"*, pulse
**Más información → Ejecutar de todas formas**. Si hay proxy, la descarga necesita acceso a
`www.python.org`, `bootstrap.pypa.io`, `pypi.org` y `files.pythonhosted.org`.

## Firmas

- **Formato:** JPG o PNG, con fondo claro o transparente. El fondo se quita y la firma se recorta
  sola; no hace falta prepararlas.
- **Nombre del archivo:** debe contener nombre y apellido, por ejemplo `Christopher Coica.jpg` o
  `Firma de Juan Alvarado.png`. Se reconoce por inicial + apellido, que es como aparece en el
  cajetín: `C. COICA`, `J. ALVARADO`.
- **Iniciales de la tabla de revisiones:** se deducen de los nombres del cajetín
  (`C. COICA` → `CC`).
- **`firmas\equivalencias.txt` (opcional):** para casos que no se reconocen solos:
  ```
  # persona del cajetín = archivo de firma
  A. CALLUPE = Armando.jpg
  P. MINAYA = Firma Pilar.png
  # iniciales de la tabla de revisiones = persona
  JQ = J. QUISPE
  ```

## Dónde firma

1. **Cajetín de responsables** (DIBUJADO, REVISADO, DISEÑADO, DIS. APRO, PROY. APRO): a la izquierda
   del nombre, en el hueco entre el cargo y el nombre.
2. **Tabla de revisiones**: en la revisión más reciente, en las columnas POR, REV, ING y APRO:
   - si encima de esa revisión hay una fila vacía (`.`), la firma va dentro de esa fila;
   - si la revisión ocupa la primera fila, la firma va encima del borde de la tabla.

El plano no se modifica: la firma se agrega como una capa encima. El PDF debe conservar el texto:
en AutoCAD use *Capture fonts used in the drawing*, no *Convert all text to geometry*.

## Resultado (`firmados\`)

- `<plano>_firmado.pdf`, respetando las subcarpetas de origen.
- `informe_firmas.csv` (se abre en Excel): una fila por casilla, con la persona, el archivo de firma
  usado y el estado (`firmado`, `falta firma`, aviso o error).
- `revision_firmas.png`: todas las firmas ya limpias y el nombre de cajetín que se les asignó,
  para revisarlas de un vistazo.

## Opciones (terminal)

```
firmar.bat CARPETA [--persona "A. CALLUPE"] [--solo-cajetin] [--simular]
```

- `--persona`: firma solo las casillas de esa persona. Se puede repetir.
- `--solo-cajetin`: no firma la tabla de revisiones.
- `--simular`: genera el informe sin crear los PDF.

## Cómo funciona

`firmar.bat` es a la vez script de Windows y programa Python. La parte de Windows prepara el Python
portable y luego se ejecuta a sí misma con `python -x`, que salta la primera línea. Los tamaños y
márgenes de la firma están al inicio de la sección Python.
