# ============================================================
# DESTILACIÓN PARAMÉTRICA DE beta_SW-UDE(t,I) — v5.1 · FAMILIAS COVID
# ============================================================
#
# Versión ampliada para el manuscrito con familias mecanísticas orientadas a COVID-19.
#
# PRINCIPIOS METODOLÓGICOS
# ------------------------
# 1. Condiciones iniciales exactamente coherentes con el manuscrito:
#       S0 = 19_348_776
#       I0 =     26_390
#       R0 =    284_834
#       N  = 19_660_000
#
# 2. Integrador EXCLUSIVAMENTE DISCRETO:
#       Euler explícito con Δt = 1 día.
#    No se utiliza ningún solver ODE continuo.
#
# 3. Dos objetivos conceptualmente separados:
#       (a) fidelidad a beta_SW-UDE:
#           beta(t,I_SWUDE/N) ≈ beta_Windowed
#       (b) fidelidad dinámica:
#           I_SIR(t) ≈ I_observado(t)
#
#    La trayectoria autónoma usa siempre I_simulada/N dentro de beta.
#
# 4. Selección exclusivamente con TRAIN.
#    La validez de TEST jamás interviene en el ranking de selección.
#
# 5. Los controles (C1, C11, C12, C4, C5 y C6) y las familias COVID
#    (C7, C8, C9, C13 y C15) se reportan como análisis de sensibilidad
#    y NO compiten por el modelo principal.
#    La selección principal se realiza sólo entre M1 y M2.
#
# 6. Persistencia es la línea base externa de referencia.
#    Se reporta el cociente RMSE_modelo / RMSE_persistencia.
#
# 7. Se conservan los parámetros de los 10 refinamientos dinámicos
#    y se exportan tablas completas para el anexo.
#
# REQUISITOS DEL NOTEBOOK:
#   OUTDIR, N_REF, GAMMA, U0_SIR
# ============================================================

using CSV
using DataFrames
using Statistics
using Random
using Printf
using LinearAlgebra
using Optim
using Plots
using Base.Threads

@assert @isdefined(OUTDIR) "Debe existir OUTDIR."
@assert @isdefined(N_REF)  "Debe existir N_REF."
@assert @isdefined(GAMMA)  "Debe existir GAMMA."
@assert @isdefined(U0_SIR) "Debe existir U0_SIR = [S0, I0, R0]."


# ============================================================
# 1. CONFIGURACIÓN
# ============================================================

const DT = 1.0

const N_STARTS         = 50
const ALG_MAXITER      = 2500
const N_DYNAMIC_STARTS = 10
const DYN_MAXITER      = 500
const RANDOM_SEED      = 20260912

const LAMBDA_BETA = 0.50
const LAMBDA_I    = 0.50

@assert isapprox(
    LAMBDA_BETA + LAMBDA_I,
    1.0;
    atol=1e-12
)

# M1/M2 son los modelos principales.
# C1/C11/C12 son controles y análisis de sensibilidad.
# C4/C5/C6 corresponden al grupo :extendida.
# C7/C8/C9/C13/C15 corresponden al grupo :covid.
#
# En esta versión se ejecutan TODAS las familias registradas.
# La selección principal se mantiene exclusivamente entre M1 y M2;
# :control, :extendida y :covid se reportan como sensibilidad.
const GRUPOS = [:principal, :control, :extendida, :covid]

BLAS.set_num_threads(1)

const EXP_DIR = joinpath(
    OUTDIR,
    "destilacion_parametrica_v5_1_covid"
)

mkpath(EXP_DIR)

println("="^66)
println("CONFIGURACIÓN")
println("="^66)
println("Integrador       : Euler discreto")
println("Δt               : ", DT, " día")
println("Threads Julia    : ", Threads.nthreads())
println("Threads CPU      : ", Sys.CPU_THREADS)
println("Threads BLAS     : ", BLAS.get_num_threads())
println("Multistarts alg. : ", N_STARTS)
println("Refinam. dinám.  : ", N_DYNAMIC_STARTS)
println("lambda_beta      : ", LAMBDA_BETA)
println("lambda_I         : ", LAMBDA_I)
println("Grupos activos   : ", GRUPOS)
println("Salida           : ", EXP_DIR)

Threads.nthreads() == 1 &&
    @warn "Julia usa 1 thread: los multistarts no se paralelizarán."


# ============================================================
# 2. DATOS
# ============================================================

const ARCHIVO = joinpath(
    OUTDIR,
    "datos_reales_curvas.csv"
)

@assert isfile(ARCHIVO) "No existe $ARCHIVO"

df = CSV.read(
    ARCHIVO,
    DataFrame
)

for c in (
    :dia,
    :I_observado,
    :I_UDE,
    :I_Windowed,
    :beta_UDE,
    :beta_Windowed
)
    @assert c in propertynames(df) "Falta la columna $c en $ARCHIVO"
end


function col_completa(df, c::Symbol)

    v = df[!, c]

    idx = findall(
        ismissing,
        v
    )

    isempty(idx) ||
        error(
            "La columna $c tiene missing en las filas $idx."
        )

    x = Float64.(v)

    all(isfinite, x) ||
        error(
            "La columna $c tiene valores no finitos."
        )

    return x
end


tofloat_nan(x) =
    ismissing(x) ?
    NaN :
    Float64(x)


const t = col_completa(
    df,
    :dia
)

const I_obs = col_completa(
    df,
    :I_observado
)

const I_UDE = col_completa(
    df,
    :I_UDE
)

const I_SWUDE = col_completa(
    df,
    :I_Windowed
)

const beta_UDE =
    tofloat_nan.(
        df.beta_UDE
    )

const beta_obj =
    tofloat_nan.(
        df.beta_Windowed
    )

const n = length(t)

@assert issorted(t) "t debe estar ordenado."

@assert all(
    l -> l == n,
    length.(
        (
            I_obs,
            I_UDE,
            I_SWUDE,
            beta_UDE,
            beta_obj
        )
    )
)

@assert N_REF > 0
@assert GAMMA >= 0

# IMPORTANTE:
# Para la fidelidad a beta_SW-UDE se usa la trayectoria asociada
# al propio SW-UDE, no I_observado.
#
# Esto define la pareja de destilación:
#
#   (t, I_SWUDE/N) -> beta_Windowed
#
const I_beta_ref =
    I_SWUDE

const I_beta_norm =
    I_beta_ref ./ N_REF


# ============================================================
# 3. CONDICIONES INICIALES
# ============================================================

const u0 =
    Float64.(
        U0_SIR
    )

@assert length(u0) == 3 "U0_SIR debe ser [S0, I0, R0]."
@assert all(isfinite, u0)
@assert all(>=(0.0), u0)

const S0_REF_MS = 19_348_776.0
const I0_REF_MS =     26_390.0
const R0_REF_MS =    284_834.0

const U0_REF_MS = Float64[
    S0_REF_MS,
    I0_REF_MS,
    R0_REF_MS
]

println("\n", "="^66)
println("CONDICIONES INICIALES")
println("="^66)

@printf(
    "S0            = %15.2f   (manuscrito %15.2f)\n",
    u0[1],
    S0_REF_MS
)

@printf(
    "I0            = %15.2f   (manuscrito %15.2f)\n",
    u0[2],
    I0_REF_MS
)

@printf(
    "R0            = %15.2f   (manuscrito %15.2f)\n",
    u0[3],
    R0_REF_MS
)

@printf(
    "S0+I0+R0      = %15.2f   N_REF = %15.2f\n",
    sum(u0),
    N_REF
)

all(
    isapprox.(
        u0,
        U0_REF_MS;
        rtol=0.0,
        atol=0.5
    )
) || error(
    "U0_SIR no coincide con las condiciones iniciales del manuscrito. " *
    "Debe ser [19_348_776, 26_390, 284_834]."
)

isapprox(
    sum(u0),
    N_REF;
    rtol=0.0,
    atol=0.5
) || error(
    "S0 + I0 + R0 = $(sum(u0)) no coincide con N_REF = $N_REF."
)

isapprox(
    u0[2],
    I_obs[1];
    rtol=0.05
) || @warn(
    "I0 del SIR difiere >5% del primer I observado ($(I_obs[1]))."
)

println("Condiciones iniciales consistentes con el manuscrito ✓")


# ============================================================
# 4. PARTICIÓN TRAIN / TEST
# ============================================================

