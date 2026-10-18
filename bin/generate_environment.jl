# ============================================================
# generate_environment.jl — crea el Project.toml y el Manifest.toml del
# repositorio, con las versiones de la corrida que produjo las cifras.
#
#     julia bin/generate_environment.jl
#
# Hay que correrlo UNA VEZ, en la máquina de la corrida de referencia, y
# versionar los dos archivos que deja. Después, cualquiera reconstruye el
# entorno con `julia --project=. install_dependencies.jl`, que ya no
# resuelve nada: lee el Manifest.
#
# Por qué hace falta un script y no basta un Project.toml escrito a mano:
# el Manifest.toml lista el árbol completo de dependencias con su versión
# y su hash, y eso solo lo puede escribir Pkg resolviendo de verdad. Un
# Project.toml a mano, además, necesita el UUID de cada paquete, y un UUID
# mal copiado produce un error que no dice qué pasó.
#
# ------------------------------------------------------------
# Lo que el repositorio necesita de verdad
# ------------------------------------------------------------
# La lista sale de los `using` e `import` de los diecinueve módulos y los
# trece runners publicados, no del entorno global. Es notablemente más
# corta, por dos razones:
#
#   · No hay solver ODE. El SIR se integra con un Euler explícito escrito
#     a mano, con Δt = 1 día (ver docs/DECISIONS.md). Así que
#     DifferentialEquations, SciMLBase y Distributions no son
#     dependencias: ninguna aparece en el código publicado.
#
#   · La regresión simbólica salió del manuscrito, de modo que
#     SymbolicRegression y MLJ tampoco. Eran los dos paquetes pesados y
#     los únicos que fallaron al instalar en septiembre.
#
# IJulia queda fuera también: sirve para el notebook, no para el Nivel 2.
# ============================================================

using Pkg

const REPO = normpath(joinpath(@__DIR__, ".."))

# Paquete => versión de la corrida de referencia, tal como la reportó
# Pkg.status() en el entorno global v1.10 el 2026-10-18.
const FIJADOS = [
    ("CSV",                    "0.10.17"),
    ("Colors",                 "0.13.1"),
    ("ComponentArrays",        "0.15.47"),
    ("DataFrames",             "1.8.2"),
    ("Lux",                    "1.31.4"),
    ("Measures",               "0.3.3"),
    ("Optim",                  "2.2.2"),
    ("Optimisers",             "0.4.9"),
    ("Optimization",           "5.9.0"),
    ("OptimizationOptimisers", "0.3.23"),
    ("Plots",                  "1.41.7"),
    ("Zygote",                 "0.7.12"),
    # Confirmados el 2026-10-18 en una segunda consulta: sí estaban en el
    # entorno de la corrida, solo que no aparecían en el status general.
    ("StatsPlots",             "0.15.8"),
    ("HypothesisTests",        "0.11.8"),
]

# Ninguno sin versión de referencia: las diecinueve están fijadas.
#
# Glob estuvo en esta lista un rato. El runner 23 lo importaba, pero no lo
# usa: arma las rutas con joinpath sobre SEMILLAS_ESPERADAS y comprueba con
# isfile, y no hay una sola llamada a glob() en el código. El import se
# quitó, así que Glob no es dependencia de nada.
const SIN_VERSION = String[]

# Biblioteca estándar: en un entorno de proyecto hay que declararla.
const ESTANDAR = ["Statistics", "Random", "Printf", "LinearAlgebra", "Dates"]

println("Julia    : ", VERSION)
println("Proyecto : ", REPO)
if VERSION < v"1.10" || VERSION >= v"1.11"
    @warn "docs/ENVIRONMENT.md declara Julia 1.10.5. Esta es $(VERSION); el Manifest quedará atado a esta versión."
end

Pkg.activate(REPO)

println("\nFijando las versiones de la corrida de referencia:")
for (nombre, version) in FIJADOS
    println("  $nombre $version")
    Pkg.add(Pkg.PackageSpec(name=nombre, version=version))
end

if !isempty(SIN_VERSION)
    println("\nSin versión de referencia (las elige Pkg):")
    for nombre in SIN_VERSION
        println("  $nombre")
        Pkg.add(nombre)
    end
end

println("\nBiblioteca estándar:")
for nombre in ESTANDAR
    println("  $nombre")
    Pkg.add(nombre)
end

Pkg.resolve()
Pkg.precompile()

println("\n", "="^70)
println("Entorno del repositorio")
println("="^70)
Pkg.status()

for f in ("Project.toml", "Manifest.toml")
    ruta = joinpath(REPO, f)
    println(isfile(ruta) ? "  escrito  $f  ($(filesize(ruta)) bytes)" : "  FALTA    $f")
end

println("""

Siguiente paso: versionar Project.toml y Manifest.toml, y comprobar que
el instalador los lee sin resolver nada:

    julia --project=. install_dependencies.jl
    ./smoke_test.sh
""")
