#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generate_fig_temporal_supervision_horizon.py
============================================

Genera `figures/temporal_supervision_horizon.pdf`: el esquema de los tres
regímenes de supervisión temporal que definen el largo de ventana m.

    (a) m = 1      supervisión local
    (b) 1 < m < T  anclada en observaciones
    (c) m = T      trayectoria global

Los rótulos son los del manuscrito (sec:temporal_supervision_horizon):
"supervision is entirely local" para m=1, "observation-anchored training"
para el caso intermedio y "global trajectory training" para m=T. La
figura vive en Materiales y Métodos, unas cuatrocientas líneas antes de
que aparezcan los nombres UDE y SW-UDE, así que rotular los paneles con
ellos sería una referencia hacia adelante.

La figura NO lee datos del pipeline: es un esquema. Pero tampoco está
dibujada a mano. La trayectoria de referencia es analítica y las cadenas
de predicción se obtienen aplicando de verdad un operador de un paso
Phi_theta deliberadamente sesgado, de modo que la deriva que se ve en (c)
es la que produce la acumulación del error, no una curva colocada a ojo.
Ese es el punto del esquema: con m=1 la pérdida nunca ve el error
acumulado; con m=T lo ve todo pero ya no puede anclarse.

Decisiones de diseño, para que quede registro:

- Los tres paneles comparten la MISMA trayectoria, la MISMA grilla de
  observación y los MISMOS ejes. Lo único que cambia entre ellos es dónde
  se reancla la predicción. Si cambiara algo más, el lector no podría
  atribuir la diferencia al régimen de supervisión.
- El residuo que entra en la pérdida se dibuja explícitamente y está en
  la leyenda. Es el elemento que distingue a los tres regímenes.
- Sin fondos de color: tintar (a) de rojo y (c) de verde insinúa un
  juicio que el artículo no sostiene.
- Sin recuadros de texto: esa prosa va al caption de LaTeX.
- Paleta neutra con un único acento para el residuo. Azul, rojo y verde
  están reservados en el artículo para UDE, SW-UDE y fórmula simbólica;
  este esquema no habla de métodos, así que no los usa.

Uso:
    python3 generate_fig_temporal_supervision_horizon.py --outdir figures

