# Multi-seed version of the real-data window sensitivity experiment.
# Run once per seed with SIR_UDE_SEED=<seed>; each run writes to its own
# results/real_data/multiseed/seed_<seed>/ directory. After all seeds finish,
# combine them with experiments/23_consolidate_multiseed_real_data.jl.
# Example: SIR_UDE_SEED=1 julia experiments/22_run_real_data_window_sensitivity_multiseed.jl

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

# Carga autosuficiente de src/lib/18 si no está en sir_ude_lib.jl
if !isdefined(Main, :run_window_sensitivity_real_split)
    ruta_lib18 = joinpath(@__DIR__, "..", "src", "lib", "18_real_data_window_sensitivity_split.jl")
    isfile(ruta_lib18) || error("Falta $ruta_lib18 -- copiá src/lib/18_... a src/lib/ antes de correr esto.")
    include(ruta_lib18)
end

SEMILLA = parse(Int, get(ENV, "SIR_UDE_SEED", "1234"))

CSV_PATH = joinpath(@__DIR__, "..", "data", "historical_data_july_january.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

OUTDIR = joinpath("results", "real_data", "multiseed", "seed_$(SEMILLA)")
mkpath(OUTDIR)
mkpath("results/logs")

I_obs = cargar_serie_real(CSV_PATH)

GAMMA_REAL = GAMMA_REF_FIJO   # 1/7, igual que antes
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ Semilla = ", SEMILLA, " -- N fijo (fuente de referencia): N_REAL = ", N_REAL)

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
println("Training-horizon endpoint: T_TRAIN_REAL = ", T_TRAIN_REAL)

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
CSV.write(joinpath(OUTDIR, "real_data_sensitivity_m_seed$(SEMILLA).csv"), df)

println("\n✓ Semilla ", SEMILLA, " lista (", formatear_duracion(time() - t0), ").")
println("  CSV: ", joinpath(OUTDIR, "real_data_sensitivity_m_seed$(SEMILLA).csv"))
println("  Cuando estén las 5 semillas, correr experiments/23_consolidate_multiseed_real_data.jl")
