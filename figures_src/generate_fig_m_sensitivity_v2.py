#!/usr/bin/env python3
"""
04_m_sensitivity_v2.py
=======================

Genera `figures/m_sensitivity_v2.pdf` (main3_corregido.tex,
línea 538, sección de sensibilidad al largo de ventana m).

Reemplaza a la v3 (Lineal/Tanh). Muestra Abrupt intervention y Seasonal
-- los dos escenarios seleccionados en
`claude/validacion_regeneracion_figures_sinteticas.md` por tener la
mayor correlación entre RMSE_beta y RMSE_I a lo largo de la grilla de m
(excluyendo Constant/Linear/Tanh, ya cubiertos por la Figura S1 y el
texto principal).

Layout: (a) RMSE_beta vs. m, (b) RMSE_I vs. m; una curva por escenario,
coloreada con la paleta cualitativa reservada (nunca azul/rojo/negro/
verde); todos los largos de ventana m = {1, 2, 5, 7, 10, 15, 20, 30, 50}
se muestran sin exclusión. Una línea vertical fina y punteada marca
m_ref = 10 como referencia del período infeccioso.
Línea horizontal discontinua, en el mismo color del
escenario, marcando la referencia de UDE global (sin ventaneo) de ese
escenario -- tomada de la fila `modelo == "UDE"` de
`outputs/all_scenarios/summary_ALL_scenarios.csv` (equivale
numéricamente a la fila m=T_SYNTH=50 del CSV de sensibilidad, que es la
ventana igual a la serie completa).

Fuente: outputs/window_sensitivity_v2/sensitivity_m_ALL_scenarios_v2.csv
        outputs/all_scenarios/summary_ALL_scenarios.csv

Uso:
    python3 generate_fig_S2_sensitivity_m_v4.py \\
        --outputs-dir /ruta/a/SW_UDE/outputs --outdir figures
"""

import argparse
import os
import sys

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from matplotlib.lines import Line2D
from matplotlib.ticker import FixedLocator, FixedFormatter

from style_figures import (
    set_mpl_style, guardar, figsize, QUALITATIVE_PALETTE, LEGEND_KW,
    M_REF_SYNTH, COLOR_TRUE, COLOR_NEUTRO, LINEWIDTH, LINEWIDTH_REF, MARKERSIZE,
)

ESCENARIOS = ["Abrupt intervention", "Seasonal"]
M_GRID = (1, 2, 5, 7, 10, 15, 20, 30, 50)
M_REF = M_REF_SYNTH  # 1/gamma. Referencia de contexto; no restringe la grilla.
COLOR_POR_ESCENARIO = {
    "Abrupt intervention": QUALITATIVE_PALETTE[0],  # "#ff7f0e"
    "Seasonal": QUALITATIVE_PALETTE[1],              # "#9467bd"
}