Reproducibilidad: con SOURCE_DATE_EPOCH fijado, el PDF sale byte a byte
idéntico entre corridas.
"""

import argparse
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

# Si el script vive junto a style_figures.py usa el estilo central del
# artículo; si no, aplica el mismo rcParams por su cuenta.
from style_figures import (
    set_mpl_style, guardar, figsize, QUALITATIVE_PALETTE,
    COLOR_TRUE as _NEGRO, COLOR_REF, TINTA,
    PT_TITULO, PT_LEYENDA, LINEWIDTH_REF,
)

# ----------------------------------------------------------------------
# Parámetros del esquema
# ----------------------------------------------------------------------
T = 20            # número de transiciones; observaciones en k = 0..T
DT = 1.0
# Largo de ventana dibujado en el panel (b). Es una elección de dibujo,
# no el m del artículo: el manuscrito no fija un m en esta sección —"we do
# not impose an optimal value of m a priori"— y el adoptado para la serie
# real es m=10, que sobre T=20 dejaría solo dos ventanas e ilegible el
# reanclaje. Por eso el panel se rotula 1 < m < T y no con un número.
M_WIN = 5
SEED = 1234       # misma semilla que las corridas de semilla única

# Operador de un paso sesgado: Phi_theta avanza con una ganancia algo
# mayor que la verdadera y un sesgo constante. Un paso casi no se nota;
# T pasos sí. Esa es toda la física del esquema.
GANANCIA = 1.26
SESGO = -0.0085
SIGMA_OBS = 0.022  # ruido de observación, para que el residuo de (a) exista

# El esquema no habla de métodos: va en grises, con un único acento para
# el residuo, que es el elemento que hay que mirar. El acento sale de
# QUALITATIVE_PALETTE, reservada a dimensiones que no son método.
COLOR_TRUE = COLOR_REF       # trayectoria de referencia, al fondo
COLOR_OBS = _NEGRO
COLOR_PRED = TINTA
COLOR_ARROW = "#777777"
COLOR_RESID = QUALITATIVE_PALETTE[0]


def u_true(t):
    """Trayectoria de referencia, analítica."""
    return (0.68
            + 0.26 * np.sin(2 * np.pi * t / 22.0 + 0.9)
            + 0.10 * np.sin(4 * np.pi * t / 22.0 + 2.0))


def f_true(t):
    """Su derivada, que es el campo vectorial 'verdadero'."""
    return (0.26 * (2 * np.pi / 22.0) * np.cos(2 * np.pi * t / 22.0 + 0.9)
            + 0.10 * (4 * np.pi / 22.0) * np.cos(4 * np.pi * t / 22.0 + 2.0))


def phi(u, k):
    """Phi_theta: un paso del modelo aprendido, desde el estado u en t=k."""
    return u + DT * (GANANCIA * f_true(k * DT) + SESGO)


def cadena(u0, k0, pasos):
    """Aplica Phi_theta recursivamente; devuelve (tiempos, estados)."""
    ts, us = [k0 * DT], [u0]
    u = u0
    for i in range(pasos):
        u = phi(u, k0 + i)
        ts.append((k0 + i + 1) * DT)
        us.append(u)
    return np.array(ts), np.array(us)


def dibujar_panel(ax, anclas, pasos_por_ancla, t_obs, u_obs, titulo):
    """Dibuja un régimen de supervisión sobre la grilla común."""
    t_fino = np.linspace(0, T * DT, 400)
    ax.plot(t_fino, u_true(t_fino), color=COLOR_TRUE, lw=LINEWIDTH_REF,
            ls=(0, (5, 2.5)), zorder=1)

    for k0 in anclas:
        pasos = min(pasos_por_ancla, T - k0)
        if pasos <= 0:
            continue
        ts, us = cadena(u_obs[k0], k0, pasos)

        # flechas de un paso: Phi_theta aplicado una vez
        for i in range(len(ts) - 1):
            ax.annotate("", xy=(ts[i + 1], us[i + 1]), xytext=(ts[i], us[i]),
                        arrowprops=dict(arrowstyle="-|>", color=COLOR_ARROW,
                                        lw=0.7, shrinkA=2.0, shrinkB=2.4,
                                        mutation_scale=6), zorder=2)

        # residuo: lo que efectivamente entra en la pérdida
        for i in range(1, len(ts)):
            k = k0 + i
            ax.plot([ts[i], ts[i]], [us[i], u_obs[k]], color=COLOR_RESID,
                    lw=1.2, solid_capstyle="butt", zorder=3)

        # estados predichos
        ax.plot(ts[1:], us[1:], ls="none", marker="o", markersize=3.4,
                markerfacecolor="white", markeredgecolor=COLOR_PRED,
                markeredgewidth=0.8, zorder=4)

    # estados observados (los mismos en los tres paneles)
    ax.plot(t_obs, u_obs, ls="none", marker="o", markersize=3.2,
            color=COLOR_OBS, zorder=5)

    ax.set_title(titulo, fontsize=PT_TITULO)
    ax.set_xlabel("$t$")
    ax.set_xlim(-0.8, T * DT + 0.8)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", default="figures", help="Carpeta de salida.")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    set_mpl_style()

    k = np.arange(T + 1)
    t_obs = k * DT
    rng = np.random.default_rng(SEED)
    u_obs = u_true(t_obs) + rng.normal(0.0, SIGMA_OBS, size=t_obs.shape)

    fig, axes = plt.subplots(1, 3, figsize=figsize(2.55), sharey=True,
                             constrained_layout=True)

    dibujar_panel(axes[0], anclas=list(range(T)), pasos_por_ancla=1,
                  t_obs=t_obs, u_obs=u_obs,
                  titulo="(a) Local supervision\n($m = 1$)")
    dibujar_panel(axes[1], anclas=list(range(0, T, M_WIN)), pasos_por_ancla=M_WIN,
                  t_obs=t_obs, u_obs=u_obs,
                  titulo="(b) Observation-anchored\n($1 < m < T$)")
    dibujar_panel(axes[2], anclas=[0], pasos_por_ancla=T,
                  t_obs=t_obs, u_obs=u_obs,
                  titulo="(c) Global trajectory\n($m = T$)")

    axes[0].set_ylabel("$u(t)$")

    handles = [
        Line2D([], [], ls="none", marker="o", markersize=3.2, color=COLOR_OBS,
               label=r"Observed state $u^{\mathrm{obs}}_k$"),
        Line2D([], [], ls="none", marker="o", markersize=3.4,
               markerfacecolor="white", markeredgecolor=COLOR_PRED,
               markeredgewidth=0.8, label=r"Predicted state $\hat u_{k+i}$"),
        Line2D([], [], color=COLOR_ARROW, lw=0.7,
               label=r"One-step model map $\Phi_\theta$"),
        Line2D([], [], color=COLOR_RESID, lw=1.2,
               label="Residual entering the loss"),
        Line2D([], [], color=COLOR_TRUE, lw=LINEWIDTH_REF, ls=(0, (5, 2.5)),
               label="Reference trajectory"),
    ]
    fig.legend(handles=handles, loc="lower center", ncol=5, frameon=False,
               fontsize=PT_LEYENDA, bbox_to_anchor=(0.5, -0.08),
               columnspacing=1.2, handletextpad=0.5, handlelength=2.0)

    out = guardar(fig, args.outdir, "temporal_supervision_horizon")
    plt.close(fig)
    print("escrito:", os.path.abspath(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
