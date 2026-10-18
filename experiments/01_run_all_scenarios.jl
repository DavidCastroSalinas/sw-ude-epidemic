# ============================================================
# Run all 7 scenarios (corrected architecture) + summary figure  [Sections 13.5-13.6]
# ============================================================
# Run from the command line with:
#     julia --project=. experiments/01_run_all_scenarios.jl
# (or just `julia experiments/01_run_all_scenarios.jl` if you have the packages installed
# globally). Adjust the `cd`/`outdir` below if you want the figures and
# CSVs somewhere else.
# ============================================================

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

mkpath("results/all_scenarios")
# make_gif=true: versión final -- genera, además de las figuras estáticas,
# un GIF animado por escenario y por método (UDE / SW-UDE) mostrando
# cómo evoluciona β̂(t,I) a lo largo del entrenamiento (ver make_gif_beta,
# src/lib/02_plotting_base.jl). Antes de esta versión, make_gif estaba
# desactivado en TODAS las corridas del proyecto (make_gif=false en cada
# llamada), así que ningún GIF se había generado nunca pese a que la
# función ya estaba completamente implementada.
results_all, df_resumen_all = run_all_experiments(outdir="results/all_scenarios", make_gif=true)

# Publication-style summary figure: β recovery panel for all 7 scenarios
fig_resumen = plot_beta_grid_summary(results_all; outdir="results/all_scenarios")
println("\n✓ Done. See results/all_scenarios/ for per-scenario figures, CSVs, and the")
println("  consolidated summary figure figura_resumen_beta_todos_escenarios.{png,pdf}")
