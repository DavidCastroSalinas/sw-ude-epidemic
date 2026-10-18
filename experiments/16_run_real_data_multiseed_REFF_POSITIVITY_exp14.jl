# ============================================================
# experiments/16_run_real_data_multiseed.jl
#
# Corrida multi-semilla de datos reales (N=80 851, γ=1/7, m=10) para
# refrescar dos cifras que hoy están footnoteadas en el manuscrito como
# provenientes de la corrida ANTERIOR al parche de consistencia de β̂:
#
#   1. Máximo de R_eff(t) por semilla y método (media ± DE, y en cuántas
#      de las 10 semillas supera 1) -- Sección de R_eff por fases.
#   2. Mínimo global de β̂ en las 20 corridas (10 semillas x 2 métodos)
#      -- párrafo de "control de robustez" antes de la sensibilidad a N.
#
# Requiere que `src/lib/11_real_data.jl` ya esté en su versión PARCHEADA:
# evaluar_datos_reales_v2 debe evaluar β̂ sobre el I que cada método
# propaga (pred_g[2,k] / pred_w[2,k]), no sobre el I observado. Si tu
# `src/lib/11_real_data.jl` es el archivo que ya me pasaste como
# `11_real_data_corregido.jl`, esto ya está aplicado.
#
# [2026-09-07] ACTUALIZADO A PEDIDO DE DAVID: ya NO deriva N con
# `sugerir_N` sobre la serie digitalizada con R0=0. Ahora usa
# `construir_serie_referencia_fija` para anclar la serie a las condiciones
# iniciales de Córdova-Lepe et al. 2026 (Medwave e3191) al 10 de julio de
# 2020: N=19.660.000, S0=19.348.776, I0=26.390, R0=284.834, γ=1/7. La
# serie resultante tiene 206 días (10 de julio de 2020 -- 31 de enero de
# 2021), no 215.
# ============================================================

# --- AJUSTA ESTE INCLUDE a como cargas el resto de la librería en tus
#     otros runners (p.ej. el mismo header que usa experiments/13_...).
#     Debe dejar definidas: cargar_serie_real, construir_SIR_desde_I,
#     evaluar_datos_reales_v2, r_effective, build_network, etc.
include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

using Statistics, CSV, DataFrames

# ── Config oficial adoptada en el manuscrito [ACTUALIZADA 2026-09-07] ──
const GAMMA_OFICIAL = GAMMA_REF_FIJO   # 1/7, igual que antes
const M_OFICIAL     = 10
const HIDDEN        = 16
const LAYERS        = 2
const EPOCHS        = 8000
const LR            = 0.005
const FRAC_TRAIN    = 0.8
const SEEDS         = 1:10

# --- AJUSTA esta ruta a tu CSV real (la misma que usan experiments/11_ y 13_) ---
const RUTA_SERIE  = "data/historical_data_july_january.csv"
const OUTDIR_BASE = "results/datos_reales_multiseed"

mkpath(OUTDIR_BASE)

# ── Cargar y anclar la serie una sola vez (no depende de la semilla) ──
I_obs_raw = cargar_serie_real(RUTA_SERIE)
resultado_ancla = construir_serie_referencia_fija(I_obs_raw)  # usa los _REF_FIJO por defecto
SIR = resultado_ancla.SIR

println("✓ Serie reconstruida: T=$(size(SIR, 2) - 1) transiciones (206 días esperados), ",
        "N=$N_REF_FIJO, γ=$GAMMA_OFICIAL, factor de reescala=$(resultado_ancla.factor_reescala)")

# ── Loop de semillas ───────────────────────────────────────────────────
resumen = DataFrame(seed=Int[], metodo=String[], Reff_max=Float64[],
                     beta_min=Float64[], beta_max=Float64[])

for s in SEEDS
    println("\n" * "="^70)
    println("  SEMILLA $s de $(last(SEEDS))")
    println("="^70)

    resultado = evaluar_datos_reales_v2(SIR;
        N=N_REF_FIJO, γ=GAMMA_OFICIAL, hidden=HIDDEN, layers=LAYERS,
        lr=LR, epochs=EPOCHS, m=M_OFICIAL, frac_train=FRAC_TRAIN,
        seed_red=s, outdir="$OUTDIR_BASE/seed$s")

    beta_g = resultado.global_.beta                                   # UDE
    beta_w = resultado.ventanas.beta                                  # SW-UDE
    S_g    = resultado.global_.pred[1, 1:resultado.config.T]
    S_w    = resultado.ventanas.pred[1, 1:resultado.config.T]

    reff_g = r_effective(beta_g, S_g, N_REF_FIJO, GAMMA_OFICIAL)
    reff_w = r_effective(beta_w, S_w, N_REF_FIJO, GAMMA_OFICIAL)

    push!(resumen, (seed=s, metodo="UDE",    Reff_max=maximum(reff_g),
                     beta_min=minimum(beta_g), beta_max=maximum(beta_g)))
    push!(resumen, (seed=s, metodo="SW-UDE", Reff_max=maximum(reff_w),
                     beta_min=minimum(beta_w), beta_max=maximum(beta_w)))

    # checkpoint incremental por si el proceso se corta a mitad de camino
    CSV.write("$OUTDIR_BASE/summary_multiseed_partial.csv", resumen)
end

# ── Agregados exactos que pide el manuscrito ───────────────────────────
println("\n" * "="^70)
println("  RESUMEN FINAL (10 semillas)")
println("="^70)

for metodo in ("UDE", "SW-UDE")
    filas  = filter(r -> r.metodo == metodo, resumen)
    mu     = mean(filas.Reff_max)
    sd     = std(filas.Reff_max)
    n_sup1 = count(>(1.0), filas.Reff_max)
    println("$metodo:  Reff_max = $(round(mu, digits=3)) ± $(round(sd, digits=3))  " *
            "($n_sup1 de $(nrow(filas)) semillas superan 1)")  # [2026-09-09] FIX: length(::DataFrame) no existe -- era nrow(filas)
end

beta_min_global = minimum(resumen.beta_min)
println("\nMínimo global de β̂ en las $(2 * length(SEEDS)) corridas: " *
        "$(round(beta_min_global, digits=4))")

CSV.write("$OUTDIR_BASE/summary_multiseed.csv", resumen)
println("\n✓ Resumen guardado en $OUTDIR_BASE/summary_multiseed.csv")
println("  (columnas: seed, metodo, Reff_max, beta_min, beta_max)")