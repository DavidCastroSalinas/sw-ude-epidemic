#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# poblar_repositorio.sh — copia, con lista blanca, los archivos de los
# bloques 1–10 desde el árbol de trabajo hacia este repositorio.
#
#     bin/poblar_repositorio.sh /ruta/al/arbol/de/trabajo          # simulacro
#     bin/poblar_repositorio.sh /ruta/al/arbol/de/trabajo --aplicar
#     bin/poblar_repositorio.sh /ruta/al/arbol/de/trabajo --aplicar --forzar
#
# Por omisión no escribe nada: enumera lo que copiaría y lo que no
# encuentra. Con --aplicar copia de verdad, y sin --forzar se niega a pisar
# un archivo que ya exista en el repositorio.
#
# La lista blanca es la de docs/PENDIENTES.md §2 y refleja dos decisiones
# del plan: la regresión simbólica (módulos 16 y 17, runners 25–28 y
# 14_run_pipeline_beta_simbolica.jl, figuras sr_*) queda fuera, y también
# quedan fuera 07_noise_sensitivity.jl y 13_real_data_sensitivity_n_gamma.jl.
# Con eso el Project.toml deja de depender de SymbolicRegression.jl y MLJ.jl.
#
# Código de salida: 0 si no faltó ningún archivo de la lista, 1 si faltó
# alguno o si se abortó una copia por colisión.

set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ORIGEN="${1:-}"
APLICAR=0
FORZAR=0
shift || true
for arg in "$@"; do
    case "$arg" in
        --aplicar) APLICAR=1 ;;
        --forzar)  FORZAR=1 ;;
        *) echo "opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

if [[ -z "$ORIGEN" || ! -d "$ORIGEN" ]]; then
    cat >&2 <<'USO'
Uso: bin/poblar_repositorio.sh <árbol-de-trabajo> [--aplicar] [--forzar]

  <árbol-de-trabajo>  directorio raíz del proyecto original, el que
                      contiene lib/, runners/, results/, figures/ y data/.
USO
    exit 2
fi
ORIGEN="$(cd "$ORIGEN" && pwd)"

# ----------------------------------------------------------------------
# Subdirectorios del árbol de trabajo.
#
# El árbol original usa lib/ y runners/; este repositorio usa src/lib/ y
# experiments/. Si el árbol de origen tiene otra disposición, ajustar estas
# cuatro variables o exportarlas antes de llamar al script.
# ----------------------------------------------------------------------
DIR_LIB="${DIR_LIB:-lib}"
DIR_RUNNERS="${DIR_RUNNERS:-runners}"
DIR_RESULTADOS="${DIR_RESULTADOS:-results}"
DIR_FIGURAS="${DIR_FIGURAS:-figures}"
DIR_FIGURAS_SRC="${DIR_FIGURAS_SRC:-figures_src}"

FALTANTES=0
COPIADOS=0
COLISIONES=0

# copiar <ruta-relativa-en-origen> <ruta-relativa-en-repositorio>
copiar() {
    local rel_orig="$1" rel_dest="$2"
    local src="$ORIGEN/$rel_orig" dst="$RAIZ/$rel_dest"

    if [[ ! -e "$src" ]]; then
        printf '  FALTA    %s\n' "$rel_orig"
        FALTANTES=$((FALTANTES + 1))
        return
    fi
    if [[ -e "$dst" && $FORZAR -eq 0 ]]; then
        printf '  EXISTE   %s  (no se pisa; usar --forzar)\n' "$rel_dest"
        COLISIONES=$((COLISIONES + 1))
        return
    fi
    if [[ $APLICAR -eq 1 ]]; then
        mkdir -p "$(dirname "$dst")"
        cp -R "$src" "$dst"
    fi
    printf '  copia    %s  ->  %s\n' "$rel_orig" "$rel_dest"
    COPIADOS=$((COPIADOS + 1))
}

encabezado() { printf '\n%s\n%s\n' "$1" "$(printf '%.0s-' $(seq ${#1}))"; }

if [[ $APLICAR -eq 0 ]]; then
    echo "SIMULACRO — no se escribe nada. Añadir --aplicar para copiar."
fi
echo "origen:      $ORIGEN"
echo "destino:     $RAIZ"

# ----------------------------------------------------------------------
# 2.1 Biblioteca
# ----------------------------------------------------------------------
encabezado "src/lib/ — biblioteca"

MODULOS=(
    00_setup.jl
    01_model_training.jl
    02_plotting_base.jl
    03_scenario_config.jl
    04_progress.jl
    05_run_experiment.jl
    08_experiment18_core.jl
    09_experiment18_plots.jl
    10_final_synthetic_experiments.jl
    11_real_data.jl
    12_extended_metrics.jl
    14_real_data_window_sensitivity.jl
    15_real_data_extrapolation_horizons.jl
    # Los dos siguientes NO los carga src/sir_ude_lib.jl: los cargan en
    # diferido los runners 16_PAREADO, 21 y 22, dentro de un `if`, con su
    # propio joinpath. Por eso no aparecían al recorrer la cadena de
    # include del cargador, y faltaban.
    18_real_data_window_sensitivity_split.jl
    19_real_data_multiseed.jl
    27_ruido_relativo.jl
)
for m in "${MODULOS[@]}"; do
    copiar "$DIR_LIB/$m" "src/lib/$m"
