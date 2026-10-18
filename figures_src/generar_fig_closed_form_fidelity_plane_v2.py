#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generar_fig_closed_form_fidelity_plane.py
==========================================

Genera `figures/closed_form_fidelity_plane_v2.pdf` (main.tex, línea 1421,
fig:fidelity_plane).

Plano de las dos fidelidades para las trece familias destiladas:

    x : RMSE_beta / RMSE_beta,persistencia   (fidelidad funcional)
    y : RMSE_I    / RMSE_I,persistencia      (fidelidad dinámica)

Ambos ejes logarítmicos. Las líneas en 1 son la persistencia de cada eje,
de modo que el cuadrante inferior izquierdo contiene las familias que la
superan en los dos.

Sustituye a `generar_fig_destilacion_plano.py`. Cambios:

- Texto en inglés. Las etiquetas de los ejes estaban escritas a mano con
  coma decimal ("0,3", "0,5"); ahora son punto decimal.
- Jerarquía de lectura: el contraste principal del análisis es M1 frente
  a M2, y antes los tres de primer plano —M1, M2 y E— llevaban el mismo
  realce, de modo que E competía. Ahora solo M1 y M2 van con etiqueta en
  negrita y borde grueso; E se ve, un escalón atrás, como sensibilidad.
- E era verde #2ca02c, el mismo color del rectángulo "better than
  persistence": un marcador verde dentro de una región verde.
- Colores y tamaños del módulo central, al ancho final de la caja.

La forma del marcador codifica el mecanismo y el dígito de adentro es el
número de parámetros k, de modo que la identidad nunca depende solo del
color.

Entrada: results/destilacion_v51/resumen_familias.csv
Uso:
    python3 generar_fig_closed_form_fidelity_plane.py \\
        --resumen results/destilacion_v51/resumen_familias.csv --outdir figures
