# ============================================================
# src/lib/11_real_data.jl — Pipeline para datos reales (serie univariada)
# ============================================================

# ── 1. Carga y construcción de la serie SIR real ─────────────────────────

"""
    cargar_serie_real(path; columna_valor=:Valor, columna_orden=Symbol("Día histórico"))

Carga el CSV de una serie univariada (una fila por día) y devuelve un
`Vector{Float64}` ordenado cronológicamente según `columna_orden`.

Pensado para `historical_data_july_january.csv` (columnas: "Día histórico",
"Mes", "Día", "Valor"), pero sirve para cualquier CSV con una columna de
orden entero y una columna numérica de valores.
"""
function cargar_serie_real(path::String;
                            columna_valor::Symbol=:Valor,
                            columna_orden::Symbol=Symbol("Día histórico"))
    df = CSV.read(path, DataFrame)
    @assert columna_valor in propertynames(df) "No existe la columna $columna_valor en $path"
    @assert columna_orden in propertynames(df) "No existe la columna $columna_orden en $path"
    df_ordenado = sort(df, columna_orden)

    msg_orden = "La columna de orden ($columna_orden) tiene saltos o duplicados -- revisar el CSV " *
                "(días faltantes deben interpolarse explícitamente antes de continuar, no ignorarse)."
    @assert all(diff(df_ordenado[!, columna_orden]) .== 1) msg_orden

    serie = Float64.(df_ordenado[!, columna_valor])
    @assert all(isfinite, serie) "La serie contiene NaN/Inf -- imputar o eliminar antes de continuar"
    @assert all(serie .>= 0) "La serie contiene valores negativos -- revisar la columna $columna_valor"

    println("✓ Serie cargada: $(length(serie)) días, de $(df_ordenado[1, columna_orden]) ",
            "a $(df_ordenado[end, columna_orden])  (min=$(minimum(serie)), max=$(maximum(serie)))")
    return serie
end

"""
    construir_SIR_desde_I(I_obs; N, γ, Δt=1.0, R0=0.0)

Reconstruye S(t) y R(t) a partir de una serie observada de I(t) (único
compartimento realmente medido en vigilancia epidemiológica), usando la
MISMA recursión discreta que el modelo SIR-UDE:

    R_{k+1} = R_k + γ·I_k·Δt
    S_{k+1} = N - I_{k+1} - R_{k+1}

Esto es una construcción "gray-box": S y R quedan determinados por I, γ, N
y R₀, NO son mediciones independientes. Sus RMSE/MAE deben reportarse
como diagnóstico de consistencia interna del modelo, nunca como si fueran
tan confiables como el ajuste a I(t) (la única serie observada).

Supuestos epidemiológicos que ESTE CÓDIGO NO PUEDE VALIDAR por sí solo y
que deben fijarse con criterio de dominio antes de interpretar resultados:
  • `N`  : población efectiva en riesgo (tamaño de la población de
           vigilancia/catchment), NO necesariamente la población total del
           país o región -- casi nunca se conoce con exactitud a partir de
           un conteo de casos. Ver `construir_serie_referencia_fija`
           inferior razonable, a validar/reemplazar con la fuente de datos.
  • `γ`  : tasa de recuperación = 1/(duración infecciosa media). Para
           influenza suele usarse un período infeccioso de 3–7 días
           (γ ≈ 0.14–0.33 día⁻¹); para otras enfermedades respiratorias
           ajustar según literatura. El valor por defecto aquí (γ=0.20,
           período de 5 días) es un punto de partida, NO una calibración.
  • `R0` : recuperados acumulados al inicio de la serie. Si la serie no
           arranca al comienzo real del brote/temporada (aquí: julio, que
           puede no ser el inicio real de la temporada respiratoria), R₀=0
           subestima los recuperados acumulados y por lo tanto S₀ queda
           sobreestimado. Es una limitación a declarar explícitamente en
           el artículo, no un detalle técnico menor.

Lanza un error si `S(t) < 0` en algún punto (señal de que `N` es demasiado
pequeño para la trayectoria de I observada dado ese γ).

Devuelve una matriz 3×length(I_obs) = [S; I; R].
"""
function construir_SIR_desde_I(I_obs::Vector{Float64};
                                N::Float64, γ::Float64,
                                Δt::Float64=1.0, R0::Float64=0.0)
    Tn = length(I_obs)
    S  = zeros(Tn)
    R  = zeros(Tn)
    R[1] = R0
    S[1] = N - I_obs[1] - R[1]

    for k in 1:(Tn - 1)
        R[k+1] = R[k] + γ * I_obs[k] * Δt
        S[k+1] = N - I_obs[k+1] - R[k+1]
    end

    n_negativos = count(<(0), S)
    if n_negativos > 0
        error("S(t) < 0 en $n_negativos de $Tn días -- N=$N es demasiado pequeño para " *
              "esta trayectoria de I con γ=$γ. Aumentar N o revisar γ/R0.")
    end

    return permutedims(hcat(S, I_obs, R))   # 3×Tn
