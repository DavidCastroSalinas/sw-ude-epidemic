# Real-data robustness summary across network seeds.
# Smoke mode uses 2 seeds, 30 epochs, and a temporary output directory.
# Full runs use 10 seeds and write to results/real_data_multiseed/.

if get(ENV, "SIR_UDE_SMOKE_TEST", "0") == "1"
    ENV["SIR_UDE_SMOKE_EPOCHS"] = get(ENV, "SIR_UDE_SMOKE_EPOCHS", "30")
end

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

const GAMMA_OFICIAL = GAMMA_REF_FIJO
const M_OFICIAL     = 10
const HIDDEN        = 16
const LAYERS        = 2
const EPOCHS        = epocas_final(8000)
const LR            = 0.005
const FRAC_TRAIN    = 0.8
const SEEDS         = semillas_final(1:10)

const RUTA_SERIE = joinpath(@__DIR__, "..", "data", "historical_data_july_january.csv")
const OUTDIR_BASE = SMOKE_TEST ? mktempdir() : joinpath("results", "real_data_multiseed")

mkpath(OUTDIR_BASE)
if SMOKE_TEST
    println("⚠ Smoke outputs will be written to a temporary directory: ", OUTDIR_BASE)
end

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
println("  RESUMEN FINAL ($(length(SEEDS)) semillas)")
println("="^70)

for metodo in ("UDE", "SW-UDE")
    filas  = filter(r -> r.metodo == metodo, resumen)
    mu     = mean(filas.Reff_max)
    sd     = std(filas.Reff_max)
    n_sup1 = count(>(1.0), filas.Reff_max)
    println("$metodo:  Reff_max = $(round(mu, digits=3)) ± $(round(sd, digits=3))  " *
            "($n_sup1 de $(nrow(filas)) semillas superan 1)")
end

beta_min_global = minimum(resumen.beta_min)
println("\nMínimo global de β̂ en las $(2 * length(SEEDS)) corridas: " *
        "$(round(beta_min_global, digits=4))")

CSV.write("$OUTDIR_BASE/summary_multiseed.csv", resumen)
println("\n✓ Resumen guardado en $OUTDIR_BASE/summary_multiseed.csv")
println("  (columnas: seed, metodo, Reff_max, beta_min, beta_max)")