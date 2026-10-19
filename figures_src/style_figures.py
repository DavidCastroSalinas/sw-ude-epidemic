#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
style_figures.py — estilo único de las figuras del artículo SW-UDE.

Versión normalizada (2026-10-12). Reemplaza al módulo anterior y a los
colores que los scripts de destilación definían por su cuenta. Todos los
`generar_fig_*.py` del artículo importan de aquí y no redefinen nada.

Las decisiones de abajo no son de gusto: salen de tres restricciones del
medio impreso, y cada una se puede comprobar.


1. TAMAÑO — se dibuja al tamaño final, no se escala
-----------------------------------------------------------------------
El manuscrito usa la clase MDPI, a una columna, y llama a las figuras con
`width=0.95\\textwidth` (cinco de seis) y `width=0.82\\textwidth` (el plano
de fidelidad). Una figura dibujada a 9 pulgadas y colocada en una caja de
5,98 queda reducida al 66 %: una etiqueta de 9 pt se imprime a 5,9 pt y
un trazo de 0,8 pt a 0,53 pt. Por eso `figsize()` devuelve directamente el
ancho final y los scripts dibujan a ese tamaño, con factor de escala 1.

ANCHO_CAJA_CM = 16,0 es el `\\textwidth` estándar de MDPI. Conviene
confirmarlo una vez contra el documento real:

    \\the\\textwidth      % en el .tex, imprime el valor en puntos TeX

y ajustar la constante si no coincide (1 pt TeX = 1/72,27 pulgadas).


2. COLOR — paleta Okabe-Ito, validada, no elegida a ojo
-----------------------------------------------------------------------
La paleta anterior usaba los colores por defecto de matplotlib. El par
rojo #d62728 (SW-UDE) y verde #2ca02c (forma cerrada) tiene una
separación de ΔE 3,9 bajo deuteranopía: para una fracción apreciable de
lectores son el mismo color, y ambos aparecen juntos en el panel (a) de
`closed_form_fidelity_v2`. Los colores de abajo son Okabe-Ito y llevan
ΔE 11,0 en el peor par bajo deuteranopía, con ΔE 25,8 en visión normal.

La identidad nunca depende solo del color: cada serie lleva además un
trazo y un marcador propios, de modo que la figura se lee en escala de
grises y en una fotocopia.