end

# Condiciones de referencia de Córdova-Lepe et al. (2026), ancladas
# al 10 de julio de 2020. La serie digitalizada se reescala desde esa fecha
# para coincidir con la prevalencia reportada; el resultado contiene 206 días.
const N_REF_FIJO     = 19_660_000.0
const S0_REF_FIJO    = 19_348_776.0
const I0_REF_FIJO    = 26_390.0
const R0_REF_FIJO    = 284_834.0
const GAMMA_REF_FIJO = 1 / 7
const BETA0_REF_FIJO = 0.20   # sesgo inicial de la capa de salida de build_network
                               # (reemplaza el 0.25 general -- ver src/lib/01_model_training.jl,
                               # kwarg `bias_inicial`; pasar Float32(BETA0_REF_FIJO) explícitamente
                               # desde los runners de datos reales, NO se cambió el default global)
const DIA_ANCLA_REF   = 10    # "Día histórico" = 10  →  10 de julio de 2020
const FECHA_ANCLA_REF = "10 de julio de 2020"
const FECHA_FIN_SERIE = "31 de enero de 2021"

"""
    construir_serie_referencia_fija(I_obs_raw; N=N_REF_FIJO, S0=S0_REF_FIJO,
                                     I0=I0_REF_FIJO, R0=R0_REF_FIJO,
                                     γ=GAMMA_REF_FIJO, dia_ancla_idx=DIA_ANCLA_REF,
                                     Δt=1.0)

Reescala la serie observada desde la fecha de referencia y reconstruye S y
R con las condiciones iniciales fijas. Excluye los días anteriores al ancla.
Devuelve la matriz SIR, el factor de reescala y el número de días excluidos.
"""
function construir_serie_referencia_fija(I_obs_raw::Vector{Float64};
                                          N::Float64=N_REF_FIJO, S0::Float64=S0_REF_FIJO,
                                          I0::Float64=I0_REF_FIJO, R0::Float64=R0_REF_FIJO,
                                          γ::Float64=GAMMA_REF_FIJO,
                                          dia_ancla_idx::Int=DIA_ANCLA_REF, Δt::Float64=1.0)
    @assert 1 <= dia_ancla_idx <= length(I_obs_raw) "dia_ancla_idx fuera de rango"
    factor = I0 / I_obs_raw[dia_ancla_idx]
    I_sub  = I_obs_raw[dia_ancla_idx:end] .* factor
    n_descartados = dia_ancla_idx - 1
    @assert isapprox(I_sub[1], I0; atol=1e-6) "Reescala inconsistente: I_sub[1] no coincide con I0"
    SIR = construir_SIR_desde_I(I_sub; N=N, γ=γ, Δt=Δt, R0=R0)
    @assert isapprox(SIR[1, 1], S0; atol=1.0) "S0 reconstruido no coincide con S0_REF_FIJO"
    return (SIR=SIR, factor_reescala=factor, n_dias_descartados=n_descartados)
end


# ── 2. Modelo SIR-UDE parametrizado (config explícito, sin constantes globales) ─

"""
    make_real_data_config(SIR::Matrix{Float64}; N, γ, Δt=1.0)

Empaqueta (N, γ, Δt, T, ts, u0) para una serie real, en el mismo formato
que usan las funciones `_rd` de este archivo. `T` y `u0` se derivan de
`SIR` (T = número de columnas - 1; u0 = primera columna).
"""
function make_real_data_config(SIR::Matrix{Float64}; N::Float64, γ::Float64, Δt::Float64=1.0)
    Tn = size(SIR, 2) - 1
    return (N=N, γ=γ, Δt=Δt, T=Tn, ts=collect(0.0:Δt:Float64(Tn)), u0=SIR[:, 1])
