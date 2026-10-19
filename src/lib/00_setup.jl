#import Pkg; Pkg.add("Colors")

using Lux
using Random
using ComponentArrays          # parámetros de red como array diferenciable
using Optimization             # interfaz SciML unificada
using OptimizationOptimisers   # ADAM y otros optimizadores
using Optimisers               # ClipNorm / OptimiserChain para recorte de gradiente
using Zygote                   # diferenciación automática
using Statistics
using Printf
using Plots
using Measures                 # mm/cm units for figure margins (Plots re-exports
                                # these, but we `using` it explicitly and add it as
                                # a direct dependency so it always resolves)
using Colors                   # necesario para colorant"..." en las paletas
using CSV, DataFrames

println("✓ Librerías cargadas")

# Smoke mode checks the pipeline with fewer epochs and seeds. Its numerical
# results are not valid for the article. Enable it before starting a runner
# with SIR_UDE_SMOKE_TEST=1.
const SMOKE_TEST = get(ENV, "SIR_UDE_SMOKE_TEST", "0") == "1"
if SMOKE_TEST
    println("⚠ SIR_UDE_SMOKE_TEST=1 -- usando épocas/semillas reducidas (corrida de PRUEBA).")
    println("  Los números resultantes NO son válidos para el artículo. Corré sin esta")
    println("  variable de entorno para la versión final.")
end

"""
    epocas_final(n::Int)

Devuelve `n` tal cual, salvo que `SIR_UDE_SMOKE_TEST=1` esté activa, en
cuyo caso devuelve `min(n, SIR_UDE_SMOKE_EPOCHS)` (150 por defecto).
El runner 09 fija este límite en 30 para que su prueba sea más rápida.
"""
epocas_final(n::Int) = SMOKE_TEST ? min(n, max(1, parse(Int, get(ENV, "SIR_UDE_SMOKE_EPOCHS", "150")))) : n

"""
    semillas_final(rango)

Devuelve `rango` tal cual, salvo que `SIR_UDE_SMOKE_TEST=1` esté activa,
en cuyo caso devuelve como máximo las primeras 2 semillas de `rango`.
"""
semillas_final(rango) = SMOKE_TEST ? first(rango, min(2, length(rango))) : rango

# ============================================================
# Nomenclatura de métodos para figuras, tablas y mensajes
# ------------------------------------------------------------
# Por recomendación de los profesores del proyecto, el método antes
# llamado "Global" se presenta al lector como "UDE", y el método antes
# llamado "por ventanas"/"Windowed"/"Windowed UDE" se presenta como
# "Sliding Windows", abreviado "SW-UDE" en gráficos, tablas y mensajes
# (donde antes decía "Windowed UDE", ahora dice "SW-UDE"). Esto
# es puramente de presentación: los símbolos internos `:global`/`:ventanas`,
# los nombres de función (`train_global`, `entrenar_ventanas`, etc.), los
# nombres de variable (`rmse_global`, `beta_global`, ...) y los valores
# almacenados en columnas de datos usadas como claves internas (p. ej. la
# columna `metodo` de los DataFrames de Sección 18, con valores "global"/
# "ventanas") NO cambian -- cambiarlos rompería el filtrado y las
# comparaciones pareadas ya implementados. `metodo_display` centraliza la
# conversión de esos identificadores internos al texto que debe VERSE en
# gráficos, tablas y mensajes impresos.
# ============================================================

"""
    metodo_display(metodo; m=nothing)

Convierte el identificador interno del método (`:global`/`"global"` o
`:ventanas`/`"ventanas"`) en el texto que debe mostrarse al lector:
`"UDE"` o `"SW-UDE"` (con `" (m=...)"` opcional si se provee `m`).
No modifica el identificador interno -- solo se usa para construir
títulos, etiquetas y mensajes.
"""
function metodo_display(metodo; m=nothing)
    base = String(metodo) in ("global", "Global") ? "UDE" : "SW-UDE"
    return (base == "SW-UDE" && m !== nothing) ? "$base (m=$m)" : base
end

# ============================================================
# Global figure style (applies to every plot in this project)
# ------------------------------------------------------------
# Centralizing font sizes and margins here means individual plotting
# functions only need to override `size`, `legend`, or margins when a
# panel genuinely needs something different (e.g. a multi-panel layout,
# or a legend with many entries) — everything else falls back to these
# defaults, keeping every figure visually consistent and avoiding
# clipped/overlapping text.
# ============================================================
default(
    titlefontsize      = 10,   # per-subplot title
    plot_titlefontsize = 13,   # shared/overall title (via `plot_title=`)
    guidefontsize      = 10,   # axis labels (xlabel/ylabel)
    tickfontsize       = 8,    # axis tick numbers
    legendfontsize     = 8,
    left_margin        = 6mm,
    right_margin       = 6mm,
    top_margin         = 6mm,
    bottom_margin      = 6mm,
    fg_legend          = :black,
    background_color_legend = RGBA(1, 1, 1, 0.75),  # translucent white behind legends
)

# ============================================================
# EPS export helper
# ------------------------------------------------------------
# The GR backend (Plots.jl default) does NOT implement direct
# `savefig(plt, "*.eps")` in headless/no-display mode — it only
# natively writes PNG, PDF, SVG and PS. Requesting ".eps" directly
# raises: MethodError: no method matching _show(..., MIME{:"image/eps"}, ...).
#
# The standard workaround is to save a PDF first and convert it to EPS
# with an external tool (Ghostscript `gs`, or `pdftops` from poppler-utils).
# Both are extremely common on any machine with a LaTeX toolchain, which
# this project assumes given it's feeding an MDPI manuscript.
# ============================================================

