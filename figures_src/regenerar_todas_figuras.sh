#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# regenerar_todas_figuras.sh — reconstruye las seis figuras que cita
# main.tex, todas al mismo directorio de salida.
#
#     ./regenerar_todas_figuras.sh /ruta/a/outputs [carpeta_salida]
#
# Es un envoltorio de figuras_notebook.py, que es el registro único de las
# figuras: qué script produce cada una y con qué argumentos. Antes esa
# lista estaba aquí y duplicada en el notebook, que es la vía segura para
# que una figura se regenere con argumentos viejos.
#
# Lo mismo desde Python o un notebook:
#     from figuras_notebook import generar_y_mostrar
#     generar_y_mostrar(outputs_dir="outputs")

set -uo pipefail

OUTPUTS_DIR="${1:?Uso: ./regenerar_todas_figuras.sh /ruta/a/outputs [carpeta_salida]}"
SALIDA_DIR="${2:-figures}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "$AQUI/figuras_notebook.py" \
    --outputs-dir "$OUTPUTS_DIR" --outdir "$SALIDA_DIR" ${DESTILACION_DIR:+--destilacion-dir "$DESTILACION_DIR"}