ESTILO_POR_ESCENARIO = {
    "Abrupt intervention": dict(
        linestyle="-",
        marker="o",
        linewidth=LINEWIDTH,
        markersize=MARKERSIZE,
        markerfacecolor="white",
        markeredgewidth=1.0,
    ),
    "Seasonal": dict(
        linestyle=(0, (5, 3)),
        marker="s",
        linewidth=LINEWIDTH,
        markersize=MARKERSIZE,
        markerfacecolor="white",
        markeredgewidth=1.0,
    ),
}

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outputs-dir", default="outputs",
                     help="Carpeta con window_sensitivity_v2/ y all_scenarios/.")
    ap.add_argument("--outdir", default="figures", help="Carpeta de salida para los PDF/PNG.")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    set_mpl_style()

    path_m = os.path.join(args.outputs_dir, "window_sensitivity_v2",
                           "sensitivity_m_ALL_scenarios_v2.csv")
    path_resumen = os.path.join(args.outputs_dir, "all_scenarios", "summary_ALL_scenarios.csv")
    for p in (path_m, path_resumen):
        if not os.path.exists(p):
            print(f"[S2_v2] ERROR -- no se encontró: {p}")
            return 1

    df_m = pd.read_csv(path_m)
    df_resumen = pd.read_csv(path_resumen)

    fig, (axL, axR) = plt.subplots(1, 2, figsize=figsize(2.9), constrained_layout=True)

    for nombre in ESCENARIOS:
        color = COLOR_POR_ESCENARIO[nombre]
        estilo = ESTILO_POR_ESCENARIO[nombre]
        d = df_m[(df_m.escenario == nombre) & df_m.m.isin(M_GRID)].sort_values("m")
        if d.empty:
            print(f"[S2_v2] AVISO -- sin filas para escenario '{nombre}' en {path_m}")
            continue

        ref_row = df_resumen[(df_resumen.escenario == nombre) & (df_resumen.modelo == "UDE")]
        if ref_row.empty:
            print(f"[S2_v2] AVISO -- sin fila UDE global para '{nombre}' en {path_resumen}")
            ref_beta = ref_I = None
        else:
            ref_beta = float(ref_row["RMSE_beta"].iloc[0])
            ref_I = float(ref_row["RMSE_I"].iloc[0])

        # -- panel (a): RMSE_beta vs m --
        #axL.plot(d.m, d.RMSE_beta, "o-", color=color, zorder=3, label=nombre)
        # Panel (a): error de la función latente
        axL.plot(
            d.m, d.RMSE_beta,
            color=color,
            markeredgecolor=color,
            **estilo,
            zorder=3,
            label=nombre,
        )
        
        if ref_beta is not None:
            axL.axhline(
                ref_beta, color=color,
                ls="-.", lw=LINEWIDTH_REF, alpha=0.9,
            )


        # -- panel (b): RMSE_I vs m --
        #axR.plot(d.m, d.RMSE_I, "o-", color=color, zorder=3, label=nombre)
        # Panel (b): error de reconstrucción de estados
        axR.plot(
            d.m, d.RMSE_I,
            color=color,
            markeredgecolor=color,
            **estilo,
            zorder=3,
            label=nombre,
        )
        if ref_I is not None:
            axR.axhline(
                ref_I, color=color,
                ls="-.", lw=LINEWIDTH_REF, alpha=0.9,
            )

    for ax in (axL, axR):
        ax.set_yscale("log")
        # Eje x logarítmico: la grilla es {1,2,5,7,10,15,20,30,50} y en
        # escala lineal los m chicos se apelotonan contra el margen, que es
        # justamente donde están los mínimos de los dos paneles.
        ax.set_xscale("log")
        ax.xaxis.set_major_locator(FixedLocator(M_GRID))
        ax.xaxis.set_major_formatter(FixedFormatter([str(v) for v in M_GRID]))
        ax.xaxis.set_minor_locator(FixedLocator([]))
        ax.axvline(M_REF, color=COLOR_TRUE, ls=":", lw=LINEWIDTH_REF, alpha=0.65,
                   zorder=1)
        ax.set_xlabel("$m$")

    axL.set_ylabel(r"$\mathrm{RMSE}_\beta$ (log scale)")
    axL.set_title("(a) Latent-function error")
    axR.set_ylabel(r"$\mathrm{RMSE}_I$ (log scale)")
    axR.set_title("(b) State reconstruction error")

    handles = [
        Line2D([], [], color=COLOR_POR_ESCENARIO[n], **ESTILO_POR_ESCENARIO[n],
               markeredgecolor=COLOR_POR_ESCENARIO[n], label=n)
        for n in ESCENARIOS
    ] + [
        Line2D([], [], color=COLOR_NEUTRO, ls="-.", lw=LINEWIDTH_REF,
               label=r"Global UDE ($m=T=%d$)" % max(M_GRID)),
        Line2D([], [], color=COLOR_TRUE, ls=":", lw=LINEWIDTH_REF, alpha=0.65,
               label=r"$m_{\mathrm{ref}}=%d$" % M_REF),
    ]
    fig.legend(handles=handles, loc="lower center", ncol=4, frameon=False,
               fontsize=LEGEND_KW["fontsize"], bbox_to_anchor=(0.5, -0.10),
               columnspacing=1.2, handletextpad=0.5, handlelength=2.2)

    # Sin título general: el caption de LaTeX describe la figura, igual
    # que en hospital_state_reconstruction. Las líneas dash-dot son la
    # referencia del UDE global y se explican ahí.

    out = guardar(fig, args.outdir, "m_sensitivity_v2")
    plt.close(fig)
    print(f"[S2_v2] Guardado: {os.path.abspath(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