3. TRAZO Y TIPOGRAFÍA — pisos de legibilidad impresa
-----------------------------------------------------------------------
Nada por debajo de 7 pt ni de 0,5 pt de trazo al tamaño final.
`comprobar_minimos()` lo verifica sobre una figura ya construida y es lo
que cada script llama antes de guardar.
"""

import os

import matplotlib

# ----------------------------------------------------------------------
# 1. Geometría
# ----------------------------------------------------------------------
ANCHO_CAJA_CM = 16.0                      # \textwidth de la clase MDPI
ANCHO_CAJA_IN = ANCHO_CAJA_CM / 2.54      # 6.30 in

FRAC_ANCHA = 0.95   # las cinco figuras de \includegraphics[width=0.95\textwidth]
FRAC_PLANO = 0.82   # closed_form_fidelity_plane_v2


def figsize(alto_in, frac=FRAC_ANCHA):
    """Ancho final en la caja del documento, por el alto que se pida.

    Se dibuja a este tamaño para que LaTeX no reescale y los cuerpos
    tipográficos lleguen al papel con el valor que tienen aquí.
    """
    return (frac * ANCHO_CAJA_IN, alto_in)


# ----------------------------------------------------------------------
# 2. Color
# ----------------------------------------------------------------------
# Colores de método. Fijos en todo el artículo; ninguna otra dimensión
# los usa. Validados en conjunto: deutan ΔE 11,0 · normal ΔE 25,8.
COLOR_UDE = "#0072B2"    # azul      -- UDE global, y solo UDE
COLOR_SWUDE = "#D55E00"  # bermellón -- SW-UDE, y solo SW-UDE
COLOR_CLOSED = "#009E73"  # verde azulado -- forma cerrada, y solo eso
COLOR_TRUE = "#000000"   # negro     -- observado / referencia
COLOR_REF = "#9A9A9A"    # gris      -- cortes, persistencia, auxiliares

# Alias retrocompatible con el nombre que usaban los scripts viejos.
COLOR_SYM = COLOR_CLOSED
COLOR_SPLIT = COLOR_REF

# Paleta para dimensiones que NO son método — escenario, tramo.
# Oscurecida respecto de Okabe-Ito puro para pasar el contraste 3:1 contra
# papel blanco, que las versiones claras no alcanzan en trazo fino.
# Validada: deutan ΔE 15,3 · normal ΔE 15,3 · contraste >= 3:1.
QUALITATIVE_PALETTE = ["#B35806", "#8C4A72"]

# Neutro para series presentes pero deliberadamente secundarias.
COLOR_NEUTRO = "#595959"
COLOR_FONDO = "#AFAFAF"   # series de contexto, sin identidad propia
TINTA = "#333333"

# ----------------------------------------------------------------------
# Familias de forma cerrada (M1, M2, E y las diez de sensibilidad)
# ----------------------------------------------------------------------
# No llevan un matiz cada una. Tres matices oscuros, mutuamente
# distinguibles bajo daltonismo Y distinguibles del bermellón de SW-UDE,
# no caben: oscurecerlos lo suficiente para el contraste 3:1 les quita el
# croma que la separación necesita. Comprobado con el validador sobre
# cuatro combinaciones; todas fallan algún criterio.
#
# Las familias son además UNA categoría —candidatas de forma cerrada—
# frente a SW-UDE, no tres categorías independientes. Así que comparten
# el color de forma cerrada y se distinguen por trazo, que es legible en
# escala de grises, y por su etiqueta impresa al lado.
#
# E queda un escalón atrás en neutro: el contraste principal del análisis
# es M1 frente a M2, y E entra como sensibilidad. Es una diferencia de
# croma, no de matiz, así que ningún tipo de daltonismo la pierde.
ESTILO_FAMILIA = {
    "M1": dict(color=COLOR_CLOSED, linestyle=(0, (6, 2))),
    "M2": dict(color=COLOR_CLOSED, linestyle=(0, (2.5, 1.6))),
    "E":  dict(color=COLOR_NEUTRO, linestyle=(0, (6, 1.6, 1, 1.6))),
}
FAMILIAS_PRIMER_PLANO = ("M1", "M2")   # realce de etiqueta en el plano

# ----------------------------------------------------------------------
# 3. Trazo, marcadores y cuerpos tipográficos — al tamaño final
# ----------------------------------------------------------------------
PT_MIN = 7.0      # piso de cuerpo tipográfico impreso
LW_MIN = 0.5      # piso de grosor de trazo impreso

PT_BASE = 8.0
PT_TITULO = 8.5   # rótulo de panel, (a) / (b) / (c)
PT_ETIQUETA = 8.0  # nombres de eje
PT_TICK = 7.5
PT_LEYENDA = 7.5
PT_ANOTACION = 7.0

LINEWIDTH = 1.3        # curva de datos
LINEWIDTH_REF = 0.8    # línea de referencia, corte, umbral
LINEWIDTH_FINA = 0.5   # curva individual en haces multisemilla
MARKERSIZE = 4.0
ERRORBAR_CAPSIZE = 2.5
ERRORBAR_LINEWIDTH = 1.3

# Trazo y marcador por método: la identidad no es solo el color.
LS_TRUE, LS_UDE, LS_SWUDE, LS_CLOSED = "-", (0, (4, 2)), (0, (1, 1.6)), (0, (6, 2, 1, 2))
MARKER_UDE, MARKER_SWUDE = "o", "s"

STYLE_TRUE = dict(color=COLOR_TRUE, linestyle=LS_TRUE, linewidth=LINEWIDTH + 0.3)
STYLE_UDE = dict(color=COLOR_UDE, linestyle=LS_UDE, linewidth=LINEWIDTH)
STYLE_SWUDE = dict(color=COLOR_SWUDE, linestyle=LS_SWUDE, linewidth=LINEWIDTH)
STYLE_CLOSED = dict(color=COLOR_CLOSED, linestyle=LS_CLOSED, linewidth=LINEWIDTH)
STYLE_SYM = STYLE_CLOSED

STYLE_UDE_PT = dict(color=COLOR_UDE, marker=MARKER_UDE, markersize=MARKERSIZE,
                    linewidth=LINEWIDTH, linestyle="-")
STYLE_SWUDE_PT = dict(color=COLOR_SWUDE, marker=MARKER_SWUDE, markersize=MARKERSIZE,
                      linewidth=LINEWIDTH, linestyle="-")

LEGEND_KW = dict(frameon=False, fontsize=PT_LEYENDA, handlelength=2.4,
                 handletextpad=0.6, columnspacing=1.3, borderaxespad=0.4)


def set_mpl_style():
    """rcParams común. Los cuerpos son los que llegan al papel."""
    matplotlib.rcParams.update({
        "font.family": "serif",
        "mathtext.fontset": "dejavuserif",
        "font.size": PT_BASE,
        "axes.titlesize": PT_TITULO,
        "axes.labelsize": PT_ETIQUETA,
        "xtick.labelsize": PT_TICK,
        "ytick.labelsize": PT_TICK,
        "legend.fontsize": PT_LEYENDA,
        "axes.linewidth": 0.6,
        "xtick.major.width": 0.6, "ytick.major.width": 0.6,
        "xtick.major.size": 2.5, "ytick.major.size": 2.5,
        "xtick.direction": "out", "ytick.direction": "out",
        "lines.linewidth": LINEWIDTH,
        "lines.markersize": MARKERSIZE,
        "axes.grid": True,
        "grid.alpha": 0.20, "grid.linewidth": 0.5, "grid.color": "#B0B0B0",
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.axisbelow": True,
        "figure.dpi": 150, "savefig.dpi": 600,
        "savefig.bbox": "tight", "savefig.pad_inches": 0.02,
        "pdf.fonttype": 42, "ps.fonttype": 42,  # texto embebido y seleccionable
        "pdf.compression": 6,
        "axes.unicode_minus": False,            # signo menos ASCII, no U+2212
    })


# ----------------------------------------------------------------------
# Autochequeo y guardado
# ----------------------------------------------------------------------
def comprobar_minimos(fig, pt_min=PT_MIN, lw_min=LW_MIN, verboso=True):
    """Recorre la figura ya construida y avisa de lo que no se va a leer.

    Comprueba los pisos impresos y, sobre todo, que la figura se dibujó al
    ancho de su caja: si no, LaTeX la reescala y todos los cuerpos de
    abajo cambian.
    """
    problemas = []

    ancho = fig.get_size_inches()[0]
    destinos = {round(FRAC_ANCHA * ANCHO_CAJA_IN, 2), round(FRAC_PLANO * ANCHO_CAJA_IN, 2)}
    if round(ancho, 2) not in destinos:
        problemas.append(
            "ancho %.2f in: no coincide con ninguna caja del .tex (%s). "
            "LaTeX la va a reescalar." % (ancho, ", ".join("%.2f" % d for d in sorted(destinos))))

    for ax in fig.get_axes():
        textos = [ax.title, ax.xaxis.label, ax.yaxis.label]
        textos += list(ax.get_xticklabels()) + list(ax.get_yticklabels())
        textos += [t for t in ax.texts]
        leyenda = ax.get_legend()
        if leyenda is not None:
            textos += leyenda.get_texts()
        for t in textos:
            if t.get_text() and t.get_fontsize() < pt_min:
                problemas.append("texto a %.1f pt (< %.1f): %r"
                                 % (t.get_fontsize(), pt_min, t.get_text()[:38]))
        for ln in ax.get_lines():
            if ln.get_linestyle() not in ("None", "none", "") and 0 < ln.get_linewidth() < lw_min:
                problemas.append("trazo a %.2f pt (< %.2f): %r"
                                 % (ln.get_linewidth(), lw_min, (ln.get_label() or "")[:38]))

    for leg in getattr(fig, "legends", []):
        for t in leg.get_texts():
            if t.get_fontsize() < pt_min:
                problemas.append("leyenda de figura a %.1f pt (< %.1f)" % (t.get_fontsize(), pt_min))

    if verboso:
        if problemas:
            print("  [estilo] %d aviso(s):" % len(problemas))
            for p in problemas:
                print("    - " + p)
        else:
            print("  [estilo] tamaño y mínimos de impresión: correcto")
    return problemas


def guardar(fig, outdir, nombre_base, png=True, comprobar=True):
    """Guarda la figura como PDF (y PNG de control) y devuelve la ruta.

    Determinista: con SOURCE_DATE_EPOCH fijado, el PDF sale byte a byte
    igual entre corridas. `figures_src/regenerate_all.sh` lo fija.
    """
    if comprobar:
        comprobar_minimos(fig)
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, "%s.pdf" % nombre_base)
    fig.savefig(out, metadata={"Creator": "", "Producer": ""})
    if png:
        fig.savefig(out.replace(".pdf", ".png"))
    return out


# ----------------------------------------------------------------------
# Constantes del pipeline, idénticas a main.tex
# ----------------------------------------------------------------------
N_SYNTH, GAMMA_SYNTH, DT_SYNTH, T_SYNTH = 1000.0, 0.10, 1.0, 50
U0_SYNTH = (990.0, 10.0, 0.0)
BETA_MIN = 1e-6

# Serie real (Sección 2.4.4 y Tabla 2 de main.tex)
M_ADOPTADO_REAL = 10          # horizonte adoptado para la serie real
M_REF_REAL = 7                # 1/gamma, referencia de contexto, no criterio
DIA_SPLIT_REAL = 164          # frontera entrenamiento / prueba

# Referencia del período infeccioso en los sintéticos: 1/gamma = 10.
# Se muestra como contexto. NO excluye ninguna ventana de la grilla: el
# manuscrito trata m como factor experimental y no impone un óptimo a
# priori ("we do not impose an optimal value of m a priori"). La versión
# anterior de este módulo exportaba FLOOR_SYNTH con el comentario opuesto.
M_REF_SYNTH = int(round(1.0 / GAMMA_SYNTH))

SLUG_ES = {
    "Constant": "constante", "Linear": "lineal", "Tanh": "tanh",
    "Two-wave": "dos_olas", "Abrupt intervention": "intervencion",
    "Seasonal": "estacional", "Hospital saturation": "saturacion",
}
