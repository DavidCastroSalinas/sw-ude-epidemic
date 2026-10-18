# ============================================================
# src/lib/12_extended_metrics.jl — Métricas adicionales para el artículo
# ============================================================
#
# `compute_metrics` (Sección 9) ya reporta RMSE/MAE absolutos por
# compartimento y para β. Ese conjunto es necesario pero, para una
# publicación, insuficiente por dos motivos:
#
#   1. RMSE/MAE absolutos no son comparables entre escenarios ni entre
#      series de distinta escala (p. ej. datos sintéticos con N=1000 vs.
#      datos reales con miles de casos) -- hacen falta versiones
#      normalizadas/relativas.
#   2. Para datos reales no existe β_real, así que RMSE_β/MAE_β no se
#      pueden calcular. Hacen falta métricas que NO dependan de conocer
#      la tasa de transmisión verdadera: bondad de ajuste relativa sobre
#      I(t) (la única serie observada), regularidad/suavidad de β̂
#      (proxy cuantitativo de interpretabilidad), el número reproductivo
#      efectivo R_eff(t) (cantidad epidemiológica estándar, calculable
#      sin β_real), error de sincronización del peak epidémico, y error
#      de generalización fuera de muestra (train/test).
#
# Todas las funciones de este archivo son genéricas: reciben vectores
# `pred`/`obs`, no dependen de las constantes globales de 00_setup.jl, y
# por lo tanto sirven tanto para los experimentos sintéticos ya corridos
# (Secciones 13–18) como para el pipeline de datos reales (11_real_data.jl).
# ============================================================


# ── 1. Bondad de ajuste relativa/normalizada ──────────────────────────────

"""
    nrmse(pred, obs; modo=:rango)

RMSE normalizado, adimensional -- permite comparar el ajuste entre series
de distinta magnitud (p. ej. escenarios sintéticos vs. datos reales).
`modo`:
  :rango → RMSE / (max(obs) - min(obs))
  :media → RMSE / mean(obs)
"""
function nrmse(pred::AbstractVector, obs::AbstractVector; modo::Symbol=:rango)
    @assert length(pred) == length(obs)
    rmse_val = sqrt(mean((pred .- obs) .^ 2))
    denom = modo == :rango ? (maximum(obs) - minimum(obs)) : mean(obs)
    @assert denom > 0 "Denominador no positivo para NRMSE (modo=$modo) -- revisar `obs`"
    return rmse_val / denom
end

"""
    mape(pred, obs)

Mean Absolute Percentage Error, en porcentaje. Excluye puntos con
`obs ≈ 0` (indefinido) e informa cuántos se excluyeron -- común en series
epidemiológicas que pueden tocar cero.
"""
function mape(pred::AbstractVector, obs::AbstractVector; obs_min::Float64=1e-6)
    @assert length(pred) == length(obs)
    validos = abs.(obs) .> obs_min
    n_excluidos = count(!, validos)
    if n_excluidos > 0
        @warn "MAPE: se excluyeron $n_excluidos/$(length(obs)) puntos con obs≈0"
    end
    return 100 * mean(abs.((obs[validos] .- pred[validos]) ./ obs[validos]))
end

"""
    smape(pred, obs)

Symmetric MAPE, en porcentaje -- más estable que MAPE cuando `obs` se
acerca a cero (denominador es la magnitud promedio de pred y obs, nunca
exactamente cero salvo que ambos lo sean).
"""
function smape(pred::AbstractVector, obs::AbstractVector)
    @assert length(pred) == length(obs)
    denom = (abs.(pred) .+ abs.(obs)) ./ 2
    validos = denom .> 1e-10
    return 100 * mean(abs.(pred[validos] .- obs[validos]) ./ denom[validos])
end