if :es_test in propertynames(df)

    es_test =
        Bool.(
            df.es_test
        )

    idx_train =
        findall(
            .!es_test
        )

    idx_test =
        findall(
            es_test
        )

    @assert !isempty(idx_train)
    @assert !isempty(idx_test)

    @assert maximum(idx_train) < minimum(idx_test) "es_test debe definir una partición cronológica."

    println("\nPartición tomada de la columna es_test.")

else

    ntr =
        floor(
            Int,
            0.80 * n
        )

    idx_train =
        collect(
            1:ntr
        )

    idx_test =
        collect(
            (ntr + 1):n
        )

    println("\nSin es_test: se usa 80/20 cronológico.")
end

const IDX_TRAIN = idx_train
const IDX_TEST  = idx_test

const t_train =
    t[IDX_TRAIN]

const I_train =
    I_obs[IDX_TRAIN]

const I_beta_train_norm =
    I_beta_norm[IDX_TRAIN]

const beta_train =
    beta_obj[IDX_TRAIN]

const t_test_ini =
    t[first(IDX_TEST)]

malos =
    IDX_TRAIN[
        findall(
            x -> !isfinite(x),
            beta_train
        )
    ]

isempty(malos) ||
    error(
        "beta_Windowed tiene missing/no finitos dentro de TRAIN: $malos"
    )

const PASOS =
    diff(t)

all(
    x -> isapprox(
        x,
        DT;
        atol=1e-9,
        rtol=0.0
    ),
    PASOS
) || error(
    "Euler discreto requiere una malla uniforme con Δt = $DT, " *
    "pero diff(t) va de $(minimum(PASOS)) a $(maximum(PASOS))."
)

println("Malla temporal uniforme con Δt = $DT ✓")

println(
    "N = $n | train = $(length(IDX_TRAIN)) " *
    "(t = $(t[first(IDX_TRAIN)])–$(t[last(IDX_TRAIN)]))" *
    " | test = $(length(IDX_TEST)) " *
    "(t = $(t[first(IDX_TEST)])–$(t[last(IDX_TEST)]))"
)


# ============================================================
# 5. MÉTRICAS Y PERSISTENCIA
# ============================================================

rmse(y, yhat) =
    sqrt(
        mean(
            (y .- yhat).^2
        )
    )

mae(y, yhat) =
    mean(
        abs.(
            y .- yhat
        )
    )


function r2_score(
    y,
    yhat
)

    sst =
        sum(
            (y .- mean(y)).^2
        )

    return sst <= eps(Float64) ?
        NaN :
        1 - sum(
            (y .- yhat).^2
        ) / sst
end


function metricas(
    obs,
    pred,
    idx
)

    v = [
        k for k in idx
        if isfinite(obs[k]) &&
           isfinite(pred[k])
    ]

    isempty(v) &&
        return (
            rmse=NaN,
            mae=NaN,
            r2=NaN,
            n=0
        )

    y =
        obs[v]

    yhat =
        pred[v]

    return (
        rmse=rmse(y, yhat),
        mae=mae(y, yhat),
        r2=r2_score(y, yhat),
        n=length(v)
    )
end


const I_PERS_VAL =
    I_obs[
        last(IDX_TRAIN)
    ]

const BETA_PERS_VAL =
    beta_obj[
        last(IDX_TRAIN)
    ]

const RMSE_I_PERS =
    rmse(
        I_obs[IDX_TEST],
        fill(
            I_PERS_VAL,
            length(IDX_TEST)
        )
    )

const idx_beta_test = [
    k for k in IDX_TEST
    if isfinite(
        beta_obj[k]
    )
]

const RMSE_BETA_PERS =
    rmse(
        beta_obj[idx_beta_test],
        fill(
            BETA_PERS_VAL,
            length(idx_beta_test)
        )
    )

const MAE_I_PERS =
    mae(
        I_obs[IDX_TEST],
        fill(
            I_PERS_VAL,
            length(IDX_TEST)
        )
    )

const R2_I_PERS =
    r2_score(
        I_obs[IDX_TEST],
        fill(
            I_PERS_VAL,
            length(IDX_TEST)
        )
    )

println("\n", "="^66)
println("LÍNEAS BASE DE PERSISTENCIA")
println("="^66)

@printf(
    "I(t) ≡ I(%.0f) = %.0f | RMSE = %.1f | MAE = %.1f | R² = %+.4f\n",
    t[last(IDX_TRAIN)],
    I_PERS_VAL,
    RMSE_I_PERS,
    MAE_I_PERS,
    R2_I_PERS
)

@printf(
    "β(t) ≡ β(%.0f) = %.6f | RMSE = %.8f\n",
    t[last(IDX_TRAIN)],
    BETA_PERS_VAL,
    RMSE_BETA_PERS
)


# ============================================================
# 6. INTEGRADOR DISCRETO
# ============================================================

"""
    simular_euler(fbeta, p, tvec, u0_local;
                  dt=DT,
                  exigir_beta_positiva=true,
                  exigir_estados_no_negativos=true)

Mapa SIR discreto de Euler explícito:

    S[k+1] = S[k] - β(t[k], I[k]/N) S[k] I[k]/N Δt
    I[k+1] = I[k] + β(t[k], I[k]/N) S[k] I[k]/N Δt - γ I[k] Δt
    R[k+1] = R[k] + γ I[k] Δt

β se evalúa SIEMPRE sobre I[k] simulada.

Durante TRAIN/optimización:
    exigir_beta_positiva = true
    exigir_estados_no_negativos = true

Para evaluación final:
    ambas condiciones pueden relajarse para que la trayectoria se reporte
    y la validez de TEST se evalúe por separado, sin contaminar la selección.

Siempre se rechazan trayectorias no finitas.
"""
function simular_euler(
    fbeta,
    p,
    tvec,
    u0_local;
    dt=DT,
    exigir_beta_positiva::Bool=true,
    exigir_estados_no_negativos::Bool=true
)

    m =
        length(
            tvec
        )

    m >= 2 ||
        return nothing

    U =
        Array{Float64}(
            undef,
            3,
            m
        )

    S =
        Float64(
            u0_local[1]
        )

    I =
        Float64(
            u0_local[2]
        )

    R =
        Float64(
            u0_local[3]
        )

    U[1, 1] = S
    U[2, 1] = I
    U[3, 1] = R

    @inbounds for k in 1:(m - 1)

        h =
            tvec[k + 1] -
            tvec[k]

        isfinite(h) ||
            return nothing

        isapprox(
            h,
            dt;
            atol=1e-9,
            rtol=0.0
        ) || return nothing

        b =
            fbeta(
                p,
                tvec[k],
                I / N_REF
            )

        isfinite(b) ||
            return nothing

        if exigir_beta_positiva &&
           b <= 0.0

            return nothing
        end

        inc =
            b *
            S *
            I /
            N_REF *
            dt

        rec =
            GAMMA *
            I *
            dt

        S_new =
            S -
            inc

        I_new =
            I +
            inc -
            rec

        R_new =
            R +
            rec

        (
            isfinite(S_new) &&
            isfinite(I_new) &&
            isfinite(R_new)
        ) || return nothing

        if exigir_estados_no_negativos &&
           (
               S_new < -1e-6 ||
               I_new < -1e-6 ||
               R_new < -1e-6
           )

            return nothing
        end

        S = S_new
        I = I_new
        R = R_new

        U[1, k + 1] = S
        U[2, k + 1] = I
        U[3, k + 1] = R
    end

    return U
end


simular_SIR(
    fbeta,
    p,
    tvec,
    u0_local;
    exigir_beta_positiva::Bool=true,
    exigir_estados_no_negativos::Bool=true
) =
    simular_euler(
        fbeta,
        p,
        tvec,
        u0_local;
        dt=DT,
        exigir_beta_positiva=exigir_beta_positiva,
        exigir_estados_no_negativos=exigir_estados_no_negativos
    )


# ============================================================
# 7. REGISTRO DE FAMILIAS
# ============================================================

sigmoide(x) =
    1 /
    (
        1 +
        exp(
            -clamp(
                x,
                -40.0,
                40.0
            )
        )
    )

const DUR_TRAIN =
    t[last(IDX_TRAIN)] -
    t[first(IDX_TRAIN)]

const PERIODO_MIN =
    30.0

# El período libre debe caber al menos una vez dentro de TRAIN.
const PERIODO_MAX =
    DUR_TRAIN

