function run_experiment(scenario_key::Symbol;
                        m::Int           = 6,
                        epochs::Int      = 2000,
                        lr::Float64      = 0.01,
                        hidden::Int      = 0,
                        layers::Int      = 1,
                        seed::Int        = 1234,
                        outdir::String   = "figures",
                        save_csv::Bool   = true,
                        make_gif::Bool   = true,
                        guardar_cada::Int = 25,
                        clip_norm::Union{Nothing,Float64} = nothing)

    @assert haskey(BETA_FUNCTIONS, scenario_key) "Escenario desconocido: $scenario_key\nOpciones: $(collect(keys(BETA_FUNCTIONS)))"

    beta_fn = BETA_FUNCTIONS[scenario_key]
    label   = SCENARIO_LABELS[scenario_key]
    file_key = scenario_file_key(scenario_key)

    println("\n" * "="^65)
    println("  Escenario : $label")
    println("  m=$m  |  epochs=$epochs  |  lr=$lr  |  hidden=$hidden  |  seed=$seed  |  clip_norm=$clip_norm")
    println("="^65)

    datos = generate_sir_trajectory(beta_fn)
    println("✓ Trayectoria sintética generada (T=$T, N=$N)")

    nn_beta, p0, st_nn = build_network(hidden, layers; seed=seed)
    println("✓ Red neuronal: ", nn_beta)

    println("\n[1/2] Entrenamiento UDE...")
    p_g, loss_g, iter_g, snaps_g = train_global(datos, nn_beta, st_nn, p0;
                                                  epochs=epochs, lr=lr,
                                                  guardar_cada=guardar_cada)

    println("\n[2/2] Entrenamiento SW-UDE (m=$m)...")
    p_w, loss_w, iter_w, snaps_w = train_windowed(datos, nn_beta, st_nn, p0;
                                                   m=m, epochs=epochs, lr=lr,
                                                   guardar_cada=guardar_cada,
                                                   clip_norm=clip_norm)

    pred_g = rollout(p_g, st_nn, nn_beta)
    pred_w = rollout(p_w, st_nn, nn_beta)
    ts_β, β_true, β_g, β_dir_g = eval_beta_on_ref(p_g, st_nn, nn_beta, datos, beta_fn)
    _,    _,      β_w, β_dir_w  = eval_beta_on_ref(p_w, st_nn, nn_beta, datos, beta_fn)
    mG = compute_metrics(pred_g, datos, β_g, β_true)
    mW = compute_metrics(pred_w, datos, β_w, β_true)

    println("\n── Métricas UDE ──────────────────────────")
    println(@sprintf("  RMSE_S=%.4f  RMSE_I=%.4f  RMSE_R=%.4f", mG.RMSE_S, mG.RMSE_I, mG.RMSE_R))
    println(@sprintf("  MAE_S =%.4f  MAE_I =%.4f  MAE_R =%.4f", mG.MAE_S,  mG.MAE_I,  mG.MAE_R))
    println(@sprintf("  RMSE_β=%.6f  MAE_β=%.6f",               mG.RMSE_β, mG.MAE_β))
    println("\n── Métricas SW-UDE (m=$m) ─────────────────")
    println(@sprintf("  RMSE_S=%.4f  RMSE_I=%.4f  RMSE_R=%.4f", mW.RMSE_S, mW.RMSE_I, mW.RMSE_R))
    println(@sprintf("  MAE_S =%.4f  MAE_I =%.4f  MAE_R =%.4f", mW.MAE_S,  mW.MAE_I,  mW.MAE_R))
    println(@sprintf("  RMSE_β=%.6f  MAE_β=%.6f",               mW.RMSE_β, mW.MAE_β))

    if hidden == 0
        w_t = p_w.layer_1.weight[1, 1]
        w_I = p_w.layer_1.weight[1, 2]
        b   = p_w.layer_1.bias[1]
        println("\n  Ecuación aprendida (SW-UDE):")
        println(@sprintf("  βθ(t,I) = %.5f*(t/T) + %.5f*(I/N) + %.5f", w_t, w_I, b))
    end

    p_est, p_bet = plot_results(scenario_key, datos, ts_β, β_true,
                                pred_g, β_g, β_dir_g, pred_w, β_w, β_dir_w,
                                m; outdir=outdir)
    p_loss = plot(loss_g, lw=2, color=:royalblue, label="UDE",
                  xlabel="Iteration", ylabel="Loss", yscale=:log10,
                  title="Convergence — $label",
                  legend=:topright, size=(800, 480),
                  left_margin=8mm, bottom_margin=8mm)
    plot!(p_loss, loss_w, lw=2, color=:crimson, ls=:dash, label="SW-UDE (m=$m)")
    savefig_all(p_loss, "$outdir/$(file_key)_$(m)_loss"; formats=(:png, :pdf, :eps))
    if make_gif
        make_gif_beta(scenario_key, ts_β, β_true, iter_g, snaps_g,
                      st_nn, nn_beta, datos; outdir=outdir, suffix="_UDE")
        make_gif_beta(scenario_key, ts_β, β_true, iter_w, snaps_w,
                      st_nn, nn_beta, datos; outdir=outdir, suffix="_windowed_UDE")
    end

    if save_csv
        mkpath(outdir)
        df = DataFrame(
            escenario = [label,        label],
            modelo    = ["UDE",        "SW-UDE (m=$(m))"],
            m         = [NaN,          Float64(m)],
            RMSE_S    = [mG.RMSE_S,    mW.RMSE_S],
            RMSE_I    = [mG.RMSE_I,    mW.RMSE_I],
            RMSE_R    = [mG.RMSE_R,    mW.RMSE_R],
            MAE_S     = [mG.MAE_S,     mW.MAE_S],
            MAE_I     = [mG.MAE_I,     mW.MAE_I],
            MAE_R     = [mG.MAE_R,     mW.MAE_R],
            RMSE_beta = [mG.RMSE_β,    mW.RMSE_β],
            MAE_beta  = [mG.MAE_β,     mW.MAE_β],
        )
        CSV.write("$outdir/$(file_key)_$(m)_metrics.csv", df)
        println("  CSV guardado en $outdir/$(file_key)_$(m)_metrics.csv")

        # ── Curvas completas (para regenerar figuras fuera de Julia,
        # p. ej. en el notebook de ajustes de figuras) ────────────────
        # NOTA: antes de esta versión, el proyecto solo guardaba métricas
        # ESCALARES (RMSE/MAE) -- las curvas S/I/R(t) y β(t) solo existían
        # dentro de los objetos Plots.jl usados para dibujar el PNG/PDF/EPS,
        # sin CSV equivalente. Sin esto, un notebook externo no puede
        # reconstruir la figura de estados ni la de β, solo los gráficos de
        # barras/boxplot que sí dependían de CSV ya existentes.
        df_curvas_estados = DataFrame(
            t                = ts,
            S_observado      = datos[1, :], I_observado = datos[2, :], R_observado = datos[3, :],
            S_UDE            = pred_g[1, :], I_UDE       = pred_g[2, :], R_UDE       = pred_g[3, :],
            S_Windowed       = pred_w[1, :], I_Windowed  = pred_w[2, :], R_Windowed  = pred_w[3, :],
        )
        CSV.write("$outdir/$(file_key)_$(m)_curves_states.csv", df_curvas_estados)

        df_curvas_beta = DataFrame(
            t                    = ts_β,
            beta_real            = β_true,
            beta_UDE             = β_g,
            beta_Windowed        = β_w,
            beta_directa_UDE     = β_dir_g,
            beta_directa_Windowed = β_dir_w,
        )
        CSV.write("$outdir/$(file_key)_$(m)_curves_beta.csv", df_curvas_beta)

        df_curvas_loss = DataFrame(
            iteracion     = 1:max(length(loss_g), length(loss_w)),
            loss_UDE      = vcat(loss_g, fill(missing, max(0, length(loss_w) - length(loss_g)))),
            loss_Windowed = vcat(loss_w, fill(missing, max(0, length(loss_g) - length(loss_w)))),
        )
        CSV.write("$outdir/$(file_key)_$(m)_curves_loss.csv", df_curvas_loss)

        println("  Curvas guardadas en $outdir/$(file_key)_$(m)_curves_{states,beta,loss}.csv")
    end

    return (
        metrics_global     = mG,
        metrics_windowed   = mW,
        p_global           = p_g,
        p_windowed         = p_w,
        datos              = datos,
        ts_beta            = ts_β,
        β_true             = β_true,
        β_global           = β_g,
        β_windowed         = β_w,
        β_directa_global   = β_dir_g,
        β_directa_windowed = β_dir_w,
        loss_global        = loss_g,
        loss_windowed      = loss_w,
        fig_estados        = p_est,
        fig_beta           = p_bet,
        fig_loss           = p_loss,
        m_used             = m,
        hidden_used        = hidden,
        layers_used        = layers,
    )
