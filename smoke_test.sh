#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# smoke_test.sh — Nivel 1: comprueba que el entorno está bien armado antes
# de comprometer horas de cómputo. No reproduce ninguna cifra.
#
#     SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh
#
# Lo que sí hace, sin Julia:
#   · el verificador de cifras corre y no reporta ninguna FALLA;
#   · las seis figuras se regeneran desde los CSV entregados;
#   · el manifiesto cuadra con lo que hay en disco.
#
# Lo que hace además, si hay Julia:
#   · el entorno instala y precompila;
#   · cada runner presente corre con SIR_UDE_SMOKE_TEST=1.
#
# ADVERTENCIA sobre el modo reducido: la variable SIR_UDE_SMOKE_TEST no
# está implementada en el módulo del experimento 11. Correrlo aquí lo
# ejecuta COMPLETO, con sus 50 multistarts, y además sobrescribe
# results/destilacion_v51/. Por eso la etapa de Julia está desactivada
# salvo que se pida con --con-julia. Ver docs/PENDIENTES.md.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

CON_JULIA=0
for arg in "$@"; do
    case "$arg" in
        --con-julia) CON_JULIA=1 ;;
        *) echo "opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

fallos=0
etapa() { printf '\n== %s ==\n' "$1"; }
mal()   { printf 'FALLA: %s\n' "$1"; fallos=$((fallos + 1)); }

etapa "Nivel 0 — verificador de cifras"
if python3 verify/verificar_cifras.py --solo-fallas; then
    echo "sin fallas."
else
    mal "el verificador reporta cifras que no cuadran."
fi

etapa "Figuras — regeneración desde los CSV entregados"
if python3 -c "import matplotlib, numpy, pandas" 2>/dev/null; then
    # A un directorio aparte: comparar antes de reemplazar figures/, que es
    # lo que compila el manuscrito.
    rm -rf "$RAIZ/figures_regeneradas"
    if ( cd "$RAIZ/figures_src" && python3 figuras_notebook.py \
            --outputs-dir "$RAIZ/results" --outdir "$RAIZ/figures_regeneradas" ); then
        n=$(find "$RAIZ/figures_regeneradas" -name '*.pdf' 2>/dev/null | wc -l | tr -d ' ')
        [[ "$n" -eq 6 ]] || mal "se regeneraron $n figuras de 6."
    else
        mal "la regeneración de figuras terminó con error."
    fi
else
    echo "omitida: faltan dependencias de figura (pip install -r figures_src/requirements.txt)."
fi

etapa "Manifiesto"
if [[ -f results/MANIFEST.sha256 ]]; then
    bash bin/generar_manifest.sh --verificar || \
        mal "el manifiesto no cuadra con results/, data/ o figures/."
else
    echo "no existe results/MANIFEST.sha256; generándolo."
    bash bin/generar_manifest.sh >/dev/null
fi

if [[ $CON_JULIA -eq 1 ]]; then
    etapa "Entorno de Julia"
    JULIA="${JULIA:-julia}"
    if command -v "$JULIA" >/dev/null 2>&1; then
        "$JULIA" --project=. install_dependencies.jl || mal "no instaló el entorno."

        etapa "Runners presentes (modo reducido)"
        export SIR_UDE_SMOKE_TEST=1
        for r in experiments/*.jl; do
            [[ -f "$r" ]] || continue
            echo "-- $r"
            "$JULIA" --project=. --threads=auto "$r" || mal "falló $r"
        done
    else
        mal "no se encontró Julia; fijar JULIA=/ruta/a/julia."
    fi
else
    echo
    echo "Etapa de Julia omitida. Añadir --con-julia para incluirla, teniendo"
    echo "en cuenta la advertencia de la cabecera de este archivo."
fi

printf '\n%s\n' "------------------------------------------------------------"
if [[ $fallos -eq 0 ]]; then
    echo "Smoke test sin fallas."
    exit 0
fi
printf '%d fallas.\n' "$fallos"
exit 1
