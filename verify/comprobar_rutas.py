#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
comprobar_rutas.py — ¿cada script escribe donde el README dice?

    python3 verify/comprobar_rutas.py
    python3 verify/comprobar_rutas.py --solo-problemas

El repositorio renombró la disposición del árbol de trabajo:

    lib/      ->  src/lib/
    runners/  ->  experiments/
    outputs/  ->  results/

`bin/poblar_repositorio.sh` copia los runners y los módulos **tal cual**,
sin tocar su contenido, que es lo correcto: adaptar código al copiarlo es
la forma más rápida de que el repositorio deje de ser el que produjo las
cifras. La consecuencia es que un script escrito contra la disposición
vieja sigue apuntando ahí, y al correrlo desde el repositorio escribe en
el sitio equivocado o no encuentra lo que busca.

Este comprobador lee cada script y clasifica las rutas que menciona:

  ancladas   se resuelven desde la ubicación del propio archivo
             (@__DIR__ en Julia, __file__ en Python). Correctas: funcionan
             desde cualquier directorio.
  viejas     mencionan lib/, runners/ u outputs/, que en este repositorio
             no existen. También en la forma por componentes,
             joinpath("outputs", ...) o joinpath(@__DIR__, "..", "lib", ...),
             que no aparece como literal de ruta y por eso se escapa de
             una búsqueda ingenua: así cargan tres runners los módulos
             18 y 19, en diferido.
  absolutas  rutas de una máquina concreta; no funcionan en otra.
  relativas  dependen del directorio desde el que se invoque.

Sin dependencias fuera de la biblioteca estándar.
Código de salida 1 si hay rutas viejas o absolutas.
"""

import argparse
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DIRS_ESCANEAR = ["experiments", "src", "figures_src", "bin", "verify", "."]
EXTENSIONES = (".jl", ".py", ".sh")

# Estas herramientas nombran la disposición vieja por oficio: su trabajo
# es precisamente detectarla o traducirla.
EXENTOS = {"verify/comprobar_rutas.py", "bin/adaptar_salidas.sh",
           "bin/poblar_repositorio.sh"}

ANCLAS = re.compile(r"@__DIR__|__file__|BASH_SOURCE|PROGRAM_FILE")
# lib/ solo cuando NO viene precedido de src/, que es la ruta correcta en
# este repositorio, y siempre al principio de un literal de ruta.
VIEJAS = re.compile(r'''["'(]\s*(?:\./)?((?<!src/)lib|runners|outputs)/''')
# La misma disposición vieja, armada por componentes: joinpath("outputs", …)
# y joinpath(@__DIR__, "..", "lib", …). No llevan barra, así que VIEJAS no
# las ve.
VIEJAS_COMP = re.compile(r'''joinpath\(\s*"(outputs|runners)"|"\.\."\s*,\s*"(lib|runners|outputs)"''')
ABSOLUTAS = re.compile(r'["\'](/(?:home|Users|mnt|media|opt|srv)/[^"\']{3,})["\']')
# Literales de ruta con una carpeta conocida del repositorio
RELATIVAS = re.compile(r'["\']((?:data|results|figures|src|experiments|docs)/[^"\']*)["\']')


def en_docstring(lineas, idx):
    """¿La línea idx cae dentro de un docstring triple?

    Una mención en prosa dentro de la documentación de un archivo no es
    una ruta que el archivo use.
    """
    abiertas = 0
    for l in lineas[:idx]:
        abiertas += l.count('"' * 3) + l.count("'" * 3)
    return abiertas % 2 == 1


def escanear(path):
    try:
        txt = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return None
    lineas = txt.splitlines()
    out = {"ancla": False, "viejas": [], "absolutas": [], "relativas": []}
    out["ancla"] = bool(ANCLAS.search(txt))
    for i, l in enumerate(lineas, 1):
        limpia = l.strip()
        # saltar comentarios: los avisos de este mismo archivo no cuentan
        if limpia.startswith(("#", "//", "%", '"' * 3, "'" * 3, "*")):
            continue
        if en_docstring(lineas, i - 1):
            continue
        for m in VIEJAS.finditer(l):
            out["viejas"].append((i, m.group(1) + "/", limpia[:76]))
        for m in VIEJAS_COMP.finditer(l):
            out["viejas"].append((i, (m.group(1) or m.group(2)) + "/ (por componentes)",
                                  limpia[:76]))
        for m in ABSOLUTAS.finditer(l):
            out["absolutas"].append((i, m.group(1), limpia[:76]))
        for m in RELATIVAS.finditer(l):
            out["relativas"].append((i, m.group(1), limpia[:76]))
    return out


def archivos(raiz):
    out = []
    for d in DIRS_ESCANEAR:
        base = os.path.join(raiz, d)
        if not os.path.isdir(base):
            continue
        if d == ".":
            for f in sorted(os.listdir(base)):
                if f.endswith(EXTENSIONES) and os.path.isfile(os.path.join(base, f)):
                    out.append(f)
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in ("__pycache__", ".ipynb_checkpoints")]
            for f in sorted(filenames):
                if f.endswith(EXTENSIONES):
                    out.append(os.path.relpath(os.path.join(dirpath, f), raiz))
    return sorted(set(out))


def main():
    global RAIZ
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--solo-problemas", action="store_true")
    ap.add_argument("--raiz", default=RAIZ)
    args = ap.parse_args()
    RAIZ = os.path.abspath(args.raiz)

    con_problema, revisados = [], 0
    for rel in archivos(RAIZ):
        if rel in EXENTOS:
            continue
        r = escanear(os.path.join(RAIZ, rel))
        if r is None:
            continue
        revisados += 1
        problema = bool(r["viejas"] or r["absolutas"])
        if problema:
            con_problema.append(rel)
        if args.solo_problemas and not problema:
            continue

        estado = "ancla la raíz en su propia ubicación" if r["ancla"] else \
                 ("sin ancla" if (r["relativas"] or r["viejas"]) else "sin rutas")
        marca = "PROBLEMA" if problema else "  ok    "
        print("\n%s  %-56s %s" % (marca, rel, estado))

        for etiqueta, clave in (("ruta de la disposición vieja", "viejas"),
                                ("ruta absoluta de una máquina", "absolutas")):
            for n, val, linea in r[clave][:6]:
                print("          %s  línea %-4d %s" % (etiqueta, n, val))
                print("            %s" % linea)
        if not r["ancla"]:
            for n, val, linea in r["relativas"][:3]:
                print("          relativa al directorio actual  línea %-4d %s" % (n, val))

    print("\n" + "=" * 74)
    print("%d archivos revisados · %d con rutas viejas o absolutas" % (revisados, len(con_problema)))
    print("=" * 74)
    if con_problema:
        print("\nEstos escriben o leen fuera de la disposición del repositorio:\n")
        for r in con_problema:
            print("  · %s" % r)
        print("""
El repositorio usa src/lib/, experiments/ y results/; el árbol de trabajo
usaba lib/, runners/ y outputs/. Un script copiado sin adaptar sigue
apuntando a los nombres viejos, así que el Nivel 2 no corre tal cual.

El patrón que sí funciona, y que ya usa el runner de la destilación:

    const REPO    = normpath(joinpath(@__DIR__, ".."))
    const DESTINO = joinpath(REPO, "results", "<carpeta del experimento>")

Con eso el script corre desde cualquier directorio y escribe donde el
mapa del README dice.""")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
