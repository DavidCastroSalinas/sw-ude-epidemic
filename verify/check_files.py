#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_files.py — ¿está todo lo que el repositorio promete?

    python3 verify/check_files.py
    python3 verify/check_files.py --solo-faltantes

Comprueba, sin correr nada y sin dependencias fuera de la biblioteca
estándar:

  1. los archivos de raíz que un anexo de artículo necesita;
  2. los runners que `run_all.sh` y el mapa del README enumeran;
  3. los módulos de `src/lib/` que `docs/EXPERIMENTS.md` cita;
  3b. los módulos que los runners `include`, leídos del propio código:
      tres los cargan en diferido, dentro de un `if`, y por eso no
      aparecen en la cadena de `include` de `src/sir_ude_lib.jl` ni,
      hasta ahora, en ninguna lista;
  4. las fuentes CSV declaradas en `verify/manuscript_values.yaml`;
  5. los scripts de figura del registro de `figures_src/`;
  6. los seis PDF que `main.tex` compila.

Es complementario al verificador de cifras: aquél comprueba que los
números cuadren, éste que los archivos existan. Código de salida 1 si
falta algo que bloquea la publicación.
"""

import argparse
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (ruta, bloquea_publicacion, para qué sirve)
RAIZ_ESPERADA = [
    ("README.md",                       True,  "puerta de entrada"),
    ("LICENSE",                         True,  "licencia del código; sin ella el repositorio no es reutilizable"),
    ("LICENSE-DATA",                    True,  "licencia de datos y figuras"),
    ("CITATION.cff",                    True,  "cómo citar; GitHub y Zenodo lo leen"),
    ("CHANGELOG.md",                    False, "qué cambió respecto del árbol de trabajo"),
    ("Project.toml",                    True,  "dependencias de Julia; sin él no hay Nivel 2"),
    ("Manifest.toml",                   True,  "versiones exactas de la corrida de referencia"),
    ("install_dependencies.jl",         True,  "instala el entorno"),
    ("run_all.sh",                      True,  "Nivel 2"),
    ("smoke_test.sh",                   True,  "Nivel 1"),
    (".gitignore",                      False, "qué no se versiona"),
    ("verify/verify_values.py",      True,  "Nivel 0"),
    ("verify/manuscript_values.yaml",   True,  "las cifras declaradas"),
    ("verify/check_unused_code.py", False, "código que no usa el artículo"),
    ("bin/poblar_repositorio.sh",       False, "poblado desde el árbol de trabajo"),
    ("bin/generate_manifest.sh",         False, "huellas de los resultados"),
    ("bin/generate_environment.jl",          False, "escribe Project.toml y Manifest.toml"),
    ("data/README.md",                  True,  "procedencia y licencia de la serie"),
    ("docs/EXPERIMENTS.md",            False, "mapa experimento -> código -> datos"),
    ("docs/ENVIRONMENT.md",                 False, "versiones, hilos, tiempos de pared"),
    ("docs/DECISIONS.md",              False, "supuestos que afectan la reproducción"),
    ("docs/FIGURE_STYLE.md",          False, "estándar de presentación de figuras"),
    ("docs/PENDIENTES.md",              False, "lo que falta"),
    ("figures_src/requirements.txt",    False, "dependencias de las figuras"),
    ("figures_src/style_figures.py",   True,  "estilo único de las figuras"),
    ("figures_src/figure_registry.py", True,  "registro único de figuras"),
]

FIGURAS_TEX = [
    "temporal_supervision_horizon", "hospital_state_reconstruction",
    "m_sensitivity_v2", "real_multiseed_v2",
    "closed_form_fidelity_v2", "closed_form_fidelity_plane_v2",
]


def existe(rel):
    return os.path.exists(os.path.join(RAIZ, rel))


def runners_de_run_all():
    """Los runners que run_all.sh enumera, en su orden."""
    p = os.path.join(RAIZ, "run_all.sh")
    if not os.path.exists(p):
        return []
    txt = open(p, encoding="utf-8").read()
    bloque = re.search(r"EXPERIMENTS=\((.*?)\n\)", txt, re.S)
    if not bloque:
        return []
    out = []
    for linea in bloque.group(1).splitlines():
        m = re.search(r'"([^"|]+)\|([^|]*)\|([^"]+)"', linea)
        if m:
            out.append((m.group(1).strip(), m.group(3).strip()))
    return out


def modulos_de_experimentos():
    """Los src/lib/*.jl que docs/EXPERIMENTS.md cita."""
    p = os.path.join(RAIZ, "docs", "EXPERIMENTS.md")
    if not os.path.exists(p):
        return []
    txt = open(p, encoding="utf-8").read()
    return sorted(set(re.findall(r"`(src/(?:lib/)?[0-9A-Za-z_]+\.jl)`", txt)))


def modulos_incluidos_por_runners():
    """Los src/lib/*.jl que los runners cargan, leídos del propio código.

    Dos vías, y la segunda es la que se escapa de todas las listas:

        include(joinpath(LIBDIR, "00_setup.jl"))          vía el cargador
        include(joinpath(@__DIR__, "..", "src", "lib",    en diferido,
                         "19_real_data_multiseed.jl"))    dentro de un if

    La segunda no la ve quien recorre la cadena de `include` del cargador,
    porque el runner la arma por su cuenta y solo si hace falta.
    """
    out = set()
    for d in ("experiments", "src"):
        base = os.path.join(RAIZ, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _, filenames in os.walk(base):
            for f in sorted(filenames):
                if not f.endswith(".jl"):
                    continue
                txt = open(os.path.join(dirpath, f), encoding="utf-8",
                           errors="ignore").read()
                # joinpath(..., "src", "lib", "NN_x.jl")  y  joinpath(LIBDIR, "NN_x.jl")
                for m in re.finditer(r'"(?:src"\s*,\s*")?lib"\s*,\s*"([0-9A-Za-z_]+\.jl)"', txt):
                    out.add("src/lib/" + m.group(1))
                for m in re.finditer(r'joinpath\(\s*LIBDIR\s*,\s*"([0-9A-Za-z_]+\.jl)"', txt):
                    out.add("src/lib/" + m.group(1))
    return sorted(out)


def fuentes_del_yaml():
    """Los CSV que manuscript_values.yaml declara como fuente."""
    p = os.path.join(RAIZ, "verify", "manuscript_values.yaml")
    if not os.path.exists(p):
        return []
    txt = open(p, encoding="utf-8").read()
    return sorted(set(re.findall(r"^\s*fuente:\s*(\S+)\s*$", txt, re.M)))


def scripts_del_registro():
    """Los generar_fig_*.py que figure_registry.py enumera."""
    p = os.path.join(RAIZ, "figures_src", "figure_registry.py")
    if not os.path.exists(p):
        return []
    txt = open(p, encoding="utf-8").read()
    return sorted(set(re.findall(r'"((?:generar_fig|\d\d)_[0-9A-Za-z_]+\.py)"', txt)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--solo-faltantes", action="store_true")
    args = ap.parse_args()

    faltan_bloqueantes, faltan_menores, total = [], [], 0

    def revisar(rel, bloquea, nota, grupo):
        nonlocal total
        total += 1
        hay = existe(rel)
        if hay:
            if not args.solo_faltantes:
                print("  presente  %s" % rel)
        else:
            marca = "FALTA   " if bloquea else "falta   "
            print("  %s  %-44s %s" % (marca, rel, nota))
            (faltan_bloqueantes if bloquea else faltan_menores).append((rel, grupo, nota))

    def titulo(t):
        print("\n%s\n%s" % (t, "-" * len(t)))

    titulo("1 · archivos de raíz y documentación")
    for rel, bloquea, nota in RAIZ_ESPERADA:
        revisar(rel, bloquea, nota, "raíz")

    titulo("2 · runners enumerados por run_all.sh")
    rs = runners_de_run_all()
    if not rs:
        print("  (no pude leer la lista de run_all.sh)")
    for num, script in rs:
        revisar("experiments/%s" % script, True, "experimento %s" % num, "runner")

    titulo("3 · módulos de src/ citados por docs/EXPERIMENTS.md")
    ms = modulos_de_experimentos()
    if not ms:
        print("  (ninguno citado)")
    for m in ms:
        revisar(m, True, "módulo citado", "módulo")

    titulo("3b · módulos que los runners include (leído del código)")
    inc = modulos_incluidos_por_runners()
    if not inc:
        print("  (no pude resolver ningún include)")
    for m in inc:
        revisar(m, True, "lo include un runner", "módulo")

    titulo("4 · CSV declarados como fuente en manuscript_values.yaml")
    for f in fuentes_del_yaml():
        revisar(f, True, "fuente de una cifra declarada", "csv")

    titulo("5 · scripts del registro de figuras")
    for s in scripts_del_registro():
        revisar("figures_src/%s" % s, True, "script de figura", "figura")

    titulo("6 · los seis PDF que compila main.tex")
    for f in FIGURAS_TEX:
        revisar("figures/%s.pdf" % f, True, "figura del manuscrito", "pdf")

    print("\n" + "=" * 70)
    print("%d rutas comprobadas · %d presentes · %d faltan (%d bloquean la publicación)"
          % (total, total - len(faltan_bloqueantes) - len(faltan_menores),
             len(faltan_bloqueantes) + len(faltan_menores), len(faltan_bloqueantes)))
    print("=" * 70)

    if faltan_bloqueantes:
        print("\nBloquean la publicación:")
        for rel, grupo, nota in faltan_bloqueantes:
            print("  · %-40s %s" % (rel, nota))
    if faltan_menores:
        print("\nConviene tenerlos, no bloquean:")
        for rel, grupo, nota in faltan_menores:
            print("  · %-40s %s" % (rel, nota))

    return 1 if faltan_bloqueantes else 0


if __name__ == "__main__":
    sys.exit(main())
