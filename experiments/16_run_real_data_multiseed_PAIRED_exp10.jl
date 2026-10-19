# Paired multi-seed comparison of UDE and SW-UDE on real data (n=10).
# Uses the fixed reference conditions in src/lib/11_real_data.jl.
# Run with: julia experiments/16_run_real_data_multiseed_PAIRED_exp10.jl
# Override the window or seed count with SIR_UDE_M_OVERRIDE and smoke mode.

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

if !isdefined(Main, :evaluar_real_data_paired_multiseed)
    ruta = joinpath(@__DIR__, "..", "src", "lib", "19_real_data_multiseed.jl")
    isfile(ruta) || error("Falta $ruta -- copiá src/lib/19_real_data_multiseed.jl a src/lib/")
    include(ruta)
end

CSV_PATH = joinpath(@__DIR__, "..", "data", "historical_data_july_january.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

mkpath("results/logs")

M_ELEGIDO = parse(Int, get(ENV, "SIR_UDE_M_OVERRIDE", "10"))
SEEDS     = semillas_final(1:10)

I_obs      = cargar_serie_real(CSV_PATH)
GAMMA_REAL = GAMMA_REF_FIJO   # 1/7, igual que antes
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ N fijo (fuente de referencia): N_REAL = ", N_REAL, "  m = ", M_ELEGIDO)

cfg_arq  = SCENARIO_CONFIG[:realchile]

t0 = time()
df, dfp = evaluar_real_data_paired_multiseed(SIR_real;
    N = N_REAL, γ = GAMMA_REAL,
    hidden = cfg_arq.hidden, layers = cfg_arq.layers,
    lr = cfg_arq.lr, epochs = cfg_arq.epochs,
    m = M_ELEGIDO, frac_train = 0.8,
    seeds = SEEDS, clip_norm = cfg_arq.clip_norm,
    outdir = "results/real_data_paired_multiseed")

println("\n✓ Listo (", formatear_duracion(time() - t0), ").")
println("    results/real_data_paired_multiseed/real_data_paired_multiseed.csv")
println("    results/real_data_paired_multiseed/real_data_paired.csv")
println("    results/real_data_paired_multiseed/boxplot_*.{png,pdf,eps}")
