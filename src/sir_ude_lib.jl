# ============================================================
# sir_ude_lib.jl
# ------------------------------------------------------------
# Windowed Recurrent SIR-UDE — full library, command-line ready.
#
# This file assembles the entire modeling / training / plotting /
# statistical-comparison toolkit that used to live in the Jupyter
# notebook `sir_ude_experiments_v3_accionable_1_.ipynb`, split into
# the files under `src/lib/` so it can be `include`-d from plain Julia
# scripts and run with `julia scriptname.jl` instead of Jupyter.
#
# All chart-facing text (titles, axis labels, legends, annotations)
# has been translated to English. Docstrings/comments remain in
# Spanish (they are developer documentation, not figures) but every
# function name and call signature is unchanged from the notebook,
# so any code you already have that calls these functions keeps
# working unmodified.
#
# NOTA (21-ago-2026, renumeración): los archivos de `src/lib/` se
# renumeraron para que todo lo que trabaja con la serie REAL quede en un
# bloque de números contiguo (11 a 15 acá abajo; 16 y 17 -- regresión
# simbólica -- siguen fuera de este bundle por ser pesados/opcionales,
# igual que antes). El orden de `include` no es un requisito funcional
# (las funciones se resuelven en el momento de la LLAMADA, no de la
# definición), pero se dejó en orden numérico para que sea fácil de leer.
#
# Usage from a runner script:
#     include(joinpath(@__DIR__, "sir_ude_lib.jl"))
#     run_experiment(:lineal; m=10, epochs=7000)
# ============================================================

const LIBDIR = joinpath(@__DIR__, "lib")

# ── Núcleo compartido (setup, entrenamiento, ploteo base, config, progreso) ─
include(joinpath(LIBDIR, "00_setup.jl"))
include(joinpath(LIBDIR, "01_model_training.jl"))
include(joinpath(LIBDIR, "02_plotting_base.jl"))
include(joinpath(LIBDIR, "03_scenario_config.jl"))
include(joinpath(LIBDIR, "04_progress.jl"))

# ── Experimentos SINTÉTICOS (7 escenarios) ────────────────────────────────
include(joinpath(LIBDIR, "05_run_experiment.jl"))
include(joinpath(LIBDIR, "27_noise_relative.jl"))
include(joinpath(LIBDIR, "08_experiment18_core.jl"))
include(joinpath(LIBDIR, "09_experiment18_plots.jl"))
include(joinpath(LIBDIR, "10_final_synthetic_experiments.jl"))

# ── Datos REALES (bloque 11-15 menos el 13, ver nota abajo; 16-17,
# regresión simbólica sobre β̂(t,I), quedan fuera de este bundle por ser
# pesados/opcionales -- los incluye aparte
# experiments/14_run_pipeline_beta_simbolica.jl) ──────────────────────────────
include(joinpath(LIBDIR, "11_real_data.jl"))
include(joinpath(LIBDIR, "12_extended_metrics.jl"))
# [2026-09-07] src/lib/13_real_data_sensitivity_n_gamma.jl SE ELIMINÓ, a pedido
# de David: "quiero dejarlo fijo [N] y omitir los experimentos relacionados
# a la sensibilidad de N". Ese archivo solo definía
# `evaluar_sensibilidad_datos_reales`, usada exclusivamente por el también
# eliminado experiments/11_run_real_data_sensitivity_n_gamma.jl (Exp 13,
# generaba tab:datos_reales_sensibilidad_N_gamma) y por
# experiments/19_robustez_reff_N_SUPLEMENTARIO_exp13.jl (también eliminado --
# exploraba el día de cruce de R_eff para varios N). Ningún otro archivo
# de este proyecto llama a esa función (verificado con grep); las dos
# menciones que quedan en 10_final_synthetic_experiments.jl y
# 14_real_data_window_sensitivity.jl son solo comentarios/docstrings.
include(joinpath(LIBDIR, "14_real_data_window_sensitivity.jl"))
include(joinpath(LIBDIR, "15_real_data_extrapolation_horizons.jl"))

# ── Grilla de m escalada por 1/γ (2026-09-05, reemplaza listas fijas) ────

# NOTA (05-sep-2026, rediseño de ruido): src/lib/07_noise_sensitivity.jl y
# experiments/03_run_noise_sensitivity_all.jl (esquema de σ absoluto en
# individuos) se ELIMINARON -- reemplazados por src/lib/27_noise_relative.jl
# (σ_rel multiplicativo, ver ese archivo). Ver MAPA_EXPERIMENTS.md,
# "quinta pasada", para el detalle completo del rediseño.

println("\n✓ sir_ude_lib.jl loaded — all sections (1–18, minus 13, removed")
println("  2026-09-07) available, plus the final-suite generalizations for")
println("  the 7 synthetic scenarios in 10_final_synthetic_experiments.jl,")
println("  plus the real-data block (11,12,14,15): real_data (now with FIXED")
println("  reference initial conditions, see construir_serie_referencia_fija),")
println("  extended_metrics, window-size sensitivity, and extrapolation")
println("  metrics by forecast horizon, plus progress-tracking utilities in")
println("  04_progress.jl. (N/γ sensitivity, src/lib/13, was REMOVED at David's")
println("  request -- N is now fixed, not swept.)")
println("  (Symbolic regression on β̂(t,I) -- 16_symbolic_regression_beta.jl and")
println("  17_pipeline_beta_simbolica.jl -- is NOT included here; it's heavier")
println("  and optional, see experiments/14_run_pipeline_beta_simbolica.jl.)")
