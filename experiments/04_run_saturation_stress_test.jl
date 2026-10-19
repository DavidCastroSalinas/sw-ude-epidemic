# Saturation stability stress test (Section 14b.2).
# Trains UDE and SW-UDE for each (m, clip_norm) pair and writes one summary
# CSV. The combined output avoids filename collisions between clip_norm runs.
# Run with: julia --project=. experiments/04_run_saturation_stress_test.jl

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

mkpath("results/saturacion_stress_test")
COMBINACIONES = [(m_test, clip_test) for m_test in [1, 2, 3, 5, 10] for clip_test in [nothing, 5.0, 1.0]]
prog = iniciar_progreso("Stress test :saturacion (m × clip_norm)", length(COMBINACIONES))
filas = NamedTuple[]
for (m_test, clip_test) in COMBINACIONES
    println("\n--- :saturacion  m=$m_test  clip_norm=$clip_test ---")
    res = run_experiment(:saturacion;
                          m         = m_test,
                          epochs    = epocas_final(3000),
                          lr        = 0.003,
                          hidden    = 16,
                          layers    = 2,
                          clip_norm = clip_test,
                          save_csv  = false,
                          make_gif  = false,
                          outdir    = "results/saturacion_stress_test")
    mG, mW = res.metrics_global, res.metrics_windowed
    @printf("  RMSE_S=%.4f  RMSE_I=%.4f  RMSE_R=%.4f  RMSE_β=%.6f\n",
            mW.RMSE_S, mW.RMSE_I, mW.RMSE_R, mW.RMSE_β)
    push!(filas, (
        # clip_norm=missing cuando no hay recorte de gradiente -- mismo
        # idioma que ya usa el resto del proyecto (ver `m=missing` para el
        # método :global en src/lib/08_experiment18_core.jl) en vez de mezclar
        # String y Float64 en la misma columna.
        m = m_test, clip_norm = (clip_test === nothing ? missing : clip_test),
        rmse_S_global = mG.RMSE_S, rmse_I_global = mG.RMSE_I, rmse_R_global = mG.RMSE_R,
        rmse_beta_global = mG.RMSE_β, mae_beta_global = mG.MAE_β,
        rmse_S_ventanas = mW.RMSE_S, rmse_I_ventanas = mW.RMSE_I, rmse_R_ventanas = mW.RMSE_R,
        rmse_beta_ventanas = mW.RMSE_β, mae_beta_ventanas = mW.MAE_β,
    ))
    avanzar!(prog; detalle="m=$m_test, clip_norm=$clip_test")
end
finalizar_progreso!(prog)

df_resumen = DataFrame(filas)
path_resumen = joinpath("results", "saturacion_stress_test", "summary_stress_test.csv")
CSV.write(path_resumen, df_resumen)
println("\n✓ Exp 7 completo. Resumen (15 filas) guardado en $path_resumen")
println(df_resumen)
