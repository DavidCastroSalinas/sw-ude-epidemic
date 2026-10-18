# ============================================================
# src/lib/14_real_data_window_sensitivity.jl
# ------------------------------------------------------------
# Experimento simple de sensibilidad al tamaño de ventana m sobre la
# serie REAL (datos_historicos_julio_enero.csv), pedido explícitamente
# como complemento de `evaluar_datos_reales_v2` (src/lib/11_real_data.jl):
# UNA sola corrida (seed=1234, sin barrido de semillas) que entrena
# SW-UDE (`train_windowed_rd`) para una lista de tamaños de
# ventana m y guarda el error de ajuste en un CSV listo para graficar
# (eje X = m real, en días -- NUNCA el porcentaje; eje Y = RMSE_SIR).
#
# Por qué es "simple" (a propósito, a diferencia de evaluar_datos_reales_v2):
#   - NO separa entrenamiento/validación (`idx_entren` = toda la serie).
#     Esto significa que el RMSE_SIR reportado aquí es un ajuste DENTRO
#     de muestra, útil para ver la FORMA de la curva RMSE_SIR vs. m, no
#     como evidencia de capacidad predictiva -- para eso sigue estando
#     `evaluar_datos_reales_v2` (con su split train/test) en
#     src/lib/11_real_data.jl.
#   - Entrena solo SW-UDE (no tiene sentido barrer "m" para el
#     método Global).
#
# Qué es RMSE_SIR: a diferencia de RMSE_S/RMSE_I/RMSE_R (por
# compartimento, igual que `compute_metrics`), RMSE_SIR es el RMSE
# COMBINADO sobre el estado completo [S;I;R] (las 3*(T+1) entradas de la
# matriz aplanada), en las mismas unidades absolutas (individuos) que ya
# usa `compute_metrics`/`tabla_metricas_extendidas`. Recordatorio
# heredado de src/lib/11_real_data.jl: S y R son reconstrucciones gray-box a
# partir de I(t) (única serie realmente observada), no mediciones
# independientes -- por eso RMSE_SIR queda dominado por la escala de S/R
# (que rondan N), y se guardan también RMSE_S/I/R por separado para
# lectura sin ese sesgo de escala.
# ============================================================


"""
    m_values_from_pcts(T::Int; pcts=[1.00,0.80,0.50,0.25,0.15], m_abs=[20,10,5,2,1])

Arma la grilla de tamaños de ventana a barrer, devuelta como
`Vector{NamedTuple}` con campos `(m, porcentaje_T, origen)`:

  - `pcts`  se interpretan como fracción de `T` (100%, 80%, 50%, 25%, 15%
    del horizonte real), redondeando al entero más cercano (mínimo 1) --
    columna `porcentaje_T` = 100·p, `origen` = "porcentaje_T".
  - `m_abs` se usan directamente como valores de m, SIN escalar (pensados
    para ventanas cortas: 20, 10, 5, 2, 1 días) -- `porcentaje_T` queda
    `NaN` (no `missing`, para que la columna sea `Vector{Float64}`
    homogénea al pasar por `DataFrame`/CSV, mismo criterio ya usado en
    `evaluar_sensibilidad_datos_reales`), `origen` = "valor_absoluto".

El orden de salida es el mismo que el pedido (porcentajes de mayor a
menor, luego los valores absolutos), sin eliminar duplicados -- si algún
m coincide entre ambas listas, ambas filas se guardan (columna `origen`
permite distinguirlas).
"""
function m_values_from_pcts(T::Int;
                             pcts::Vector{Float64}=[1.00, 0.80, 0.50, 0.25, 0.15],
                             m_abs::Vector{Int}=[20, 10, 5, 2, 1])
    @assert T >= 1 "T debe ser >= 1"
    filas_m = NamedTuple[]
    for p in pcts
        m = clamp(round(Int, p * T), 1, T)
        push!(filas_m, (m=m, porcentaje_T=round(p * 100, digits=1), origen="porcentaje_T"))
    end
    for m in m_abs
        @assert m >= 1 "m_abs debe contener enteros >= 1 (recibido m=$m)"
        push!(filas_m, (m=m, porcentaje_T=NaN, origen="valor_absoluto"))
    end
    return filas_m
end

println("✓ m_values_from_pcts definida")


# [2026-10-18] `run_window_sensitivity_real` estaba aquí. Ningún runner del
# artículo la llamaba: quedó superada y se eliminó. Ver CHANGELOG.md.



# [2026-10-18] `elegir_m_automatico` estaba aquí. Ningún runner del
# artículo la llamaba: quedó superada y se eliminó. Ver CHANGELOG.md.

