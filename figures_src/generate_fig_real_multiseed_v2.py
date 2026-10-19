#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_fig_real_multiseed.py
==============================

Genera `figures/real_multiseed_v2.pdf` (main.tex, línea 1176,
fig:real_multiseed).

Tres paneles sobre las diez inicializaciones de la serie chilena:

  (a) I(t)            reconstrucción, con la frontera entrenamiento/prueba
  (b) beta(t,I)       tasa inferida, con beta = 0 como referencia de
                      admisibilidad física
  (c) R_eff(t)        con R_eff = 1 como umbral de crecimiento local

Reemplaza a la figura de una sola corrida. El argumento de la Sección 4.2
ya no es el ajuste de una semilla sino la estabilidad entre
inicializaciones, y una corrida única no puede mostrarla: invita además a
la objeción de que se eligió una semilla favorable.

Por eso los tres paneles dibujan las diez curvas individuales, finas, y
encima la mediana y el rango intercuartílico. La variabilidad entre
semillas es parte del resultado, no ruido que convenga suavizar, así que
las curvas individuales se mantienen legibles y la banda va por detrás.

Entrada: un directorio con subcarpetas seed1 .. seed10, cada una con
         real_data_curves.csv (206 filas; columnas dia, es_test,
         I_observado, I_UDE, I_Windowed, beta_UDE, beta_Windowed,
         Reff_UDE, Reff_Windowed).

Uso:
    python3 generate_fig_real_multiseed.py \\
        --multiseed-dir outputs/real_data_multiseed --outdir figures