end

"""
    beta_theta_rd(cfg, t, I, p, st_nn, nn_beta)

Idéntica a `beta_theta` (Sección 6) pero usando `cfg.T` y `cfg.N` en vez de
las constantes globales `T`/`N`.
"""
function beta_theta_rd(cfg, t, I, p, st_nn, nn_beta)
    x = Float32[t / cfg.T, I / cfg.N]
    z, _ = nn_beta(x, p, st_nn)
    return z[1]
end

"""
    paso_sir_ude_rd(cfg, u, t_k, p, st_nn, nn_beta)

Idéntica a `paso_sir_ude`, parametrizada por `cfg` (N, γ, Δt).
"""
function paso_sir_ude_rd(cfg, u, t_k, p, st_nn, nn_beta)
    S, I, R = u[1], u[2], u[3]
    β = beta_theta_rd(cfg, t_k, I, p, st_nn, nn_beta)
    contagios   = β * S * I / cfg.N * cfg.Δt
    recuperados = cfg.γ * I * cfg.Δt
    return [S - contagios, I + contagios - recuperados, R + recuperados]
end

"""
    rollout_rd(cfg, p, st_nn, nn_beta)

Idéntica a `rollout`, propagando autónomamente desde `cfg.u0` sobre
`cfg.T` pasos con `cfg.ts`.
"""
function rollout_rd(cfg, p, st_nn, nn_beta)
    pred = zeros(3, cfg.T + 1)
    pred[:, 1] .= cfg.u0
    for k in 1:cfg.T
        pred[:, k+1] .= paso_sir_ude_rd(cfg, pred[:, k], cfg.ts[k], p, st_nn, nn_beta)
    end
    return pred
end

"""
    train_global_rd(cfg, datos, nn_beta, st_nn, p0; epochs=1500, lr=0.01, guardar_cada=25)

Idéntica a `train_global` (Sección 7), parametrizada por `cfg`. Si
`idx_entren` se especifica (rango de columnas de `datos`), la pérdida solo
se calcula sobre esos días -- para hacer un split entrenamiento/validación
real (ver `split_train_test`).
"""
function train_global_rd(cfg, datos, nn_beta, st_nn, p0;
                          epochs::Int=1500, lr::Float64=0.01, guardar_cada::Int=25,
                          idx_entren::UnitRange{Int}=1:cfg.T)
    losses = Float64[]

    function loss_fn(p, _)
        acc   = 0.0
        u_hat = datos[:, 1]
        # Se propaga siempre desde el día 1 (autónomo, igual que Global
        # sintético) pero la pérdida solo acumula sobre `idx_entren`, de
        # modo que los días de test NO influyen en el gradiente.
        for k in 1:cfg.T
            u_hat = paso_sir_ude_rd(cfg, u_hat, cfg.ts[k], p, st_nn, nn_beta)
            if k in idx_entren
                diff = (u_hat .- datos[:, k+1]) ./ cfg.N
                acc += sum(diff .^ 2)
            end
        end
        return acc / length(idx_entren)
    end

    callback = function(state, loss)
        push!(losses, loss)
        iter = length(losses)
        if iter % 100 == 0
            @printf("  [UDE-RD]  iter %4d  L=%.6e\n", iter, loss)
        end
        return false
    end

    optf    = Optimization.OptimizationFunction(loss_fn, Optimization.AutoZygote())
    optprob = Optimization.OptimizationProblem(optf, p0)
    res     = Optimization.solve(optprob, ADAM(lr); maxiters=epochs, callback=callback)

    @printf("  [UDE-RD] Final  L=%.6e\n", losses[end])
    return res.u, losses
end

