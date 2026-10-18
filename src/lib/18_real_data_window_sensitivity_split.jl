# ============================================================
# src/lib/18_real_data_window_sensitivity_split.jl   (v2)
# ------------------------------------------------------------
# Sensibilidad a m sobre datos reales, SIN fuga de información.
#
# POR QUÉ ESTE ARCHIVO EXISTE
# ------------------------------------------------------------
# `run_window_sensitivity_real` (src/lib/14) entrena cada valor de m sobre la
# serie COMPLETA -- su propio encabezado lo declara: "NO separa
# entrenamiento/validación (idx_entren = toda la serie)". Sirve para ver la
# FORMA de la curva, pero no para SELECCIONAR m: el m elegido así ya vio el
# período de prueba sobre el que después se reportan las métricas fuera de
# muestra.
#
# CAMBIOS DE v2 RESPECTO DE v1
#   • Registra TV(β̂) = media de |Δβ̂| entre pasos consecutivos, junto con
#     β̂_min, β̂_max y la fracción de pasos con β̂ < 0.
#     Motivo: en datos reales no existe β_true, así que RMSE_β no se puede
#     calcular y el error de trayectoria NO es un buen proxy de
#     identificabilidad (el artículo muestra que ambas métricas se
#     disocian). TV(β̂) es un diagnóstico que SÍ se puede medir sobre datos
#     reales: si las ventanas cortas dejan que β absorba ruido, TV(β̂) debe
#     crecer al bajar m. La fracción de β̂<0 detecta el modo de falla
#     observado con N demográfico (β negativa ⇒ flujo de contagio
#     invertido).
#   • Guarda `epochs` en el CSV, para poder distinguir sin ambigüedad una
#     corrida real de una hecha con SIR_UDE_SMOKE_TEST=1.
#   • El m sugerido se reporta por RMSE_I (única serie observada), no por
#     RMSE_SIR: S y R son construidos a partir de I y no son mediciones
#     independientes.
#
# NO modifica src/lib/14 ni ninguna función ya validada.
# ============================================================


