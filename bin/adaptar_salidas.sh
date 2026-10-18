#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# adaptar_salidas.sh — apunta las salidas de los runners a results/.
#
#     bin/adaptar_salidas.sh            # simulacro: enumera los cambios
#     bin/adaptar_salidas.sh --aplicar
#
# Los runners vienen del árbol de trabajo, cuya disposición era otra:
#
#     outputs/  ->  results/
#     runners/  ->  experiments/
#     lib/      ->  src/lib/
#
# Escriben con
# rutas relativas al directorio actual —`CSV.write("outputs/x/y.csv", df)`—
# y `run_all.sh` corre desde la raíz del repositorio, así que basta con
# cambiar ese literal para que cada experimento escriba en la carpeta que
# el mapa del README le asigna.
#
# Es la ÚNICA adaptación que se le hace al código copiado, y es de una
# sola regla: la palabra `outputs/` nombra la carpeta de salidas del árbol
# de trabajo, que en el repositorio se llama `results/`. La regla se
# aplica igual en los tres sitios donde aparece:
#
#   · rutas de escritura   CSV.write("outputs/x/y.csv", df)
#   · valores por omisión  outdir::String="outputs/final_suite"
#   · mensajes y comentarios que le dicen al usuario dónde mirar
#
# Y en dos formas más, que arman la ruta por componentes y por eso no
# aparecen como literal:
#
#   · escritura   joinpath("outputs", "datos_reales", ...)
#   · carga       joinpath(@__DIR__, "..", "lib", "19_....jl")
#
# La segunda es la que importa de verdad: tres runners cargan los módulos
# 18 y 19 así, en diferido, y sin el «src» intermedio no los encuentran.
#
# Lo mismo con los otros dos nombres: un comentario que dice «ver
# lib/00_setup.jl» o un println que remite a «runners/09b_...» mandan al
# lector a carpetas que en el repositorio no existen.
#
# Los valores por omisión importan tanto como las rutas: si un runner
# llama a una función sin pasar `outdir`, escribe donde diga el defecto.
# Y los mensajes importan porque si no, el runner termina diciendo que
# dejó los resultados en una carpeta que no existe.
#
# No se toca ninguna otra línea, ninguna fórmula y ningún parámetro
# numérico. El simulacro enumera cada cambio con su número de línea para
# auditarlo antes de aplicarlo, y el script es idempotente.
#
# Lo que NO arregla: invocar un runner suelto desde otro directorio sigue
# dependiendo del directorio actual, igual que en el árbol de trabajo. La
# vía documentada es ./run_all.sh, que hace cd a la raíz.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APLICAR=0
for arg in "$@"; do
    case "$arg" in
        --aplicar) APLICAR=1 ;;
        *) echo "opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

[[ $APLICAR -eq 1 ]] || echo "SIMULACRO — no se escribe nada. Añadir --aplicar."
echo "repositorio: $RAIZ"

total=0
tocados=0
for f in "$RAIZ"/experiments/*.jl "$RAIZ"/src/*.jl "$RAIZ"/src/lib/*.jl; do
    [[ -e "$f" ]] || continue
    n=$(grep -cE '(outputs|runners)/|(^|[^/[:alnum:]])lib/|joinpath\(\s*"outputs"|"\.\."\s*,\s*"lib"' "$f" 2>/dev/null || true)
    n=${n:-0}
    [[ "$n" -gt 0 ]] || continue

    rel="${f#$RAIZ/}"
    tocados=$((tocados + 1))
    total=$((total + n))
    printf '\n%s  (%s ocurrencia%s)\n' "$rel" "$n" "$([[ "$n" -eq 1 ]] || echo s)"
    grep -nE '(outputs|runners)/|(^|[^/[:alnum:]])lib/|joinpath\(\s*"outputs"|"\.\."\s*,\s*"lib"' "$f" | sed 's/^/    /' | cut -c1-110

    if [[ $APLICAR -eq 1 ]]; then
        # El orden importa: lib/ se renombra con un guardia para no
        # convertir src/lib/ en src/src/lib/ al aplicarlo dos veces.
        sed -i -e 's|outputs/|results/|g' \
               -e 's|runners/|experiments/|g' \
               -e 's|\([^/[:alnum:]]\)lib/|\1src/lib/|g' \
               -e 's|^lib/|src/lib/|' \
               -e 's|joinpath(\(\s*\)"outputs"|joinpath(\1"results"|g' \
               -e 's|"\.\."\(\s*\),\(\s*\)"lib"|".."\1,\2"src", "lib"|g' "$f"
    fi
done

printf '\n%s\n' "------------------------------------------------------------"
if [[ "$tocados" -eq 0 ]]; then
    echo "Nada que adaptar: nadie nombra la disposición del árbol de trabajo."
    exit 0
fi
printf '%d archivo(s) · %d ocurrencia(s) de la disposición vieja\n' "$tocados" "$total"
if [[ $APLICAR -eq 1 ]]; then
    echo
    echo "Comprobar con:  python3 verify/comprobar_rutas.py --solo-problemas"
    echo "y luego:        git diff --stat experiments/"
else
    echo
    echo "Añadir --aplicar para hacerlo."
fi
