# ============================================================
# Sensibilidad a m sobre datos reales, CON split entrenamiento/prueba -- v2
# ============================================================
# Reemplaza a experiments/15_run_real_data_window_sensitivity_split.jl SOLO en
# la grilla de m; el motor de entrenamiento, el split 80/20 y las métricas
# (RMSE_I_train / RMSE_I_test, etc.) son idénticos -- misma
# run_window_sensitivity_real_split de src/lib/18_real_data_window_sensitivity_split.jl.
#
# REVERTIDO 2026-09-05 (revisión de experimentos vs. manuscrito): entre el
# 2026-08-30 y esta revisión, la grilla pasó a generarse automáticamente
# con `generar_grilla_m(γ, Δt, T_train)`, un módulo que existió hasta el
# 2026-10-18 y se eliminó al quedar sin uso:
#
#   m_γ = ceil(1/(γ·Δt))   (τ_I en pasos temporales)
#   grilla = { ceil(m_γ/2), m_γ, 2·m_γ, 3·m_γ, ..., K·m_γ, T_train }
#
# Para γ=1/7, T_train=171 esto da m_γ=7 y una grilla de 26 múltiplos de 7
# (7,14,...,168) más el ancla 171 -- ~27 valores de m en total (con
# m=10 agregado aparte). Dos problemas confirmados al revisar esto contra
# el manuscrito: (1) NO reproduce `tab:datos_reales_sensibilidad_m`, cuya
# grilla real y ya citada es `[1, 2, 4, 7, 10, 14, 21, 35, 54, 107, 171]`
# (11 valores, sin m=1/m=2 en la grilla automática pese a que el texto los
# discute explícitamente); y (2) más del DOBLE de entrenamientos que la
# grilla real para un experimento que ya cuesta 8-10h -- optimización en
# la dirección contraria a la buscada. Además queda inconsistente con
# `experiments/22_...` (Exp 9), que sigue usando la lista manual de 11 valores
# para la resolución m=7 vs m=10. Se revierte a esa misma lista de 11
# valores (ver `M_GRID_REAL_V2` más abajo) -- Exp 8 y Exp 9 vuelven a usar
# la misma grilla, y el costo de cómputo vuelve al de antes.
#
#     julia experiments/21_run_real_data_window_sensitivity_split_v2.jl
#     SIR_UDE_SMOKE_TEST=1 julia experiments/21_...   # validación en minutos
#
# Valores oficiales (HASTA 2026-09-07): γ = 1/7, N derivado con sugerir_N,
# seed = 1234.
#
# [2026-09-07] ACTUALIZADO A PEDIDO DE DAVID: N ya NO se deriva con
# `sugerir_N` sobre la serie digitalizada con R0=0. Ahora se usa
# `construir_serie_referencia_fija` (src/lib/11_real_data.jl, sección 1bis)
# para anclar la serie a las condiciones iniciales fijas de Córdova-Lepe
# et al. 2026 (Medwave e3191) al 10 de julio de 2020: N=19.660.000,
# S0=19.348.776, I0=26.390, R0=284.834, γ=1/7. La serie resultante tiene
# 206 días (10 de julio de 2020 -- 31 de enero de 2021), NO 215 -- son
# exactamente los mismos días que usó Córdova-Lepe et al. (David,
# 2026-09-07). Esto cambia T_train (antes 171 con la serie de 215 días y
# frac_train=0.8; ahora T_train=164) -- la grilla manual `M_GRID_REAL_V2`
# de abajo se mantiene con los mismos 10 valores citados en
# `tab:datos_reales_sensibilidad_m`, pero el ANCLA final ya no es el 171
# fijo: se recalcula como `T_TRAIN_REAL` para seguir representando "todo
# el horizonte de entrenamiento en una ventana", ahora =164.
# ============================================================

include(joinpath(@__DIR__, "..", "sir_ude_lib.jl"))
using CSV   # redundante si sir_ude_lib.jl ya lo carga; no hace daño repetirlo

# Carga autosuficiente de src/lib/18 si no está en sir_ude_lib.jl
if !isdefined(Main, :run_window_sensitivity_real_split)
    ruta_lib18 = joinpath(@__DIR__, "..", "src", "lib", "18_real_data_window_sensitivity_split.jl")
    isfile(ruta_lib18) || error("Falta $ruta_lib18 -- copiá src/lib/18_... a src/lib/ antes de correr esto.")
    include(ruta_lib18)
end

CSV_PATH = joinpath(@__DIR__, "..", "data", "datos_historicos_julio_enero.csv")
isfile(CSV_PATH) || error("No se encontró $CSV_PATH")

mkpath("results/datos_reales")
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
    outdir = "results/datos_reales")

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
CSV.write("results/datos_reales/datos_reales_sensibilidad_m_split_v2.csv", df)

println("\n✓ Listo (", formatear_duracion(time() - t0), ").")
println("    results/datos_reales/datos_reales_sensibilidad_m_split.csv        (salida original)")
println("    results/datos_reales/datos_reales_sensibilidad_m_split.{png,pdf,eps}")
println("    results/datos_reales/datos_reales_TVbeta_vs_m.{png,pdf,eps}")
println("    results/datos_reales/datos_reales_sensibilidad_m_split_v2.csv     (+ es_control, es_adoptado, r_m)")
println("\n  1/γ = ", round(1 / GAMMA_REAL, digits=2), " días -- m_γ=", M_GAMMA_REAL,
        " -- controles sub-epidemiológicos: m<", M_GAMMA_REAL, " -- y es_adoptado (m=", M_ADOPTADO, ").")
println("  Elegí m contrastando RMSE_I_train (banda del 5%) con TV(β̂) y con 1/γ.")
println("  Si el m elegido NO es el que usa experiments/13_..., correlo con")
println("  SIR_UDE_M_OVERRIDE=<m> para regenerar métricas, curvas y horizontes.")
