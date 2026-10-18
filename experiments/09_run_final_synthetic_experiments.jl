# ============================================================
# Runner 09 — VERSIÓN FINAL (sintética): cierra los experimentos sobre los
# 7 escenarios sintéticos que en el proyecto original quedaban parciales o
# sin correr (ver src/lib/10_final_synthetic_experiments.jl para el detalle de
# cada gap).
# ============================================================
# Este script asume que YA corriste, al menos una vez, los runners 01-04
# (o vas a correrlos junto con `run_final_paralelo.sh` / `run_all.sh`) --
# este archivo NO los repite, solo agrega lo que faltaba:
#
#   A) Multi-semilla (10 seeds) + comparación pareada (t de Student +
#      Wilcoxon) para los 7 escenarios (antes: solo :lineal completo,
#      :dos_olas/:estacional parcial, el resto sin ninguna repetición).
#   B) Trayectorias puntuales para los 7 escenarios (antes: solo :lineal).
#
# NOTA (05-sep-2026, rediseño de ruido): este runner traía un paso (B)
# adicional que corría el experimento de ruido para los 7 escenarios --
# se QUITÓ de acá porque duplicaba EXACTAMENTE lo que ya hace
# `experiments/09b_run_ruido_pareado.jl` (Exp 4, el experimento de ruido
# unificado y CENTRAL, ver MAPA_EXPERIMENTOS.md): mismos escenarios,
# semillas y sigma_values, solo que escribiendo a una carpeta de salida
# distinta (`results/final_suite` en vez de `results/final_suite_ruido`).
# Mantenerlo acá significaba correr ~420 entrenamientos dos veces para
# nada. El experimento de ruido vive ahora en un solo lugar: 09b.
#
# NOTA (21-ago-2026, renumeración): este runner se llamaba
# `10_run_final_all_experiments.jl` y traía, además de lo anterior, un
# paso (D) de sensibilidad de datos reales a N/γ. Ese paso se separó a su
# propio archivo, `11_run_real_data_sensitivity_n_gamma.jl`, para que
# todos los runners que trabajan con datos reales (10 a 14) queden en un
# bloque de números contiguo, sin este runner -- que es 100% sobre los 7
# escenarios SINTÉTICOS -- interrumpiéndolo en el medio. Si antes corrías
# este archivo esperando que también corriera (D), ahora hace falta correr
# el 11 aparte (`run_all.sh`/`run_final_paralelo.sh` ya lo hacen por vos).
#
# NOTA sobre redundancia: (A) para :lineal/:dos_olas/:estacional es un
# superconjunto EXACTO de lo que hacían los runners DEPRECATED
# 05/06 (eliminados en la limpieza profunda, ver MAPA_EXPERIMENTOS.md).
# Para la versión final, corré SOLO este runner 09.
#
# ADVERTENCIA DE TIEMPO DE CÓMPUTO -- VERSIÓN FINAL (épocas completas)
# ------------------------------------------------------------
# Esto es, por lejos, lo más caro del proyecto (sin contar el runner 11,
# que ahora corre aparte):
#   (A) ~490 entrenamientos completos (10 global + ~61 por ventanas en
#       promedio, x 7 escenarios), hasta 8000 épocas cada uno.
#   (B) 14 entrenamientos (rápidos, 1 seed).
# ~504 entrenamientos en total (el experimento de ruido, ~560 más con la
# grilla σ_rel de 4 niveles, corre aparte en experiments/09b_run_ruido_pareado.jl).
# En un solo hilo de CPU esto puede tomar de varias horas a más de un día.
# Para una corrida de PRUEBA rápida (minutos, no horas -- valida que el
# pipeline corre sin errores, los NÚMEROS no sirven para el artículo),
# activá el modo smoke test:
#     SIR_UDE_SMOKE_TEST=1 julia experiments/09_run_final_synthetic_experiments.jl
# (reduce automáticamente épocas y semillas, ver src/lib/00_setup.jl). No
# hace falta editar `SEEDS_RED` ni ningún grid a mano para esto.
#
# Para la corrida en paralelo con seguimiento de progreso apto para
# `nohup`, usar `./run_final_paralelo.sh` en la raíz del proyecto en vez
# de invocar este archivo suelto -- ver ese script y el README para el
# resto de la orquestación (qué corre en paralelo con qué).
# ============================================================

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

mkpath("results/final_suite")
mkpath("results/trayectorias")

SEEDS_RED = 1:10   # SIR_UDE_SMOKE_TEST=1 lo reduce automáticamente -- no editar a mano

t_inicio_total = time()

# ── A) Multi-semilla + comparación pareada, los 7 escenarios ──────────────
println("\n" * "="^70)
println("  (A) Multi-semilla + comparación pareada — 7 escenarios")
println("="^70)
t0 = time()
df_comparacion = correr_todos_experimentos_multisemilla(seeds_red=SEEDS_RED,
                                                          outdir="results/final_suite")
println("  (A) tiempo total: ", formatear_duracion(time() - t0))

# ── B) Trayectorias puntuales, los 7 escenarios ────────────────────────────
println("\n" * "="^70)
println("  (B) Trayectorias puntuales — 7 escenarios")
println("="^70)
t0 = time()
graficar_todas_trayectorias(seed_red=1, outdir="results/trayectorias")
println("  (B) tiempo total: ", formatear_duracion(time() - t0))

println("\n" * "="^70)
println("  ✓ VERSIÓN FINAL (sintética) completa. Tiempo total: ", formatear_duracion(time() - t_inicio_total))
println("  Resultados nuevos en:")
println("    results/final_suite/comparacion_pareada_TODOS_escenarios.csv")
println("    results/trayectorias/  (7 escenarios × 2 métodos)")
println("  Recuerda que experiments/01_run_all_scenarios.jl ahora también genera")
println("  los GIF de evolución de β (antes desactivados en todo el proyecto).")
println("  Para el experimento de ruido (Exp 4, unificado, σ_rel), correr aparte")
println("  experiments/09b_run_ruido_pareado.jl -- ver results/final_suite_ruido/.")
println("  Para la sensibilidad de datos reales a N/γ (antes el paso D de este")
println("  runner), correr aparte experiments/11_run_real_data_sensitivity_n_gamma.jl.")
println("="^70)
