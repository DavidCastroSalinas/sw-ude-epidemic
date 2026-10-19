#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# smoke_test.sh — Nivel 1: comprueba que el entorno está bien armado antes
# de comprometer horas de cómputo. No reproduce ninguna cifra.
#
#     SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh
#     SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia
#     SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia --con-destilacion-smoke
#
# Lo que sí hace, sin Julia:
#   · el verificador de cifras corre y no reporta ninguna FALLA;
#   · las seis figuras se regeneran desde los CSV entregados;
#   · el manifiesto cuadra con lo que hay en disco.
#
# Lo que hace además, si hay Julia y se pide --con-julia:
#   · el entorno instala y precompila en una copia temporal;
#   · los runners ligeros corren con SIR_UDE_SMOKE_TEST=1;
#   · los resultados del repositorio no se sobrescriben.
#
# Para probar también el flujo de destilación sin ejecutar el experimento
# completo ni reemplazar sus resultados, añadir --con-destilacion-smoke.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

CON_JULIA=0
CON_DESTILACION_SMOKE=0
for arg in "$@"; do
    case "$arg" in
        --con-julia) CON_JULIA=1 ;;
        --con-destilacion-smoke) CON_DESTILACION_SMOKE=1 ;;
        *) echo "opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

if [[ $CON_DESTILACION_SMOKE -eq 1 && $CON_JULIA -ne 1 ]]; then
    echo "usar --con-destilacion-smoke junto con --con-julia" >&2
    exit 2
fi

fallos=0
etapa() { printf '\n== %s ==\n' "$1"; }
mal()   { printf 'FALLA: %s\n' "$1"; fallos=$((fallos + 1)); }

etapa "Nivel 0 — verificador de cifras"
if python3 verify/verify_values.py --solo-fallas; then
    echo "sin fallas."
else
    mal "el verificador reporta cifras que no cuadran."
fi

etapa "Figuras — regeneración desde los CSV entregados"
if python3 -c "import matplotlib, numpy, pandas" 2>/dev/null; then
    # A un directorio aparte: comparar antes de reemplazar figures/, que es
    # lo que compila el manuscrito.
    rm -rf "$RAIZ/figures_regeneradas"
    if ( cd "$RAIZ/figures_src" && python3 figure_registry.py \
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
    bash bin/generate_manifest.sh --verificar || \
        mal "el manifiesto no cuadra con results/, data/ o figures/."
else
    echo "no existe results/MANIFEST.sha256; generándolo."
    bash bin/generate_manifest.sh >/dev/null
fi

if [[ $CON_JULIA -eq 1 ]]; then
    etapa "Entorno de Julia"
    JULIA="${JULIA:-julia}"
    if command -v "$JULIA" >/dev/null 2>&1; then
        export SIR_UDE_SMOKE_TEST=1
        SMOKE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/sw-ude-smoke.XXXXXX")" || {
            mal "no se pudo crear el directorio temporal del smoke."
            SMOKE_TMP=""
        }

        if [[ -n "$SMOKE_TMP" ]]; then
            trap 'if [[ -n "${SMOKE_TMP:-}" ]]; then rm -rf "$SMOKE_TMP"; fi' EXIT
            SMOKE_REPO="$SMOKE_TMP/repo"
            mkdir -p "$SMOKE_REPO"
            if tar --exclude='./.git' -C "$RAIZ" -cf - . | tar -C "$SMOKE_REPO" -xf -; then
                echo "Copia temporal: $SMOKE_REPO"
                if ( cd "$SMOKE_REPO" && "$JULIA" --project=. install_dependencies.jl ); then
                    etapa "Runners presentes (modo reducido)"
                    for r in "$SMOKE_REPO"/experiments/*.jl; do
                        [[ -f "$r" ]] || continue
                        rel="${r#"$SMOKE_REPO"/}"
                        [[ "$rel" == "experiments/29_run_distillation_parametric_v51.jl" ]] && continue
                        echo "-- $rel"
                        ( cd "$SMOKE_REPO" && "$JULIA" --project=. --threads=auto "$rel" ) || mal "falló $rel"
                    done

                    if [[ $CON_DESTILACION_SMOKE -eq 1 ]]; then
                        etapa "Destilación paramétrica (smoke reducido)"
                        ( cd "$SMOKE_REPO" && SIR_UDE_DESTILACION_SMOKE=1 \
                            "$JULIA" --project=. --threads=auto \
                            experiments/29_run_distillation_parametric_v51.jl ) || \
                            mal "falló el smoke reducido de la destilación."
                    else
                        echo "Destilación omitida; añadir --con-destilacion-smoke para probarla en modo reducido."
                    fi
                else
                    mal "no instaló el entorno Julia en la copia temporal."
                fi
            else
                mal "no se pudo preparar la copia temporal del repositorio."
            fi
        fi
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
