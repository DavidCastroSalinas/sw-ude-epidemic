# ============================================================
# Pasos 2-4 del flujo de datos reales: entrenar (m fijo), graficar
# (interpolación + extrapolación) y calcular RMSE de extrapolación
# por horizonte (1, 2, 3, 5, 7, 10 días a futuro).
# ============================================================
# Run from the command line with:
#     julia experiments/13_run_real_data_extrapolation_horizons.jl
#
# NOTA (21-ago-2026): m=5 y N=80851.0 son los valores OFICIALES fijos del
# caso real (los mismos que experiments/10 y 12) -- este runner YA NO lee
# results/real_data/real_data_sensitivity_m.csv ni auto-selecciona
# m con `elegir_m_automatico`. Ya no depende de que
# experiments/12_run_real_data_window_sensitivity.jl haya corrido antes (podés
# correr este runner solo). Si en algún momento querés volver a
# auto-seleccionar m a partir del barrido de experiments/12, usar
# `elegir_m_automatico` (src/lib/14_real_data_window_sensitivity.jl) sobre ese
# CSV en vez de la constante `M_FIJO` de abajo.
#
# [2026-09-07] ACTUALIZADO A PEDIDO DE DAVID: N ya NO se deriva con
# `sugerir_N` sobre la serie digitalizada con R0=0. Ahora se usa
# `construir_serie_referencia_fija` (src/lib/11_real_data.jl, sección 1bis)
# para anclar la serie a las condiciones iniciales fijas de Córdova-Lepe
# et al. 2026 (Medwave e3191) al 10 de julio de 2020: N=19.660.000,
# S0=19.348.776, I0=26.390, R0=284.834, γ=1/7. La serie resultante tiene
# 206 días, no 215. Este runner produce Exp 11 (horizontes) y Exp 12
# (rollout autónomo 43 días) -- ambos quedan afectados.
#
# Si preferís forzar otro valor de m puntualmente (sin editar el archivo),
# exportá SIR_UDE_M_OVERRIDE antes de correr, p. ej.:
#     SIR_UDE_M_OVERRIDE=20 julia experiments/13_run_real_data_extrapolation_horizons.jl
#
# Qué hace, en orden:
#   [Paso 2] Entrena Global y SW-UDE (m = M_FIJO) sobre la serie
#            real completa, con split entrenamiento/validación 80/20
#            (evaluar_datos_reales_v2, src/lib/11_real_data.jl) -- épocas
#            completas (las de SCENARIO_CONFIG[:estacional]).
#   [Paso 3] evaluar_datos_reales_v2 ya genera las figuras de
#            interpolación + extrapolación:
#              figures/real_data/real_data_I_comparison.{png,pdf,eps}
#            (línea vertical discontinua = corte train/test: a la
#            izquierda es interpolación -- el modelo vio esos días para
#            ajustar sus parámetros --, a la derecha es extrapolación --
#            el modelo jamás ajustó sus parámetros contra esos días,
#            solo continúa su propia trayectoria hacia adelante).
#   [Paso 4] rmse_extrapolacion_horizontes (src/lib/15_real_data_extrapolation_horizons.jl) mide, para cada
#            horizonte h ∈ {1,2,3,5,7,10} días, el RMSE de pronósticos
#            anclados en el estado REAL observado y propagados h días
#            hacia adelante con el modelo ya entrenado (rolling-origin
#            sobre todo el tramo de test -- ver docstring del módulo para
#            la justificación de por qué NO es un solo punto).
#
# BEFORE RUNNING: copy your CSV to data/historical_data_july_january.csv
# relative to the project root (or edit CSV_PATH below).
# ============================================================

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

# ── Cargar la serie y fijar los mismos supuestos que experiments/10 y 12 ───────
I_obs = cargar_serie_real(CSV_PATH)

GAMMA_REAL = GAMMA_REF_FIJO   # 1/7, igual que antes
resultado_ancla = construir_serie_referencia_fija(I_obs)  # usa los _REF_FIJO por defecto
SIR_real = resultado_ancla.SIR
N_REAL   = N_REF_FIJO
println("✓ N fijo (fuente de referencia): N_REAL = ", N_REAL,
        "  (antes se derivaba con sugerir_N; ya no aplica)")

# ── PASO 2: entrenar Global + SW-UDE (m=M_ELEGIDO) con split 80/20 ───────
# Arquitectura heredada del escenario :estacional (igual que experiments/10),
# con las épocas COMPLETAS (8000).
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