Las cifras de la Sección 4.2.5 se recalculan desde estos mismos CSV y se
imprimen al final, para contrastarlas con el texto antes de publicar.
"""

import argparse
import csv
import glob
import os
import sys
import warnings

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

from style_figures import (
    set_mpl_style, guardar, figsize, LEGEND_KW,
    COLOR_UDE, COLOR_SWUDE, COLOR_TRUE, COLOR_REF, COLOR_NEUTRO,
    LS_UDE, LS_SWUDE, LINEWIDTH, LINEWIDTH_REF, LINEWIDTH_FINA,
    PT_ANOTACION, DIA_SPLIT_REAL, M_ADOPTADO_REAL,
)

# Las curvas individuales tienen que verse. La banda va detrás y no las
# sustituye: entre semillas la dispersión es el resultado.
ALPHA_INDIVIDUAL = 0.45
ALPHA_BANDA = 0.16

# El panel (a) se recorta: una de las diez corridas del UDE global llega a
# 6,5e5, dieciocho veces el máximo observado, y en escala completa aplasta
# todo lo demás. El recorte se anota dentro del panel.
TOPE_I_MILES = 100.0

METODOS = [
    ("UDE", "I_UDE", "beta_UDE", "Reff_UDE", COLOR_UDE, LS_UDE, "Global UDE"),
    ("SWUDE", "I_Windowed", "beta_Windowed", "Reff_Windowed", COLOR_SWUDE, LS_SWUDE,
     "SW-UDE ($m=%d$)" % M_ADOPTADO_REAL),
]


def leer_curvas(path):
    filas = list(csv.DictReader(open(path)))
    datos = {}
    for c in filas[0]:
        if c == "es_test":
            datos[c] = np.array([f[c].strip().lower() == "true" for f in filas])
        else:
            datos[c] = np.array([np.nan if f[c] in ("", "NaN") else float(f[c])
                                 for f in filas])
    return datos


def cargar(multiseed_dir):
    rutas = sorted(glob.glob(os.path.join(multiseed_dir, "seed*", "real_data_curves.csv")),
                   key=lambda s: int(os.path.basename(os.path.dirname(s))[4:]))
    if not rutas:
        return None, None
    return [leer_curvas(p) for p in rutas], [os.path.basename(os.path.dirname(p)) for p in rutas]


def banda(series):
    """Mediana y cuartiles a lo largo de las semillas, día a día.

    La última fila de beta y R_eff es NaN en las diez semillas —están
    definidas sobre transiciones, no sobre estados—, así que esa columna
    es un corte todo-NaN. numpy avisa; el resultado NaN es el correcto, de
    modo que el aviso se silencia en vez de enmascarar el dato.
    """
    m = np.vstack(series)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        return (np.nanmedian(m, axis=0),
                np.nanpercentile(m, 25, axis=0),
                np.nanpercentile(m, 75, axis=0))


def dibujar(ax, dia, por_semilla, color, ls, escala=1.0):
    series = [v / escala for v in por_semilla]
    for v in series:
        ax.plot(dia, v, color=color, lw=LINEWIDTH_FINA, alpha=ALPHA_INDIVIDUAL,
                solid_capstyle="round", zorder=3)
    med, q1, q3 = banda(series)
    ax.fill_between(dia, q1, q3, color=color, alpha=ALPHA_BANDA, lw=0, zorder=2)
    ax.plot(dia, med, color=color, ls=ls, lw=LINEWIDTH + 0.2, zorder=5)


def cifras_425(seeds):
    """Recalcula las cifras que la Sección 4.2.5 cita."""
    def tramos(v, minimo=15):
        ok = np.isfinite(v) & (v > 1.0)
        out, i = [], 0
        while i < len(ok):
            if ok[i]:
                j = i
                while j + 1 < len(ok) and ok[j + 1]:
                    j += 1
                if j - i + 1 >= minimo:
                    out.append((i, j))
                i = j + 1
            else:
                i += 1
        return out

    dia = seeds[0]["dia"]
    r = {}
    for etiqueta, bcol, rcol in (("SW-UDE", "beta_Windowed", "Reff_Windowed"),
                                 ("UDE", "beta_UDE", "Reff_UDE")):
        bs = [d[bcol][np.isfinite(d[bcol])] for d in seeds]
        inicios, rmax = [], []
        for d in seeds:
            t = tramos(d[rcol])
            inicios.append(dia[t[0][0]] if t else np.nan)
            rmax.append(np.nanmax(d[rcol]))
        r[etiqueta] = dict(
            beta_min=min(b.min() for b in bs), beta_max=max(b.max() for b in bs),
            negativas=sum(bool((b < 0).any()) for b in bs),
            inicio_min=np.nanmin(inicios), inicio_max=np.nanmax(inicios),
            rmax_media=float(np.mean(rmax)), rmax_sd=float(np.std(rmax, ddof=1)),
            rmax_peor=max(rmax))
    return r


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # Por omisión, results/ del repositorio, resuelto desde la ubicación de
    # este archivo. "outputs/..." era la disposición del árbol de trabajo y
    # aquí no existe, así que el script fallaba si se invocaba suelto.
    ap.add_argument("--multiseed-dir", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "results", "datos_reales_multiseed"))
    ap.add_argument("--outdir", default="figures")
    args = ap.parse_args()

    seeds, nombres = cargar(args.multiseed_dir)
    if seeds is None:
        print("ERROR -- no encontré seed*/real_data_curves.csv en %s" % args.multiseed_dir)
        return 1
    print("[multiseed] %d semillas: %s" % (len(seeds), ", ".join(nombres)))

    set_mpl_style()
    dia = seeds[0]["dia"]
    t_split = float(DIA_SPLIT_REAL)

    fig, (axa, axb, axc) = plt.subplots(3, 1, figsize=figsize(6.5), sharex=True,
                                        constrained_layout=True)

    # ---------------- (a) I(t) ----------------
    for _, icol, _, _, color, ls, _ in METODOS:
        dibujar(axa, dia, [d[icol] for d in seeds], color, ls, escala=1e3)
    axa.plot(dia, seeds[0]["I_observado"] / 1e3, color=COLOR_TRUE, ls="-",
             lw=LINEWIDTH + 0.4, zorder=6)
    axa.axvline(t_split, color=COLOR_REF, ls="-", lw=LINEWIDTH_REF, zorder=1)
    axa.set_ylim(0, TOPE_I_MILES)
    axa.set_ylabel(r"$I(t)$ (thousands of cases)")
    axa.set_title("(a) Reconstruction of $I(t)$", loc="left")

    fuera = sum(np.nanmax(d["I_UDE"]) / 1e3 > TOPE_I_MILES for d in seeds)
    if fuera:
        peor = max(np.nanmax(d["I_UDE"]) for d in seeds)
        axa.annotate("%d global-UDE run%s off scale (max %.1f$\\times10^{5}$)"
                     % (fuera, "" if fuera == 1 else "s", peor / 1e5),
                     xy=(0.015, 0.93), xycoords="axes fraction",
                     fontsize=PT_ANOTACION, color=COLOR_NEUTRO, ha="left", va="top")

    axa.annotate("Training", xy=(t_split - 3, TOPE_I_MILES * 0.985), ha="right", va="top",
                 fontsize=PT_ANOTACION, color=COLOR_NEUTRO)
    axa.annotate("Held-out", xy=(t_split + 3, TOPE_I_MILES * 0.985), ha="left", va="top",
                 fontsize=PT_ANOTACION, color=COLOR_NEUTRO)

    # ---------------- (b) beta(t,I) ----------------
    for _, _, bcol, _, color, ls, _ in METODOS:
        dibujar(axb, dia, [d[bcol] for d in seeds], color, ls)
    axb.axhline(0.0, color=COLOR_TRUE, ls=(0, (3, 2)), lw=LINEWIDTH_REF, zorder=4)
    axb.axvline(t_split, color=COLOR_REF, ls="-", lw=LINEWIDTH_REF, zorder=1)
    axb.set_ylabel(r"$\widehat{\beta}(t,I)$")
    axb.set_title(r"(b) Inferred transmission rate", loc="left")
    axb.annotate(r"$\beta=0$: physical admissibility", xy=(2, 0.0), xytext=(2, 6),
                 textcoords="offset points", fontsize=PT_ANOTACION,
                 color=COLOR_NEUTRO, ha="left", va="bottom")

    # ---------------- (c) R_eff(t) ----------------
    for _, _, _, rcol, color, ls, _ in METODOS:
        dibujar(axc, dia, [d[rcol] for d in seeds], color, ls)
    axc.axhline(1.0, color=COLOR_TRUE, ls=(0, (3, 2)), lw=LINEWIDTH_REF, zorder=4)
    axc.axvline(t_split, color=COLOR_REF, ls="-", lw=LINEWIDTH_REF, zorder=1)
    axc.set_ylabel(r"$R_{\mathrm{eff}}(t)$")
    axc.set_xlabel(r"$t$ (days)")
    axc.set_xlim(float(dia.min()), float(dia.max()))
    axc.set_title(r"(c) Effective reproduction number", loc="left")
    axc.annotate(r"$R_{\mathrm{eff}}=1$: local growth threshold", xy=(2, 1.0),
                 xytext=(2, 6), textcoords="offset points", fontsize=PT_ANOTACION,
                 color=COLOR_NEUTRO, ha="left", va="bottom")

    manejadores = [
        Line2D([], [], color=COLOR_TRUE, ls="-", lw=LINEWIDTH + 0.4, label="Observed"),
    ] + [
        Line2D([], [], color=c, ls=ls, lw=LINEWIDTH + 0.2, label=et)
        for _, _, _, _, c, ls, et in METODOS
    ] + [
        Line2D([], [], color=COLOR_NEUTRO, lw=LINEWIDTH_FINA, alpha=ALPHA_INDIVIDUAL,
               label="Individual initializations ($n=%d$)" % len(seeds)),
        Line2D([], [], color=COLOR_NEUTRO, lw=6, alpha=ALPHA_BANDA + 0.12,
               label="Interquartile range"),
    ]
    fig.legend(handles=manejadores, loc="lower center", ncol=3, frameon=False,
               fontsize=LEGEND_KW["fontsize"], bbox_to_anchor=(0.5, -0.055),
               columnspacing=1.4, handletextpad=0.6, handlelength=2.2)

    out = guardar(fig, args.outdir, "real_multiseed_v2")
    plt.close(fig)
    print("escrito:", os.path.abspath(out))

    c = cifras_425(seeds)
    print("\nCifras de la Sección 4.2.5 recalculadas desde estos CSV:")
    print("  SW-UDE beta en [%.3f, %.3f]; corridas con beta<0: %d"
          % (c["SW-UDE"]["beta_min"], c["SW-UDE"]["beta_max"], c["SW-UDE"]["negativas"]))
    print("  UDE    beta mínimo %.3f; corridas con beta<0: %d"
          % (c["UDE"]["beta_min"], c["UDE"]["negativas"]))
    print("  SW-UDE cruce sostenido de R_eff entre t=%d y t=%d"
          % (c["SW-UDE"]["inicio_min"], c["SW-UDE"]["inicio_max"]))
    print("  UDE    cruce sostenido entre t=%d y t=%d"
          % (c["UDE"]["inicio_min"], c["UDE"]["inicio_max"]))
    print("  R_eff máximo: SW-UDE %.3f±%.3f · UDE %.3f±%.3f (peor corrida %.3f)"
          % (c["SW-UDE"]["rmax_media"], c["SW-UDE"]["rmax_sd"],
             c["UDE"]["rmax_media"], c["UDE"]["rmax_sd"], c["UDE"]["rmax_peor"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
