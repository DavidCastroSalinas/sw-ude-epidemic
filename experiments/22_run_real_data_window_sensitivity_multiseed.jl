# ============================================================
# Sensibilidad a m sobre datos reales -- multi-semilla (v3)
# ============================================================
# Extiende a experiments/21_run_real_data_window_sensitivity_split_v2.jl con la
# única mejora que de verdad vale la pena pagar con una re-corrida completa:
# el barrido de m deja de depender de una sola semilla (seed=1234) y pasa a
# promediarse sobre varias semillas de inicialización de la red, tal como el
# propio manuscrito señala como limitación ("el barrido se realizó con una
# única semilla") en la Sección de sensibilidad a m con datos reales.
#
# La GRILLA de m (M_GRID_REAL_V2, con m=7=1/gamma como piso epidemiológico y
# m=10 conservado por continuidad con lo ya reportado) es EXACTAMENTE la
# misma que en el runner 21 -- este script no vuelve a tocar esos valores,
# solo agrega semillas. Ver experiments/21_..._v2.jl y
# main3_corregido.tex (subsubsec:datos_reales_seleccion_m) para la
# justificación de la grilla en sí.
#
# Diseño: UN PROCESO POR SEMILLA (no un loop secuencial sobre semillas
# dentro de un mismo proceso), para aprovechar los 32 núcleos ya
# confirmados en la máquina. Cada corrida de una semilla ya recorre las 11
# ventanas de M_GRID_REAL_V2 puertas adentro (run_window_sensitivity_real_split
# barre m_abs); son las semillas, no los valores de m, las que se
# paralelizan aquí. Con 5 procesos concurrentes y BLAS acotado por proceso
# (ver experiments/lanzar_multiseed_real_data.sh), el tiempo de pared total para
# las 5 semillas debería ser aproximadamente el mismo que una sola corrida
# de ~9-11h del runner 21, no 5 veces más.
#
# La semilla la fija la variable de entorno SIR_UDE_SEED (default: 1234,
# la misma que ya está reportada en el artículo -- así esa corrida existente
# se puede reutilizar como la primera de las cinco, sin volver a computarla,
# si preferís no relanzarla).
#
#     SIR_UDE_SEED=1234  julia experiments/22_run_real_data_window_sensitivity_multiseed.jl
#     SIR_UDE_SEED=1     julia experiments/22_run_real_data_window_sensitivity_multiseed.jl
#     SIR_UDE_SEED=2     julia experiments/22_run_real_data_window_sensitivity_multiseed.jl
#     SIR_UDE_SEED=3     julia experiments/22_run_real_data_window_sensitivity_multiseed.jl
#     SIR_UDE_SEED=4     julia experiments/22_run_real_data_window_sensitivity_multiseed.jl
#
#     SIR_UDE_SMOKE_TEST=1 SIR_UDE_SEED=1  julia experiments/22_...   # validar rápido, una semilla
#
# Cada corrida escribe en su propia subcarpeta
# (results/datos_reales/multiseed/seed_<seed>/), así que las 5 no se pisan
# entre sí. experiments/23_consolidar_multiseed_real_data.jl junta los 5 CSV
# después.
#
# Valores oficiales (HASTA 2026-09-07, sin cambios respecto al runner 21):
# γ = 1/7, N derivado con sugerir_N, arquitectura/epochs/lr de
# SCENARIO_CONFIG[:realchile].
#
# [2026-09-07] ACTUALIZADO: N ya NO se deriva con `sugerir_N`. Se usa
# `construir_serie_referencia_fija` (src/lib/11_real_data.jl) para anclar la
# serie a las condiciones iniciales fijas de Córdova-Lepe et al. 2026
# (Medwave e3191) al 10 de julio de 2020: N=19.660.000, S0=19.348.776,
# I0=26.390, R0=284.834, γ=1/7. La serie resultante tiene 206 días (10 de
# julio de 2020 -- 31 de enero de 2021), NO 215 -- son exactamente los
# mismos días que usó Córdova-Lepe et al. (David, 2026-09-07). La grilla
# de m (M_GRID_REAL_V2) mantiene los mismos 10 valores del runner 21, pero
# el ANCLA final ya no es el 171 fijo (calculado para T_train=171 sobre la
# serie vieja de 215 días): se recalcula como `T_TRAIN_REAL` (=164 con la
# serie nueva y frac_train=0.8) para seguir representando "todo el
# horizonte de entrenamiento en una ventana", igual que en el runner 21.
# ============================================================

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))
using CSV   # redundante si sir_ude_lib.jl ya lo carga; no hace daño repetirlo

