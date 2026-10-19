# ============================================================
# experiments/16b_recover_summary_exp14.jl
# ------------------------------------------------------------
# [2026-09-09] Script de recuperación, no un experimento nuevo.
#
# experiments/16_run_real_data_multiseed_REFF_POSITIVITY_exp14.jl entrenó
# las 10 semillas completas (guardando cada una en
# results/real_data_multiseed/summary_multiseed_partial.csv, dentro
# del loop) pero se cayó DESPUÉS de eso, al imprimir el resumen final, por
# un bug de código (`length(::DataFrame)` no existe en DataFrames.jl --
# tenía que ser `nrow(...)`; ya corregido en el runner 16 original,
# ver el comentario "[2026-09-09] FIX" ahí).
#
# Como el entrenamiento de las 10 semillas (~3.6 h) ya está hecho y
# guardado en el CSV parcial, este script SOLO relee ese CSV y repite la
# agregación final + el guardado del CSV definitivo -- no reentrena nada,
# tarda segundos.
#
# Uso:
#     julia experiments/16b_recover_summary_exp14.jl
# ============================================================

using Statistics, CSV, DataFrames

const OUTDIR_BASE = "results/real_data_multiseed"
const PARCIAL     = "$OUTDIR_BASE/summary_multiseed_partial.csv"

isfile(PARCIAL) || error("No se encontró $PARCIAL -- este script asume que " *
                          "el runner 16 original ya corrió las 10 semillas " *
                          "y se cayó recién en el resumen final.")

resumen = CSV.read(PARCIAL, DataFrame)

nrow(resumen) == 20 || @warn "Se esperaban 20 filas (10 semillas x 2 métodos), " *
                              "hay $(nrow(resumen)) -- revisá si el parcial quedó incompleto."

println("\n" * "="^70)
println("  RESUMEN FINAL (10 semillas) -- recuperado de $PARCIAL")
println("="^70)

const SEEDS = 1:10  # igual que en el runner 16 original

for metodo in ("UDE", "SW-UDE")
    filas  = filter(r -> r.metodo == metodo, resumen)
    mu     = mean(filas.Reff_max)
    sd     = std(filas.Reff_max)
    n_sup1 = count(>(1.0), filas.Reff_max)
    println("$metodo:  Reff_max = $(round(mu, digits=3)) ± $(round(sd, digits=3))  " *
            "($n_sup1 de $(nrow(filas)) semillas superan 1)")
end

beta_min_global = minimum(resumen.beta_min)
println("\nMínimo global de β̂ en las $(2 * length(SEEDS)) corridas: " *
        "$(round(beta_min_global, digits=4))")

CSV.write("$OUTDIR_BASE/summary_multiseed.csv", resumen)
println("\n✓ Resumen guardado en $OUTDIR_BASE/summary_multiseed.csv")
println("  (columnas: seed, metodo, Reff_max, beta_min, beta_max)")
