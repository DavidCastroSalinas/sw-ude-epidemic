# ============================================================
# Datos reales: comparación pareada multi-semilla UDE vs SW-UDE
# ============================================================
#   julia experiments/16_run_real_data_multiseed.jl
#   SIR_UDE_SMOKE_TEST=1 julia experiments/16_...    # validación en minutos
#
# ~11 min por semilla (ambos métodos) => ~110 min con 10 semillas.
# Cierra la limitación declarada en el manuscrito: hoy toda la sección de
# datos reales usa una única semilla y no admite ningún valor p.
#
# m por defecto = 10 (el seleccionado con el barrido sin fuga + TV(β̂)).
# Override:  SIR_UDE_M_OVERRIDE=5 julia experiments/16_...
#
# [2026-09-07] ACTUALIZADO A PEDIDO DE DAVID: N ya NO se deriva con
# `sugerir_N` sobre la serie digitalizada con R0=0. Ahora se usa
# `construir_serie_referencia_fija` (src/lib/11_real_data.jl, sección 1bis)
# para anclar la serie a las condiciones iniciales fijas de Córdova-Lepe
# et al. 2026 (Medwave e3191) al 10 de julio de 2020: N=19.660.000,
# S0=19.348.776, I0=26.390, R0=284.834, γ=1/7. La serie resultante tiene
# 206 días (10 de julio de 2020 -- 31 de enero de 2021), no 215. Este es
# el runner de la CIFRA CENTRAL de la sección de datos reales
# (`tab:datos_reales_pareado`, n=10 semillas) -- cualquier corrida nueva
# de este archivo invalida y reemplaza esa tabla y su análoga
# suplementaria `tab:S1_datos_reales_pareado_supp`.
# ============================================================

include(joinpath(@__DIR__, "..", "sir_ude_lib.jl"))

if !isdefined(Main, :evaluar_datos_reales_multisemilla)
    ruta = joinpath(@__DIR__, "..", "src", "lib", "19_real_data_multiseed.jl")
    isfile(ruta) || error("Falta $ruta -- copiá src/lib/19_real_data_multiseed.jl a src/lib/")
    include(ruta)
end

CSV_PATH = joinpath(@__DIR__, "..", "data", "datos_historicos_julio_enero.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

mkpath("results/logs")

M_ELEGIDO = parse(Int, get(ENV, "SIR_UDE_M_OVERRIDE", "10"))
SEEDS     = semillas_final(1:10)

I_obs      = cargar_serie_real(CSV_PATH)
GAMMA_REAL = GAMMA_REF_FIJO   # 1/7, igual que antes
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ N fijo (fuente de referencia): N_REAL = ", N_REAL,
        "  (antes se derivaba con sugerir_N; ya no aplica)   m = ", M_ELEGIDO)

cfg_arq  = SCENARIO_CONFIG[:realchile]

t0 = time()
df, dfp = evaluar_datos_reales_multisemilla(SIR_real;
    N = N_REAL, γ = GAMMA_REAL,
    hidden = cfg_arq.hidden, layers = cfg_arq.layers,
    lr = cfg_arq.lr, epochs = cfg_arq.epochs,
    m = M_ELEGIDO, frac_train = 0.8,
    seeds = SEEDS, clip_norm = cfg_arq.clip_norm,
    outdir = "results/datos_reales_multisemilla")

println("\n✓ Listo (", formatear_duracion(time() - t0), ").")
println("    results/datos_reales_multisemilla/datos_reales_multisemilla.csv")
println("    results/datos_reales_multisemilla/datos_reales_pareado.csv")
println("    results/datos_reales_multisemilla/boxplot_*.{png,pdf,eps}")
