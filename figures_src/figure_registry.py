#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
figure_registry.py — genera las seis figuras de main.tex y las muestra
dentro de un notebook.

    from figure_registry import generar_y_mostrar
    generar_y_mostrar(outputs_dir=None)        # las seis
    generar_y_mostrar("real_multiseed_v2")          # una sola

También sirve desde la línea de comandos, que es como lo invoca
`regenerate_all_figures.sh`:

    python3 figure_registry.py --outputs-dir results --outdir figures
    python3 figure_registry.py m_sensitivity_v2 real_multiseed_v2

Los CSV de la destilación —figuras 5 y 6— pueden estar fuera de
`results/`: en la corrida de septiembre el módulo escribió en el
directorio de trabajo del notebook. Si es el caso, se indica aparte:

    fn.localizar_destilacion("~/codigos/SW_UDE")   # los busca
    fn.usar_destilacion("<la ruta que salga>")     # los fija

Este archivo es el **registro único** de las figuras del artículo. El
script de shell no mantiene su propia lista: la duplicación era la vía
segura para que una figura se regenerara con argumentos viejos.

Cada figura se genera en un proceso aparte, con el mismo intérprete del
kernel. Así una corrida desde el notebook produce exactamente el mismo
PDF que la de shell —incluido `SOURCE_DATE_EPOCH`, que los hace byte a
byte reproducibles— y el estado de matplotlib del notebook no contamina
el de las figuras ni al revés.

Lo que se muestra en el notebook es el PNG de control que cada script
escribe junto al PDF. El PDF es lo que compila LaTeX; el PNG sale del
mismo `savefig` y sirve para mirarlo.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)   # la raíz del repositorio, no el cwd

# Por omisión se trabaja contra el repositorio, se invoque desde donde se
# invoque. Antes eran rutas relativas al directorio actual, de modo que
# llamar al script desde dentro de figures_src/ escribía las figuras en
# figures_src/figures/ en vez de en figures/.
RESULTS_DEF = os.path.join(RAIZ, "results")
FIGURES_DEF = os.path.join(RAIZ, "figures")

# Fecha fija y arbitraria. matplotlib estampa la fecha de creación dentro
# del PDF; sin esto dos corridas del mismo script dan huellas distintas y
# results/MANIFEST.sha256 deja de cuadrar sin que nada esté mal.
EPOCA_FIJA = "1577836800"


class Figura:
    """Una figura del manuscrito y cómo producirla."""

    def __init__(self, nombre, numero, titulo, script, args):
        self.nombre = nombre        # nombre del archivo, sin extensión
        self.numero = numero        # orden de aparición en main.tex
        self.titulo = titulo
        self.script = script
        self._args = args           # función(outputs_dir, outdir) -> list[str]

    def args(self, outputs_dir, outdir):
        return self._args(outputs_dir, outdir)

    def __repr__(self):
        return "<Figura %d %s>" % (self.numero, self.nombre)


# Los CSV de la destilación (figuras 5 y 6) no viven necesariamente bajo
# results/. En la corrida de septiembre el módulo escribió en el
# directorio de trabajo del notebook, no en el árbol de salidas, así que
# su ubicación es un parámetro aparte. localizar_destilacion() ayuda a
# encontrarla.
DESTILACION_DIR = None


def _dest(outputs_dir):
    return DESTILACION_DIR or os.path.join(outputs_dir, "destilacion_v51")


ARCHIVOS_DESTILACION = ("trajectories.csv", "summary_families.csv")


def localizar_destilacion(raiz, profundidad=6):
    """Busca bajo `raiz` el directorio que tiene los CSV de la destilación.

    Devuelve la lista de candidatos, el primero el más probable. Pensado
    para cuando la corrida dejó las salidas fuera del árbol de resultados.
    """
    raiz = os.path.abspath(os.path.expanduser(raiz))
    base = raiz.rstrip(os.sep).count(os.sep)
    encontrados = []
    for dirpath, dirnames, filenames in os.walk(raiz):
        if dirpath.count(os.sep) - base >= profundidad:
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if not d.startswith((".", "__"))]
        if all(a in filenames for a in ARCHIVOS_DESTILACION):
            encontrados.append(dirpath)
    for d in encontrados:
        print("  " + d)
    if not encontrados:
        print("  (no encontré ningún directorio con %s bajo %s)"
              % (" y ".join(ARCHIVOS_DESTILACION), raiz))
    return encontrados


