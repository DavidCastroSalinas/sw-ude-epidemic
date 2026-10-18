# Runner 09b — Experimento de ruido unificado (Exp 4, HALLAZGO CENTRAL
# sintético). Rediseño 05-sep-2026: ruido MULTIPLICATIVO relativo a la
# magnitud de cada observación (σ_rel), grilla {0.00,0.05,0.10,0.20},
# REEMPLAZA los dos esquemas anteriores (fracción de N y σ absoluto en
# individuos, este último antes en experiments/03_run_noise_sensitivity_all.jl,
# eliminado) -- ver src/lib/27_noise_relative.jl y MAPA_EXPERIMENTS.md.
include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

@assert length(SCENARIO_ORDER) == 7 "SCENARIO_ORDER todavía tiene :realchile -- arreglá src/lib/03 primero"

mkpath("results/final_suite_ruido")

df = correr_todo_experimento5_ruido(sigma_values = [0.00, 0.05, 0.10, 0.20],
                                     seeds_red   = 1:10,
                                     outdir      = "results/final_suite_ruido")
println("\n✓ Listo. CSVs en results/final_suite_ruido/ (incluye")
println("  noise_detalle_unificado_ALL_scenarios.csv con el esquema")
println("  escenario/metodo/seed/sigma_rel/porcentaje_ruido/RMSE_SIR/RMSE_I/RMSE_beta)")
