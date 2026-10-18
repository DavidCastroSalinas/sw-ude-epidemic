function plot_results(scenario_key, datos, ts_beta, β_true,
                      pred_g, β_g, β_dir_g,
                      pred_w, β_w, β_dir_w,
                      m_val; outdir="figuras")
    mkpath(outdir)
    label = SCENARIO_LABELS[scenario_key]

    # Reconstrucción de estados (9 series → legenda externa para no tapar curvas)
    p1 = plot(ts, datos[1,:], lw=3, color=:black, label="S (observed data)",
              xlabel="Days", ylabel="Individuals",
              title="State reconstruction — $label",
              legend=:outertopright, size=(950, 480),
              left_margin=6mm, right_margin=2mm, top_margin=6mm, bottom_margin=8mm)
    plot!(p1, ts, pred_g[1,:], lw=2, ls=:dash, color=:royalblue, label="S UDE")
    plot!(p1, ts, pred_w[1,:], lw=2, ls=:dot,  color=:crimson,   label="S SW-UDE (m=$m_val)")
    plot!(p1, ts, datos[2,:], lw=3, color=:black,  label="I (observed data)")
    plot!(p1, ts, pred_g[2,:], lw=2, ls=:dash, color=:royalblue, label="I UDE")
    plot!(p1, ts, pred_w[2,:], lw=2, ls=:dot,  color=:crimson,   label="I SW-UDE")
    plot!(p1, ts, datos[3,:], lw=3, color=:black,  label="R (observed data)")
    plot!(p1, ts, pred_g[3,:], lw=2, ls=:dash, color=:royalblue, label="R UDE")
    plot!(p1, ts, pred_w[3,:], lw=2, ls=:dot,  color=:crimson,   label="R SW-UDE")
    savefig_all(p1, "$outdir/$(scenario_key)_estados"; formats=(:png, :pdf, :eps))
    # Recuperación de β (hasta 4 series → misma convención de legenda externa)
    valid_dir = .!isnan.(β_dir_g)
    p2 = plot(ts_beta, β_true, lw=3, color=:black, label="β (observed data)",
              xlabel="Days", ylabel="β(t,I)",
              title="Transmission-rate recovery — $label",
              legend=:outertopright, size=(950, 480),
              left_margin=6mm, right_margin=2mm, top_margin=6mm, bottom_margin=8mm)
    plot!(p2, ts_beta, β_g, lw=2, ls=:dash, color=:royalblue, label="β UDE")
    plot!(p2, ts_beta, β_w, lw=2, ls=:dot,  color=:crimson,   label="β SW-UDE (m=$m_val)")
    if any(valid_dir)
        scatter!(p2, ts_beta[valid_dir], β_dir_g[valid_dir],
                 ms=2, color=:gray, alpha=0.5, label="β (direct estimate)")
    end
    savefig_all(p2, "$outdir/$(scenario_key)_beta"; formats=(:png, :pdf, :eps))

    println("  Figuras guardadas en $outdir/$(scenario_key)_*.{png,eps,pdf}")
    return p1, p2
end

function make_gif_beta(scenario_key, ts_beta, β_true, iter_snaps, params_snaps,
                       st_nn, nn_beta, datos; outdir="figuras", fps=8, suffix="")
    mkpath(outdir)
    label = SCENARIO_LABELS[scenario_key]

    beta_snaps = [
        [beta_theta(ts[k], datos[2,k], p, st_nn, nn_beta) for k in 1:T]
        for p in params_snaps
    ]

    all_vals = vcat(beta_snaps..., β_true)
    β_min_p  = minimum(all_vals) - 0.02
    β_max_p  = maximum(all_vals) + 0.02

    anim = @animate for j in eachindex(beta_snaps)
        plot(ts_beta, β_true, lw=3, color=:black, label="β (observed data)",
             xlabel="Days", ylabel="β(t,I)",
             title="βθ progression — $label\nIteration $(iter_snaps[j])",
             ylims=(β_min_p, β_max_p), legend=:bottomleft,
             size=(750, 480), top_margin=8mm)
        plot!(ts_beta, beta_snaps[j], lw=3, ls=:dash, color=:crimson, label="learned β")
    end

    gif_path = "$outdir/$(scenario_key)$(suffix)_gif_beta.gif"
    gif(anim, gif_path; fps=fps)
    println("  GIF guardado en $gif_path")
    return gif_path
end

function plot_sensitivity(scenario_key, m_values, metrics_vec; outdir="figuras")
    mkpath(outdir)
    label  = SCENARIO_LABELS[scenario_key]
    rmse_β = [m.RMSE_β for m in metrics_vec]
    rmse_I = [m.RMSE_I for m in metrics_vec]

    # NOTA: MAE_β se sigue calculando y guardando en el CSV de la corrida
    # (compute_metrics no cambia), pero deliberadamente NO se grafica --
    # se reporta una sola métrica de error de β (RMSE) en las figuras,
    # para no duplicar información redundante en el panel. MAE sigue
    # disponible para quien necesite auditarlo desde el CSV.
    p1 = plot(m_values, rmse_β, lw=2, marker=:circle, color=:crimson, label="RMSE_β",
              xlabel="m", ylabel="Error in β", title="Parameter estimation error",
              legend=:outertopright)
    p2 = plot(m_values, rmse_I, lw=2, marker=:circle, color=:royalblue, label="RMSE_I",
              xlabel="m", ylabel="RMSE_I", title="State prediction error",
              legend=:outertopright)
    p_full = plot(p1, p2, layout=(1,2), size=(1200, 450),
                  plot_title="Sensitivity to window length m — $label",
                  left_margin=6mm, right_margin=4mm, top_margin=8mm, bottom_margin=8mm)
    savefig_all(p_full, "$outdir/$(scenario_key)_sensibilidad_m"; formats=(:png, :pdf, :eps))
    println("  Figura de sensibilidad guardada")
    return p_full
end

println("✓ Funciones de graficación definidas")
