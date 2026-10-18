# ============================================================
# Experimento 11 — Destilación paramétrica de beta_SW-UDE(t,I), v5.1
# ------------------------------------------------------------
# Runner de línea de comandos. Equivale a ejecutar
# experiments/29_notebook_destilacion_parametrica_v51.ipynb, pero sin
# Jupyter: fija el preámbulo que el módulo espera (OUTDIR, N_REF, GAMMA,
# U0_SIR) e incluye src/lib/29_destilacion_parametrica_v51.jl sin
# modificar una sola línea de su lógica.
#
# Uso:
#     julia --threads=auto experiments/29_run_destilacion_parametrica_v51.jl
#
# Salidas: results/destilacion_v51/*.csv  (42 archivos)
#          results/destilacion_v51/*.png  (3 figuras de control)
#
# Sustenta: tab:destilacion_parametros, tab:destilacion_I,
#           tab:destilacion_sensibilidad, fig:destilacion_beta_I,
#           fig:destilacion_plano
#
# Smoke reducido (sólo prueba el flujo, no resultados científicos):
#     SIR_UDE_DESTILACION_SMOKE=1 julia --threads=auto \
#         experiments/29_run_destilacion_parametrica_v51.jl
# En ese modo usa pocos arranques y conserva todas las salidas en OUTDIR
# temporal, sin reemplazar results/destilacion_v51/.
#
# Tiempo de pared medido: ver docs/ENTORNO.md
# ============================================================

using CSV
using DataFrames
using LinearAlgebra
using Base.Threads

const REPO   = normpath(joinpath(@__DIR__, ".."))
const DATA   = joinpath(REPO, "data", "datos_reales_curvas.csv")
const DESTINO = joinpath(REPO, "results", "destilacion_v51")

@assert isfile(DATA) "No existe $(DATA)"

# El módulo escribe en OUTDIR/destilacion_parametrica_v5_1_covid y lee
# OUTDIR/datos_reales_curvas.csv. Se le da un directorio de trabajo propio
# para no ensuciar el árbol del repositorio.
OUTDIR = mktempdir(; cleanup = false)
cp(DATA, joinpath(OUTDIR, "datos_reales_curvas.csv"))

# ── Condiciones iniciales del manuscrito (Sección 4.2, Córdova-Lepe et al.)
N_REF = 19_660_000.0
GAMMA = 1 / 7

S0 = 19_348_776.0
I0 =     26_390.0
R0 =    284_834.0

U0_SIR = Float64[S0, I0, R0]
@assert sum(U0_SIR) == N_REF "S0+I0+R0 debe ser exactamente N_REF"

println("Julia            : ", VERSION)
println("Threads          : ", Threads.nthreads())
println("BLAS threads     : ", BLAS.get_num_threads())
println("Directorio trabajo: ", OUTDIR)
if Threads.nthreads() == 1
    @warn "Un solo thread: los 50 multistarts no se paralelizarán."
end

# ── Chequeo previo de la serie ────────────────────────────────────────────
let df = CSV.read(DATA, DataFrame)
    for c in [:dia, :es_test, :I_observado, :I_UDE, :I_Windowed,
              :beta_UDE, :beta_Windowed]
        @assert c in propertynames(df) "Falta la columna $(c) en $(DATA)"
    end
    es_test = Bool.(df.es_test)
    println("TRAIN n = ", count(.!es_test), " | TEST n = ", count(es_test))
end

# ── Experimento ───────────────────────────────────────────────────────────
@time include(joinpath(REPO, "src", "lib", "29_destilacion_parametrica_v51.jl"))

# ── Recolección de salidas ────────────────────────────────────────────────
if get(ENV, "SIR_UDE_DESTILACION_SMOKE", "0") == "1"
    println("\n✓ Smoke reducido completado; salidas temporales en ", EXP_DIR)
else
    mkpath(DESTINO)
    for f in readdir(EXP_DIR)
        cp(joinpath(EXP_DIR, f), joinpath(DESTINO, f); force = true)
    end
    println("\n✓ ", length(readdir(DESTINO)), " archivos en ", DESTINO)
end