"""
    train_windowed_rd(cfg, datos, nn_beta, st_nn, p0; m, epochs, lr, guardar_cada,
                       clip_norm=nothing, idx_entren=1:cfg.T)

Idéntica a `train_windowed` (Sección 8), parametrizada por `cfg`. Una
ventana `[idx0, idx0+m]` se incluye en la pérdida solo si TODOS sus pasos
caen dentro de `idx_entren` -- evita que una ventana "vea" datos de test.
"""
function train_windowed_rd(cfg, datos, nn_beta, st_nn, p0;
                            m::Int=6, epochs::Int=1500, lr::Float64=0.01,
                            guardar_cada::Int=25,
                            clip_norm::Union{Nothing,Float64}=nothing,
                            idx_entren::UnitRange{Int}=1:cfg.T)
    n_total_ventanas = length(cfg.ts) - m
    ventanas_validas  = [idx0 for idx0 in 1:n_total_ventanas
                         if all((idx0):(idx0 + m - 1) .∈ Ref(idx_entren))]
    @assert !isempty(ventanas_validas) "idx_entren es demasiado corto para admitir ventanas de largo m=$m"

    losses = Float64[]

    function loss_fn(p, _)
        acc = 0.0
        for idx0 in ventanas_validas
            u_hat = datos[:, idx0]
            for j in 0:(m-1)
                u_hat  = paso_sir_ude_rd(cfg, u_hat, cfg.ts[idx0 + j], p, st_nn, nn_beta)
                u_real = datos[:, idx0 + j + 1]
                diff   = (u_hat .- u_real) ./ cfg.N
                acc   += sum(diff .^ 2)
            end
        end
        return acc / (length(ventanas_validas) * m)
    end

    callback = function(state, loss)
        push!(losses, loss)
        iter = length(losses)
        if iter % 100 == 0
            @printf("  [SW-UDE-RD m=%d]  iter %4d  L=%.6e\n", m, iter, loss)
        end
        return false
    end

    optimiser = clip_norm === nothing ?
        ADAM(lr) :
        Optimisers.OptimiserChain(Optimisers.ClipNorm(clip_norm), ADAM(lr))

    optf    = Optimization.OptimizationFunction(loss_fn, Optimization.AutoZygote())
    optprob = Optimization.OptimizationProblem(optf, p0)
    res     = Optimization.solve(optprob, optimiser; maxiters=epochs, callback=callback)

    @printf("  [SW-UDE-RD m=%d] Final  L=%.6e\n", m, losses[end])
    return res.u, losses
end

println("✓ Pipeline de datos reales definido:")
println("    cargar_serie_real, construir_SIR_desde_I")
println("    construir_serie_referencia_fija (nueva, 2026-09-07 -- IC fijas Córdova-Lepe et al.)")
println("    make_real_data_config, beta_theta_rd, paso_sir_ude_rd, rollout_rd")
println("    train_global_rd, train_windowed_rd")


# ── 3. Orquestador: entrena, evalúa (dentro y fuera de muestra), grafica ──