@assert PERIODO_MAX > PERIODO_MIN

const OMEGA_MIN =
    2π /
    PERIODO_MAX

const OMEGA_MAX =
    2π /
    PERIODO_MIN

# Frecuencia anual fija para el control estacional C13.
const OMEGA_ANUAL =
    2π /
    365.0

# Control lento:
# período entre 2× y 10× la ventana de TRAIN,
# de modo que el seno sólo puede representar una variación lenta.
const OMEGA_MIN_LENTO =
    2π /
    (
        10 *
        DUR_TRAIN
    )

const OMEGA_MAX_LENTO =
    2π /
    (
        2 *
        DUR_TRAIN
    )

@printf(
    "\nPeríodo M1/M2 admisible : %.1f – %.1f días\n",
    PERIODO_MIN,
    PERIODO_MAX
)

@printf(
    "Control C11             : %.1f – %.1f días\n",
    2 * DUR_TRAIN,
    10 * DUR_TRAIN
)


struct Familia
    clave::String
    etiqueta::String
    f::Function
    pars::Vector{String}
    lower::Vector{Float64}
    upper::Vector{Float64}
    inicios::Vector{Vector{Float64}}
    grupo::Symbol
end


const B0_LO = 0.0
const B0_HI = 0.50

const B_LO =
    -3e-3

const B_HI =
     3e-3

const A_LO = 0.0
const A_HI = 0.30

const W2_LO = 0.0
const W2_HI = 300.0

beta_media =
    clamp(
        mean(beta_train),
        B0_LO + 1e-6,
        B0_HI - 1e-6
    )

FAMILIAS =
    Familia[]


# ------------------------------------------------------------
# M1 — principal
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "M1",
        "β₀ + b·t + A·sin(ωt+φ)",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt +
            p[3] *
            sin(
                p[4] * tt +
                p[5]
            ),
        [
            "β₀",
            "b",
            "A",
            "ω",
            "φ"
        ],
        [
            B0_LO,
            B_LO,
            A_LO,
            OMEGA_MIN,
            -π
        ],
        [
            B0_HI,
            B_HI,
            A_HI,
            OMEGA_MAX,
            π
        ],
        [
            [
                beta_media,
                0.0,
                0.020,
                OMEGA_MIN,
                0.0
            ],
            [
                beta_media,
                3e-4,
                0.015,
                2π /
                min(
                    159.0,
                    PERIODO_MAX
                ),
                0.0
            ]
        ],
        :principal
    )
)


# ------------------------------------------------------------
# M2 — principal
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "M2",
        "M1 − w₂·(I/N)",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt +
            p[3] *
            sin(
                p[4] * tt +
                p[5]
            ) -
            p[6] * In,
        [
            "β₀",
            "b",
            "A",
            "ω",
            "φ",
            "w₂"
        ],
        [
            B0_LO,
            B_LO,
            A_LO,
            OMEGA_MIN,
            -π,
            W2_LO
        ],
        [
            B0_HI,
            B_HI,
            A_HI,
            OMEGA_MAX,
            π,
            W2_HI
        ],
        [
            [
                beta_media,
                0.0,
                0.020,
                OMEGA_MIN,
                0.0,
                10.0
            ],
            [
                beta_media,
                3e-4,
                0.015,
                2π /
                min(
                    159.0,
                    PERIODO_MAX
                ),
                0.0,
                13.0
            ]
        ],
        :principal
    )
)


# ------------------------------------------------------------
# C12 — control:
# transición logística temporal + feedback
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C12",
        "β₀ + (β₂−β₀)·σ(k(t−t₀)) − w₂·(I/N)",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            (
                p[2] -
                p[1]
            ) *
            sigmoide(
                p[3] *
                (
                    tt -
                    p[4]
                )
            ) -
            p[5] * In,
        [
            "β₀",
            "β₂",
            "k",
            "t₀",
            "w₂"
        ],
        [
            B0_LO,
            B0_LO,
            0.0,
            t[first(IDX_TRAIN)],
            W2_LO
        ],
        [
            B0_HI,
            B0_HI,
            1.0,
            t[last(IDX_TRAIN)],
            W2_HI
        ],
        [
            [
                0.176,
                0.212,
                0.51,
                0.94 * DUR_TRAIN,
                46.0
            ],
            [
                beta_media,
                beta_media * 1.2,
                0.20,
                0.60 * DUR_TRAIN,
                20.0
            ]
        ],
        :control
    )
)


# ------------------------------------------------------------
# C11 — control de periodicidad lenta
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C11",
        "M2 con período entre 2× y 10× TRAIN",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt +
            p[3] *
            sin(
                p[4] * tt +
                p[5]
            ) -
            p[6] * In,
        [
            "β₀",
            "b",
            "A",
            "ω",
            "φ",
            "w₂"
        ],
        [
            B0_LO,
            B_LO,
            A_LO,
            OMEGA_MIN_LENTO,
            -π,
            W2_LO
        ],
        [
            B0_HI,
            B_HI,
            A_HI,
            OMEGA_MAX_LENTO,
            π,
            W2_HI
        ],
        [
            [
                beta_media,
                3e-4,
                0.015,
                OMEGA_MAX_LENTO,
                0.0,
                13.0
            ]
        ],
        :control
    )
)


# ------------------------------------------------------------
# C1 — control parsimonioso
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C1",
        "β₀ + b·t",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt,
        [
            "β₀",
            "b"
        ],
        [
            B0_LO,
            B_LO
        ],
        [
            B0_HI,
            B_HI
        ],
        [
            [
                beta_media,
                3e-4
            ]
        ],
        :control
    )
)


# ------------------------------------------------------------
# Formas conductuales opcionales
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C4",
        "(β₀+b·t)/(1+κ·I/N)",
        (
            p,
            tt,
            In
        ) ->
            (
                p[1] +
                p[2] * tt
            ) /
            (
                1 +
                p[3] * In
            ),
        [
            "β₀",
            "b",
            "κ"
        ],
        [
            B0_LO,
            B_LO,
            0.0
        ],
        [
            B0_HI,
            B_HI,
            5000.0
        ],
        [
            [
                beta_media,
                3e-4,
                100.0
            ]
        ],
        :extendida
    )
)

push!(
    FAMILIAS,
    Familia(
        "C5",
        "(β₀+b·t)·exp(−κ·I/N)",
        (
            p,
            tt,
            In
        ) ->
            (
                p[1] +
                p[2] * tt
            ) *
            exp(
                -clamp(
                    p[3] * In,
                    -40.0,
                    40.0
                )
            ),
        [
            "β₀",
            "b",
            "κ"
        ],
        [
            B0_LO,
            B_LO,
            0.0
        ],
        [
            B0_HI,
            B_HI,
            5000.0
        ],
        [
            [
                beta_media,
                3e-4,
                100.0
            ]
        ],
        :extendida
    )
)

push!(
    FAMILIAS,
    Familia(
        "C6",
        "β₀+b·t − Δ·σ(k(I/N − I_c))",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt -
            p[3] *
            sigmoide(
                p[4] *
                (
                    In -
                    p[5]
                )
            ),
        [
            "β₀",
            "b",
            "Δ",
            "k",
            "I_c"
        ],
        [
            B0_LO,
            B_LO,
            0.0,
            0.0,
            0.0
        ],
        [
            B0_HI,
            B_HI,
            0.30,
            20000.0,
            4e-3
        ],
        [
            [
                beta_media,
                3e-4,
                0.02,
                5000.0,
                1.5e-3
            ]
        ],
        :extendida
    )
)



# ============================================================
# FAMILIAS ADICIONALES ORIENTADAS A COVID-19
# ============================================================
#
# Estas familias no compiten por la selección principal M1/M2.
# Se incluyen como experimentos de sensibilidad mecanística.
#
# C7  : feedback no lineal tipo Hill racional
# C8  : reducción máxima saturante tipo Hill
# C9  : intervención temprana + relajación tardía + feedback
# C13 : estacionalidad anual fija + feedback
# C15 : link exponencial; beta positiva por construcción
# ============================================================


