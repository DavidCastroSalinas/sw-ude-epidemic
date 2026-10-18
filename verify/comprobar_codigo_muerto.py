#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
comprobar_codigo_muerto.py — ¿sobra algo en el conjunto publicado?

    python3 verify/comprobar_codigo_muerto.py
    python3 verify/comprobar_codigo_muerto.py --solo-seguros

Un anexo de artículo se lee, no se explora. Una función que nadie llama o
un paquete que nadie usa le cuestan al lector el tiempo de averiguar para
qué están, y al que reproduce una dependencia que no hacía falta.

Busca tres cosas, de más segura a menos:

  1. Paquetes importados y no usados. Para cada `using X` comprueba si
     algún símbolo característico de X aparece en ALGÚN archivo del
     conjunto publicado, no solo en el que lo importa: `include` en Julia
     evalúa en el ámbito de `Main`, de modo que `src/lib/00_setup.jl` hace
     los `using` de todo el proyecto y los módulos que entran después los
     usan sin volver a importarlos. Juzgarlo archivo por archivo da diez
     falsos positivos, todos en 00_setup.

     La tabla de símbolos está abajo y es explícita: sin Julia no hay
     forma de preguntarle a Pkg qué exporta un paquete, así que se declara.

  2. Funciones definidas y nunca referenciadas. Cuenta el nombre a secas,
     no `nombre(`: en Julia una función se pasa como valor con frecuencia,
     y las siete leyes de transmisión de los escenarios sintéticos viven
     en un diccionario, `:dos_olas => beta_dos_olas`. Exigir el paréntesis
     las daba por muertas a las siete.

Lo que NO puede decidir: si algo se llama desde el notebook, desde el REPL
o por un nombre construido en tiempo de ejecución. Por eso separa lo
seguro —cero referencias en todo el repositorio, documentación incluida—
de lo dudoso, y solo lo primero se puede borrar sin leer.