def usar_destilacion(directorio):
    """Fija de dónde salen los CSV de las figuras 5 y 6."""
    global DESTILACION_DIR
    DESTILACION_DIR = os.path.abspath(os.path.expanduser(directorio)) if directorio else None
    faltan = [a for a in ARCHIVOS_DESTILACION
              if DESTILACION_DIR and not os.path.exists(os.path.join(DESTILACION_DIR, a))]
    if DESTILACION_DIR is None:
        print("destilación: vuelve a <outputs_dir>/distillation_v51")
    elif faltan:
        print("AVISO -- en %s faltan: %s" % (DESTILACION_DIR, ", ".join(faltan)))
    else:
        print("destilación: %s" % DESTILACION_DIR)
    return DESTILACION_DIR


FIGURAS = [
    Figura("temporal_supervision_horizon", 1,
           "Horizonte de supervisión temporal (esquema)",
           "generate_fig_temporal_supervision_horizon.py",
           lambda o, d: ["--outdir", d]),
    Figura("hospital_state_reconstruction", 2,
           "Reconstrucción de estados, saturación hospitalaria",
           "generate_fig_hospital_state_reconstruction.py",
           lambda o, d: ["--outputs-dir", o, "--outdir", d]),
    Figura("m_sensitivity_v2", 3,
           "Sensibilidad al horizonte de supervisión",
           "generate_fig_m_sensitivity_v2.py",
           lambda o, d: ["--outputs-dir", o, "--outdir", d]),
    Figura("real_multiseed_v2", 4,
           "Serie chilena, diez inicializaciones",
           "generate_fig_real_multiseed_v2.py",
           lambda o, d: ["--multiseed-dir", os.path.join(o, "datos_reales_multiseed"),
                         "--outdir", d]),
    Figura("closed_form_fidelity_v2", 5,
           "Fidelidad funcional y dinámica de las formas cerradas",
           "generate_fig_closed_form_fidelity_v2.py",
           lambda o, d: ["--trajectories", os.path.join(_dest(o), "trajectories.csv"),
                         "--outdir", d]),
    Figura("closed_form_fidelity_plane_v2", 6,
           "Plano de las dos fidelidades, trece familias",
           "generate_fig_closed_form_fidelity_plane_v2.py",
           lambda o, d: ["--resumen", os.path.join(_dest(o), "summary_families.csv"),
                         "--outdir", d]),
]

POR_NOMBRE = {f.nombre: f for f in FIGURAS}


def _resolver(cuales):
    """Acepta None, un nombre, un número o una lista de cualquiera de los dos."""
    if cuales is None:
        return list(FIGURAS)
    if isinstance(cuales, (str, int)):
        cuales = [cuales]
    salida = []
    for c in cuales:
        if isinstance(c, Figura):
            salida.append(c)
        elif isinstance(c, int) or (isinstance(c, str) and c.isdigit()):
            n = int(c)
            coincide = [f for f in FIGURAS if f.numero == n]
            if not coincide:
                raise ValueError("no hay figura número %d (1 a %d)" % (n, len(FIGURAS)))
            salida.append(coincide[0])
        elif c in POR_NOMBRE:
            salida.append(POR_NOMBRE[c])
        else:
            raise ValueError("figura desconocida: %r. Conocidas: %s"
                             % (c, ", ".join(POR_NOMBRE)))
    return salida


def _en_notebook():
    try:
        from IPython import get_ipython
        return get_ipython() is not None and "IPKernelApp" in get_ipython().config
    except Exception:
        return False