# ------------------------------------------------------------
# C7 — feedback Hill racional
#
# β = (β₀+b·t) / (1 + κ·(I/N)^h)
#
# h permite pasar desde una respuesta suave/sublineal hasta
# una respuesta más abrupta. La potencia se calcula en forma
# estable para prevalencias pequeñas.
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C7",
        "(β₀+b·t)/(1+κ·(I/N)^h)",
        (
            p,
            tt,
            In
        ) -> begin

            Ih =
                In <= 0.0 ?
                0.0 :
                exp(
                    clamp(
                        p[4] * log(In),
                        -40.0,
                        40.0
                    )
                )

            return (
                p[1] +
                p[2] * tt
            ) /
            (
                1.0 +
                p[3] * Ih
            )
        end,
        [
            "β₀",
            "b",
            "κ",
            "h"
        ],
        [
            B0_LO,
            B_LO,
            0.0,
            0.5
        ],
        [
            B0_HI,
            B_HI,
            2.0e5,
            2.0
        ],
        [
            [
                beta_media,
                3e-4,
                100.0,
                1.0
            ],
            [
                beta_media,
                3e-4,
                5.0e4,
                2.0
            ],
            [
                beta_media,
                3e-4,
                10.0,
                0.5
            ]
        ],
        :covid
    )
)


# ------------------------------------------------------------
# C8 — respuesta Hill saturante
#
# β = β₀+b·t − Δ·(I/N)^h / (K^h + (I/N)^h)
#
# K es la prevalencia aproximada en que se alcanza el 50 %
# de la reducción máxima Δ.
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C8",
        "β₀+b·t − Δ·(I/N)^h/(K^h+(I/N)^h)",
        (
            p,
            tt,
            In
        ) -> begin

            Ih =
                In <= 0.0 ?
                0.0 :
                exp(
                    clamp(
                        p[5] * log(In),
                        -40.0,
                        40.0
                    )
                )

            Kh =
                exp(
                    clamp(
                        p[5] * log(p[4]),
                        -40.0,
                        40.0
                    )
                )

            frac =
                Ih /
                max(
                    Kh + Ih,
                    1e-15
                )

            return (
                p[1] +
                p[2] * tt -
                p[3] * frac
            )
        end,
        [
            "β₀",
            "b",
            "Δ",
            "K",
            "h"
        ],
        [
            B0_LO,
            B_LO,
            0.0,
            1e-5,
            0.5
        ],
        [
            B0_HI,
            B_HI,
            0.30,
            1e-2,
            5.0
        ],
        [
            [
                beta_media,
                3e-4,
                0.02,
                1.5e-3,
                2.0
            ],
            [
                beta_media,
                3e-4,
                0.04,
                1.0e-3,
                1.0
            ]
        ],
        :covid
    )
)


# ------------------------------------------------------------
# C9 — intervención + relajación + feedback
#
# β = β₀+b·t
#     − Δ₁ σ(k₁(t−t₁))
#     + Δ₂ σ(k₂(t−t₂))
#     − w₂ I/N
#
# Para reducir permutaciones no identificables, t₁ se restringe
# a la primera mitad de TRAIN y t₂ a la segunda mitad.
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C9",
        "β₀+b·t − Δ₁σ(k₁(t−t₁)) + Δ₂σ(k₂(t−t₂)) − w₂·(I/N)",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt -
            p[3] *
            sigmoide(
                p[4] *
                (
                    tt -
                    p[5]
                )
            ) +
            p[6] *
            sigmoide(
                p[7] *
                (
                    tt -
                    p[8]
                )
            ) -
            p[9] * In,
        [
            "β₀",
            "b",
            "Δ₁",
            "k₁",
            "t₁",
            "Δ₂",
            "k₂",
            "t₂",
            "w₂"
        ],
        [
            B0_LO,
            B_LO,
            0.0,
            0.0,
            t[first(IDX_TRAIN)],
            0.0,
            0.0,
            t[first(IDX_TRAIN)] + 0.50 * DUR_TRAIN,
            W2_LO
        ],
        [
            B0_HI,
            B_HI,
            0.30,
            1.0,
            t[first(IDX_TRAIN)] + 0.50 * DUR_TRAIN,
            0.30,
            1.0,
            t[last(IDX_TRAIN)],
            W2_HI
        ],
        [
            [
                0.18,
                2e-4,
                0.04,
                0.15,
                0.25 * DUR_TRAIN,
                0.04,
                0.15,
                0.75 * DUR_TRAIN,
                15.0
            ],
            [
                beta_media,
                3e-4,
                0.02,
                0.08,
                0.35 * DUR_TRAIN,
                0.02,
                0.08,
                0.70 * DUR_TRAIN,
                10.0
            ]
        ],
        :covid
    )
)


# ------------------------------------------------------------
# C13 — estacionalidad anual fija + feedback
#
# β = β₀+b·t + A sin(2πt/365 + φ) − w₂ I/N
#
# Fijar la frecuencia evita intentar identificar un período anual
# a partir de una ventana TRAIN más corta que un año.
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C13",
        "β₀+b·t + A·sin(2πt/365+φ) − w₂·(I/N)",
        (
            p,
            tt,
            In
        ) ->
            p[1] +
            p[2] * tt +
            p[3] *
            sin(
                OMEGA_ANUAL * tt +
                p[4]
            ) -
            p[5] * In,
        [
            "β₀",
            "b",
            "A",
            "φ",
            "w₂"
        ],
        [
            B0_LO,
            B_LO,
            A_LO,
            -π,
            W2_LO
        ],
        [
            B0_HI,
            B_HI,
            A_HI,
            π,
            W2_HI
        ],
        [
            [
                beta_media,
                3e-4,
                0.015,
                0.0,
                13.0
            ],
            [
                beta_media,
                2e-4,
                0.03,
                π / 2,
                20.0
            ]
        ],
        :covid
    )
)


# ------------------------------------------------------------
# C15 — link exponencial positivo
#
# β = exp(η₀ + η₁ t + A sin(ωt+φ) − κ I/N)
#
# Esta parametrización garantiza beta > 0 por construcción.
# El argumento del exponencial se limita sólo por estabilidad
# numérica; con las cotas utilizadas normalmente no se alcanza
# dicho límite.
# ------------------------------------------------------------

push!(
    FAMILIAS,
    Familia(
        "C15",
        "exp(η₀+η₁·t+A·sin(ωt+φ)−κ·I/N)",
        (
            p,
            tt,
            In
        ) ->
            exp(
                clamp(
                    p[1] +
                    p[2] * tt +
                    p[3] *
                    sin(
                        p[4] * tt +
                        p[5]
                    ) -
                    p[6] * In,
                    -40.0,
                    40.0
                )
            ),
        [
            "η₀",
            "η₁",
            "A",
            "ω",
            "φ",
            "κ"
        ],
        [
            -5.0,
            -1e-2,
            0.0,
            OMEGA_MIN,
            -π,
            0.0
        ],
        [
            -0.5,
            1e-2,
            1.0,
            OMEGA_MAX,
            π,
            1000.0
        ],
        [
            [
                log(max(beta_media, 1e-6)),
                2e-3,
                0.08,
                OMEGA_MIN,
                0.0,
                100.0
            ],
            [
                log(max(beta_media, 1e-6)),
                1e-3,
                0.05,
                2π /
                min(
                    120.0,
                    PERIODO_MAX
                ),
                0.0,
                50.0
            ]
        ],
        :covid
    )
)



const ACTIVAS = [
    fam
    for fam in FAMILIAS
    if fam.grupo in GRUPOS
]

# Número máximo de parámetros entre todas las familias registradas.
# Se utiliza sólo para exportación tabular y evita asumir una
# dimensión fija (por ejemplo, 6 parámetros).
const MAX_PARAMETROS_FAMILIA =
    maximum(
        length(fam.pars)
        for fam in FAMILIAS
    )

println(
    "Máximo número de parámetros por familia: ",
    MAX_PARAMETROS_FAMILIA
)

println(
    "\nFamilias activas: ",
    join(
        [
            "$(f.clave)[$(f.grupo)]"
            for f in ACTIVAS
        ],
        ", "
    )
)


# ============================================================
# 8. OBJETIVOS
# ============================================================

function objetivo_beta(
    fam::Familia,
    p,
    tvec,
    In_beta_ref,
    bobj
)

    sse =
        0.0

    bmin =
        Inf

    @inbounds for k in eachindex(tvec)

        pred =
            fam.f(
                p,
                tvec[k],
                In_beta_ref[k]
            )

        isfinite(pred) ||
            return 1e12

        bmin =
            min(
                bmin,
                pred
            )

        d =
            pred -
            bobj[k]

        sse +=
            d * d
    end

    bmin <= 0.0 &&
        return (
            1e6 +
            1e6 *
            abs(bmin)
        )

    return sse /
           length(tvec)
