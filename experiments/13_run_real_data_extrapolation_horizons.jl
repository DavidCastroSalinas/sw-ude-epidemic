# Real-data evaluation: fit with a train/test split, plot interpolation and
# extrapolation, then score rolling-origin forecasts at horizons
# {1, 2, 3, 5, 7, 10} days.
# Run with: julia experiments/13_run_real_data_extrapolation_horizons.jl
# Requires data/historical_data_july_january.csv. The default window is m=10;
# override it with SIR_UDE_M_OVERRIDE=<m>.

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

CSV_PATH = joinpath(@__DIR__, "..", "data", "historical_data_july_january.csv")
if !isfile(CSV_PATH)
    error("No se encontró $CSV_PATH -- copia el CSV a data/historical_data_july_january.csv " *
          "antes de correr este script (ver comentario al inicio del archivo).")
end

mkpath("results/real_data")

# ── m fijo (valor oficial del caso real) -- SIR_UDE_M_OVERRIDE sigue
# disponible como escape hatch puntual sin tocar este archivo. ────────────
M_FIJO = 10
M_OVERRIDE = get(ENV, "SIR_UDE_M_OVERRIDE", "")
if !isempty(M_OVERRIDE)
    M_ELEGIDO = parse(Int, M_OVERRIDE)
    println("→ SIR_UDE_M_OVERRIDE=$M_OVERRIDE -- se fuerza m=$M_ELEGIDO (en vez de M_FIJO=$M_FIJO).")
else
    M_ELEGIDO = M_FIJO
end

# ── Cargar la serie y aplicar la configuración de datos reales ─────
I_obs = cargar_serie_real(CSV_PATH)

GAMMA_REAL = GAMMA_REF_FIJO
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ N fijo (fuente de referencia): N_REAL = ", N_REAL)

# ── PASO 2: entrenar Global + SW-UDE (m=M_ELEGIDO) con split 80/20 ───────
# La configuración de arquitectura y épocas proviene del escenario real.
cfg_arq = SCENARIO_CONFIG[:realchile]

t_inicio = time()
resultado = evaluar_datos_reales_v2(SIR_real;
    N = N_REAL, γ = GAMMA_REAL,
    hidden = cfg_arq.hidden, layers = cfg_arq.layers,
    lr = cfg_arq.lr, epochs = epocas_final(cfg_arq.epochs), m = M_ELEGIDO,
    frac_train = 0.8, seed_red = 1234,
    clip_norm = cfg_arq.clip_norm,
    outdir = "results/real_data")

# ── PASO 3: ya generado por evaluar_datos_reales_v2 ────────────────────────
println("\n✓ Paso 3 (figuras de interpolación + extrapolación) ya generado en:")
println("    figures/real_data/real_data_I_comparison.{png,pdf,eps}")
println("    (línea vertical discontinua = corte train/test: izquierda = ",
         "interpolación, derecha = extrapolación)")

# ── PASO 4: RMSE de extrapolación por horizonte (1,2,3,5,7,10 días) ───────
df_horizontes = evaluar_extrapolacion_horizontes_real(resultado, SIR_real;
    hidden = cfg_arq.hidden, layers = cfg_arq.layers, seed_red = 1234,
    horizontes = [1, 2, 3, 5, 7, 10],
    outdir = "results/real_data")

println("\n✓ Listo (", formatear_duracion(time() - t_inicio), "). Resultados en results/real_data/:")
println("    metrics_extended_real_data.csv           (paso 2)")
println("    real_data_curves.csv                        (paso 2, curvas día a día)")
println("    real_data_I_comparison.{png,pdf,eps}       (paso 3: interpolación+extrapolación)")
println("    real_data_beta_comparison.{png,pdf,eps}    (paso 3: β̂ aprendida)")
println("    real_data_reff.{png,pdf,eps}                (paso 3: R_eff)")
println("    real_data_extrapolation_horizons.csv      (paso 4: RMSE por horizonte)")
println("    real_data_extrapolation_horizons.{png,pdf,eps}  (paso 4: figura)")