Sin dependencias fuera de la biblioteca estándar.
Código de salida 1 si hay hallazgos seguros.
"""

import argparse
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Paquete -> símbolos por los que se reconoce su uso. Declarado a mano:
# sin Julia instalada no hay manera de preguntarle a Pkg qué exporta cada
# uno. Si un paquete nuevo entra al repositorio, hay que añadirlo aquí o
# saldrá como no usado.
SIMBOLOS = {
    "CSV":                    ["CSV."],
    "DataFrames":             ["DataFrame", "nrow", "ncol", "groupby", "combine",
                               "select", "innerjoin", "leftjoin", "rename!",
                               "sort!", "eachrow", "Not(", "names("],
    "Statistics":             ["mean(", "std(", "median(", "var(", "quantile(", "cor("],
    "Random":                 ["Random.", "seed!", "randn", "rand(", "shuffle",
                               "MersenneTwister"],
    "Printf":                 ["@printf", "@sprintf", "Printf."],
    "LinearAlgebra":          ["BLAS", "norm(", "dot(", "diagm", "LinearAlgebra."],
    "Dates":                  ["Dates.", "now(", "Date(", "DateTime("],
    "Plots":                  ["plot(", "plot!", "savefig", "scatter", "heatmap",
                               "hline", "vline", "Plots.", "annotate!", "bar("],
    "StatsPlots":             ["boxplot", "violin", "@df", "dotplot", "density("],
    "Measures":               ["mm", "Measures."],
    "Colors":                 ["RGB", "colorant", "Colors."],
    "Lux":                    ["Lux.", "Chain(", "Dense("],
    "ComponentArrays":        ["ComponentArray", "ComponentVector"],
    "Optimization":           ["Optimization.", "OptimizationProblem",
                               "OptimizationFunction", "AutoZygote"],
    "OptimizationOptimisers": ["OptimizationOptimisers.", "ADAM", "Adam"],
    "Optimisers":             ["Optimisers.", "ADAM", "Adam", "OptimiserChain"],
    "Optim":                  ["Optim.", "BFGS", "LBFGS", "NelderMead"],
    "Zygote":                 ["Zygote.", "gradient(", "AutoZygote"],
    "HypothesisTests":        ["OneSampleTTest", "SignedRankTest", "pvalue",
                               "confint", "HypothesisTests."],
    "Glob":                   ["glob("],
}

DIRS_CODIGO = ["src", "experiments"]
DIRS_TEXTO = ["docs", "verify", "bin", "figures_src", "."]


def archivos_julia(raiz):
    out = []
    for d in DIRS_CODIGO:
        base = os.path.join(raiz, d)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if not x.startswith(".")]
            for f in sorted(filenames):
                if f.endswith(".jl"):
                    out.append(os.path.relpath(os.path.join(dirpath, f), raiz))
    return sorted(out)


def sin_comentarios(txt):
    """El cuerpo del archivo sin comentarios ni docstrings.

    Una función nombrada solo en un comentario no está llamada, y un
    paquete nombrado solo en un comentario no está usado. Los docstrings
    cuentan igual, y hay que quitarlos a propósito: un docstring suele
    repetir la firma de la función que documenta, de modo que el nombre
    aparece seguido de paréntesis sin que nadie la llame. `sugerir_N` se
    escapaba por eso.
    """
    sin_doc = re.sub(r'""".*?"""', "\n", txt, flags=re.S)
    sin_com = "\n".join(l for l in sin_doc.splitlines()
                         if not l.lstrip().startswith("#"))
    # Y sin literales de cadena: un nombre dentro de un println no es una
    # llamada. `sugerir_N` aparecía en el println que lista lo que el
    # módulo define, marcada «(deprecada)», y eso la daba por viva.
    return re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', sin_com)


def solo_prosa(txt):
    """Lo contrario: comentarios, docstrings y literales de cadena.

    Las tres cosas son prosa dirigida al lector, no llamadas. Un nombre
    que solo aparece aquí es código muerto documentado.
    """
    doc = "\n".join(re.findall(r'""".*?"""', txt, flags=re.S))
    com = "\n".join(l for l in txt.splitlines() if l.lstrip().startswith("#"))
    cad = "\n".join(re.findall(r'"(?:[^"\\\n]|\\.)*"', txt))
    return doc + "\n" + com + "\n" + cad


def paquetes_no_usados(textos):
    """Paquetes importados que nadie usa en NINGÚN archivo publicado.

    El ámbito es el conjunto entero, no el archivo: ver el encabezado.
    Devuelve [(paquete, archivos que lo importan, por qué)].
    """
    importado = {}
    for rel, txt in textos.items():
        for m in re.finditer(r'^\s*(?:using|import)\s+([A-Za-z][A-Za-z0-9_, ]*)',
                             sin_comentarios(txt), re.M):
            for nombre in (p.strip().split(".")[0] for p in m.group(1).split(",")):
                if nombre and nombre != "Base":
                    importado.setdefault(nombre, []).append(rel)

    # Todo el código publicado, sin comentarios y sin las líneas de import,
    # que es donde un paquete se usaría de verdad.
    todo = []
    for txt in textos.values():
        cuerpo = sin_comentarios(txt)
        cuerpo = re.sub(r'^\s*(?:using|import)\s+.*$', "", cuerpo, flags=re.M)
        todo.append(cuerpo)
    todo = "\n".join(todo)

    out = []
    for nombre, donde in sorted(importado.items()):
        marcas = SIMBOLOS.get(nombre)
        if marcas is None:
            out.append((nombre, donde, "sin tabla de símbolos: añadir a SIMBOLOS"))
        elif not any(s in todo for s in marcas):
            out.append((nombre, donde,
                        "ningún símbolo de %s aparece en el conjunto publicado" % nombre))
    return out


def definiciones(txt):
    """Nombres de función definidos en el archivo."""
    nombres = set()
    cuerpo = sin_comentarios(txt)
    for m in re.finditer(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_!]*)\s*\(', cuerpo, re.M):
        nombres.add(m.group(1))
    # forma corta:  f(x) = ...
    for m in re.finditer(r'^\s*([a-z_][A-Za-z0-9_!]*)\s*\([^)]*\)\s*=\s*[^=]', cuerpo, re.M):
        nombres.add(m.group(1))
    return nombres


def main():
    global RAIZ
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--solo-seguros", action="store_true",
                    help="solo lo que tiene cero referencias en todo el repositorio")
    ap.add_argument("--raiz", default=RAIZ)
    args = ap.parse_args()
    RAIZ = os.path.abspath(args.raiz)

    jl = archivos_julia(RAIZ)
    textos = {}
    for rel in jl:
        textos[rel] = open(os.path.join(RAIZ, rel), encoding="utf-8",
                           errors="ignore").read()

    # ---------------- 1 · paquetes importados y no usados ----------------
    print("1 · paquetes importados y no usados")
    print("-" * 36)
    hallazgos_pkg = paquetes_no_usados(textos)
    for nombre, donde, por_que in hallazgos_pkg:
        print("  %-18s %s" % (nombre, por_que))
        for rel in donde:
            print("        lo importa  %s" % rel)
    if not hallazgos_pkg:
        print("  (ninguno)")

    # ---------------- 2 · funciones nunca llamadas ----------------
    # Referencias en TODO el repositorio, no solo en el código: una función
    # citada en la documentación no es invisible para el lector.
    otros = []
    for d in DIRS_TEXTO:
        base = os.path.join(RAIZ, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames
                           if not x.startswith(".") and x != "__pycache__"]
            for f in sorted(filenames):
                if os.path.splitext(f)[1] in (".md", ".py", ".sh", ".yaml",
                                              ".yml", ".ipynb", ".txt"):
                    try:
                        otros.append(open(os.path.join(dirpath, f),
                                          encoding="utf-8", errors="ignore").read())
                    except OSError:
                        pass
            if d == ".":
                break

    # Los comentarios y docstrings del código son documentación: una
    # función nombrada ahí y nunca llamada es código muerto documentado,
    # que es una decisión humana, no un borrado automático.
    otros.extend(solo_prosa(t) for t in textos.values())

    print("\n2 · funciones definidas y nunca llamadas")
    print("-" * 40)
    seguros, dudosos = [], []
    for rel in jl:
        for fn in sorted(definiciones(textos[rel])):
            # Referencias en el código, fuera de su propia definición. El
            # nombre a secas, sin exigir paréntesis: una función se pasa
            # como valor con frecuencia.
            n_codigo = 0
            for otro, t in textos.items():
                cuerpo = sin_comentarios(t)
                if otro == rel:
                    cuerpo = re.sub(r'^\s*function\s+%s\b.*$' % re.escape(fn),
                                    "", cuerpo, flags=re.M)
                    cuerpo = re.sub(r'^\s*%s\s*\([^)]*\)\s*=' % re.escape(fn),
                                    "", cuerpo, flags=re.M)
                n_codigo += len(re.findall(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])'
                                           % re.escape(fn), cuerpo))
            if n_codigo:
                continue
            n_texto = sum(1 for t in otros if fn in t)
            (dudosos if n_texto else seguros).append((rel, fn, n_texto))

    for rel, fn, n in seguros:
        print("  SEGURO   %-44s %-34s 0 referencias en el repositorio" % (rel, fn))
    if not args.solo_seguros:
        for rel, fn, n in dudosos:
            print("  dudoso   %-44s %-34s citada en %d archivo(s) de texto"
                  % (rel, fn, n))
    if not seguros and not dudosos:
        print("  (ninguna)")

    print("\n" + "=" * 74)
    print("%d archivos Julia · %d paquete(s) sin usar · %d función(es) segura(s) · %d dudosa(s)"
          % (len(jl), len(hallazgos_pkg), len(seguros), len(dudosos)))
    print("=" * 74)
    if hallazgos_pkg or seguros:
        print("""
Lo SEGURO se puede quitar sin leer: cero referencias en el código y cero
en la documentación. Lo dudoso hay que mirarlo: puede llamarse desde el
notebook, desde el REPL o por un nombre construido en ejecución.""")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