end


function objetivo_dinamico(
    fam::Familia,
    p,
    tvec,
    Iobj,
    In_beta_ref,
    bobj,
    u0_local
)

    # --------------------------------------------------------
    # 1. Fidelidad a beta_SW-UDE sobre la trayectoria SW-UDE
    # --------------------------------------------------------

    bpred = [
        fam.f(
            p,
            tvec[k],
            In_beta_ref[k]
        )
        for k in eachindex(tvec)
    ]

    any(
        x ->
            !isfinite(x) ||
            x <= 0.0,
        bpred
    ) && return 1e12

    loss_b =
        mean(
            (bpred .- bobj).^2
        ) /
        max(
            var(bobj),
            1e-12
        )

    # --------------------------------------------------------
    # 2. Dinámica autónoma contra I_observado
    # --------------------------------------------------------

    U =
        simular_SIR(
            fam.f,
            p,
            tvec,
            u0_local;
            exigir_beta_positiva=true,
            exigir_estados_no_negativos=true
        )

    U === nothing &&
        return 1e12

    Ipred =
        vec(
            U[2, :]
        )

    any(
        x ->
            !isfinite(x) ||
            x < 0.0,
        Ipred
    ) && return 1e12

    @inbounds for k in eachindex(tvec)

        bs =
            fam.f(
                p,
                tvec[k],
                Ipred[k] /
                N_REF
            )

        (
            isfinite(bs) &&
            bs > 0.0
        ) || return 1e12
    end

    loss_I =
        mean(
            (Ipred .- Iobj).^2
        ) /
        max(
            var(Iobj),
            1e-12
        )

    return (
        LAMBDA_BETA * loss_b +
        LAMBDA_I    * loss_I
    )
end


# ============================================================
# 9. MULTISTART
# ============================================================

function al_interior(
    p,
    lo,
    hi
)

    e =
        1e-8 .*
        max.(
            hi .- lo,
            1.0
        )

    return clamp.(
        p,
        lo .+ e,
        hi .- e
    )
end


function generar_inicios(
    fam::Familia,
    nstarts,
    seed
)

    rng =
        MersenneTwister(
            seed
        )

    starts =
        Vector{
            Vector{Float64}
        }()

    for p in fam.inicios

        length(p) ==
        length(fam.lower) &&
            push!(
                starts,
                al_interior(
                    Float64.(p),
                    fam.lower,
                    fam.upper
                )
            )
    end

    push!(
        starts,
        al_interior(
            (
                fam.lower .+
                fam.upper
            ) ./ 2,
            fam.lower,
            fam.upper
        )
    )

    while length(starts) < nstarts

        r =
            rand(
                rng,
                length(fam.lower)
            )

        push!(
            starts,
            al_interior(
                fam.lower .+
                r .*
                (
                    fam.upper .-
                    fam.lower
                ),
                fam.lower,
                fam.upper
            )
        )
    end

    return starts[
        1:nstarts
    ]
end


function correr_multistart(
    fam::Familia,
    f,
    inicios,
    maxiter,
    outer,
    etapa
)

    m =
        length(
            inicios
        )

    losses =
        fill(
            Inf,
            m
        )

    convergio =
        fill(
            false,
            m
        )

    thread_id =
        zeros(
            Int,
            m
        )

    params =
        Vector{
            Union{
                Nothing,
                Vector{Float64}
            }
        }(
            undef,
            m
        )

    fill!(
        params,
        nothing
    )

    println("\n", "-"^66)
    println("$etapa — $(fam.clave): $(fam.etiqueta)")
    println("-"^66)
    println(
        "arranques: $m | threads: ",
        Threads.nthreads()
    )

    Threads.@threads for j in 1:m

        thread_id[j] =
            Threads.threadid()

        try

            res =
                optimize(
                    f,
                    fam.lower,
                    fam.upper,
                    inicios[j],
                    Fminbox(
                        LBFGS()
                    ),
                    Optim.Options(
                        iterations=maxiter,
                        outer_iterations=outer,
                        show_trace=false,
                        store_trace=false
                    )
                )

            L =
                Optim.minimum(
                    res
                )

            po =
                Float64.(
                    Optim.minimizer(
                        res
                    )
                )

            if isfinite(L) &&
               all(isfinite, po)

                losses[j] =
                    L

                params[j] =
                    copy(po)

                convergio[j] =
                    Optim.converged(
                        res
                    )
            end

        catch err

            @warn(
                "Falló $(fam.clave), arranque $j, etapa $etapa",
                exception=(
                    err,
                    catch_backtrace()
                )
            )

            losses[j] =
                Inf

            params[j] =
                nothing

            convergio[j] =
                false
        end
    end

    validos = [
        j for j in 1:m
        if isfinite(losses[j]) &&
           params[j] !== nothing
    ]

    isempty(validos) &&
        return (
            nothing,
            nothing,
            losses,
            params
        )

    mejor =
        validos[
            argmin(
                losses[validos]
            )
        ]

    tabla =
        DataFrame(
            arranque=collect(1:m),
            thread=thread_id,
            loss=losses,
            convergio=convergio
        )

    sort!(
        tabla,
        :loss
    )

    @printf(
        "mejor arranque %d | loss = %.10e\n",
        mejor,
        losses[mejor]
    )

    return (
        copy(
            params[mejor]::Vector{Float64}
        ),
        tabla,
        losses,
        params
    )
end


# ============================================================
# 10. EVALUACIÓN COMPLETA DE UN CONJUNTO DE PARÁMETROS
# ============================================================

function validez_segmento(
    U,
    beta_sir,
    idx
)

    U === nothing &&
        return false

    isempty(idx) &&
        return false

    return (
        all(
            isfinite,
            U[:, idx]
        )
        &&
        all(
            U[:, idx] .>= -1e-6
        )
        &&
        all(
            isfinite,
            beta_sir[idx]
        )
        &&
        all(
            beta_sir[idx] .> 0.0
        )
    )
end


function evaluar_parametros(
    fam::Familia,
    p
)

    # --------------------------------------------------------
    # beta para evaluar fidelidad al SW-UDE:
    # se evalúa sobre I_SWUDE/N.
    # --------------------------------------------------------

    beta_fit = [
        fam.f(
            p,
            t[k],
            I_beta_norm[k]
        )
        for k in eachindex(t)
    ]

    mb_tr =
        metricas(
            beta_obj,
            beta_fit,
            IDX_TRAIN
        )

    mb_te =
        metricas(
            beta_obj,
            beta_fit,
            IDX_TEST
        )

    beta_ref_valida_train =
        all(
            isfinite,
            beta_fit[IDX_TRAIN]
        ) &&
        all(
            beta_fit[IDX_TRAIN] .> 0.0
        )

    beta_ref_valida_test =
        all(
            isfinite,
            beta_fit[IDX_TEST]
        ) &&
        all(
            beta_fit[IDX_TEST] .> 0.0
        )

    # --------------------------------------------------------
    # TRAIN autónomo:
    # esta validez es la ÚNICA que puede intervenir en selección.
    # --------------------------------------------------------

    U_train =
        simular_SIR(
            fam.f,
            p,
            t_train,
            u0;
            exigir_beta_positiva=true,
            exigir_estados_no_negativos=true
        )

    valido_train =
        false

    I_train_fit =
        fill(
            NaN,
            length(IDX_TRAIN)
        )

    beta_sir_train =
        fill(
            NaN,
            length(IDX_TRAIN)
        )

    if U_train !== nothing

        I_train_fit .=
            vec(
                U_train[2, :]
            )

        beta_sir_train .= [
            fam.f(
                p,
                t_train[k],
                I_train_fit[k] /
                N_REF
            )
            for k in eachindex(t_train)
        ]

        valido_train =
            all(
                isfinite,
                U_train
            ) &&
            all(
                U_train .>= -1e-6
            ) &&
            all(
                isfinite,
                beta_sir_train
            ) &&
            all(
                beta_sir_train .> 0.0
            ) &&
            beta_ref_valida_train
    end

    # --------------------------------------------------------
    # Serie completa:
    # se permite beta/estado negativo para poder REPORTAR
    # la falla en TEST sin excluir la familia del ranking TRAIN.
    # --------------------------------------------------------

    U_full =
        simular_SIR(
            fam.f,
            p,
            t,
            u0;
            exigir_beta_positiva=false,
            exigir_estados_no_negativos=false
        )

    I_fit =
        fill(
            NaN,
            n
        )

    beta_sir =
        fill(
            NaN,
            n
        )

    if U_full !== nothing

        I_fit .=
            vec(
                U_full[2, :]
            )

        beta_sir .= [
            fam.f(
                p,
                t[k],
                I_fit[k] /
                N_REF
            )
            for k in eachindex(t)
        ]

    else

        # Aunque TEST haya producido no-finitos,
        # se conservan los valores válidos de TRAIN.
        I_fit[IDX_TRAIN] .=
            I_train_fit

        beta_sir[IDX_TRAIN] .=
            beta_sir_train
    end

    valido_test =
        valido_train &&
        beta_ref_valida_test &&
        validez_segmento(
            U_full,
            beta_sir,
            IDX_TEST
        )

    mI_tr =
        metricas(
            I_obs,
            I_fit,
            IDX_TRAIN
        )

    mI_te =
        metricas(
            I_obs,
            I_fit,
            IDX_TEST
        )

    coc_beta_pers =
        isfinite(mb_te.rmse) &&
        RMSE_BETA_PERS > 0 ?
        mb_te.rmse /
        RMSE_BETA_PERS :
        NaN

    coc_I_pers =
        isfinite(mI_te.rmse) &&
        RMSE_I_PERS > 0 ?
        mI_te.rmse /
        RMSE_I_PERS :
        NaN

    return (
        beta_fit=beta_fit,
        beta_sir=beta_sir,
        I_fit=I_fit,

        mb_tr=mb_tr,
        mb_te=mb_te,
        mI_tr=mI_tr,
        mI_te=mI_te,

        valido_train=valido_train,
        valido_test=valido_test,
        beta_ref_valida_train=beta_ref_valida_train,
        beta_ref_valida_test=beta_ref_valida_test,

        coc_beta_pers=coc_beta_pers,
        coc_I_pers=coc_I_pers
    )
