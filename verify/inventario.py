#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
inventario.py — qué hay en el repositorio y qué pinta cada cosa.

    python3 verify/inventario.py                # inventario completo
    python3 verify/inventario.py --senales      # solo lo que hay que decidir
    python3 verify/inventario.py --huerfanos    # solo lo que nadie referencia

No es un `ls`: clasifica cada archivo por el papel que cumple en un anexo
de artículo, busca los que no referencia nadie y levanta las señales
conocidas de desorden. Sin dependencias fuera de la biblioteca estándar,
igual que los otros dos verificadores.

Los cuatro papeles:

  entrega     lo que el revisor usa: datos, resultados, código, figuras,
              documentación y verificadores
  andamiaje   sirvió para CONSTRUIR el repositorio, no para usarlo
  interno     notas de trabajo; útiles para el autor, ruido para el lector
  generado    se reconstruye a demanda; no debería versionarse

Las señales no son opiniones sueltas: cada una tiene su entrada en
docs/PENDIENTES.md.
"""

import argparse
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IGNORAR_DIR = {".git", "__pycache__", ".venv", "venv", ".ipynb_checkpoints",
               "figures_regeneradas"}

# (patrón de ruta, papel, por qué)
REGLAS = [
    (r"^bin/poblar_repositorio\.sh$",  "andamiaje",
     "construye el repositorio desde el árbol de trabajo; un revisor no lo usa"),
    (r"^bin/",                          "entrega",   "utilidad del repositorio"),
    (r"^docs/HISTORIAL",                "interno",   "nota de traspaso entre sesiones"),
    (r"^docs/PENDIENTES\.md$",          "interno",
     "lista de tareas; publicada dice dónde están los puntos débiles"),
    (r"^docs/",                         "entrega",   "documentación"),
    (r"^data/",                         "entrega",   "datos de entrada"),
    (r"^results/",                      "entrega",   "resultados citados"),
    (r"^src/",                          "entrega",   "biblioteca"),
    (r"^experiments/.*\.ipynb$",        "interno",
     "notebook que duplica al runner .jl del mismo experimento"),
    (r"^experiments/",                  "entrega",   "runner"),
    (r"^figures/",                      "entrega",   "figura del manuscrito"),
    (r"^figures_src/figuras\.ipynb$",   "entrega",   "ejemplo de uso"),
    (r"^figures_src/",                  "entrega",   "código de figuras"),
    (r"^verify/",                       "entrega",   "verificación"),
    (r"\.pyc$",                         "generado",  "bytecode de Python"),
    (r"^figures/.*\.png$",              "generado",  "PNG de control"),
    (r"^(README|CHANGELOG|LICENSE)",    "entrega",   "raíz"),
    (r"^\.",                            "entrega",   "configuración"),
    (r"^(run_all|smoke_test)\.sh$",     "entrega",   "nivel de reproducción"),
    (r"\.jl$",                          "entrega",   "código Julia"),
    (r"\.toml$",                        "entrega",   "entorno"),
]

# Señales de desorden. Cada una: (nombre, función, nota).
# La función recibe la lista de rutas relativas y devuelve los hallazgos.
def _senal_datos_con_salida(rutas):
    """data/ debería tener solo lo observado."""
    out = []
    p = "data/real_data_curves.csv"
    if p in rutas:
        cab = os.path.join(RAIZ, p)
        try:
            cols = open(cab, encoding="utf-8").readline().strip().split(",")
        except OSError:
            return out
        derivadas = [c for c in cols if c not in ("dia", "es_test", "I_observado")]
        if derivadas:
            out.append("%s: %d de %d columnas son salida del modelo (%s…), "
                       "no observación. Un revisor espera que data/ sea lo empírico."
                       % (p, len(derivadas), len(cols), ", ".join(derivadas[:3])))
    return out


def _senal_nombres_confundibles(rutas):
    """Directorios cuyo nombre se distingue en poquísimas letras."""
    dirs = sorted({r.split("/")[1] for r in rutas
                   if r.startswith("results/") and "/" in r[8:]})
    out = []
    for i, a in enumerate(dirs):
        for b in dirs[i + 1:]:
            if a[:12] == b[:12] and a != b:
                out.append("results/%s y results/%s se distinguen al final del nombre; "
                           "contienen corridas distintas con cifras parecidas" % (a, b))
    return out


def _senal_extensiones_mezcladas(rutas):
    exts = {}
    for r in rutas:
        if r.startswith("docs/"):
            exts.setdefault(os.path.splitext(r)[1], []).append(r)
    if len(exts) > 1:
        minor = sorted(exts, key=lambda e: len(exts[e]))[:-1]
        return ["docs/ mezcla extensiones: %s" %
                "; ".join("%s en %s" % (", ".join(os.path.basename(x) for x in exts[e]), e)
                          for e in minor)]
    return []


def _senal_generados_versionados(rutas, versionados):
    return ["%s está versionado y se regenera a demanda" % r
            for r in rutas if papel(r)[0] == "generado" and r in versionados]


SENALES = [
    ("data/ contiene salida de modelo", _senal_datos_con_salida, "PENDIENTES §2.6"),
    ("nombres de carpeta confundibles", _senal_nombres_confundibles, "PENDIENTES §2.8"),
    ("extensiones mezcladas en docs/", _senal_extensiones_mezcladas, "—"),
]


def papel(rel):
    for patron, p, por_que in REGLAS:
        if re.search(patron, rel):
            return p, por_que
    return "revisar", "ninguna regla lo cubre"


def listar(raiz):
    out = []
    for dirpath, dirnames, filenames in os.walk(raiz):
        dirnames[:] = [d for d in dirnames if d not in IGNORAR_DIR]
        for f in filenames:
            rel = os.path.relpath(os.path.join(dirpath, f), raiz).replace(os.sep, "/")
            out.append(rel)
    return sorted(out)


def referencias(rutas):
    """Qué rutas aparecen mencionadas en algún archivo de texto del repositorio."""
    texto = []
    for r in rutas:
        if os.path.splitext(r)[1] in (".md", ".py", ".sh", ".jl", ".yaml", ".yml",
                                      ".txt", ".ipynb", ".cff", ".toml"):
            try:
                texto.append((r, open(os.path.join(RAIZ, r), encoding="utf-8",
                                      errors="ignore").read()))
            except OSError:
                pass
    citados = set()
    for rel in rutas:
        base = os.path.basename(rel)
        for origen, cuerpo in texto:
            if origen == rel:
                continue
            if rel in cuerpo or base in cuerpo:
                citados.add(rel)
                break
    return citados


def humano(n):
    for u in ("B", "K", "M", "G"):
        if n < 1024 or u == "G":
            return "%.0f%s" % (n, u)
        n /= 1024.0


def main():
    global RAIZ
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--senales", action="store_true", help="solo lo que hay que decidir")
    ap.add_argument("--huerfanos", action="store_true", help="solo lo que nadie referencia")
    ap.add_argument("--raiz", default=RAIZ, help="repositorio a inventariar")
    args = ap.parse_args()

    RAIZ = os.path.abspath(args.raiz)
    rutas = listar(RAIZ)
    if not rutas:
        print("No encontré archivos en %s" % RAIZ)
        return 1

    por_papel = {}
    for r in rutas:
        por_papel.setdefault(papel(r)[0], []).append(r)

    if not (args.senales or args.huerfanos):
        print("Inventario de %s\n" % RAIZ)
        actual = None
        # Por directorio, con la raíz primero: ordenar por ruta completa
        # desperdigaba los archivos de raíz entre medias.
        for r in sorted(rutas, key=lambda x: (os.path.dirname(x), os.path.basename(x))):
            d = os.path.dirname(r) or "."
            # results/ se resume: son cientos de CSV equivalentes
            if d.startswith("results/"):
                continue
            if d != actual:
                print("\n%s/" % d.rstrip("/") if d != "." else "\n(raíz)")
                actual = d
            tam = humano(os.path.getsize(os.path.join(RAIZ, r)))
            pap, por_que = papel(r)
            marca = "  " if pap == "entrega" else "> "
            print("  %s%-46s %6s  %-10s %s"
                  % (marca, os.path.basename(r), tam, pap,
                     "" if pap == "entrega" else por_que))

        print("\nresults/")
        for d in sorted({r.split("/")[1] for r in rutas if r.startswith("results/")
                         and r.count("/") >= 2}):
            n = len([r for r in rutas if r.startswith("results/%s/" % d)])
            print("  %-48s %3d archivos" % (d + "/", n))

    if not args.huerfanos:
        print("\n" + "=" * 72)
        print("SEÑALES — lo que conviene decidir antes de publicar")
        print("=" * 72)
        hubo = False
        for nombre, fn, nota in SENALES:
            hallazgos = fn(rutas)
            for h in hallazgos:
                hubo = True
                print("\n  · %s" % h)
                if nota != "—":
                    print("    ver %s" % nota)
        gen = [r for r in rutas if papel(r)[0] == "generado"]
        if gen:
            hubo = True
            print("\n  · %d archivo(s) generado(s) presentes; se reconstruyen a demanda:"
                  % len(gen))
            for r in gen[:6]:
                print("      %s" % r)
        for pap, nota in (("andamiaje", "sirvió para construir el repositorio, no para usarlo"),
                          ("interno", "útil para el autor, ruido para el lector")):
            if por_papel.get(pap):
                hubo = True
                print("\n  · %s (%s):" % (pap, nota))
                for r in por_papel[pap]:
                    print("      %-44s %s" % (r, papel(r)[1]))
        if por_papel.get("revisar"):
            hubo = True
            print("\n  · sin clasificar; ninguna regla los cubre:")
            for r in por_papel["revisar"]:
                print("      %s" % r)
        if not hubo:
            print("\n  (ninguna)")

    if not args.senales:
        print("\n" + "=" * 72)
        print("HUÉRFANOS — no los menciona ningún otro archivo del repositorio")
        print("=" * 72)
        citados = referencias(rutas)
        huerfanos = [r for r in rutas
                     if r not in citados and not r.startswith("results/")
                     and papel(r)[0] != "generado"]
        if huerfanos:
            print("\n  Un archivo que nadie referencia o sobra, o le falta entrar")
            print("  en el README y en el mapa de docs/EXPERIMENTS.md.\n")
            for r in huerfanos:
                print("      %s" % r)
        else:
            print("\n  (ninguno)")

    print("\n" + "=" * 72)
    print("%d archivos · %s" % (len(rutas), " · ".join(
        "%d %s" % (len(v), k) for k, v in sorted(por_papel.items()))))
    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
