#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verificar_cifras.py — contrasta cada cifra citada en el manuscrito contra
el CSV que la sustenta, dentro de este mismo repositorio.

    python3 verify/verificar_cifras.py                  # todo
    python3 verify/verificar_cifras.py --tabla tab:destilacion_I
    python3 verify/verificar_cifras.py --solo-fallas
    python3 verify/verificar_cifras.py --json informe.json

No requiere Julia, ni pandas, ni numpy. PyYAML se usa si está instalado;
si no, se recurre al lector mínimo incluido más abajo, que cubre el
subconjunto de YAML empleado por verify/cifras_manuscrito.yaml.

Código de salida: 0 si no hubo ninguna FALLA, 1 si hubo al menos una.
"""

import argparse
import csv
import json
import math
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(RAIZ, "verify", "cifras_manuscrito.yaml")


# ----------------------------------------------------------------------
# Lectura del archivo de especificación
# ----------------------------------------------------------------------

def _escalar(txt):
    t = txt.strip()
    if t.startswith(('"', "'")) and t.endswith(('"', "'")) and len(t) >= 2:
        return t[1:-1]
    if t in ("true", "True"):
        return True
    if t in ("false", "False"):
        return False
    if t in ("null", "~", ""):
        return None
    try:
        return int(t)
    except ValueError:
        pass
    try:
        return float(t)
    except ValueError:
        pass
    return t


def _inline_dict(txt):
    cuerpo = txt.strip()[1:-1].strip()
    salida = {}
    if not cuerpo:
        return salida
    for par in cuerpo.split(","):
        k, _, v = par.partition(":")
        salida[k.strip()] = _escalar(v)
    return salida


def _yaml_minimo(ruta):
    """Lector para el subconjunto usado: lista de mapas planos en el nivel
    superior, con valores escalares o diccionarios en línea."""
    items, actual = [], None
    with open(ruta, encoding="utf-8") as fh:
        for linea in fh:
            cruda = linea.rstrip("\n")
            sin = cruda.strip()
            if not sin or sin.startswith("#"):
                continue
            if cruda.startswith("- "):
                actual = {}
                items.append(actual)
                cruda = "  " + cruda[2:]
                sin = cruda.strip()
            if actual is None:
                continue
            clave, _, valor = sin.partition(":")
            valor = valor.strip()
            if valor.startswith("{"):
                actual[clave.strip()] = _inline_dict(valor)
            else:
                actual[clave.strip()] = _escalar(valor)
    return items


def leer_spec(ruta):
    try:
        import yaml  # noqa
        with open(ruta, encoding="utf-8") as fh:
            datos = yaml.safe_load(fh)
        return datos if isinstance(datos, list) else datos.get("cifras", [])
    except ImportError:
        return _yaml_minimo(ruta)


# ----------------------------------------------------------------------
# Reducciones
# ----------------------------------------------------------------------

def _mediana(v):
    s = sorted(v)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


REDUCCIONES = {
    "first": lambda v: v[0],
    "last": lambda v: v[-1],
    "mean": lambda v: sum(v) / len(v),
    "median": _mediana,
    "min": min,
    "max": max,
    "sum": sum,
    "count": len,
    # Cuántos valores de la columna son negativos o positivos. Sirve para
    # las afirmaciones de admisibilidad del tipo "en cuatro de las diez
    # corridas la tasa inferida se vuelve negativa", que de otro modo no
    # se pueden expresar: el campo `filtro` solo compara por igualdad.
    "count_neg": lambda v: sum(1 for x in v if x < 0),
    "count_pos": lambda v: sum(1 for x in v if x > 0),
    "std": lambda v: math.sqrt(sum((x - sum(v) / len(v)) ** 2 for x in v)
                               / (len(v) - 1)) if len(v) > 1 else 0.0,
}


# Transformaciones aplicables al valor reducido antes de comparar.
TRANSFORMACIONES = {
    "inverso": lambda x: 1.0 / x,
    "periodo": lambda x: 2.0 * math.pi / x,   # de frecuencia angular a días
    "exp": math.exp,
    "log": math.log,
    "sqrt": math.sqrt,
    "negativo": lambda x: -x,
}


def _num(txt):
    t = (txt or "").strip()
    if t in ("", "NA", "NaN", "nan", "missing", "NULL"):
        return None
    try:
        return float(t)
    except ValueError:
        return None


# ----------------------------------------------------------------------
# Evaluación de una cifra
# ----------------------------------------------------------------------

_CACHE = {}


def cargar_csv(ruta_rel):
    if ruta_rel not in _CACHE:
        ruta = os.path.join(RAIZ, ruta_rel)
        if not os.path.exists(ruta):
            _CACHE[ruta_rel] = None
        else:
            with open(ruta, encoding="utf-8-sig", newline="") as fh:
                _CACHE[ruta_rel] = list(csv.DictReader(fh))
    return _CACHE[ruta_rel]


def evaluar(cifra):
    """Devuelve (estado, calculado, detalle) con estado en
    PASA / FALLA / OMITIDA."""
    if cifra.get("estado") == "pendiente":
        return "OMITIDA", None, cifra.get("nota", "dato aún no incorporado")

    fuente = cifra.get("fuente")
    filas = cargar_csv(fuente)
    if filas is None:
        return "OMITIDA", None, "falta %s" % fuente

    filtro = cifra.get("filtro") or {}
    sel = [f for f in filas
           if all(str(f.get(k, "")).strip() == str(v).strip()
                  for k, v in filtro.items())]
    # `filtro` solo compara por igualdad, y hay afirmaciones que se definen
    # por exclusión: «en las 21 combinaciones con ruido» son todas las filas
    # salvo las de sigma = 0. Por eso `filtro_no`.
    filtro_no = cifra.get("filtro_no") or {}
    if filtro_no:
        sel = [f for f in sel
               if not any(str(f.get(k, "")).strip() == str(v).strip()
                          for k, v in filtro_no.items())]
    if not sel:
        return "FALLA", None, "el filtro %r no selecciona ninguna fila" % filtro

    col = cifra.get("columna")
    if col is not None and col not in sel[0]:
        return "FALLA", None, "no existe la columna %r en %s" % (col, fuente)

    # `columna_vs` compara dos columnas fila por fila, y la reducción opera
    # sobre la diferencia. Hace falta para las afirmaciones de recuento
    # pareado: «el error es mayor con ventanas que global en 18 de las 21
    # combinaciones» es count_pos de (media_Windowed - media_UDE). Con una
    # sola columna no se puede expresar.
    col_vs = cifra.get("columna_vs")
    if col_vs is not None and col_vs not in sel[0]:
        return "FALLA", None, "no existe la columna %r en %s" % (col_vs, fuente)

    red = cifra.get("reduccion", "first")
    if red == "count":
        calc = float(len(sel))
    elif col_vs is not None:
        pares = [(_num(f[col]), _num(f[col_vs])) for f in sel]
        vals = [a - b for a, b in pares if a is not None and b is not None]
        if not vals:
            return "FALLA", None, "sin pares numéricos en %r y %r" % (col, col_vs)
        if red not in REDUCCIONES:
            return "FALLA", None, "reducción desconocida %r" % red
        calc = float(REDUCCIONES[red](vals))
    else:
        vals = [_num(f[col]) for f in sel]
        vals = [v for v in vals if v is not None]
        if not vals:
            return "FALLA", None, "la columna %r no tiene valores numéricos" % col
        if red not in REDUCCIONES:
            return "FALLA", None, "reducción desconocida %r" % red
        calc = float(REDUCCIONES[red](vals))

    trans = cifra.get("transformacion")
    if trans:
        if trans not in TRANSFORMACIONES:
            return "FALLA", None, "transformación desconocida %r" % trans
        try:
            calc = float(TRANSFORMACIONES[trans](calc))
        except (ZeroDivisionError, ValueError, OverflowError) as exc:
            return "FALLA", None, "transformación %s falló: %s" % (trans, exc)

    calc *= float(cifra.get("escala", 1.0))
    if cifra.get("valor_absoluto"):
        calc = abs(calc)

    esperado = float(cifra["valor"])
    dec = cifra.get("redondeo")

    if dec is not None:
        obtenido = round(calc, int(dec))
        if int(dec) <= 0:
            obtenido = float(int(round(calc, int(dec))))
        ok = abs(obtenido - esperado) < 10 ** (-int(dec) - 6) if dec > 0 \
            else obtenido == esperado
        detalle = "cita %s · CSV %.10g → redondeado %s" % (
            _fmt(esperado), calc, _fmt(obtenido))
        return ("PASA" if ok else "FALLA"), calc, detalle

    # Algunas celdas del manuscrito son desigualdades, no valores: la
    # tabla tab:synthetic_multiseed imprime "$<0.0001^{t}$" donde el
    # p-valor cae por debajo de lo que la tabla muestra. Comparar por
    # igualdad ahí es incorrecto en los dos sentidos: FALLA si el valor
    # real es menor, que es justo lo que la cita afirma.
    comp = cifra.get("comparacion")
    if comp in ("menor_que", "mayor_que"):
        ok = calc < esperado if comp == "menor_que" else calc > esperado
        signo = "<" if comp == "menor_que" else ">"
        detalle = "cita %s %s · CSV %.10g" % (signo, _fmt(esperado), calc)
        return ("PASA" if ok else "FALLA"), calc, detalle

    tol = float(cifra.get("tolerancia", 0.005))
    ref = abs(esperado) if esperado else 1.0
    ok = abs(calc - esperado) <= tol * ref
    detalle = "cita %s · CSV %.10g · desvío %.3g%%" % (
        _fmt(esperado), calc, 100 * abs(calc - esperado) / ref)
    return ("PASA" if ok else "FALLA"), calc, detalle


def _fmt(x):
    if x == int(x) and abs(x) < 1e15:
        return str(int(x))
    return ("%.10g" % x)


# ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec", default=SPEC)
    ap.add_argument("--tabla", help="verificar solo esta tabla/figura")
    ap.add_argument("--solo-fallas", action="store_true")
    ap.add_argument("--json", help="además, escribir el informe en JSON")
    args = ap.parse_args()

    if not os.path.exists(args.spec):
        print("No existe el archivo de cifras: %s" % args.spec, file=sys.stderr)
        return 2

    cifras = leer_spec(args.spec)
    if args.tabla:
        cifras = [c for c in cifras if c.get("tabla") == args.tabla]

    informe, n = [], {"PASA": 0, "FALLA": 0, "OMITIDA": 0}
    ancho = max([len(c.get("id", "")) for c in cifras] or [10])
    tabla_actual = None

    for c in cifras:
        estado, calc, detalle = evaluar(c)
        n[estado] += 1
        informe.append({"id": c.get("id"), "tabla": c.get("tabla"),
                        "estado": estado, "citado": c.get("valor"),
                        "calculado": calc, "detalle": detalle,
                        "fuente": c.get("fuente")})
        if args.solo_fallas and estado != "FALLA":
            continue
        if c.get("tabla") != tabla_actual:
            tabla_actual = c.get("tabla")
            print("\n%s" % tabla_actual)
            print("-" * max(len(str(tabla_actual)), 4))
        marca = {"PASA": "PASA   ", "FALLA": "FALLA  ", "OMITIDA": "omitida"}[estado]
        print("  %s  %-*s  %s" % (marca, ancho, c.get("id", ""), detalle))

    print("\n" + "=" * 72)
    print("%d verificadas · %d PASA · %d FALLA · %d omitidas"
          % (len(cifras), n["PASA"], n["FALLA"], n["OMITIDA"]))
    print("=" * 72)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(informe, fh, ensure_ascii=False, indent=2)
        print("Informe JSON: %s" % args.json)

    return 1 if n["FALLA"] else 0


if __name__ == "__main__":
    sys.exit(main())
