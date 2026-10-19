# Real-data window-length sensitivity with an 80/20 train/test split.
# Uses the manuscript grid [1, 2, 4, 7, 10, 14, 21, 35, 54, 107] plus the
# training-horizon endpoint, recomputed from the current reference series.
# Run with: julia experiments/21_run_real_data_window_sensitivity_split_v2.jl
# Override the selected window with SIR_UDE_M_OVERRIDE=<m>.

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

# Carga autosuficiente de src/lib/18 si no está en sir_ude_lib.jl
if !isdefined(Main, :run_window_sensitivity_real_split)
    ruta_lib18 = joinpath(@__DIR__, "..", "src", "lib", "18_real_data_window_sensitivity_split.jl")
    isfile(ruta_lib18) || error("Falta $ruta_lib18 -- copiá src/lib/18_... a src/lib/ antes de correr esto.")
    include(ruta_lib18)
end

CSV_PATH = joinpath(@__DIR__, "..", "data", "historical_data_july_january.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

mkpath("results/real_data")
mkpath("results/logs")

I_obs = cargar_serie_real(CSV_PATH)

GAMMA_REAL  = GAMMA_REF_FIJO   # 1/7, igual que antes
DT_REAL     = 1.0
FRAC_TRAIN  = 0.8

resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ N fijo (fuente de referencia): N_REAL = ", N_REAL,
        "  (antes se derivaba con sugerir_N; ya no aplica)")

cfg_arq  = SCENARIO_CONFIG[:realchile]

# ── T_train: mismo cálculo que usa internamente run_window_sensitivity_real_split ──
cfg_real            = make_real_data_config(SIR_real; N=N_REAL, γ=GAMMA_REAL, Δt=DT_REAL)
idx_entren, _       = split_train_test(cfg_real.T; frac_train=FRAC_TRAIN)
const T_TRAIN_REAL  = length(idx_entren)

# ── Grilla: lista manual ya citada en el manuscrito, con el ANCLA FINAL
# recalculada al T_train real de la serie actual ─────────────────────────
# REVERTIDO 2026-09-05 (revisión de experimentos vs. manuscrito): esto
# generaba la grilla automáticamente con `generar_grilla_m(γ, Δt, T_train)`
# -- para γ=1/7, T_train=171 eso da 26 múltiplos de 7 (7,14,...,168) más
# el ancla 171, es decir ~27 valores de m en vez de los 11 que realmente
# están citados en `tab:datos_reales_sensibilidad_m` del manuscrito
# (`[1, 2, 4, 7, 10, 14, 21, 35, 54, 107, 171]`) -- más del doble de
# entrenamientos para un experimento que ya cuesta 8-10h, sin m=1 ni m=2
# (que el propio texto discute explícitamente, p.ej. "un criterio
# orientado solo a extrapolación habría seleccionado m=1"), y además
# INCONSISTENTE con la grilla multi-semilla de `experiments/22_...` (Exp 9),
# que sí sigue usando la lista manual correcta. Se revierte a esa misma
# lista para (a) no inflar el costo de cómputo y (b) mantener Exp 8 y
# Exp 9 sobre la misma grilla, como corresponde.
#
# [2026-09-07] ANCLA ACTUALIZADA A PEDIDO DE DAVID: la serie ya usa
# exactamente los mismos días que Córdova-Lepe et al. (206 días,
# `construir_serie_referencia_fija`) -- no hace falta descartar más datos.
# Lo que cambió es que, al ser 9 días más corta que la serie vieja de 215
# días, el 80% de entrenamiento ya no da T_train=171 sino T_train=164
# (calculado arriba, `T_TRAIN_REAL`). El ancla final de la grilla -- que
# representa "todo el horizonte de entrenamiento en una sola ventana",
# equivalente a la UDE estándar -- se reemplaza por `T_TRAIN_REAL` en vez
# del 171 fijo, para que siga representando exactamente eso bajo la serie
# nueva. Los otros 10 valores (1,2,4,7,10,14,21,35,54,107) NO cambian.
const M_GAMMA_REAL       = Int(ceil(1 / (GAMMA_REAL * DT_REAL)))   # =7, solo para el diagnóstico r_m/es_control
const M_ADOPTADO         = 10  # el que ya usa el resto del artículo -- se conserva aunque no sea múltiplo de m_γ

