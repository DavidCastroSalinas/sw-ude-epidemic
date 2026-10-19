"""
    graficar_boxplot_metrica(df; caso_beta, metrica=:rmse_beta, m_ventanas=nothing, outdir)

Boxplot comparando :global vs :ventanas (opcionalmente un `m` específico)
para la métrica indicada (`:rmse_beta`, `:rmse_global`, `:rmse_S`, etc.).
"""
function graficar_boxplot_metrica(df::DataFrame; caso_beta::String,
                                   metrica::Symbol=:rmse_beta,
                                   m_ventanas=nothing,
                                   outdir::String="figures/experiments")
    mkpath(outdir)
    sub = filter(r -> r.caso_beta == caso_beta &&
                       (r.metodo == "global" ||
                        (r.metodo == "ventanas" && (m_ventanas === nothing || r.m == m_ventanas))),
                 df)
    # `sub.metodo` sigue almacenando "global"/"ventanas" (columna interna, sin
    # cambios); `metodo_para_mostrar` es solo el texto que se dibuja en el eje x.
    metodo_para_mostrar = metodo_display.(sub.metodo)
    p = boxplot(metodo_para_mostrar, sub[!, metrica], legend=false,
                xlabel="Method", ylabel=String(metrica),
                title="$caso_beta — $(metrica)" *
                      (m_ventanas === nothing ? "" : " (m=$m_ventanas)"),
                size=(650, 480), left_margin=8mm, bottom_margin=8mm)
    savefig_all(p, "$outdir/$(caso_beta)_boxplot_$(metrica)"; formats=(:png, :pdf, :eps))
    return p
end

