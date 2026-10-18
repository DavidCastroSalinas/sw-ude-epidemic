#!/usr/bin/env python3
"""
05_hospital_state_reconstruction.py
====================================

Genera `figures/hospital_state_reconstruction.pdf` (main3_corregido.tex,
línea 1635). Reconstrucción de S, I, R para UDE y SW-UDE, escenario
Hospital saturation (corrida única, seed=1234), más una segunda fila con
el error absoluto |reconstruido - referencia| (a la escala 0-1000 de
S/I/R el error de SW-UDE es visualmente invisible junto a las curvas; la
fila de error absoluto es lo que efectivamente sustenta la afirmación
del texto sobre errores de trayectoria mayores en este escenario).

Versión refactorizada de la Sección S4 de `generar_figuras_adicionales.py`
(que leía desde un ZIP con rutas hardcodeadas); apunta directo a
`outputs/all_scenarios/saturacion_10_curvas_estados.csv` con
--outputs-dir configurable, estilo centralizado y texto en inglés.

Fuente: outputs/all_scenarios/saturacion_10_curvas_estados.csv
        (columnas: t, S_observado, I_observado, R_observado,
         S_UDE, I_UDE, R_UDE, S_Windowed, I_Windowed, R_Windowed)

Uso:
    python3 generar_fig_S4_saturacion_estados.py \\
        --outputs-dir /ruta/a/SW_UDE/outputs --outdir figures
"""

import argparse
import os
import sys

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from estilo_figuras import (
    set_mpl_style, guardar, figsize, LEGEND_KW,
    STYLE_TRUE, STYLE_UDE, STYLE_SWUDE, M_REF_SYNTH,
)

# Los estilos salen del módulo central. La versión anterior definía aquí
# sus propios colores y le daba a SW-UDE un #B34700 que no es el rojo del
# artículo y además quedaba cerca del naranja con que la figura de
# sensibilidad identifica el escenario Abrupt intervention.

PANELES = [
    ("S", "S_observado", "S_UDE", "S_Windowed"),
    ("I", "I_observado", "I_UDE", "I_Windowed"),
    ("R", "R_observado", "R_UDE", "R_Windowed"),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outputs-dir", default="outputs",
                     help="Carpeta con all_scenarios/saturacion_10_curvas_estados.csv.")
    ap.add_argument("--outdir", default="figures", help="Carpeta de salida para los PDF/PNG.")
    ap.add_argument("--escala-error", choices=("log", "lineal"), default="log",
                     dest="escala_error",
                     help="Escala del eje y en la fila de error absoluto.")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    set_mpl_style()

    path = os.path.join(args.outputs_dir, "all_scenarios", "saturacion_10_curvas_estados.csv")
    if not os.path.exists(path):
        print(f"[S4] ERROR -- no se encontró: {path}")
        return 1

    sat = pd.read_csv(path)

    fig, axes = plt.subplots(2, 3, figsize=figsize(3.7), constrained_layout=True, sharex=True)
    for col_i, (name, col_true, col_u, col_w) in enumerate(PANELES):
        ax = axes[0, col_i]
        ax.plot(sat.t, sat[col_true], **STYLE_TRUE, label="Observed")
        ax.plot(sat.t, sat[col_u], **STYLE_UDE, label="UDE")
        ax.plot(sat.t, sat[col_w], **STYLE_SWUDE, label="SW-UDE ($m=%d$)" % M_REF_SYNTH)
        ax.set_title(f"${name}(t)$")

        ax_err = axes[1, col_i]
        err_u = (sat[col_u] - sat[col_true]).abs()
        err_w = (sat[col_w] - sat[col_true]).abs()
        ax_err.plot(sat.t, err_u, **STYLE_UDE, label="UDE")
        ax_err.plot(sat.t, err_w, **STYLE_SWUDE, label="SW-UDE ($m=%d$)" % M_REF_SYNTH)
        ax_err.set_title(f"Absolute error in ${name}(t)$")
        ax_err.set_xlabel("$t$")
        # Escala logarítmica: la fila existe porque a la escala de S/I/R
        # el error de SW-UDE es invisible. Si en lineal el error del UDE
        # lo supera en un orden de magnitud, el problema se repite dentro
        # de la propia fila. --escala-error lineal vuelve al comportamiento
        # anterior.
        if args.escala_error == "log":
            ax_err.set_yscale("log")

    # Una sola leyenda para toda la figura: las dos filas muestran los
    # mismos métodos y dos recuadros tapaban las curvas.
    manejadores, etiquetas = axes[0, 0].get_legend_handles_labels()
    fig.legend(manejadores, etiquetas, loc="lower center", ncol=3,
               frameon=False, fontsize=LEGEND_KW["fontsize"],
               bbox_to_anchor=(0.5, -0.045), columnspacing=1.6,
               handletextpad=0.5, handlelength=2.2)
    # El caption de LaTeX describe la figura; no se agrega título general.
    out = guardar(fig, args.outdir, "hospital_state_reconstruction")
    plt.close(fig)
    print(f"[S4] Guardado: {os.path.abspath(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