end

println("✓ run_experiment definida")

function run_sensitivity(scenario_key::Symbol;
                         m_values::Vector{Int} = [1, 3, 5, 10, 20, 50],
                         epochs::Int           = 2000,
                         lr::Float64           = 0.01,
                         hidden::Int           = 0,
                         layers::Int           = 1,
                         seed::Int             = 1234,
                         outdir::String        = "figures",
                         save_csv::Bool        = true,
                         clip_norm::Union{Nothing,Float64} = nothing)

    @assert haskey(BETA_FUNCTIONS, scenario_key) "Escenario desconocido: $scenario_key"

    beta_fn = BETA_FUNCTIONS[scenario_key]
    label   = SCENARIO_LABELS[scenario_key]

    println("\n" * "="^65)
    println("  Sensibilidad m — Escenario: $label")
    println("="^65)

    datos   = generate_sir_trajectory(beta_fn)
    nn_beta, p0, st_nn = build_network(hidden, layers; seed=seed)

    metrics_vec = []
    rows        = []

    for m in m_values
        println("\n  → m = $m")
        p_w, _, _, _ = train_windowed(datos, nn_beta, st_nn, p0;
                                      m=m, epochs=epochs, lr=lr,
                                      guardar_cada=epochs+1,
                                      clip_norm=clip_norm)
        pred_w = rollout(p_w, st_nn, nn_beta)
        _, β_true, β_w, _ = eval_beta_on_ref(p_w, st_nn, nn_beta, datos, beta_fn)
        mW = compute_metrics(pred_w, datos, β_w, β_true)
        push!(metrics_vec, mW)
        @printf("     RMSE_β=%.6f  MAE_β=%.6f  RMSE_I=%.4f\n",
                mW.RMSE_β, mW.MAE_β, mW.RMSE_I)
        push!(rows, (
            escenario = label, m = m,
            RMSE_S = mW.RMSE_S, RMSE_I = mW.RMSE_I, RMSE_R = mW.RMSE_R,
            MAE_S  = mW.MAE_S,  MAE_I  = mW.MAE_I,  MAE_R  = mW.MAE_R,
            RMSE_beta = mW.RMSE_β, MAE_beta = mW.MAE_β,
        ))
    end

    fig_sens = plot_sensitivity(scenario_key, m_values, metrics_vec; outdir=outdir)

    if save_csv
        mkpath(outdir)
        df = DataFrame(rows)
        CSV.write("$outdir/$(file_key)_sensitivity_m.csv", df)
        println("  CSV guardado en $outdir/$(file_key)_sensitivity_m.csv")
    end

    return (metrics_vec=metrics_vec, fig_sensitivity=fig_sens)
end

println("✓ run_sensitivity definida")