"""
    evaluar_datos_reales_v2(SIR::Matrix{Float64}; N, γ, Δt=1.0,
                            hidden, layers, lr, epochs, m,
                            frac_train=0.8, seed_red=1234,
                            clip_norm=nothing, outdir="figures/real_data")

Reemplaza a `evaluar_datos_reales` (Sección 18.9 del notebook original)
con tres diferencias metodológicas importantes:

  1. Usa las funciones `_rd` parametrizadas (Sección arriba) en vez de las
     globales — funciona con el T y N reales de la serie, no T=50/N=1000.
  2. Separa entrenamiento/validación cronológicamente (`split_train_test`)
     y reporta métricas EN AMBOS tramos — sin esto, cualquier ajuste sobre
     datos reales solo demuestra memorización, no capacidad predictiva.
  3. Calcula la tabla de métricas extendidas (Sección 10) para :global y
     :ventanas sobre I(t) (única serie observada), incluyendo R_eff(t) y
     la variación total de β̂ como proxy cuantitativo de interpretabilidad.

No calcula RMSE_β/MAE_β (no existe β_real para datos reales) — eso sigue
siendo, por construcción del problema, imposible de automatizar.

Devuelve `(config=cfg, global_=(...), ventanas=(...), tabla=DataFrame)`.
"""
function evaluar_datos_reales_v2(SIR::Matrix{Float64};
                                  N::Float64, γ::Float64, Δt::Float64=1.0,
                                  hidden::Int, layers::Int, lr::Float64, epochs::Int, m::Int,
                                  frac_train::Float64=0.8, seed_red::Int=1234,
                                  clip_norm::Union{Nothing,Float64}=nothing,
                                  outdir::String="figures/real_data")
    mkpath(outdir)
    cfg = make_real_data_config(SIR; N=N, γ=γ, Δt=Δt)
    idx_entren, idx_test = split_train_test(cfg.T; frac_train=frac_train)
    println("✓ Split entrenamiento/validación: $(length(idx_entren)) días entrenamiento, ",
            "$(length(idx_test)) días validación (frac_train=$frac_train)")

    dias = cfg.ts

    # ── Global ──────────────────────────────────────────────────────────
    nn_g, p0_g, st_g = build_network(hidden, layers; seed=seed_red, bias_inicial=Float32(BETA0_REF_FIJO))
    p_g, losses_g = train_global_rd(cfg, SIR, nn_g, st_g, p0_g;
                                     epochs=epochs, lr=lr, idx_entren=idx_entren)
    pred_g = rollout_rd(cfg, p_g, st_g, nn_g)
    # Se evalúa β̂ sobre el I que CADA método propagó (pred_g[2,k]), no sobre
    # el I observado -- así el β̂ reportado es consistente con el que el
    # modelo usó durante su propio rollout (y con el que usó durante el
    # entrenamiento, donde paso_sir_ude_rd siempre parte del estado propio).
    beta_g = [beta_theta_rd(cfg, cfg.ts[k], pred_g[2, k], p_g, st_g, nn_g) for k in 1:cfg.T]

    # ── SW-UDE ──────────────────────────────────────────────────────────
    nn_w, p0_w, st_w = build_network(hidden, layers; seed=seed_red, bias_inicial=Float32(BETA0_REF_FIJO))
    p_w, losses_w = train_windowed_rd(cfg, SIR, nn_w, st_w, p0_w;
                                       m=m, epochs=epochs, lr=lr, clip_norm=clip_norm,
                                       idx_entren=idx_entren)
    pred_w = rollout_rd(cfg, p_w, st_w, nn_w)
    beta_w = [beta_theta_rd(cfg, cfg.ts[k], pred_w[2, k], p_w, st_w, nn_w) for k in 1:cfg.T]

    # ── Tabla de métricas extendidas (sobre I(t), la única serie observada) ─
    fila_g = tabla_metricas_extendidas(pred_g[2, :], SIR[2, :], dias;
                                        β̂=beta_g, S=pred_g[1, 1:cfg.T], N=N, γ=γ,
                                        idx_test=idx_test, etiqueta="UDE")
    fila_w = tabla_metricas_extendidas(pred_w[2, :], SIR[2, :], dias;
                                        β̂=beta_w, S=pred_w[1, 1:cfg.T], N=N, γ=γ,
                                        idx_test=idx_test, etiqueta="SW-UDE (m=$m)")
    tabla = DataFrame([fila_g, fila_w])
    CSV.write("$outdir/metrics_extended_real_data.csv", tabla)
    println("\n✓ Tabla de métricas extendidas:")
    println(tabla)
    println("  Guardada en $outdir/metrics_extended_real_data.csv")

    # Save daily trajectories and derived metrics for external plotting.
    reff_g = r_effective(beta_g, pred_g[1, 1:cfg.T], N, γ)
    reff_w = r_effective(beta_w, pred_w[1, 1:cfg.T], N, γ)

    # Mark a day as test when the transition producing it belongs to idx_test.
    # The initial state is always training data; day indices are shifted by
    # one relative to the transition indices.
    es_test_dias = [k in idx_test for k in 0:cfg.T]

    # β̂ y R_eff están indexados por transición (k=1..T, T valores) y por
    # tanto tienen una fila menos que las T+1 observaciones de I(t). Se
    # rellena con `missing` la fila del último día (t=T), que no es el
    # origen de ninguna transición -- antes de este fix, I_observado/I_UDE/
    # I_Windowed se truncaban también a T filas para calzar con β̂/R_eff,
    # perdiendo la última observación (t=T) tanto del CSV como de la figura.
    beta_UDE_col      = vcat(beta_g, missing)
    beta_Windowed_col = vcat(beta_w, missing)
    Reff_UDE_col      = vcat(reff_g, missing)
    Reff_Windowed_col = vcat(reff_w, missing)

    df_curvas = DataFrame(
        dia            = dias[1:(cfg.T + 1)],
        es_test        = es_test_dias,
        I_observado    = SIR[2, 1:(cfg.T + 1)],
        I_UDE          = pred_g[2, 1:(cfg.T + 1)],
        I_Windowed     = pred_w[2, 1:(cfg.T + 1)],
        beta_UDE       = beta_UDE_col,
        beta_Windowed  = beta_Windowed_col,
        Reff_UDE       = Reff_UDE_col,
        Reff_Windowed  = Reff_Windowed_col,
    )
    CSV.write("$outdir/real_data_curves.csv", df_curvas)
    println("  Curvas día a día guardadas en $outdir/real_data_curves.csv")

    # ── Figuras ─────────────────────────────────────────────────────────
    t_split = dias[length(idx_entren) + 1]

    p_beta = plot(dias[1:cfg.T], beta_g, label="β̂ UDE", color=:orange, lw=2,
                  xlabel="Day", ylabel="β̂(t,I)", title="Real data — learned β_θ",
                  legend=:outertopright, size=(950, 480),
                  left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    plot!(p_beta, dias[1:cfg.T], beta_w, label="β̂ SW-UDE (m=$m)", color=:steelblue, lw=2)
    vline!(p_beta, [t_split], color=:gray, ls=:dash, lw=1.2, label="train/test split")
    savefig_all(p_beta, "$outdir/real_data_beta_comparison"; formats=(:png, :pdf, :eps))

    p_reff = plot(dias[1:cfg.T], r_effective(beta_g, pred_g[1, 1:cfg.T], N, γ),
                  label="R_eff UDE", color=:orange, lw=2,
                  xlabel="Day", ylabel="R_eff(t)", title="Real data — effective reproduction number",
                  legend=:outertopright, size=(950, 480),
                  left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    plot!(p_reff, dias[1:cfg.T], r_effective(beta_w, pred_w[1, 1:cfg.T], N, γ),
          label="R_eff SW-UDE (m=$m)", color=:steelblue, lw=2)
    hline!(p_reff, [1.0], color=:black, ls=:dot, lw=1.4, label="R_eff = 1")
    vline!(p_reff, [t_split], color=:gray, ls=:dash, lw=1.2, label="train/test split")
    savefig_all(p_reff, "$outdir/real_data_reff"; formats=(:png, :pdf, :eps))

    p_I = plot(dias, SIR[2, :], label="Observed data", color=:black, lw=2.5,
               xlabel="Day", ylabel="Infected / cases",
               title="Real data — I(t) reconstruction (in- and out-of-sample)",
               legend=:outertopright, size=(950, 480),
               left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    plot!(p_I, dias, pred_g[2, :], label="Î UDE", color=:orange, ls=:dash, lw=1.8)
    plot!(p_I, dias, pred_w[2, :], label="Î SW-UDE", color=:steelblue, ls=:dash, lw=1.8)
    vline!(p_I, [t_split], color=:gray, ls=:dash, lw=1.2, label="train/test split")
    savefig_all(p_I, "$outdir/real_data_I_comparison"; formats=(:png, :pdf, :eps))

    println("\n✓ Figuras guardadas en $outdir/ (train/test split marcado con línea vertical)")
    println("  Preguntas de lectura cualitativa (Sección 18.9 original, siguen aplicando):")
    println("   - ¿β̂ sube antes o durante los aumentos de infectados?")
    println("   - ¿Baja en fases de control/descenso?")
    println("   - ¿R_eff cruza 1 en fases consistentes con el crecimiento/decrecimiento de I?")
    println("   - ¿El error fuera de muestra (RMSE_test) es sustancialmente peor que el de ",
             "entrenamiento? (señal de sobreajuste)")

    return (config=cfg,
            global_=(p=p_g, pred=pred_g, beta=beta_g, losses=losses_g),
            ventanas=(p=p_w, pred=pred_w, beta=beta_w, losses=losses_w),
            tabla=tabla, idx_entren=idx_entren, idx_test=idx_test)
end

println("✓ evaluar_datos_reales_v2 definida (con split entrenamiento/validación y métricas extendidas)")