"""

import argparse
import csv
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Rectangle

from estilo_figuras import (
    set_mpl_style, guardar, figsize, FRAC_PLANO,
    COLOR_CLOSED, COLOR_NEUTRO, COLOR_FONDO, COLOR_REF, TINTA,
    PT_ANOTACION, PT_LEYENDA, FAMILIAS_PRIMER_PLANO,
)

# clave de implementación -> etiqueta del manuscrito
NOM = {"M1": "M1", "M2": "M2", "C15": "E", "C1": "S1", "C4": "S2", "C5": "S3",
       "C6": "S4", "C7": "S5", "C8": "S6", "C12": "S7", "C9": "S8",
       "C11": "S9", "C13": "S10"}

# clase de mecanismo -> (marcador, etiqueta de leyenda)
CLASE = {"t":   ("o", "Time dependence only"),
         "lin": ("s", "Linear state feedback"),
         "sat": ("^", "Saturating incidence"),
         "exp": ("D", "Exponential link")}

MEC = {"M1": "t", "S1": "t",
       "M2": "lin", "S7": "lin", "S8": "lin", "S9": "lin", "S10": "lin",
       "S2": "sat", "S3": "sat", "S4": "sat", "S5": "sat", "S6": "sat",
       "E": "exp"}

# Tres niveles de lectura: M1 y M2 primero, E después, las diez de
# sensibilidad al fondo.
COLOR_POR_NOMBRE = {"M1": COLOR_CLOSED, "M2": COLOR_CLOSED, "E": COLOR_NEUTRO}

# Desplazamiento manual de cada etiqueta, como factor multiplicativo
# sobre la posición del punto (los ejes son logarítmicos).
OFF = {"M1": (0.93, 0.945, "right", "top"), "S9": (1.00, 1.065, "center", "bottom"),
       "S10": (1.13, 1.00, "left", "center"), "M2": (1.14, 1.00, "left", "center"),
       "S8": (1.15, 1.00, "left", "center"), "S1": (1.14, 1.00, "left", "center"),
       "E": (1.15, 1.00, "left", "center"), "S4": (0.99, 0.935, "center", "top"),
       "S2": (0.89, 1.070, "right", "bottom"), "S3": (1.00, 1.090, "center", "bottom"),
       "S5": (1.15, 1.00, "left", "center"), "S7": (1.15, 1.00, "left", "center"),
       "S6": (1.15, 1.00, "left", "center")}


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--resumen", default="results/destilacion_v51/resumen_familias.csv")
    ap.add_argument("--outdir", default="figures")
    args = ap.parse_args()

    if not os.path.exists(args.resumen):
        print("ERROR -- no se encontró: %s" % args.resumen)
        return 1

    set_mpl_style()
    datos = [(NOM[r["clave"]], int(r["k"]), float(r["coc_beta_pers"]),
              float(r["coc_I_pers"])) for r in csv.DictReader(open(args.resumen))]

    fig, ax = plt.subplots(figsize=figsize(4.3, FRAC_PLANO))
    ax.set_xscale("log")
    ax.set_yscale("log")
    XL, YL = (0.20, 12.0), (0.135, 1.45)
    ax.set_xlim(*XL)
    ax.set_ylim(*YL)

    # Región que supera a la persistencia en los dos ejes.
    ax.add_patch(Rectangle((XL[0], YL[0]), 1 - XL[0], 1 - YL[0],
                           facecolor=COLOR_CLOSED, alpha=0.06, lw=0, zorder=0))
    ax.axvline(1, color=COLOR_REF, lw=0.8, zorder=1)
    ax.axhline(1, color=COLOR_REF, lw=0.8, zorder=1)

    for nom, k, xb, yi in datos:
        primer_plano = nom in FAMILIAS_PRIMER_PLANO
        color = COLOR_POR_NOMBRE.get(nom, COLOR_FONDO)
        z = 5 if primer_plano else (4 if nom == "E" else 3)
        marcador = CLASE[MEC[nom]][0]

        ax.scatter(xb, yi, s=120, marker=marcador, facecolor="white",
                   edgecolor=color, linewidth=1.5 if primer_plano else 0.9,
                   zorder=z)
        # El centroide del triángulo no coincide con el centro del marcador.
        dy = -1.6 if marcador == "^" else 0.0
        ax.annotate(str(k), (xb, yi), xytext=(0, dy), textcoords="offset points",
                    ha="center", va="center", fontsize=PT_ANOTACION, color=color,
                    fontweight="bold" if primer_plano else "normal", zorder=z + 1)

        fx, fy, ha, va = OFF[nom]
        ax.annotate(nom, (xb * fx, yi * fy), fontsize=PT_LEYENDA,
                    color=TINTA if primer_plano else COLOR_NEUTRO,
                    ha=ha, va=va, zorder=8,
                    fontweight="bold" if primer_plano else "normal")

    ax.set_xlabel(r"Functional fidelity:  "
                  r"$\mathrm{RMSE}_\beta\,/\,\mathrm{RMSE}_{\beta,\mathrm{pers}}$")
    ax.set_ylabel(r"Dynamical fidelity:  "
                  r"$\mathrm{RMSE}_I\,/\,\mathrm{RMSE}_{I,\mathrm{pers}}$")
    ax.set_xticks([0.3, 0.5, 1, 2, 3, 5, 8])
    ax.set_xticklabels(["0.3", "0.5", "1", "2", "3", "5", "8"])
    ax.set_yticks([0.2, 0.3, 0.5, 0.7, 1.0])
    ax.set_yticklabels(["0.2", "0.3", "0.5", "0.7", "1"])
    ax.minorticks_off()

    ax.text(0.215, 0.147, "Better than persistence\non both axes",
            fontsize=PT_ANOTACION, color="#2F6F5A", va="bottom", ha="left",
            style="italic", zorder=2)

    handles = [Line2D([], [], marker=mk, ls="none", markerfacecolor="none",
                      markeredgecolor=TINTA, markersize=5, label=lab)
               for mk, lab in CLASE.values()]
    # Abajo a la derecha: el cuadrante alto en x y bajo en y está vacío.
    # Arriba a la izquierda el recuadro tapaba M1, S9 y S10, es decir las
    # tres familias de la región que la figura quiere mostrar.
    ax.legend(handles=handles, title="Functional form\n(number inside marker: $k$)",
              loc="lower right", frameon=True, framealpha=1.0, facecolor="white",
              edgecolor="#CCCCCC", fontsize=PT_LEYENDA, handletextpad=0.5,
              borderpad=0.5, labelspacing=0.45)
    ax.get_legend().get_title().set_fontsize(PT_LEYENDA)

    fig.tight_layout(pad=0.4)
    out = guardar(fig, args.outdir, "closed_form_fidelity_plane_v2")
    plt.close(fig)
    print("escrito:", os.path.abspath(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
