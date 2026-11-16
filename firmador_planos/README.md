# Firmador automático de planos

Coloca las firmas en los planos PDF (cajetín Ausenco / Compañía Minera Ares, A1, exportados desde Civil 3D).

## Dónde firma

1. **Cajetín de responsables** (DIBUJADO, REVISADO, DISEÑADO, DIS. APRO, PROY. APRO): a la izquierda del
   nombre, centrada en el hueco entre el cargo y el nombre (cruza la línea de la columna).
2. **Tabla de revisiones**: para la revisión más reciente (la fila superior que no sea `.`), encima del
   borde superior de la tabla, sobre las columnas POR, REV, ING y APRO según las iniciales de esa fila.
   Las iniciales se deducen del nombre del cajetín: `C. COICA` → `CC`, `A. CALLUPE` → `AC`, `Y. SILVA` → `YS`.

Las posiciones se calculan buscando el texto del PDF (no hay coordenadas fijas).
El resto del plano no se modifica: la firma se agrega como una capa encima.

## Firmas

Una carpeta con un PNG por persona, con fondo transparente, nombrado como en el cajetín:

```
firmas/
  C_COICA.png
  A_CALLUPE.png
  J_ALVARADO.png
  Y_SILVA.png
  personas.json      (opcional)
```

`personas.json` sirve para otro nombre de archivo o para iniciales que no salen del nombre
(por ejemplo `JQ`, `EN` en la tabla de revisiones):

```json
{
  "C. COICA": {"firma": "coica.png"},
  "J. QUISPE": {"firma": "J_QUISPE.png", "iniciales": ["JQ"]}
}
```

Recomendado: PNG de unos 600 px de ancho, recortado al trazo, fondo transparente.

## Uso

```bash
pip install -r requirements.txt

# ver qué y dónde firmaría, sin escribir nada
python firmar_planos.py planos/ --firmas firmas/ --dry-run

# firmar uno o varios PDFs o carpetas
python firmar_planos.py planos/ --firmas firmas/ --salida firmados/

# solo el cajetín, sin la tabla de revisiones
python firmar_planos.py plano.pdf --firmas firmas/ --solo-cajetin
```

Cada plano se guarda como `<nombre>_firmado.pdf`. Si falta la firma de alguien, ese lugar queda
sin firmar y se avisa en pantalla.

Los tamaños (alto máximo de la firma, separación sobre la tabla, etc.) están al inicio de
`firmar_planos.py`.