"""
    run_window_sensitivity_real_split(SIR; N, γ, Δt=1.0, hidden, layers,
                                      lr, epochs, seed_red=1234,
                                      clip_norm=nothing, frac_train=0.8,
                                      pcts=Float64[], m_abs=[1,2,5,10,20,32,54,107,171],
                                      outdir="results/datos_reales")

Barrido de tamaño de ventana sobre la serie real con partición
cronológica entrenamiento/prueba. Ver el encabezado del módulo.

Devuelve el `DataFrame` (ordenado por `m`) y escribe
`real_data_sensitivity_m_split.csv` en `outdir`.
"""
function run_window_sensitivity_real_split(SIR::Matrix{Float64};
                                            N::Float64, γ::Float64, Δt::Float64=1.0,
                                            hidden::Int, layers::Int,
                                            lr::Float64, epochs::Int,
                                            seed_red::Int=1234,
                                            clip_norm::Union{Nothing,Float64}=nothing,
                                            frac_train::Float64=0.8,
                                            pcts::Vector{Float64}=Float64[],
                                            m_abs::Vector{Int}=[1, 2, 5, 10, 20, 32, 54, 107, 171],
                                            outdir::String="results/datos_reales")
    mkpath(outdir)
    cfg = make_real_data_config(SIR; N=N, γ=γ, Δt=Δt)
    idx_entren, idx_test = split_train_test(cfg.T; frac_train=frac_train)
    T_train = length(idx_entren)

    # Columnas de SIR (3×(T+1)): la columna k+1 es el día k.
    k_split = last(idx_entren)
    cols_tr = 1:(k_split + 1)
    cols_te = (k_split + 2):(cfg.T + 1)

    grid_bruto  = m_values_from_pcts(T_train; pcts=pcts, m_abs=m_abs)
    grid        = [f for f in grid_bruto if f.m <= T_train]
    descartados = [f.m for f in grid_bruto if f.m > T_train]
    if !isempty(descartados)
        @warn "Se descartan m mayores que el tramo de entrenamiento ($T_train días): $descartados"
    end
    @assert !isempty(grid) "El grid quedó vacío tras filtrar m <= $T_train"

    epochs_real = epocas_final(epochs)
    if epochs_real != epochs
        @warn "SIR_UDE_SMOKE_TEST activo: se usan $epochs_real épocas en vez de $epochs. " *
              "Los números resultantes NO son válidos para el artículo."
    end

    println("\n" * "="^70)
    println("  Sensibilidad a m — datos reales — CON split entrenamiento/prueba")
    println("  T=$(cfg.T)  N=$(round(N, digits=0))  γ=$γ  seed=$seed_red  epochs=$epochs_real")
    println("  Entrenamiento: $(T_train) pasos (días 0–$(k_split))")
    println("  Prueba:        $(length(idx_test)) pasos (días $(k_split+1)–$(cfg.T-1))")
    println("  m a evaluar:   $(getindex.(grid, :m))")
    println("  ⚠ Elegir m por RMSE_I_train (única serie observada) + TV_beta.")
    println("    Las columnas _test son diagnóstico, NO criterio de selección.")
    println("="^70)

    rmse(a, b) = sqrt(mean((a .- b) .^ 2))
    mae(a,  b) = mean(abs.(a .- b))

    filas = NamedTuple[]
    prog  = iniciar_progreso("Sensibilidad a m (split) — datos reales", length(grid))

    for fila_m in grid
        m = fila_m.m
        println("\n  → m = $m")

        nn_beta, p0, st_nn = build_network(hidden, layers; seed=seed_red, bias_inicial=Float32(BETA0_REF_FIJO))
        p_w, losses_w = train_windowed_rd(cfg, SIR, nn_beta, st_nn, p0;
                                           m = m,
                                           epochs = epochs_real,
                                           lr = lr,
                                           clip_norm = clip_norm,
                                           idx_entren = idx_entren)   # ← la corrección
        pred_w = rollout_rd(cfg, p_w, st_nn, nn_beta)

        # β̂ evaluada sobre el estado OBSERVADO, igual que evaluar_datos_reales_v2
        beta_w = [beta_theta_rd(cfg, cfg.ts[k], SIR[2, k], p_w, st_nn, nn_beta)
                  for k in 1:cfg.T]
        beta_tr = beta_w[1:min(k_split, length(beta_w))]

        TV_beta       = mean(abs.(diff(beta_w)))       # variación total media
        TV_beta_train = length(beta_tr) > 1 ? mean(abs.(diff(beta_tr))) : NaN
        beta_min      = minimum(beta_w)
        beta_max      = maximum(beta_w)
        frac_beta_neg = count(<(0.0), beta_w) / length(beta_w)

        n_ventanas = count(idx0 -> all((idx0):(idx0 + m - 1) .∈ Ref(idx_entren)),
                            1:(length(cfg.ts) - m))

        RMSE_S_tr   = rmse(pred_w[1, cols_tr], SIR[1, cols_tr])
        RMSE_I_tr   = rmse(pred_w[2, cols_tr], SIR[2, cols_tr])
        RMSE_R_tr   = rmse(pred_w[3, cols_tr], SIR[3, cols_tr])
        RMSE_SIR_tr = rmse(vec(pred_w[:, cols_tr]), vec(SIR[:, cols_tr]))

        RMSE_S_te   = rmse(pred_w[1, cols_te], SIR[1, cols_te])
        RMSE_I_te   = rmse(pred_w[2, cols_te], SIR[2, cols_te])
        RMSE_R_te   = rmse(pred_w[3, cols_te], SIR[3, cols_te])
        RMSE_SIR_te = rmse(vec(pred_w[:, cols_te]), vec(SIR[:, cols_te]))

        @printf("     [train] RMSE_I=%.3f  RMSE_SIR=%.3f  |  [test] RMSE_I=%.1f\n",
                RMSE_I_tr, RMSE_SIR_tr, RMSE_I_te)
        @printf("     β̂: TV=%.6f  rango=[%.4f, %.4f]  frac<0=%.3f  |  n_vent=%d  loss=%.4e\n",
                TV_beta, beta_min, beta_max, frac_beta_neg, n_ventanas, losses_w[end])

        push!(filas, merge(fila_m, (
            n_ventanas     = n_ventanas,
            RMSE_S_train   = RMSE_S_tr,  RMSE_I_train   = RMSE_I_tr,
            RMSE_R_train   = RMSE_R_tr,  RMSE_SIR_train = RMSE_SIR_tr,
            RMSE_S_test    = RMSE_S_te,  RMSE_I_test    = RMSE_I_te,
            RMSE_R_test    = RMSE_R_te,  RMSE_SIR_test  = RMSE_SIR_te,
            MAE_SIR_train  = mae(vec(pred_w[:, cols_tr]), vec(SIR[:, cols_tr])),
            MAE_SIR_test   = mae(vec(pred_w[:, cols_te]), vec(SIR[:, cols_te])),
            TV_beta        = TV_beta,     TV_beta_train = TV_beta_train,
            beta_min       = beta_min,    beta_max      = beta_max,
            frac_beta_neg  = frac_beta_neg,
            loss_final     = losses_w[end],
            epochs         = epochs_real,
            seed           = seed_red,
            frac_train     = frac_train,
        )))
        avanzar!(prog; detalle="m=$m")
    end
    finalizar_progreso!(prog)

    df   = sort(DataFrame(filas), :m)
    path = joinpath(outdir, "real_data_sensitivity_m_split.csv")
    CSV.write(path, df)
    println("\n✓ CSV guardado en $path")
    println(df)

    # ── Lectura orientativa ─────────────────────────────────────────────
    m_I   = df.m[argmin(df.RMSE_I_train)]
    m_SIR = df.m[argmin(df.RMSE_SIR_train)]
    banda = df[df.RMSE_I_train .<= minimum(df.RMSE_I_train) * 1.05, :]
    println("\n  m que minimiza RMSE_I_train  : $m_I   (criterio válido: solo serie observada)")
    println("  m que minimiza RMSE_SIR_train: $m_SIR (S y R son construidos, no observados)")
    println("  Dentro del 5% del mejor RMSE_I_train: m ∈ $(collect(banda.m))")
    println("\n  ⚠ El error de trayectoria NO es proxy de identificabilidad de β")
    println("    (ver la disociación documentada en el artículo). Contrastar")
    println("    la banda anterior con TV_beta: un TV que se dispara al bajar m")
    println("    indica que β̂ está absorbiendo ruido en vez de mecanismo.")
    println("    TV_beta por m: ", [(df.m[i], round(df.TV_beta[i], sigdigits=3)) for i in 1:nrow(df)])
    if any(df.frac_beta_neg .> 0)
        neg = df.m[df.frac_beta_neg .> 0]
        @warn "β̂ negativa en m ∈ $(collect(neg)) -- flujo de contagio invertido. Revisar antes de usar esos valores."
    end

    p = plot(df.m, df.RMSE_I_train, lw=2, marker=:circle, color=:royalblue,
             label="RMSE_I (train)", xlabel="m (days)", ylabel="RMSE on I(t)",
             title="Real data — window-size sensitivity (train/test split, seed=$seed_red)",
             legend=:outertopright, size=(900, 480),
             left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    plot!(p, df.m, df.RMSE_I_test, lw=2, marker=:square, ls=:dash, color=:crimson,
          label="RMSE_I (test, diagnóstico)")
    savefig_all(p, joinpath(outdir, "real_data_sensitivity_m_split");
                formats=(:png, :pdf, :eps))

    p2 = plot(df.m, df.TV_beta, lw=2, marker=:diamond, color=:seagreen,
              label="TV(β̂)", xlabel="m (days)", ylabel="mean |Δβ̂|",
              title="Real data — roughness of the learned β̂ vs window length",
              legend=:outertopright, size=(900, 480),
              left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    savefig_all(p2, joinpath(outdir, "datos_reales_TVbeta_vs_m");
                formats=(:png, :pdf, :eps))

    return df
end

println("✓ run_window_sensitivity_real_split v2 definida (con TV(β̂), épocas y diagnóstico de β<0)")