# Grilla ya citada en tab:datos_reales_sensibilidad_m (10 valores fijos),
# más el ancla de horizonte completo = T_TRAIN_REAL (antes 171, fijo;
# ahora se recalcula solo, sigue siendo idéntica a la de
# experiments/22_run_real_data_window_sensitivity_multiseed.jl -- Exp 9 -- que
# usa el mismo cálculo).
const M_GRID_REAL_V2 = sort(unique([1, 2, 4, 7, 10, 14, 21, 35, 54, 107, T_TRAIN_REAL]))
println("  Ancla de horizonte completo (antes 171, serie de 215 días): T_TRAIN_REAL = ", T_TRAIN_REAL,
        "  (serie nueva de 206 días, mismos días que Córdova-Lepe et al.)")

println("γ=", GAMMA_REAL, "  Δt=", DT_REAL, "  T_train=", T_TRAIN_REAL,
        "  →  m_γ=", M_GAMMA_REAL, "  grilla=", M_GRID_REAL_V2)

t0 = time()
df = run_window_sensitivity_real_split(SIR_real;
    N = N_REAL, γ = GAMMA_REAL,
    hidden = cfg_arq.hidden, layers = cfg_arq.layers,
    lr = cfg_arq.lr, epochs = cfg_arq.epochs,
    seed_red = 1234, clip_norm = cfg_arq.clip_norm,
    frac_train = FRAC_TRAIN,
    pcts = Float64[],
    m_abs = M_GRID_REAL_V2,
    outdir = "results/real_data")

# Columnas de conveniencia, iguales en espíritu a las de
# experiments/20_run_window_sensitivity_all_v2.jl -- marcan decisiones ya
# tomadas en el texto, no recalculan nada nuevo.
#   es_control  : true para m < m_γ (controles sub-epidemiológicos: m=1 y
#                 m=2 en esta grilla)
#   es_adoptado : true solo para m = 10 (valor ya usado en el resto del artículo)
#   r_m         : γ·m·Δt -- calculado directamente para cada m de la tabla,
#                 esté o no en la grilla base generada (p.ej. también da un
#                 valor válido para m=10, aunque no sea múltiplo de m_γ)
df.es_control  = df.m .< M_GAMMA_REAL
df.es_adoptado = df.m .== M_ADOPTADO
df.r_m         = GAMMA_REAL .* df.m .* DT_REAL
CSV.write("results/real_data/real_data_sensitivity_m_split_v2.csv", df)

println("\n✓ Listo (", formatear_duracion(time() - t0), ").")
println("    results/real_data/real_data_sensitivity_m_split.csv        (salida original)")
println("    results/real_data/real_data_sensitivity_m_split.{png,pdf,eps}")
println("    results/real_data/real_data_TVbeta_vs_m.{png,pdf,eps}")
println("    results/real_data/real_data_sensitivity_m_split_v2.csv     (+ es_control, es_adoptado, r_m)")
println("\n  1/γ = ", round(1 / GAMMA_REAL, digits=2), " días -- m_γ=", M_GAMMA_REAL,
        " -- controles sub-epidemiológicos: m<", M_GAMMA_REAL, " -- y es_adoptado (m=", M_ADOPTADO, ").")
println("  Elegí m contrastando RMSE_I_train (banda del 5%) con TV(β̂) y con 1/γ.")
println("  Si el m elegido NO es el que usa experiments/13_..., correlo con")
println("  SIR_UDE_M_OVERRIDE=<m> para regenerar métricas, curvas y horizontes.")
