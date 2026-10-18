#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# run_all.sh — Nivel 2: corre los experimentos del artículo en el orden de
# la tabla del README. Horas a días; ver docs/ENTORNO.md.
#
#     ./run_all.sh              # todo lo que esté presente
#     ./run_all.sh 11           # solo el experimento 11
#     ./run_all.sh --listar     # qué correría, sin correr nada
#
# Un runner ausente se informa y se salta: el repositorio se puebla por
# bloques y no tiene sentido que falte uno y se caiga todo.
#
# ATENCIÓN: pisa results/. Los CSV versionados son los que sustentan las
# cifras del manuscrito; una vez sobrescritos, la comparación contra el
# artículo se pierde. Antes de correr esto en un clon con resultados,
# guardar results/ o trabajar sobre una copia. El script pide confirmación
# salvo que se fije SIR_UDE_SIN_PREGUNTAR=1.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

JULIA="${JULIA:-julia}"
HILOS="${JULIA_NUM_THREADS:-auto}"

# número · descripción · runner
EXPERIMENTOS=(
    "1|Panorama 7 escenarios sintéticos|01_run_all_scenarios.jl"
    "2|Sensibilidad a m, sintético|20_run_window_sensitivity_all_v2.jl"
    "3|Pareado multisemilla sin ruido|09_run_final_synthetic_experiments.jl"
    "4|Ruido observacional sigma_rel|09b_run_ruido_pareado.jl"
    "5|Saturación hospitalaria|04_run_saturacion_stress_test.jl"
    "6|Sensibilidad a m, datos reales|21_run_real_data_window_sensitivity_split_v2.jl"
    "7|Sensibilidad a m, 5 semillas|22_run_real_data_window_sensitivity_multiseed.jl"
    "7b|Consolidación multisemilla|23_consolidar_multiseed_real_data.jl"
    "8|Pareado n=10, datos reales|16_run_real_data_multiseed_PAREADO_exp10.jl"
    "9|Horizontes y rollout autónomo|13_run_real_data_extrapolation_horizons.jl"
    "10|R_eff y positividad de beta|16_run_real_data_multiseed_REFF_POSITIVIDAD_exp14.jl"
    "10b|Resumen del experimento 14|16b_recuperar_resumen_exp14.jl"
    "11|Destilación paramétrica v5.1|29_run_destilacion_parametrica_v51.jl"
)

SOLO=""
LISTAR=0
for arg in "$@"; do
    case "$arg" in
        --listar) LISTAR=1 ;;
        -*) echo "opción desconocida: $arg" >&2; exit 2 ;;
        *) SOLO="$arg" ;;
    esac
done

if [[ $LISTAR -eq 1 ]]; then
    printf '%-4s %-38s %s\n' "#" "experimento" "runner"
    for e in "${EXPERIMENTOS[@]}"; do
        IFS='|' read -r n d r <<< "$e"
        estado="presente"; [[ -f "experiments/$r" ]] || estado="AUSENTE"
        printf '%-4s %-38s %-52s %s\n' "$n" "$d" "$r" "$estado"
    done
    exit 0
fi

if ! command -v "$JULIA" >/dev/null 2>&1; then
    echo "No se encontró '$JULIA' en el PATH." >&2
    echo "Instalar Julia 1.10.5 (docs/ENTORNO.md) o fijar JULIA=/ruta/a/julia." >&2
    exit 2
fi

if [[ "${SIR_UDE_SIN_PREGUNTAR:-0}" != "1" ]]; then
    echo "Esto sobrescribe results/, que contiene los CSV que sustentan las"
    echo "cifras del manuscrito. Escribir 'si' para continuar."
    read -r r; [[ "$r" == "si" ]] || { echo "Cancelado."; exit 1; }
fi

corridos=0; ausentes=0; fallidos=0
inicio_total=$SECONDS

for e in "${EXPERIMENTOS[@]}"; do
    IFS='|' read -r n d r <<< "$e"
    [[ -n "$SOLO" && "$n" != "$SOLO" ]] && continue

    if [[ ! -f "experiments/$r" ]]; then
        printf '\n[%s] %s\n  AUSENTE: experiments/%s — ver docs/PENDIENTES.md\n' "$n" "$d" "$r"
        ausentes=$((ausentes + 1)); continue
    fi

    printf '\n[%s] %s\n  %s --project=. --threads=%s experiments/%s\n' "$n" "$d" "$JULIA" "$HILOS" "$r"
    inicio=$SECONDS
    if "$JULIA" --project=. --threads="$HILOS" "experiments/$r"; then
        printf '  ok · %s s\n' "$((SECONDS - inicio))"
        corridos=$((corridos + 1))
    else
        printf '  FALLÓ · %s s\n' "$((SECONDS - inicio))"
        fallidos=$((fallidos + 1))
    fi
done

printf '\n%s\n' "------------------------------------------------------------"
printf '%d corridos · %d ausentes · %d fallidos · %s s en total\n' \
    "$corridos" "$ausentes" "$fallidos" "$((SECONDS - inicio_total))"
echo "Anotar los tiempos en docs/ENTORNO.md."
echo "Después: bin/generar_manifest.sh y python3 verify/verificar_cifras.py"

[[ $fallidos -eq 0 ]] || exit 1