end


# ============================================================
# 11. FORMATO DE ECUACIONES
# ============================================================

function ecuacion_texto(
    fam::Familia,
    p
)

    if fam.clave == "M1"

        return @sprintf(
            "beta(t) = %.12f %+.12f*t + %.12f*sin(%.12f*t %+.12f)",
            p[1],
            p[2],
            p[3],
            p[4],
            p[5]
        )

    elseif fam.clave in (
        "M2",
        "C11"
    )

        return @sprintf(
            "beta(t,I) = %.12f %+.12f*t + %.12f*sin(%.12f*t %+.12f) - %.12f*(I/N)",
            p[1],
            p[2],
            p[3],
            p[4],
            p[5],
            p[6]
        )

    elseif fam.clave == "C1"

        return @sprintf(
            "beta(t) = %.12f %+.12f*t",
            p[1],
            p[2]
        )

    else

        return string(
            fam.etiqueta,
            " | ",
            join(
                [
                    @sprintf(
                        "%s=%.12g",
                        fam.pars[i],
                        p[i]
                    )
                    for i in eachindex(p)
                ],
                ", "
            )
        )
    end
end


# ============================================================
# 12. AJUSTE DE TODAS LAS FAMILIAS
# ============================================================

filas_res =
    NamedTuple[]

ajustes =
    Dict{
        String,
        Any
    }()


for (
    ifam,
    fam
) in enumerate(ACTIVAS)

    seed_fam =
        RANDOM_SEED +
        1000 *
        (
            ifam -
            1
        )

    # --------------------------------------------------------
    # Etapa 1: algebraica
    # --------------------------------------------------------

    f_alg =
        p ->
            objetivo_beta(
                fam,
                p,
                t_train,
                I_beta_train_norm,
                beta_train
            )

    p_alg,
    tabla_alg,
    losses_alg,
    params_alg =
        correr_multistart(
            fam,
            f_alg,
            generar_inicios(
                fam,
                N_STARTS,
                seed_fam
            ),
            ALG_MAXITER,
            20,
            "ETAPA 1 · algebraica"
        )

    if p_alg === nothing

        @warn(
            "Sin ajuste algebraico válido para $(fam.clave)"
        )

        continue
    end

    orden =
        sortperm(
            losses_alg
        )

    idx_cand = [
        j
        for j in orden
        if isfinite(losses_alg[j]) &&
           params_alg[j] !== nothing
    ]

    idx_cand =
        idx_cand[
            1:min(
                N_DYNAMIC_STARTS,
                length(idx_cand)
            )
        ]

    cand = [
        copy(
            params_alg[j]::Vector{Float64}
        )
        for j in idx_cand
    ]

    # --------------------------------------------------------
    # Etapa 2: dinámica
    # --------------------------------------------------------

    f_dyn =
        p ->
            objetivo_dinamico(
                fam,
                p,
                t_train,
                I_train,
                I_beta_train_norm,
                beta_train,
                u0
            )

    p_fin,
    tabla_dyn,
    losses_dyn,
    params_dyn =
        correr_multistart(
            fam,
            f_dyn,
            cand,
            DYN_MAXITER,
            15,
            "ETAPA 2 · dinámica"
        )

    if p_fin === nothing

        @warn(
            "Sin refinamiento dinámico válido para $(fam.clave)"
        )

        continue
    end

    L_fin =
        minimum(
            filter(
                isfinite,
                losses_dyn
            )
        )

    eval_fin =
        evaluar_parametros(
            fam,
            p_fin
        )

    # IMPORTANTE:
    # sólo la validez de TRAIN puede excluir un modelo
    # de la selección principal.
    if !eval_fin.valido_train

        @warn(
            "$(fam.clave) no es válido en TRAIN después del refinamiento."
        )
    end

    ajustes[fam.clave] = (
        fam=fam,
        p=p_fin,
        p_alg=p_alg,

        beta_fit=eval_fin.beta_fit,
        beta_SIR=eval_fin.beta_sir,
        I_fit=eval_fin.I_fit,

        tabla_alg=tabla_alg,
        tabla_dyn=tabla_dyn,

        losses_alg=losses_alg,
        params_alg=params_alg,

        # Se conservan TODOS los refinamientos dinámicos
        # para el anexo.
        losses_dyn=losses_dyn,
        params_dyn=params_dyn,

        # Índice del multistart algebraico que originó
        # cada candidato dinámico.
        idx_candidatos_alg=idx_cand
    )

    push!(
        filas_res,
        (
            clave=fam.clave,
            grupo=String(fam.grupo),
            forma=fam.etiqueta,
            k=length(p_fin),

            parametros=join(
                [
                    @sprintf(
                        "%s=%.8g",
                        fam.pars[i],
                        p_fin[i]
                    )
                    for i in eachindex(p_fin)
                ],
                ", "
            ),

            ecuacion=ecuacion_texto(
                fam,
                p_fin
            ),

            loss_conjunta_train=L_fin,

            rmse_beta_train=eval_fin.mb_tr.rmse,
            mae_beta_train=eval_fin.mb_tr.mae,
            r2_beta_train=eval_fin.mb_tr.r2,
            n_beta_train=eval_fin.mb_tr.n,

            rmse_beta_test=eval_fin.mb_te.rmse,
            mae_beta_test=eval_fin.mb_te.mae,
            r2_beta_test=eval_fin.mb_te.r2,
            n_beta_test=eval_fin.mb_te.n,

            coc_beta_pers=eval_fin.coc_beta_pers,

            rmse_I_train=eval_fin.mI_tr.rmse,
            mae_I_train=eval_fin.mI_tr.mae,
            r2_I_train=eval_fin.mI_tr.r2,
            n_I_train=eval_fin.mI_tr.n,

            rmse_I_test=eval_fin.mI_te.rmse,
            mae_I_test=eval_fin.mI_te.mae,
            r2_I_test=eval_fin.mI_te.r2,
            n_I_test=eval_fin.mI_te.n,

            coc_I_pers=eval_fin.coc_I_pers,

            I_min=minimum(
                filter(
                    isfinite,
                    eval_fin.I_fit
                )
            ),

            I_max=maximum(
                filter(
                    isfinite,
                    eval_fin.I_fit
                )
            ),

            beta_min_SIR=minimum(
                filter(
                    isfinite,
                    eval_fin.beta_sir
                )
            ),

            beta_max_SIR=maximum(
                filter(
                    isfinite,
                    eval_fin.beta_sir
                )
            ),

            valido_train=eval_fin.valido_train,
            valido_test=eval_fin.valido_test,

            beta_ref_valida_train=
                eval_fin.beta_ref_valida_train,

            beta_ref_valida_test=
                eval_fin.beta_ref_valida_test
        )
    )
