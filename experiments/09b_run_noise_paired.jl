# Paired noise experiment for the seven synthetic scenarios.
# Noise is multiplicative and relative to each observation (sigma_rel);
# see src/lib/27_noise_relative.jl.

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

@assert length(SCENARIO_ORDER) == 7 "Expected seven synthetic scenarios in SCENARIO_ORDER"

mkpath("results/final_suite_noise")

df = correr_todo_experimento5_ruido(sigma_values = [0.00, 0.05, 0.10, 0.20],
                                     seeds_red   = 1:10,
                                     outdir      = "results/final_suite_noise")
println("\n✓ Listo. CSVs en results/final_suite_noise/ (incluye")
println("  noise_unified_detail_ALL_scenarios.csv con el esquema")
println("  escenario/metodo/seed/sigma_rel/porcentaje_noise/RMSE_SIR/RMSE_I/RMSE_beta)")
