# ============================================================
# src/lib/19_real_data_multiseed.jl
# ------------------------------------------------------------
# Comparación pareada multi-semilla UDE vs SW-UDE sobre la serie real.
#
# POR QUÉ
# ------------------------------------------------------------
# Todo el bloque de datos reales corre hoy con una única semilla
# (seed=1234), a diferencia de los escenarios sintéticos, que usan n=10 con
# prueba t pareada y Wilcoxon. Eso impide reportar cualquier valor p en la
# sección real: las diferencias observadas son descriptivas, no evidencia
# estadística. Este archivo cierra esa brecha con el MISMO protocolo que
# `correr_todos_experimentos_multisemilla` usa en lo sintético.
#
# Diseño:
#   • Una red distinta por semilla, pero la MISMA semilla para UDE y para
#     SW-UDE dentro de cada repetición -> comparación pareada legítima.
#   • Partición cronológica 80/20 idéntica a `evaluar_datos_reales_v2`; la
#     pérdida de ambos métodos se restringe a `idx_entren`.
#   • Métricas sobre I(t) únicamente: es la única serie observada. S y R
#     son construidos a partir de I y no son mediciones independientes.
#   • Se reporta además MAE_test (que hoy falta en el manuscrito) y
#     TV(β̂) como diagnóstico de identificabilidad.
#
# No modifica ninguna función existente.
# ============================================================