end


isempty(filas_res) &&
    error(
        "Ninguna familia produjo un ajuste válido."
    )

resultados =
    DataFrame(
        filas_res
    )


# ============================================================
# 13. SELECCIÓN Y BASELINES
# ============================================================

# Sin categorías arbitrarias.
# El criterio externo se informa directamente mediante cocientes:
#
#   coc < 1  -> supera persistencia
#   coc = 1  -> igual persistencia
#   coc > 1  -> peor que persistencia
#
resultados.supera_persistencia_I = [
    r.valido_test &&
    isfinite(r.coc_I_pers) &&
    r.coc_I_pers < 1.0
    for r in eachrow(resultados)
]

resultados.supera_persistencia_beta = [
    r.beta_ref_valida_test &&
    isfinite(r.coc_beta_pers) &&
    r.coc_beta_pers < 1.0
    for r in eachrow(resultados)
]

# Selección: exclusivamente pérdida TRAIN + validez TRAIN.
resultados.criterio_train = [
    r.valido_train ?
    r.loss_conjunta_train :
    Inf
    for r in eachrow(resultados)
]

# Orden global sólo para presentación.
sort!(
    resultados,
    [
        :grupo,
        :criterio_train
    ]
)

# Modelos que realmente compiten por la selección principal.
idx_principales = [
    i for i in 1:nrow(resultados)
    if resultados.grupo[i] == "principal" &&
       isfinite(resultados.criterio_train[i])
]

isempty(idx_principales) &&
    error(
        "No existe ningún modelo principal válido en TRAIN."
    )

mejor_idx =
    idx_principales[
        argmin(
            resultados.criterio_train[
                idx_principales
            ]
        )
    ]

mejor =
    resultados[
        mejor_idx,
        :
    ]


# ============================================================
# 14. COMPARACIÓN DE I(t)
# ============================================================

comparacion_I =
    DataFrame(
        modelo=String[],
        tipo=String[],
        rmse_train=Float64[],
        mae_train=Float64[],
        r2_train=Float64[],
        rmse_test=Float64[],
        mae_test=Float64[],
        r2_test=Float64[],
        coc_persistencia=Float64[],
        valido_test=Bool[]
    )

push!(
    comparacion_I,
    (
        "Persistencia",
        "baseline",
        NaN,
        NaN,
        NaN,
        RMSE_I_PERS,
        MAE_I_PERS,
        R2_I_PERS,
        1.0,
        true
    )
)

for (
    nom,
    pred
) in (
    (
        "UDE",
        I_UDE
    ),
    (
        "SW-UDE",
        I_SWUDE
    )
)

    a =
        metricas(
            I_obs,
            pred,
            IDX_TRAIN
        )

    b =
        metricas(
            I_obs,
            pred,
            IDX_TEST
        )

    push!(
        comparacion_I,
        (
            nom,
            "baseline",
            a.rmse,
            a.mae,
            a.r2,
            b.rmse,
            b.mae,
            b.r2,
            b.rmse /
            RMSE_I_PERS,
            true
        )
    )
end

for r in eachrow(resultados)

    push!(
        comparacion_I,
        (
            "SIR + $(r.clave)",
            r.grupo,
            r.rmse_I_train,
            r.mae_I_train,
            r.r2_I_train,
            r.rmse_I_test,
            r.mae_I_test,
            r.r2_I_test,
            r.coc_I_pers,
            r.valido_test
        )
    )
end

sort!(
    comparacion_I,
    :coc_persistencia
)

println("\n", "="^66)
println("COMPARACIÓN DE I(t)")
println("(ordenada por RMSE / RMSE_persistencia)")
println("="^66)

show(
    comparacion_I;
    allrows=true,
    allcols=true
)

println()


println("\n", "="^66)
println("RESULTADOS POR FAMILIA")
println("="^66)

show(
    select(
        resultados,
        :clave,
        :grupo,
        :k,
        :loss_conjunta_train,
        :rmse_beta_test,
        :coc_beta_pers,
        :rmse_I_test,
        :coc_I_pers,
        :valido_train,
        :valido_test
    );
    allrows=true,
    allcols=true
)

println()


# ============================================================
# 15. CONTRASTE ENTRE FIDELIDAD A beta Y DINÁMICA
# ============================================================

principales =
    resultados[
        resultados.grupo .==
        "principal",
        :
    ]

if nrow(principales) >= 2

    rk_b =
        sortperm(
            principales.rmse_beta_test
        )

    rk_I =
        sortperm(
            principales.rmse_I_test
        )

    println("\n", "="^66)
    println("ORDENAMIENTO DE LOS MODELOS PRINCIPALES EN TEST")
    println("="^66)

    println(
        "por fidelidad a beta_SW-UDE : ",
        join(
            principales.clave[rk_b],
            " > "
        )
    )

    println(
        "por fidelidad a I(t)        : ",
        join(
            principales.clave[rk_I],
            " > "
        )
    )

    if principales.clave[rk_b[1]] ==
       principales.clave[rk_I[1]]

        println(
            "→ ambos criterios coinciden en el primer lugar."
        )

    else

        println(
            "→ los criterios difieren: " *
            "$(principales.clave[rk_b[1]]) es mejor por beta, " *
            "$(principales.clave[rk_I[1]]) es mejor por I(t)."
        )
    end
end


# ============================================================
# 16. EXPORTACIÓN DE LOS 10 REFINAMIENTOS DINÁMICOS
# ============================================================

function tabla_top_dinamico(
    a
)

    fam =
        a.fam

    validos = [
        j for j in eachindex(
            a.losses_dyn
        )
        if isfinite(
            a.losses_dyn[j]
        ) &&
        a.params_dyn[j] !== nothing
    ]

    ordenados =
        sort(
            validos;
            by=
                j ->
                    a.losses_dyn[j]
        )

    filas =
        NamedTuple[]

    for (
        ranking,
        j
    ) in enumerate(ordenados)

        p =
            a.params_dyn[j]::Vector{Float64}

        ev =
            evaluar_parametros(
                fam,
                p
            )

        # Padding dinámico para exportación.
        # MAX_PARAMETROS_FAMILIA se calcula a partir de todas las
        # familias registradas, por lo que esta rutina funciona
        # aunque una nueva familia tenga más parámetros que C9.
        ppad =
            fill(
                NaN,
                MAX_PARAMETROS_FAMILIA
            )

        ppad[
            eachindex(p)
        ] .= p

        nombres_p =
            Tuple(
                Symbol(
                    "p$(ii)"
                )
                for ii in 1:MAX_PARAMETROS_FAMILIA
            )

        columnas_p =
            NamedTuple{
                nombres_p
            }(
                Tuple(
                    ppad
                )
            )

        periodo =
            length(p) >= 4 &&
            fam.clave in (
                "M1",
                "M2",
                "C11"
            ) ?
            2π /
            abs(p[4]) :
            NaN

        fila_base =
            (
                ranking_dinamico=ranking,
                candidato_dinamico_original=j,
                candidato_algebraico_rank=j,
                multistart_algebraico_origen=
                    a.idx_candidatos_alg[j],

                loss_conjunta_train=
                    a.losses_dyn[j]
            )

        fila_metricas =
            (
                parametros=join(
                    [
                        @sprintf(
                            "%s=%.12g",
                            fam.pars[ii],
                            p[ii]
                        )
                        for ii in eachindex(p)
                    ],
                    ", "
                ),

                ecuacion=
                    ecuacion_texto(
                        fam,
                        p
                    ),

                periodo_dias=
                    periodo,

                rmse_beta_train=
                    ev.mb_tr.rmse,

                mae_beta_train=
                    ev.mb_tr.mae,

                r2_beta_train=
                    ev.mb_tr.r2,

                n_beta_train=
                    ev.mb_tr.n,

                rmse_beta_test=
                    ev.mb_te.rmse,

                mae_beta_test=
                    ev.mb_te.mae,

                r2_beta_test=
                    ev.mb_te.r2,

                n_beta_test=
                    ev.mb_te.n,

                coc_beta_pers=
                    ev.coc_beta_pers,

                rmse_I_train=
                    ev.mI_tr.rmse,

                mae_I_train=
                    ev.mI_tr.mae,

                r2_I_train=
                    ev.mI_tr.r2,

                n_I_train=
                    ev.mI_tr.n,

                rmse_I_test=
                    ev.mI_te.rmse,

                mae_I_test=
                    ev.mI_te.mae,

                r2_I_test=
                    ev.mI_te.r2,

                n_I_test=
                    ev.mI_te.n,

                coc_I_pers=
                    ev.coc_I_pers,

                valido_train=
                    ev.valido_train,

                valido_test=
                    ev.valido_test,

                beta_ref_valida_train=
                    ev.beta_ref_valida_train,

                beta_ref_valida_test=
                    ev.beta_ref_valida_test
            )

        fila =
            merge(
                fila_base,
                columnas_p,
                fila_metricas
            )

        push!(
            filas,
            fila
        )
    end

    return DataFrame(
        filas
    )