"""
    r_squared(pred, obs)

Coeficiente de determinación R² = 1 - SS_res/SS_tot. Puede ser negativo si
`pred` ajusta peor que la media de `obs` (modelo mal especificado o no
convergido) -- a diferencia de RMSE, esto hace visible ese caso.
"""
function r_squared(pred::AbstractVector, obs::AbstractVector)
    @assert length(pred) == length(obs)
    ss_res = sum((obs .- pred) .^ 2)
    ss_tot = sum((obs .- mean(obs)) .^ 2)
    @assert ss_tot > 0 "Varianza de `obs` es cero -- R² no está definido"
    return 1 - ss_res / ss_tot
end

"""
    pearson_corr(pred, obs)

Correlación de Pearson entre predicción y observación -- mide acuerdo de
FORMA/fase incluso cuando hay un sesgo sistemático de magnitud que RMSE
penalizaría fuertemente.
"""
pearson_corr(pred::AbstractVector, obs::AbstractVector) = cor(pred, obs)


# ── 2. Regularidad/interpretabilidad de β̂(t,I) ───────────────────────────

"""
    total_variation(x; normalizado=true)

Variación total de una serie: Σ|x_{k+1} - x_k|. Para β̂(t,I), es una
medida cuantitativa de "qué tan suave/errática" es la tasa de transmisión
aprendida -- opera como versión numérica de la pregunta cualitativa
"¿es más suave la de SW-UDE que la de UDE?" (Sección 18.9). Menor TV no
es automáticamente "mejor" (β real puede ser genuinamente oscilante, p.
ej. escenario estacional), pero permite comparar dos modelos entrenados
sobre LOS MISMOS datos de forma objetiva y reproducible.

`normalizado=true` divide por `length(x)-1` (variación media por paso),
para que el número no dependa del horizonte T.
"""
function total_variation(x::AbstractVector; normalizado::Bool=true)
    tv = sum(abs.(diff(x)))
    return normalizado ? tv / (length(x) - 1) : tv
end


# ── 3. Número reproductivo efectivo ────────────────────────────────────────

"""
    r_effective(β̂, S, N, γ)

R_eff(t) = β̂(t)·S(t) / (γ·N) -- cantidad epidemiológica estándar,
calculable sin conocer β_real, directamente interpretable en el artículo
(R_eff > 1 ⇒ epidemia en expansión; R_eff < 1 ⇒ en retroceso). `β̂` y `S`
deben tener la misma longitud (β̂ evaluada en los mismos instantes que S).
"""
function r_effective(β̂::AbstractVector, S::AbstractVector, N::Float64, γ::Float64)
    @assert length(β̂) == length(S)
    return (β̂ .* S) ./ (γ * N)
end


# ── 4. Sincronización del peak epidémico ──────────────────────────────────

"""
    peak_metrics(pred, obs, ts)

Compara el instante y la magnitud del máximo de `obs` contra el máximo de
`pred`. Métrica estándar en la literatura de pronóstico epidemiológico,
independiente de β_real -- aplicable a datos reales.

Devuelve NamedTuple:
  t_peak_obs, t_peak_pred   : instantes del máximo (unidades de `ts`)
  error_tiempo_peak         : t_peak_pred - t_peak_obs (signo: + = predicho tarde)
  mag_peak_obs, mag_peak_pred
  error_relativo_magnitud   : (mag_peak_pred - mag_peak_obs) / mag_peak_obs
"""
function peak_metrics(pred::AbstractVector, obs::AbstractVector, ts::AbstractVector)
    @assert length(pred) == length(obs) == length(ts)
    i_obs  = argmax(obs)
    i_pred = argmax(pred)
    mag_obs, mag_pred = obs[i_obs], pred[i_pred]
    return (
        t_peak_obs             = ts[i_obs],
        t_peak_pred             = ts[i_pred],
        error_tiempo_peak       = ts[i_pred] - ts[i_obs],
        mag_peak_obs            = mag_obs,
        mag_peak_pred           = mag_pred,
        error_relativo_magnitud = (mag_pred - mag_obs) / mag_obs,
    )
end


# ── 5. Split entrenamiento/validación (generalización fuera de muestra) ───