done
copiar "$DIR_LIB/sir_ude_lib.jl" "src/sir_ude_lib.jl"

# La destilación paramétrica no vive en lib/ ni en runners/: está sola en
# el directorio del notebook, con otro nombre. El módulo del repositorio
# es copia byte a byte de ese archivo; el runner 29 es el envoltorio que
# lo carga anclado a la raíz, y es nativo del repositorio, así que no se
# copia de ninguna parte.
DIR_DESTILACION="notebook/regresion_variantes_v5_1_corregido"
copiar "$DIR_DESTILACION/experimento_destilacion_parametrica_v5_1_familias_covid.jl" \
       "src/lib/29_destilacion_parametrica_v51.jl"

# ----------------------------------------------------------------------
# 2.2 Runners
# ----------------------------------------------------------------------
encabezado "experiments/ — runners"

RUNNERS=(
    01_run_all_scenarios.jl
    04_run_saturacion_stress_test.jl
    09_run_final_synthetic_experiments.jl
    09b_run_ruido_pareado.jl
    13_run_real_data_extrapolation_horizons.jl
    16_run_real_data_multiseed_PAREADO_exp10.jl
    16_run_real_data_multiseed_REFF_POSITIVIDAD_exp14.jl
    16b_recuperar_resumen_exp14.jl
    20_run_window_sensitivity_all_v2.jl
    21_run_real_data_window_sensitivity_split_v2.jl
    22_run_real_data_window_sensitivity_multiseed.jl
    23_consolidar_multiseed_real_data.jl
)
for r in "${RUNNERS[@]}"; do
    copiar "$DIR_RUNNERS/$r" "experiments/$r"
done

# ----------------------------------------------------------------------
# 2.3 Resultados — SOLO LOS CSV
#
# De cada carpeta se copian únicamente los .csv. Las carpetas del árbol de
# trabajo traen además EPS, PNG y PDF de control —una sola de ellas,
# datos_reales_multiseed, pesa 19 MB de los cuales casi todo son imágenes
# por semilla— y esas imágenes no son datos: el repositorio regenera sus
# seis figuras desde los CSV con figures_src/.
#
# Medido el 2026-10-13: results/ completo pesa 122 MB en el origen y
# ningún CSV llega a 1 MB. El peso está en las imágenes.
#
# Si aun así los CSV pasan de ~100 MB, la poda que queda es la de
# PENDIENTES §2.3: dejar los resumidos y mover las trayectorias día a día
# de los sintéticos a un depósito Zenodo aparte.
# ----------------------------------------------------------------------
# copiar_csv <carpeta-relativa-en-origen> <carpeta-relativa-en-destino>
copiar_csv() {
    local rel_orig="$1" rel_dest="$2"
    local src="$ORIGEN/$rel_orig" dst="$RAIZ/$rel_dest"

    if [[ ! -d "$src" ]]; then
        printf '  FALTA    %s/\n' "$rel_orig"
        FALTANTES=$((FALTANTES + 1)); return
    fi
    local n_csv n_otros
    n_csv=$(find "$src" -type f -name '*.csv' | wc -l | tr -d ' ')
    n_otros=$(find "$src" -type f ! -name '*.csv' | wc -l | tr -d ' ')
    if [[ "$n_csv" -eq 0 ]]; then
        printf '  vacía    %s/  (sin .csv)\n' "$rel_orig"
        return
    fi
    local ya
    ya=$(cd "$src" && find . -type f -name '*.csv' \
            -exec test -e "$dst/{}" \; -print | wc -l | tr -d ' ')
    if [[ $APLICAR -eq 1 ]]; then
        mkdir -p "$dst"
        if [[ $FORZAR -eq 1 ]]; then
            ( cd "$src" && find . -type f -name '*.csv' -print0 \
                | xargs -0 -r -I{} cp -f --parents {} "$dst"/ )
        else
            # Se filtran en find los que ya existen, en vez de delegarlo a
            # `cp -n`: coreutils 9 emite un aviso de portabilidad por cada
            # archivo y enterraba la salida bajo cien líneas de ruido.
            ( cd "$src" && find . -type f -name '*.csv' \
                ! -exec test -e "$dst/{}" \; -print0 \
                | xargs -0 -r -I{} cp --parents {} "$dst"/ )
        fi
    fi
    printf '  copia    %-32s %4s csv' "$rel_orig/" "$n_csv"
    [[ "$ya" -gt 0 ]] && printf '  (%s ya presentes, se respetan)' "$ya"
    [[ "$n_otros" -gt 0 ]] && printf '  (omite %s no-csv)' "$n_otros"
    printf '\n'
    COPIADOS=$((COPIADOS + n_csv - ya))
}

