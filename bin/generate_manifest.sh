#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# generate_manifest.sh — huella SHA-256 de todo lo que el repositorio
# entrega como dato: results/, data/ y figures/.
#
#     bin/generate_manifest.sh              # escribe results/MANIFEST.sha256
#     bin/generate_manifest.sh --verificar  # contrasta contra el manifiesto
#
# El manifiesto es lo que permite a un revisor comprobar que los CSV de su
# clon son byte a byte los que produjeron las cifras del manuscrito, sin
# correr nada.
#
# Los PNG quedan fuera a propósito: los scripts de figura escriben un PNG
# de control junto a cada PDF, y el módulo de destilación escribe tres
# más. Son diagnóstico, se regeneran a demanda y no forman parte de lo
# que el repositorio entrega; incluirlos haría que el manifiesto dejara
# de cuadrar en cuanto alguien regenerara una figura. Hay que regenerarlo cada vez que cambie un resultado, y
# antes del tag v1.0.0.
#
# Las rutas del manifiesto son relativas a la raíz del repositorio y van
# ordenadas, para que el archivo sea estable entre máquinas y el diff de
# git muestre exactamente qué resultado cambió.
#
# Código de salida: 0 si todo cuadra, 1 si alguna huella no coincide o
# falta algún archivo.

set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFIESTO="$RAIZ/results/MANIFEST.sha256"
DIRECTORIOS=(results data figures)

VERIFICAR=0
for arg in "$@"; do
    case "$arg" in
        --verificar) VERIFICAR=1 ;;
        *) echo "opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

# sha256sum en Linux, shasum -a 256 en macOS.
if command -v sha256sum >/dev/null 2>&1; then
    HUELLA() { sha256sum "$@"; }
    COMPROBAR() { sha256sum -c --quiet "$@"; }
elif command -v shasum >/dev/null 2>&1; then
    HUELLA() { shasum -a 256 "$@"; }
    COMPROBAR() { shasum -a 256 -c --quiet "$@"; }
else
    echo "no hay sha256sum ni shasum en el PATH" >&2
    exit 2
fi

cd "$RAIZ" || exit 2

listar() {
    local d
    for d in "${DIRECTORIOS[@]}"; do
        [[ -d "$d" ]] || continue
        find "$d" \
            -type d -name '.ipynb_checkpoints' -prune -o \
            -type f \
            ! -name 'MANIFEST.sha256' \
            ! -name 'MANIFEST.sha256.tmp' \
            ! -name '.DS_Store' \
            ! -name '*.png' \
            -print
    done | LC_ALL=C sort
}

if [[ $VERIFICAR -eq 1 ]]; then
    if [[ ! -f "$MANIFIESTO" ]]; then
        echo "no existe $MANIFIESTO; generarlo primero sin --verificar" >&2
        exit 1
    fi
    n_manifiesto=$(grep -c . "$MANIFIESTO")
    n_disco=$(listar | wc -l | tr -d ' ')

    if COMPROBAR "$MANIFIESTO"; then
        printf '%d archivos verificados, todas las huellas coinciden.\n' "$n_manifiesto"
        if [[ "$n_disco" -ne "$n_manifiesto" ]]; then
            printf 'Aviso: hay %d archivos en disco y %d en el manifiesto.\n' \
                "$n_disco" "$n_manifiesto"
            echo "El manifiesto está desactualizado; regenerarlo."
            exit 1
        fi
        exit 0
    else
        echo "Hay huellas que no coinciden. No publicar hasta resolverlo." >&2
        exit 1
    fi
fi

mkdir -p "$RAIZ/results"
listar | while IFS= read -r f; do HUELLA "$f"; done > "$MANIFIESTO.tmp"
mv "$MANIFIESTO.tmp" "$MANIFIESTO"

n=$(grep -c . "$MANIFIESTO")
printf '%s\n' "results/MANIFEST.sha256 — $n archivos"
for d in "${DIRECTORIOS[@]}"; do
    [[ -d "$d" ]] || continue
    printf '  %-10s %5s archivos  %6s\n' \
        "$d/" "$(find "$d" -type d -name '.ipynb_checkpoints' -prune -o -type f ! -name 'MANIFEST.sha256*' -print | wc -l | tr -d ' ')" \
        "$(du -sh "$d" | cut -f1)"
done