"""
    split_train_test(T::Int; frac_train=0.8)

Divide los pasos de transición `1:T` en un tramo de entrenamiento
(cronológicamente al inicio) y uno de validación (al final) -- NUNCA
mezclado aleatoriamente, porque la dependencia temporal de una serie
epidémica hace que un split aleatorio filtre información del futuro al
pasado (data leakage). Devuelve `(idx_entren::UnitRange, idx_test::UnitRange)`.

Sin esto, cualquier RMSE/R² sobre datos reales solo mide qué tan bien el
modelo memorizó la serie que vio, no su capacidad de generalización --
para un artículo que use datos reales, reportar métricas fuera de muestra
es tan importante como las métricas dentro de muestra.
"""
function split_train_test(T::Int; frac_train::Float64=0.8)
    @assert 0.0 < frac_train < 1.0
    k_split = round(Int, frac_train * T)
    k_split = clamp(k_split, 1, T - 1)   # asegura al menos 1 paso de test
    return 1:k_split, (k_split + 1):T
end


# ── 6. Tabla resumen lista para el artículo ────────────────────────────────

"""
    tabla_metricas_extendidas(pred, obs, ts; β̂=nothing, S=nothing, N=nothing,
                              γ=nothing, idx_test=nothing, etiqueta="")

Arma una fila (NamedTuple) con todas las métricas anteriores, calculadas
sobre `pred` vs `obs` (típicamente la fila I(t), la única serie
verdaderamente observada en datos reales). Los campos derivados de β̂/S/N/γ
(R_eff, su rango) y de `idx_test` (métricas fuera de muestra) son
opcionales: se omiten (quedan `missing`) si no se proveen los argumentos
necesarios, para que la misma función sirva tanto en el caso sintético
completo como en el caso real parcial.

`etiqueta` es un campo libre (p. ej. "UDE", "SW-UDE (m=10)") para
identificar la fila al convertir un vector de estas NamedTuples en
DataFrame con `DataFrame(filas)` y exportarla como Tabla del artículo.
"""
function tabla_metricas_extendidas(pred::AbstractVector, obs::AbstractVector,
                                    ts::AbstractVector;
                                    β̂::Union{Nothing,AbstractVector}=nothing,
                                    S::Union{Nothing,AbstractVector}=nothing,
                                    N::Union{Nothing,Float64}=nothing,
                                    γ::Union{Nothing,Float64}=nothing,
                                    idx_test::Union{Nothing,AbstractRange}=nothing,
                                    etiqueta::String="")
    pm = peak_metrics(pred, obs, ts)

    fila = (
        etiqueta = etiqueta,
        RMSE  = sqrt(mean((pred .- obs) .^ 2)),
        MAE   = mean(abs.(pred .- obs)),
        NRMSE_rango = nrmse(pred, obs; modo=:rango),
        MAPE_pct    = mape(pred, obs),
        sMAPE_pct   = smape(pred, obs),
        R2          = r_squared(pred, obs),
        Pearson_r   = pearson_corr(pred, obs),
        error_tiempo_peak       = pm.error_tiempo_peak,
        error_relativo_magnitud = pm.error_relativo_magnitud,
    )

    if β̂ !== nothing
        fila = merge(fila, (TV_beta_media = total_variation(β̂; normalizado=true),))
        if S !== nothing && N !== nothing && γ !== nothing
            reff = r_effective(β̂, S, N, γ)
            fila = merge(fila, (Reff_medio = mean(reff), Reff_max = maximum(reff),
                                 Reff_final = reff[end]))
        end
    end

    if idx_test !== nothing
        pred_test = pred[idx_test .+ 1]   # +1: pred/obs incluyen el estado inicial en la col. 1
        obs_test  = obs[idx_test .+ 1]
        fila = merge(fila, (
            RMSE_test  = sqrt(mean((pred_test .- obs_test) .^ 2)),
            NRMSE_test = nrmse(pred_test, obs_test; modo=:rango),
            R2_test    = r_squared(pred_test, obs_test),
        ))
    end

    return fila
end

println("✓ Métricas extendidas definidas:")
println("    nrmse, mape, smape, r_squared, pearson_corr")
println("    total_variation, r_effective, peak_metrics")
println("    split_train_test, tabla_metricas_extendidas")