encabezado "results/ — solo los CSV"

CARPETAS_RES=(
    all_scenarios
    window_sensitivity_v2
    final_suite
    final_suite_ruido
    saturacion_stress_test
    datos_reales
    datos_reales_multiseed
    datos_reales_multisemilla
)
for c in "${CARPETAS_RES[@]}"; do
    copiar_csv "$DIR_RESULTADOS/$c" "results/$c"
done

if [[ -d "$ORIGEN/$DIR_RESULTADOS" ]]; then
    printf '\n  %s/ completo en el origen: %s\n' \
        "$DIR_RESULTADOS" "$(du -sh "$ORIGEN/$DIR_RESULTADOS" | cut -f1)"
    kb=0
    for c in "${CARPETAS_RES[@]}"; do
        d="$ORIGEN/$DIR_RESULTADOS/$c"
        [[ -d "$d" ]] || continue
        k=$(find "$d" -type f -name '*.csv' -printf '%k\n' 2>/dev/null | paste -sd+ | bc 2>/dev/null)
        kb=$((kb + ${k:-0}))
    done
    printf '  solo los .csv de la lista blanca: %s MB  <-- esto es lo que se copia\n' \
        "$((kb / 1024))"
fi

# ----------------------------------------------------------------------
# Serie empírica de origen
#
# El repositorio entrega data/datos_reales_curvas.csv, que es la entrada
# del experimento 11, pero ocho de sus nueve columnas son SALIDA de la
# corrida de entrenamiento con semilla 1234. La única serie empírica es
# I_observado, y ya viene reescalada por el factor de anclaje.
#
# La serie de origen —la que el plan del 2026-09-20 llama
# datos_historicos_julio_enero.csv— no está en el repositorio, y es la que
# necesita la nota de procedencia del DEIS/MINSAL en data/README.md.
# El nombre exacto puede variar en el árbol de trabajo: ajustar con la
# variable ARCHIVO_SERIE si hace falta.
# ----------------------------------------------------------------------
encabezado "data/ — serie empírica de origen"

ARCHIVO_SERIE="${ARCHIVO_SERIE:-datos_historicos_julio_enero.csv}"
copiar "data/$ARCHIVO_SERIE" "data/$ARCHIVO_SERIE"
echo "  aviso    ningún runner del repositorio produce"
echo "           data/datos_reales_curvas.csv a partir de esta serie."
echo "           Sin ese paso, el experimento 11 no es reproducible en"
echo "           Nivel 2; ver docs/PENDIENTES.md."

# ----------------------------------------------------------------------
# 2.4 Figuras — YA NO SE COPIAN
#
# El repositorio produce sus seis figuras desde sus propios CSV, con los
# scripts de figures_src/ y el registro de figuras_notebook.py. Copiarlas
# desde el árbol de trabajo haría dos cosas malas:
#
#   · traería los PDF del conjunto viejo —beta_siete_escenarios,
#     S1_lineal_boxplots, S4_saturacion_estados, datos_reales_combinado—
#     que main.tex ya no cita, y los dejaría junto a los seis vigentes;
#   · traería versiones de los generar_fig_*.py anteriores a la
#     normalización, que quedarían al lado de los normalizados y sin
#     entrada en el registro.
#
# Para regenerar las figuras:
#     cd figures_src && python3 figuras_notebook.py
# ----------------------------------------------------------------------
encabezado "figures/ y figures_src/ — no se copian"
echo "  omitido  el repositorio genera sus seis figuras desde results/."
echo "           Ver README, sección «Las figuras»."

# ----------------------------------------------------------------------
# 2.5 Entorno
#
# Project.toml hay que regenerarlo después de podar los módulos de
# regresión simbólica, no copiarlo tal cual: el del árbol de trabajo
# todavía declara SymbolicRegression.jl y MLJ.jl.
# ----------------------------------------------------------------------
encabezado "entorno"

copiar "install_dependencies.jl" "install_dependencies.jl"
echo "  aviso    Project.toml y Manifest.toml NO se copian: hay que"
echo "           regenerarlos sin SymbolicRegression.jl ni MLJ.jl y"
echo "           comprobar que instalan de una sola pasada."

# ----------------------------------------------------------------------
encabezado "resumen"
printf '  %d archivos en la lista blanca resueltos\n' "$COPIADOS"
printf '  %d faltantes en el origen\n' "$FALTANTES"
printf '  %d colisiones con archivos ya presentes\n' "$COLISIONES"

if [[ $APLICAR -eq 1 ]]; then
    echo
    echo "Siguiente paso: bin/generar_manifest.sh y luego"
    echo "python3 verify/verificar_cifras.py"
fi

if [[ $FALTANTES -gt 0 || $COLISIONES -gt 0 ]]; then
    exit 1
fi
exit 0