def generar(cuales=None, outputs_dir=None, outdir=None, verboso=True,
            destilacion_dir=None):
    """Genera las figuras pedidas. Devuelve {nombre: ruta_del_pdf | None}.

    Una figura que falla no detiene a las demás: se informa y se sigue.
    Con los bloques del repositorio a medio poblar, eso es lo útil.
    """
    if destilacion_dir is not None:
        usar_destilacion(destilacion_dir)
    outputs_dir = os.path.abspath(outputs_dir or RESULTS_DEF)
    outdir = os.path.abspath(outdir or FIGURES_DEF)
    os.makedirs(outdir, exist_ok=True)

    entorno = dict(os.environ)
    entorno.setdefault("SOURCE_DATE_EPOCH", EPOCA_FIJA)
    entorno["MPLBACKEND"] = "Agg"

    resultados = {}
    for fig in _resolver(cuales):
        orden = [sys.executable, os.path.join(AQUI, fig.script)] + fig.args(outputs_dir, outdir)
        proc = subprocess.run(orden, cwd=AQUI, env=entorno,
                              capture_output=True, text=True)
        pdf = os.path.join(outdir, fig.nombre + ".pdf")
        ok = proc.returncode == 0 and os.path.exists(pdf)
        resultados[fig.nombre] = pdf if ok else None

        if verboso:
            print("[%d] %s — %s" % (fig.numero, fig.nombre, "ok" if ok else "FALLÓ"))
            for linea in proc.stdout.splitlines():
                # El ruido de rutas no aporta; los avisos de estilo y las
                # cifras recalculadas de la Sección 4.2.5 sí.
                if linea.startswith(("escrito:", "[S2_v2] Guardado", "[S4] Guardado")):
                    continue
                if linea.strip():
                    print("    " + linea)
            if not ok:
                for linea in proc.stderr.strip().splitlines()[-12:]:
                    print("    ! " + linea)
                if "ModuleNotFoundError" in proc.stderr:
                    print("    > Falta una dependencia de Python. En Debian y Ubuntu")
                    print("      pip al Python del sistema está bloqueado (PEP 668),")
                    print("      así que lo más simple es un entorno virtual:")
                    print("        python3 -m venv .venv && source .venv/bin/activate")
                    print("        pip install -r figures_src/requirements.txt")
                    print("      Ver docs/ENVIRONMENT.md. El verificador de cifras no")
                    print("      necesita ninguna: python3 verify/verify_values.py")
                if fig.numero in (5, 6) and DESTILACION_DIR is None:
                    print("    > Los CSV de la destilación suelen estar fuera")
                    print("      del árbol de resultados. Búscalos y fija su ruta:")
                    print("        fn.localizar_destilacion('~/codigos/SW_UDE')")
                    print("        fn.usar_destilacion('<la ruta que salga>')")
    return resultados


def mostrar(cuales=None, outdir=None, ancho=900, titulos=True):
    """Muestra en el notebook los PNG de control ya generados."""
    outdir = os.path.abspath(outdir or FIGURES_DEF)
    figs = _resolver(cuales)

    if not _en_notebook():
        for fig in figs:
            png = os.path.join(outdir, fig.nombre + ".png")
            print("%s %s" % ("  " if os.path.exists(png) else "? ", png))
        return

    from IPython.display import display, Image, Markdown

    for fig in figs:
        png = os.path.join(outdir, fig.nombre + ".png")
        if titulos:
            display(Markdown("**Figura %d — %s**  \n`%s.pdf`"
                             % (fig.numero, fig.titulo, fig.nombre)))
        if os.path.exists(png):
            display(Image(filename=png, width=ancho))
        else:
            display(Markdown("> No existe `%s`. Generala primero con `generar()`." % png))


def generar_y_mostrar(cuales=None, outputs_dir=None, outdir=None,
                      ancho=900, verboso=True, destilacion_dir=None):
    """Genera y muestra, que es lo que se quiere el 90 % de las veces."""
    res = generar(cuales, outputs_dir=outputs_dir, outdir=outdir, verboso=verboso,
                  destilacion_dir=destilacion_dir)
    mostrar([n for n, p in res.items() if p], outdir=outdir, ancho=ancho)
    faltan = [n for n, p in res.items() if not p]
    if faltan:
        print("\nNo se generaron: %s" % ", ".join(faltan))
    return res


def catalogo():
    """Qué figuras hay, en el orden en que aparecen en main.tex."""
    print("%-3s %-32s %s" % ("#", "archivo", "script"))
    for f in FIGURAS:
        print("%-3d %-32s %s" % (f.numero, f.nombre + ".pdf", f.script))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Genera las figuras de main.tex.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("figuras", nargs="*",
                    help="Nombres o números; vacío = las seis.")
    ap.add_argument("--outputs-dir", default=None,
                    help="Carpeta de resultados (por omisión, results/ del repositorio).")
    ap.add_argument("--outdir", default=None,
                    help="Carpeta de salida (por omisión, figures/ del repositorio).")
    ap.add_argument("--destilacion-dir", default=None,
                    help="Directorio con trajectories.csv y summary_families.csv "
                         "(figuras 5 y 6). Por omisión <outputs-dir>/destilacion_v51.")
    ap.add_argument("--catalogo", action="store_true", help="Lista las figuras y sale.")
    args = ap.parse_args(argv)

    if args.catalogo:
        catalogo()
        return 0

    res = generar(args.figuras or None, outputs_dir=args.outputs_dir,
                  outdir=args.outdir, destilacion_dir=args.destilacion_dir)
    faltan = [n for n, p in res.items() if not p]
    print("\n%d de %d generadas en %s" % (len(res) - len(faltan), len(res),
                                          os.path.abspath(args.outdir or FIGURES_DEF)))
    if faltan:
        print("No se generaron: %s" % ", ".join(faltan))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
