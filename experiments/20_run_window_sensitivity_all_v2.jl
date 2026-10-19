# Window-length sensitivity for all seven synthetic scenarios.
# Uses the grid reported in the manuscript: [1, 2, 5, 7, 10, 15, 20, 30, 50].
# Values 1 and 2 are below the epidemiological timescale 1/gamma and serve
# as controls. Run with: julia --project=. experiments/20_run_window_sensitivity_all_v2.jl

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

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
