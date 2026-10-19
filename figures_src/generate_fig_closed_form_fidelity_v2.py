#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_fig_closed_form_fidelity.py
====================================

Genera `figures/closed_form_fidelity_v2.pdf` (main.tex, línea 1343,
fig:closed_form_fidelity).

Dos paneles sobre las tres formas cerradas de primer plano:

  (a) Fidelidad funcional -- aproximación puntual a beta_SW-UDE
  (b) Fidelidad dinámica  -- reconstrucción autónoma en el tramo de prueba

Sustituye a `generate_fig_distillation_dos_paneles.py`. Cambios respecto de
aquella versión:

- Todo el texto en inglés, con los rótulos de main.tex: "Functional
  fidelity" y "Dynamical fidelity".
- La curva de SW-UDE ya no se llama "objetivo". beta_SW-UDE es también
  una estimación, no una verdad conocida, y el manuscrito es explícito:
  "Neither criterion constitutes validation against beta_true".
- Colores y tamaños del módulo central `style_figures.py`, no definidos
  aquí. El rojo de la versión anterior (#d62728) y el verde de E
  (#2ca02c) se separaban ΔE 3,9 bajo deuteranopía y aparecían juntos en
  el panel (a).
- Se dibuja al ancho final de la caja del documento, sin reescalado.

Entrada: results/distillation_v51/trajectories.csv
Uso:
    python3 generate_fig_closed_form_fidelity.py \\
        --trajectories results/distillation_v51/trajectories.csv --outdir figures
"""

import argparse
import csv
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from style_figures import (
    set_mpl_style, guardar, figsize, LEGEND_KW,
    COLOR_SWUDE, COLOR_TRUE, COLOR_REF, COLOR_NEUTRO, ESTILO_FAMILIA,
    LINEWIDTH, LINEWIDTH_REF, PT_ANOTACION, DIA_SPLIT_REAL,
)

# clave en el CSV -> etiqueta del artículo. El color y el trazo salen de
# ESTILO_FAMILIA, que es donde está la decisión y su justificación.
FORMAS = [("M1", "M1"), ("M2", "M2"), ("C15", "E")]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--trajectories", default="results/distillation_v51/trajectories.csv")
    ap.add_argument("--outdir", default="figures")
    args = ap.parse_args()

    if not os.path.exists(args.trajectories):
        print("ERROR -- no se encontró: %s" % args.trajectories)
        return 1

    set_mpl_style()
    rows = list(csv.DictReader(open(args.trajectories)))

    def col(name):
        return np.array([np.nan if rows[i][name] in ("", "NaN") else float(rows[i][name])
                         for i in range(len(rows))])

    t = col("t")
    conj = np.array([r["conjunto"] for r in rows])
    I_obs, I_swude, beta_swude = col("I_observado"), col("I_SWUDE"), col("beta_SWUDE")
    t_split = float(DIA_SPLIT_REAL)

    # Persistencia: I(t) = I(164) para todo t > 164.
    I_pers = float(I_obs[np.argmin(np.abs(t - t_split))])

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=figsize(4.4))

    # ------------------------------------------------------------------
    # (a) Fidelidad funcional
    # ------------------------------------------------------------------
    m = np.isfinite(beta_swude)
    ax1.axvspan(t_split, float(np.nanmax(t)), color=COLOR_REF, alpha=0.09, lw=0, zorder=0)
    ax1.axvline(t_split, color=COLOR_REF, ls="-", lw=LINEWIDTH_REF, zorder=1)

    ax1.plot(t[m], beta_swude[m], color=COLOR_SWUDE, ls=(0, (1, 1.4)), lw=1.9,
             label=r"$\widehat{\beta}$ (SW-UDE)", zorder=5)
    for clave, etiq in FORMAS:
        ax1.plot(t[m], col("beta_%s" % clave)[m], lw=LINEWIDTH,
                 label=etiq, zorder=4, **ESTILO_FAMILIA[etiq])

    ax1.set_ylabel(r"$\beta(t,I)$")
    ax1.set_xlabel(r"$t$ (days)")
    ax1.set_xlim(0, float(np.nanmax(t)))
    ax1.set_title("(a) Functional fidelity", loc="left")
    ax1.legend(ncol=4, loc="lower right", **LEGEND_KW)

    # Qué lado es cuál, sin recargar: dos palabras sobre la línea de corte.
    y_tope = ax1.get_ylim()[1]
    ax1.annotate("Training", xy=(t_split - 3, y_tope), ha="right", va="top",
                 fontsize=PT_ANOTACION, color=COLOR_NEUTRO)
    ax1.annotate("Held-out", xy=(t_split + 3, y_tope), ha="left", va="top",
                 fontsize=PT_ANOTACION, color=COLOR_NEUTRO)

    # ------------------------------------------------------------------
    # (b) Fidelidad dinámica
    # ------------------------------------------------------------------
    te = conj == "test"
    tt = t[te]

    ax2.plot(tt, I_obs[te] / 1e3, color=COLOR_TRUE, ls="-", lw=LINEWIDTH + 0.3,
             label="Observed", zorder=6)
    ax2.hlines(I_pers / 1e3, tt.min(), tt.max(), color=COLOR_REF, ls=(0, (3, 2)),
               lw=LINEWIDTH_REF, label="Persistence", zorder=2)
    ax2.plot(tt, I_swude[te] / 1e3, color=COLOR_SWUDE, ls=(0, (1, 1.4)), lw=1.9,
             label="SW-UDE", zorder=5)
    for clave, etiq in FORMAS:
        ax2.plot(tt, col("I_%s" % clave)[te] / 1e3, lw=LINEWIDTH,
                 label="SIR + " + etiq, zorder=4, **ESTILO_FAMILIA[etiq])

    ax2.set_ylabel(r"$I(t)$ (thousands of cases)")
    ax2.set_xlabel(r"$t$ (days)")
    ax2.set_xlim(tt.min(), tt.max())
    ax2.set_title("(b) Dynamical fidelity", loc="left")
    ax2.legend(ncol=3, loc="upper left", **LEGEND_KW)

    fig.tight_layout(pad=0.4)
    out = guardar(fig, args.outdir, "closed_form_fidelity_v2")
    plt.close(fig)
    print("escrito:", os.path.abspath(out))
    print("I_persistence = %.1f" % I_pers)
    return 0


if __name__ == "__main__":
    sys.exit(main())