# Carga autosuficiente de src/lib/18 si no está en sir_ude_lib.jl
if !isdefined(Main, :run_window_sensitivity_real_split)
    ruta_lib18 = joinpath(@__DIR__, "..", "src", "lib", "18_real_data_window_sensitivity_split.jl")
    isfile(ruta_lib18) || error("Falta $ruta_lib18 -- copiá src/lib/18_... a src/lib/ antes de correr esto.")
    include(ruta_lib18)
end

SEMILLA = parse(Int, get(ENV, "SIR_UDE_SEED", "1234"))

CSV_PATH = joinpath(@__DIR__, "..", "data", "datos_historicos_julio_enero.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

OUTDIR = joinpath("results", "datos_reales", "multiseed", "seed_$(SEMILLA)")
mkpath(OUTDIR)
mkpath("results/logs")

I_obs = cargar_serie_real(CSV_PATH)

GAMMA_REAL = GAMMA_REF_FIJO   # 1/7, igual que antes
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ Semilla = ", SEMILLA, " -- N fijo (fuente de referencia): N_REAL = ", N_REAL,
        "  (antes se derivaba con sugerir_N; ya no aplica)")

cfg_arq  = SCENARIO_CONFIG[:realchile]

# ── T_train: mismo cálculo que usa internamente run_window_sensitivity_real_split
# y que usa experiments/21_..._v2.jl -- para que el ancla final de la grilla
# (abajo) sea consistente entre Exp 8 y Exp 9. ──────────────────────────
cfg_real           = make_real_data_config(SIR_real; N=N_REAL, γ=GAMMA_REAL, Δt=1.0)
idx_entren, _      = split_train_test(cfg_real.T; frac_train=0.8)
const T_TRAIN_REAL = length(idx_entren)

# Misma grilla que experiments/21_..._v2.jl -- ver ese archivo para la
# justificación completa de cada valor. El ancla final ya no es el 171
# fijo (serie vieja de 215 días) -- se recalcula como T_TRAIN_REAL.
const M_GRID_REAL_V2    = sort(unique([1, 2, 4, 7, 10, 14, 21, 35, 54, 107, T_TRAIN_REAL]))
const M_CONTROL_REAL_V2 = 1
const M_ADOPTADO        = 10
println("  Ancla de horizonte completo (antes 171, serie de 215 días): T_TRAIN_REAL = ", T_TRAIN_REAL,
        "  (serie nueva de 206 días, mismos días que Córdova-Lepe et al.)")

t0 = time()
df = run_window_sensitivity_real_split(SIR_real;
    N = N_REAL, γ = GAMMA_REAL,
    hidden = cfg_arq.hidden, layers = cfg_arq.layers,
    lr = cfg_arq.lr, epochs = cfg_arq.epochs,
    seed_red = SEMILLA, clip_norm = cfg_arq.clip_norm,
    frac_train = 0.8,
    pcts = Float64[],
    m_abs = M_GRID_REAL_V2,
    outdir = OUTDIR)

df.seed        = fill(SEMILLA, nrow(df))
df.es_control  = df.m .== M_CONTROL_REAL_V2
df.es_adoptado = df.m .== M_ADOPTADO
CSV.write(joinpath(OUTDIR, "datos_reales_sensibilidad_m_seed$(SEMILLA).csv"), df)

println("\n✓ Semilla ", SEMILLA, " lista (", formatear_duracion(time() - t0), ").")
println("  CSV: ", joinpath(OUTDIR, "datos_reales_sensibilidad_m_seed$(SEMILLA).csv"))
println("  Cuando estén las 5 semillas, correr experiments/23_consolidar_multiseed_real_data.jl")
