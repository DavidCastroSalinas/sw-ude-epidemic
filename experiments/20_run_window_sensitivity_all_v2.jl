# ============================================================
# Window-length (m) sensitivity for all 7 scenarios -- v2
# ============================================================
# Reemplaza a experiments/02_run_window_sensitivity_all.jl para la grilla de m.
# No cambia el motor de entrenamiento ni las métricas -- llama a la misma
# `run_all_sensitivity` de sir_ude_lib.jl -- solo cambia QUÉ valores de m
# se prueban y por qué, de acuerdo a la discusión metodológica de
# Sección~2.1.4 (Sensitivity to Window Length) de main3_corregido.tex.
#
# REVERTIDO 2026-09-05 (revisión de experimentos vs. manuscrito): entre el
# 2026-08-30 y esta revisión, este runner pasó a generar la grilla
# automáticamente con `generar_grilla_m(γ, Δt, T_train)`
# (un módulo que existió hasta el 2026-10-18):
#
#   m_γ = ceil(1/(γ·Δt))   (τ_I en pasos temporales)
#   grilla = { ceil(m_γ/2), m_γ, 2·m_γ, 3·m_γ, ..., K·m_γ, T_train }
#
# Para γ=0.10, Δt=1.0, T_train=50 esto da m_γ=10 → grilla=[5,10,20,30,40,50]
# (6 puntos) -- que YA NO es la grilla que produjo los resultados citados en
# main3_corregido.tex/articulo_bloques_es.tex. La Sección "Sensitivity to
# Window Length" y la Tabla tab:tv_diagnostico están escritas sobre la
# grilla refinada real, `[1, 2, 5, 7, 10, 15, 20, 30, 50]` (9 puntos) --
# incluyen EXPLÍCITAMENTE m=1 y m=2 como controles por debajo del piso
# epidemiológico (el argumento central de esa sección es que el mínimo de
# RMSE_β cae en m=1/m=2 para la mayoría de los escenarios, y eso es
# precisamente lo que muestra ser un artefacto de sobreajuste; sin m=1/m=2
# en la grilla esa sección no tiene con qué sostenerse) y m=7/m=15, que
# tampoco están en la grilla automática. Se revierte a la grilla manual
# exacta para no perder la reproducibilidad de lo ya escrito y validado.
# `generar_grilla_m` (src/lib/24_generate_grilla_m.jl) quedó sin uso con esa
# reversión y se eliminó del repositorio el 2026-10-18. m_γ se calcula acá
# en una línea, más abajo, solo para el diagnóstico r_m/es_control.
#
# Grilla usada acá (idéntica a la "v2 manual, 2026-08-30" y a la que cita
# el manuscrito):
#   [1(control), 2(control), 5, 7, 10, 15, 20, 30, 50]
#
# Grillas aún más antiguas (solo para referencia histórica):
#   default:            [1, 3, 5, 10, 20, 50]
#   :tanh, :saturacion: [1, 2, 3, 5, 7, 10, 20]
#
# Run from the command line with:
#     julia --project=. experiments/20_run_window_sensitivity_all_v2.jl
# ============================================================

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))
using CSV   # redundante si sir_ude_lib.jl ya lo carga; no hace daño repetirlo

mkpath("results/window_sensitivity_v2")

# T (número de transiciones de la serie sintética) y γ, Δt vienen de
# src/lib/00_setup.jl -- misma configuración que usa el resto de la suite.
const T_TRAIN_SINTETICO = T          # = 50, sin split entrenamiento/prueba

# Grilla EXACTA usada para los resultados ya citados en el manuscrito --
# ver nota arriba. m=1 y m=2 son controles sub-epidemiológicos (m < 1/γ),
# no candidatos para el óptimo.
const M_GRID_V2         = [1, 2, 5, 7, 10, 15, 20, 30, 50]
const M_GAMMA_V2        = Int(ceil(1 / (γ * Δt)))   # =10, solo para el diagnóstico r_m/es_control de abajo
const M_CONTROLES_V2    = filter(m -> m < M_GAMMA_V2, M_GRID_V2)   # [1, 2]: controles, no candidatos

println("γ=", γ, "  Δt=", Δt, "  T_train=", T_TRAIN_SINTETICO,
        "  →  m_γ=", M_GAMMA_V2, "  grilla=", M_GRID_V2)

df_sensibilidad_all = run_all_sensitivity(
    m_values          = M_GRID_V2,
    m_values_override = Dict{Symbol,Vector{Int64}}(),  # misma grilla para los 7 escenarios, sin excepciones
    outdir            = "results/window_sensitivity_v2",
)

# `run_all_sensitivity` ya escribió su propio CSV consolidado en
# results/window_sensitivity_v2/sensitivity_m_ALL_scenarios.csv (sin
# tocar) -- esto agrega columnas de conveniencia para que downstream
# (figuras, tablas) no tenga que repetir el criterio "m < 1/gamma" a mano:
#   es_control : true para m < m_γ (controles sub-epidemiológicos, m=1 y
#                m=2 en esta grilla) -- no son candidatos al óptimo, ver
#                nota de cabecera sobre por qué igual se incluyen.
#   r_m        : γ·m·Δt, número de períodos infecciosos en la ventana
#                (calculado directamente, no por lookup -- válido para
#                cualquier m que aparezca en el CSV, esté o no en la
#                grilla base generada)
df_sensibilidad_all.es_control = df_sensibilidad_all.m .< M_GAMMA_V2
df_sensibilidad_all.r_m        = γ .* df_sensibilidad_all.m .* Δt
CSV.write("results/window_sensitivity_v2/sensitivity_m_ALL_scenarios_v2.csv", df_sensibilidad_all)

println("\n✓ Done. Dos CSV en results/window_sensitivity_v2/:")
println("    sensitivity_m_ALL_scenarios.csv     (salida original de run_all_sensitivity)")
println("    sensitivity_m_ALL_scenarios_v2.csv  (igual + columnas es_control, r_m)")
println("  1/γ = ", 1 / γ, " días -- m_γ=", M_GAMMA_V2,
        " -- controles sub-epidemiológicos: ", M_CONTROLES_V2,
        " -- r_m = períodos infecciosos por ventana.")