"""
    evaluar_real_data_paired_multiseed(SIR; N, γ, Δt=1.0, hidden, layers,
                                      lr, epochs, m, frac_train=0.8,
                                      seeds=1:10, clip_norm=nothing,
                                      outdir="results/real_data_paired_multiseed")

Entrena UDE y SW-UDE sobre la serie real para cada semilla de `seeds` y
devuelve `(df_corridas, df_pareado)`. Escribe ambos como CSV en `outdir`.

`df_corridas`: una fila por (semilla, método) con las métricas sobre I(t).
`df_pareado` : una fila por métrica con medias, desviaciones, diferencia
media, estadístico t, y valores p de la prueba t pareada y de Wilcoxon
(a dos colas y a una cola en la dirección esperada).
"""
function evaluar_real_data_paired_multiseed(SIR::Matrix{Float64};
        N::Float64, γ::Float64, Δt::Float64=1.0,
        hidden::Int, layers::Int, lr::Float64, epochs::Int, m::Int,
        frac_train::Float64=0.8,
        seeds=1:10,
        clip_norm::Union{Nothing,Float64}=nothing,
        outdir::String="results/real_data_paired_multiseed")

    mkpath(outdir)
    cfg = make_real_data_config(SIR; N=N, γ=γ, Δt=Δt)
    idx_entren, idx_test = split_train_test(cfg.T; frac_train=frac_train)
    k_split = last(idx_entren)
    cols_tr = 1:(k_split + 1)
    cols_te = (k_split + 2):(cfg.T + 1)
    obs     = SIR[2, :]
    epochs_real = epocas_final(epochs)

    _rmse(a, b) = sqrt(mean((a .- b) .^ 2))
    _mae(a, b)  = mean(abs.(a .- b))
    _r2(a, b)   = 1 - sum((a .- b) .^ 2) / sum((b .- mean(b)) .^ 2)   # a=pred, b=obs
    _mape(a, b) = 100 * mean(abs.((a .- b) ./ b))

    println("\n" * "="^70)
    println("  Datos reales — comparación pareada multi-semilla")
    println("  N=$(round(N,digits=0))  γ=$γ  m=$m  epochs=$epochs_real  semillas=$(collect(seeds))")
    println("  Entrenamiento: $(length(idx_entren)) pasos | Prueba: $(length(idx_test)) pasos")
    println("="^70)

    filas = NamedTuple[]
    prog  = iniciar_progreso("Datos reales multi-semilla", length(seeds))

    for s in seeds
        println("\n  ── semilla $s ──")

        for (etiqueta, entrenar) in (("UDE", :global), ("SW-UDE", :ventanas))
            nn, p0, st = build_network(hidden, layers; seed=s, bias_inicial=Float32(BETA0_REF_FIJO))
            p_ent = if entrenar == :global
                first(train_global_rd(cfg, SIR, nn, st, p0;
                                       epochs=epochs_real, lr=lr, idx_entren=idx_entren))
            else
                first(train_windowed_rd(cfg, SIR, nn, st, p0;
                                         m=m, epochs=epochs_real, lr=lr,
                                         clip_norm=clip_norm, idx_entren=idx_entren))
            end

            pred = rollout_rd(cfg, p_ent, st, nn)
            Ihat = pred[2, :]
            beta = [beta_theta_rd(cfg, cfg.ts[k], SIR[2, k], p_ent, st, nn) for k in 1:cfg.T]
            reff = r_effective(beta, pred[1, 1:cfg.T], N, γ)

            push!(filas, (
                seed = s, metodo = etiqueta, m = (entrenar == :global ? -1 : m),
                RMSE       = _rmse(Ihat, obs),
                MAE        = _mae(Ihat, obs),
                MAPE_pct   = _mape(Ihat, obs),
                R2         = _r2(Ihat, obs),
                RMSE_train = _rmse(Ihat[cols_tr], obs[cols_tr]),
                MAE_train  = _mae(Ihat[cols_tr], obs[cols_tr]),
                RMSE_test  = _rmse(Ihat[cols_te], obs[cols_te]),
                MAE_test   = _mae(Ihat[cols_te], obs[cols_te]),       # ← faltaba en el manuscrito
                R2_test    = _r2(Ihat[cols_te], obs[cols_te]),
                TV_beta    = mean(abs.(diff(beta))),
                beta_min   = minimum(beta), beta_max = maximum(beta),
                frac_beta_neg = count(<(0.0), beta) / length(beta),
                Reff_max   = maximum(reff), Reff_final = reff[end],
                epochs = epochs_real, N = N, gamma = γ,
            ))
            @printf("     %-7s RMSE=%8.2f  RMSE_test=%9.2f  R2_test=%8.3f  TV_beta=%.5f\n",
                    etiqueta, filas[end].RMSE, filas[end].RMSE_test,
                    filas[end].R2_test, filas[end].TV_beta)
        end
        avanzar!(prog; detalle="seed=$s")
    end
    finalizar_progreso!(prog)

    df = DataFrame(filas)
    CSV.write(joinpath(outdir, "real_data_paired_multiseed.csv"), df)

    # ── Comparación pareada ─────────────────────────────────────────────
    g = sort(df[df.metodo .== "UDE",    :], :seed)
    w = sort(df[df.metodo .== "SW-UDE", :], :seed)
    @assert g.seed == w.seed "Las semillas no quedaron pareadas"

    # true  = un valor MENOR es mejor (errores);  false = MAYOR es mejor (R²)
    direccion = [(:RMSE, true), (:MAE, true), (:MAPE_pct, true), (:R2, false),
                 (:RMSE_train, true), (:RMSE_test, true), (:MAE_test, true),
                 (:R2_test, false), (:TV_beta, true)]

    filas_p = NamedTuple[]
    for (met, menor_mejor) in direccion
        a = Float64.(g[!, met]); b = Float64.(w[!, met]); d = b .- a
        tt  = OneSampleTTest(d);  p2  = pvalue(tt)
        wt  = SignedRankTest(d);  pw2 = pvalue(wt)
        favorece = menor_mejor ? (mean(d) < 0) : (mean(d) > 0)
        favorece_w = menor_mejor ? (median(d) < 0) : (median(d) > 0)
        push!(filas_p, (
            metrica = String(met), n = length(d),
            media_UDE = mean(a), sd_UDE = std(a),
            media_SW  = mean(b), sd_SW  = std(b),
            dif_media = mean(d), t_stat = tt.t,
            p_t_dos_colas = p2,
            p_t_una_cola  = favorece ? p2/2 : 1 - p2/2,
            p_wilcoxon_dos_colas = pw2,
            p_wilcoxon_una_cola  = favorece_w ? pw2/2 : 1 - pw2/2,
            favorece_SW = favorece,
        ))
    end
    dfp = DataFrame(filas_p)
    CSV.write(joinpath(outdir, "real_data_paired.csv"), dfp)

    println("\n" * "="^70)
    println("  Comparación pareada (n=$(length(seeds)) semillas), H1: SW-UDE mejor")
    println("="^70)
    for r in eachrow(dfp)
        @printf("  %-11s UDE %10.4f ± %-9.4f  SW %10.4f ± %-9.4f  dif %+10.4f  t=%6.2f  p1=%.4g  wilc=%.4g  %s\n",
                r.metrica, r.media_UDE, r.sd_UDE, r.media_SW, r.sd_SW,
                r.dif_media, r.t_stat, r.p_t_una_cola, r.p_wilcoxon_una_cola,
                r.p_t_una_cola < 0.05 ? "*" : "")
    end
    println("\n  CSV: $outdir/real_data_paired_multiseed.csv  y  real_data_paired.csv")
    println("  Nota: TV_beta es diagnóstico de suavidad de β̂, no una métrica de error;")
    println("        interpretar su prueba con cuidado.")

    # ── Boxplots, mismo estilo que los sintéticos ───────────────────────
    for met in (:RMSE, :RMSE_test, :TV_beta)
        a = Float64.(g[!, met]); b = Float64.(w[!, met])
        p = boxplot(["UDE"], a, label="", color=:orange, alpha=0.6,
                    ylabel=String(met), title="Real data — $(String(met)) over $(length(a)) seeds",
                    size=(600, 460), left_margin=6mm, bottom_margin=6mm)
        boxplot!(p, ["SW-UDE (m=$m)"], b, label="", color=:steelblue, alpha=0.6)
        savefig_all(p, joinpath(outdir, "boxplot_$(String(met))"); formats=(:png, :pdf, :eps))
    end

    return df, dfp
end

println("✓ evaluar_real_data_paired_multiseed definida (comparación pareada sobre datos reales)")