end


top10_dinamicos =
    Dict{
        String,
        DataFrame
    }()

for r in eachrow(resultados)

    a =
        ajustes[
            r.clave
        ]

    tabla_top =
        tabla_top_dinamico(
            a
        )

    top10_dinamicos[
        r.clave
    ] =
        tabla_top

    CSV.write(
        joinpath(
            EXP_DIR,
            "top10_dinamico_$(r.clave).csv"
        ),
        tabla_top
    )
end


# ============================================================
# 17. SALIDAS CSV
# ============================================================

CSV.write(
    joinpath(
        EXP_DIR,
        "resumen_familias.csv"
    ),
    resultados
)

CSV.write(
    joinpath(
        EXP_DIR,
        "comparacion_I.csv"
    ),
    comparacion_I
)

tray =
    DataFrame(
        t=t,
        conjunto=[
            k in IDX_TEST ?
            "test" :
            "train"
            for k in eachindex(t)
        ],
        I_observado=I_obs,
        I_UDE=I_UDE,
        I_SWUDE=I_SWUDE,
        beta_UDE=beta_UDE,
        beta_SWUDE=beta_obj
    )

for r in eachrow(resultados)

    a =
        ajustes[
            r.clave
        ]

    tray[
        !,
        Symbol(
            "beta_$(r.clave)"
        )
    ] =
        a.beta_fit

    tray[
        !,
        Symbol(
            "beta_$(r.clave)_SIR"
        )
    ] =
        a.beta_SIR

    tray[
        !,
        Symbol(
            "I_$(r.clave)"
        )
    ] =
        a.I_fit

    CSV.write(
        joinpath(
            EXP_DIR,
            "multistart_algebraico_$(r.clave).csv"
        ),
        a.tabla_alg
    )

    CSV.write(
        joinpath(
            EXP_DIR,
            "refinamiento_dinamico_$(r.clave).csv"
        ),
        a.tabla_dyn
    )
end

CSV.write(
    joinpath(
        EXP_DIR,
        "trayectorias.csv"
    ),
    tray
)


# ============================================================
# 18. FIGURAS
# ============================================================

p_beta =
    plot(
        t,
        beta_obj,
        label="β SW-UDE",
        lw=3,
        xlabel="t (días)",
        ylabel="β(t)",
        title="Tasa SW-UDE y formas paramétricas",
        legend=:outerright,
        size=(
            1150,
            640
        )
    )

plot!(
    p_beta,
    t,
    beta_UDE,
    label="β UDE",
    lw=1.5,
    ls=:dot
)

for r in eachrow(resultados)

    plot!(
        p_beta,
        t,
        ajustes[
            r.clave
        ].beta_fit,
        label="$(r.clave) [$(r.grupo)]",
        lw=2
    )
end

vline!(
    p_beta,
    [
        t_test_ini
    ],
    label="inicio test",
    ls=:dash,
    lw=2
)

display(
    p_beta
)

savefig(
    p_beta,
    joinpath(
        EXP_DIR,
        "beta_familias.png"
    )
)


p_I =
    plot(
        t,
        I_obs,
        label="I observado",
        lw=3,
        xlabel="t (días)",
        ylabel="I(t)",
        title="Reconstrucción SIR discreta (Euler Δt=1)",
        legend=:outerright,
        size=(
            1150,
            640
        )
    )

plot!(
    p_I,
    t,
    I_SWUDE,
    label="SW-UDE",
    lw=2.5
)

plot!(
    p_I,
    t,
    I_UDE,
    label="UDE",
    lw=1.5,
    ls=:dot
)

hline!(
    p_I,
    [
        I_PERS_VAL
    ],
    label="persistencia",
    ls=:dashdot,
    lw=1.5,
    color=:gray
)

for r in eachrow(resultados)

    plot!(
        p_I,
        t,
        ajustes[
            r.clave
        ].I_fit,
        label="SIR + $(r.clave)",
        lw=2
    )
end

vline!(
    p_I,
    [
        t_test_ini
    ],
    label="inicio test",
    ls=:dash,
    lw=2
)

display(
    p_I
)

savefig(
    p_I,
    joinpath(
        EXP_DIR,
        "I_familias.png"
    )
)


p_I_test =
    plot(
        t[IDX_TEST],
        I_obs[IDX_TEST],
        label="I observado",
        lw=3,
        xlabel="t (días)",
        ylabel="I(t)",
        title="Ventana de prueba",
        legend=:outerright,
        size=(
            1050,
            620
        )
    )

plot!(
    p_I_test,
    t[IDX_TEST],
    I_SWUDE[IDX_TEST],
    label="SW-UDE",
    lw=2.5
)

plot!(
    p_I_test,
    t[IDX_TEST],
    I_UDE[IDX_TEST],
    label="UDE",
    lw=1.5,
    ls=:dot
)

hline!(
    p_I_test,
    [
        I_PERS_VAL
    ],
    label="persistencia",
    ls=:dashdot,
    lw=1.5,
    color=:gray
)

for r in eachrow(resultados)

    plot!(
        p_I_test,
        t[IDX_TEST],
        ajustes[
            r.clave
        ].I_fit[IDX_TEST],
        label="SIR + $(r.clave)",
        lw=2
    )
end

display(
    p_I_test
)

savefig(
    p_I_test,
    joinpath(
        EXP_DIR,
        "I_test.png"
    )
)


# ============================================================
# 19. RESULTADO FINAL
# ============================================================

println("\n", "="^66)
println("MODELO PRINCIPAL SELECCIONADO")
println("(sólo M1/M2; exclusivamente con TRAIN)")
println("="^66)

println(
    "$(mejor.clave): $(mejor.forma)"
)

println(
    "parámetros: ",
    mejor.parametros
)

println(
    "ecuación: ",
    mejor.ecuacion
)

@printf(
    "\nTRAIN  L = %.8f | RMSE β = %.8f | RMSE I = %.1f | válido = %s\n",
    mejor.loss_conjunta_train,
    mejor.rmse_beta_train,
    mejor.rmse_I_train,
    string(
        mejor.valido_train
    )
)

println(
    "\nEVALUACIÓN FINAL EN TEST " *
    "(no usada para ajustar, validar ni seleccionar):"
)

@printf(
    "  β SW-UDE | R² = %+8.4f | RMSE = %.8f | RMSE/persistencia = %.3f\n",
    mejor.r2_beta_test,
    mejor.rmse_beta_test,
    mejor.coc_beta_pers
)

@printf(
    "  I(t)      | R² = %+8.4f | RMSE = %10.1f | MAE = %10.1f | RMSE/persistencia = %.3f\n",
    mejor.r2_I_test,
    mejor.rmse_I_test,
    mejor.mae_I_test,
    mejor.coc_I_pers
)

println(
    "  validez TEST = ",
    mejor.valido_test
)

println("\nControles/sensibilidad:")

for r in eachrow(
    resultados[
        resultados.grupo .==
        "control",
        :
    ]
)

    @printf(
        "  %-4s | L_train=%.6f | RMSE_I_test=%10.1f | coc_pers=%.3f | válido_test=%s\n",
        r.clave,
        r.loss_conjunta_train,
        r.rmse_I_test,
        r.coc_I_pers,
        string(
            r.valido_test
        )
    )
end

println("\nSalidas en: ", EXP_DIR)

foreach(
    f ->
        println(
            "  ",
            f
        ),
    sort(
        readdir(
            EXP_DIR
        )
    )
)
