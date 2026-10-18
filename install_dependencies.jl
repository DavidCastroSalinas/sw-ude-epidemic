# ============================================================
# install_dependencies.jl — instala y precompila el entorno del
# repositorio a partir de Project.toml y Manifest.toml.
#
#     julia --project=. install_dependencies.jl
#
# El Manifest.toml congela las versiones exactas de la corrida de
# referencia, así que Pkg.instantiate() reconstruye ese entorno sin
# resolver dependencias de nuevo. Si falta el Manifest, se resuelve contra
# el Project y se avisa de que las versiones pueden no ser las de las
# cifras publicadas.
#
# El repositorio no depende de SymbolicRegression.jl ni de MLJ.jl: la
# regresión simbólica salió del manuscrito y sus módulos no se copiaron.
# Eran los únicos paquetes que fallaron al instalar en la corrida de
# septiembre. Ver CHANGELOG.md.
# ============================================================

using Pkg

const REPO = normpath(@__DIR__)
Pkg.activate(REPO)

println("Julia    : ", VERSION)
println("Proyecto : ", REPO)

if !isfile(joinpath(REPO, "Project.toml"))
    error("""
    Falta Project.toml en $(REPO).

    Generarlo en la máquina de la corrida de referencia:
        julia bin/generar_entorno.jl

    Ver docs/ENTORNO.md, «El entorno de la corrida de referencia».
    """)
end

if isfile(joinpath(REPO, "Manifest.toml"))
    println("Manifest : presente, se reconstruyen las versiones congeladas.")
else
    @warn """
    No hay Manifest.toml. Se resolverán las dependencias contra Project.toml,
    y las versiones resultantes pueden no ser las de la corrida que produjo
    las cifras del manuscrito.
    """
end

Pkg.instantiate()
Pkg.precompile()

println("\nEntorno instalado. Paquetes de primer nivel:")
Pkg.status()

println("""

Siguiente paso:
    ./smoke_test.sh --con-julia     (Nivel 1)
    ./run_all.sh                    (Nivel 2, sobrescribe results/)
""")