"""
    save_eps_from_pdf(pdf_path, eps_path)

Converts `pdf_path` to `eps_path` using Ghostscript (`gs`) if available,
falling back to `pdftops` (poppler-utils). Never throws: if neither tool
is found, prints a warning and returns `false` so a long training run
never aborts just because EPS export isn't possible on this machine.
"""
function save_eps_from_pdf(pdf_path::String, eps_path::String)
    if Sys.which("gs") !== nothing
        try
            run(`gs -q -dNOPAUSE -dBATCH -dEPSCrop -sDEVICE=eps2write -sOutputFile=$eps_path $pdf_path`)
            return true
        catch e
            @warn "Ghostscript failed converting $pdf_path to EPS" exception=e
        end
    end
    if Sys.which("pdftops") !== nothing
        try
            run(`pdftops -eps $pdf_path $eps_path`)
            return true
        catch e
            @warn "pdftops failed converting $pdf_path to EPS" exception=e
        end
    end
    @warn "Neither Ghostscript (gs) nor pdftops found on PATH — skipping EPS export for $eps_path. Install Ghostscript (e.g. `sudo apt install ghostscript`) to enable EPS output."
    return false
end

"""
    savefig_all(plt, base_path; formats=(:png, :pdf, :eps))

Saves `plt` to `base_path.<ext>` for every format requested. PDF is always
produced when `:eps` is requested (EPS is derived from it via
`save_eps_from_pdf`); if `:pdf` itself wasn't requested, the intermediate
PDF is deleted afterwards. This replaces the old direct
`savefig(plt, "*.eps")` calls, which fail under GR in headless mode.
"""
function savefig_all(plt, base_path::String; formats::Tuple=(:png, :pdf, :eps))
    need_pdf_file = (:pdf in formats) || (:eps in formats)
    need_pdf_file && savefig(plt, base_path * ".pdf")
    (:png in formats) && savefig(plt, base_path * ".png")
    if :eps in formats
        save_eps_from_pdf(base_path * ".pdf", base_path * ".eps")
    end
    if need_pdf_file && !(:pdf in formats)
        isfile(base_path * ".pdf") && rm(base_path * ".pdf")
    end
    return nothing
end

const N   = 1000.0   # Tamaño total de la población
const γ   = 0.10     # Tasa de recuperación [días⁻¹]
const Δt  = 1.0      # Paso temporal [días]
const T   = 50       # Número de transiciones  →  T+1 estados

# Vector de tiempos: ts[1]=0, ts[2]=1, ..., ts[T+1]=T
const ts = collect(0.0:Δt:Float64(T))   # longitud T+1

# Condición inicial
const u0 = [990.0, 10.0, 0.0]   # [S₀, I₀, R₀]

# Umbral de prevalencia para calcular β directa desde datos
const UMBRAL_SI = 1.0

println("Parámetros inicializados")
println("T = ", T, "  |  N = ", N, "  |  γ = ", γ)
println("ts: ", length(ts), " puntos, de ", ts[1], " a ", ts[end])

sigmoid(x) = 1.0 / (1.0 + exp(-x))

const β_min_real = 1.0e-6

# Caso 1: constante
function beta_real_constante(t, I)
    return 0.30
end

# Caso 2: lineal  (versión del notebook validado)
function beta_real_lineal(t, I)
    return 0.03 * t - 0.001 * I + 0.30
end

# Caso 3: no lineal tipo tanh (versión del notebook validado)
function beta_real_tanh(t, I)
    return 0.20 * tanh(1.20 * t - 0.50 * I + 5.0)  + 0.3
end

# Caso 4: dos olas
function beta_dos_olas(t, I)
    t_norm = t / T
    I_norm = I / N
    onda1  = 0.20 * exp(-8.0 * (t_norm - 0.25)^2)
    onda2  = 0.25 * exp(-8.0 * (t_norm - 0.75)^2)
    miedo  = 0.20 * I_norm
    return max(β_min_real, 0.20 + onda1 + onda2 - miedo)
end

# Caso 5: intervención abrupta
function beta_intervencion(t, I)
    t_norm     = t / T
    I_norm     = I / N
    base       = 0.40
    cuarentena = 0.30 * sigmoid(20.0 * (t_norm - 0.30))
    reapertura = 0.15 * sigmoid(20.0 * (t_norm - 0.65))
    miedo      = 0.10 * I_norm
    return max(β_min_real, base - cuarentena + reapertura - miedo)
end

# Caso 6: estacionalidad
function beta_estacional(t, I)
    I_norm   = I / N
    estacion = 0.10 * cos(2π * t / T)
    miedo    = 0.15 * I_norm
    return max(β_min_real, 0.30 + estacion - miedo)
end

# Caso 7: saturación hospitalaria
function beta_saturacion(t, I)
    I_norm  = I / N
    umbral  = 0.15
    colapso = 0.20 * sigmoid(20.0 * (I_norm - umbral))
    return max(β_min_real, 0.25 + colapso)
end

const BETA_FUNCTIONS = Dict(
    :constante    => beta_real_constante,
    :lineal       => beta_real_lineal,
    :tanh         => beta_real_tanh,
    :dos_olas     => beta_dos_olas,
    :intervencion => beta_intervencion,
    :estacional   => beta_estacional,
    :saturacion   => beta_saturacion,
)


const SCENARIO_LABELS = Dict(
    :constante    => "Constant rate",
    :lineal       => "Linear rate",
    :tanh         => "Nonlinear rate (tanh)",
    :dos_olas     => "Two-wave",
    :intervencion => "Abrupt intervention",
    :estacional   => "Seasonal",
    :saturacion   => "Hospital saturation",
)

println("✓ Funciones beta reales definidas")
println("Escenarios disponibles: ", join(sort(collect(string.(keys(BETA_FUNCTIONS)))), ", "))