"""
    graficar_beta_promedio(caso_beta, metodo, m, seeds_red; sigma_ruido=0.0,
                           seed_ruido=1234, outdir)

Entrena `metodo` (:global o :ventanas) con cada semilla en `seeds_red` sobre
la MISMA trayectoria de datos, y grafica β_real(t,I) contra la media ± σ de
β̂_θ(t,I) a través de las semillas (ítems 3 y 4 de la lista de gráficos).
"""
function graficar_beta_promedio(caso_beta::Symbol, metodo::Symbol, m, seeds_red;
                                 sigma_ruido::Float64=0.0, seed_ruido::Int=1234,
                                 outdir::String="figures/experiments")
    mkpath(outdir)
    datos_pack = generar_datos(caso_beta; sigma_ruido=sigma_ruido, seed_ruido=seed_ruido)
    cfg = SCENARIO_CONFIG[caso_beta]
    h = (hidden=cfg.hidden, layers=cfg.layers, lr=cfg.lr, epochs=cfg.epochs,
         clip_norm=cfg.clip_norm)

    beta_matrix = nothing
    ts_beta = nothing
    β_true = nothing
    for (i, seed_red) in enumerate(seeds_red)
        resultado = metodo == :global ?
            entrenar_global(datos_pack; seed_red=seed_red, hiperparametros=h) :
            entrenar_ventanas(datos_pack; m=m, seed_red=seed_red, hiperparametros=h)
        ev = evaluar_completo(resultado, datos_pack)
        if beta_matrix === nothing
            ts_beta = ev.ts_beta
            β_true  = ev.β_true
            beta_matrix = zeros(length(collect(seeds_red)), length(ts_beta))
        end
        beta_matrix[i, :] .= ev.β_hat
    end

    media = vec(mean(beta_matrix, dims=1))
    desv  = vec(std(beta_matrix,  dims=1))

    p = plot(ts_beta, β_true, label="β (observed data)", lw=2, color=:black,
             xlabel="t", ylabel="β(t,I)",
             title="$(SCENARIO_LABELS[caso_beta]) — $(metodo_display(metodo; m=(metodo == :ventanas ? m : nothing)))",
             legend=:outertopright, size=(900, 480),
             left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    plot!(p, ts_beta, media, ribbon=desv, color=:steelblue, fillalpha=0.25,
          label="β̂ mean ± σ ($(length(collect(seeds_red))) seeds)")
    savefig_all(p, "$outdir/$(caso_beta)_$(metodo)_beta_promedio"; formats=(:png, :pdf, :eps))
    return p
end

"""
    graficar_sensibilidad_m(df; caso_beta="lineal", outdir)

Curva de RMSE_β (media ± σ) en función de m, a partir de `resumen_por_m`
(ítem 5 de la lista de gráficos).
"""
function graficar_sensibilidad_m(df::DataFrame; caso_beta::String="lineal",
                                  outdir::String="figures/experiments")
    mkpath(outdir)
    resumen = sort(resumen_por_m(df; caso_beta=caso_beta), :m)
    p = plot(resumen.m, resumen.rmse_beta_media, ribbon=resumen.rmse_beta_std,
             marker=:circle, xlabel="m (window length)", ylabel="RMSE_β",
             label="RMSE_β mean ± σ", title="Sensitivity to window length m — $caso_beta",
             legend=:outertopright, size=(850, 480),
             left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    savefig_all(p, "$outdir/$(caso_beta)_sensibilidad_m"; formats=(:png, :pdf, :eps))
    return p
end

"""
    graficar_trajectories(caso_beta, metodo, m, seed_red; sigma_ruido=0.0,
                          seed_ruido=1234, outdir)

Trayectorias S, I, R reales vs. reconstruidas para una repetición puntual
(ítem 6 de la lista de gráficos).
"""
function graficar_trajectories(caso_beta::Symbol, metodo::Symbol, m, seed_red::Int;
                                sigma_ruido::Float64=0.0, seed_ruido::Int=1234,
                                outdir::String="figures/experiments")
    mkpath(outdir)
    datos_pack = generar_datos(caso_beta; sigma_ruido=sigma_ruido, seed_ruido=seed_ruido)
    cfg = SCENARIO_CONFIG[caso_beta]
    h = (hidden=cfg.hidden, layers=cfg.layers, lr=cfg.lr, epochs=cfg.epochs,
         clip_norm=cfg.clip_norm)
    resultado = metodo == :global ?
        entrenar_global(datos_pack; seed_red=seed_red, hiperparametros=h) :
        entrenar_ventanas(datos_pack; m=m, seed_red=seed_red, hiperparametros=h)
    ev = evaluar_completo(resultado, datos_pack)

    p = plot(ts, datos_pack.datos_limpio[1, :], label="S (observed data)", color=:blue, lw=2,
             legend=:outertopright, size=(950, 480),
             left_margin=6mm, right_margin=2mm, top_margin=6mm, bottom_margin=8mm)
    plot!(p, ts, ev.pred[1, :], label="Ŝ", color=:blue, ls=:dash)
    plot!(p, ts, datos_pack.datos_limpio[2, :], label="I (observed data)", color=:red, lw=2)
    plot!(p, ts, ev.pred[2, :], label="Î", color=:red, ls=:dash)
    plot!(p, ts, datos_pack.datos_limpio[3, :], label="R (observed data)", color=:green, lw=2)
    plot!(p, ts, ev.pred[3, :], label="R̂", color=:green, ls=:dash,
          xlabel="t", ylabel="Individuals",
          title="$(SCENARIO_LABELS[caso_beta]) — $(metodo_display(metodo; m=(metodo == :ventanas ? m : nothing))) (seed=$seed_red)")
    savefig_all(p, "$outdir/$(caso_beta)_$(metodo)_trajectories_seed$(seed_red)"; formats=(:png, :pdf, :eps))
    return p
end

println("✓ graficar_boxplot_metrica, graficar_beta_promedio, graficar_sensibilidad_m, graficar_trajectories definidas")

# [2026-10-18] `evaluar_datos_reales` estaba aquí. Ningún runner del
# artículo la llamaba: quedó superada y se eliminó. Ver CHANGELOG.md.

