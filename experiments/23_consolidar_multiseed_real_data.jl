# ============================================================
# Consolidación multi-semilla -- sensibilidad a m, datos reales
# ============================================================
# Junta los 5 CSV por semilla que deja experiments/22_run_real_data_window_
# sensitivity_multiseed.jl (uno por cada SIR_UDE_SEED) y calcula, para cada
# valor de m de la grilla, media y desvío estándar entre semillas de las
# métricas relevantes (RMSE_I_train, RMSE_I_test, TV(β̂), y cualquier otra
# columna numérica que traiga el CSV de origen -- el agrupamiento es
# agnóstico al nombre exacto de columnas más allá de "m" y "seed", así que
# no depende de conocer el detalle interno de run_window_sensitivity_real_split).
#
# Es deliberadamente un script SEPARADO del runner 22: no vuelve a entrenar
# nada, solo agrega los CSV ya escritos. Se puede correr y volver a correr
# las veces que haga falta (por ejemplo, si todavía faltan semillas) sin
# costo de cómputo.
#
#     julia experiments/23_consolidar_multiseed_real_data.jl
# ============================================================

# El árbol de trabajo importaba también Glob, que este runner no usa: las
# rutas se arman con joinpath sobre SEMILLAS_ESPERADAS y se comprueban con
# isfile, sin globbing. Quitarlo no cambia nada de lo que el runner
# calcula, y evita declarar en Project.toml una dependencia que el código
# no necesita. Ver docs/ENTORNO.md.
using CSV, DataFrames, Statistics

const SEMILLAS_ESPERADAS = [1234, 1, 2, 3, 4]
const DIR_BASE = joinpath("results", "datos_reales", "multiseed")

rutas = String[]
faltantes = Int[]
for s in SEMILLAS_ESPERADAS
    ruta = joinpath(DIR_BASE, "seed_$(s)", "datos_reales_sensibilidad_m_seed$(s).csv")
    if isfile(ruta)
        push!(rutas, ruta)
    else
        push!(faltantes, s)
    end
end

if !isempty(faltantes)
    println("⚠ Todavía faltan semillas: ", faltantes)
    println("  (esperaba: ", SEMILLAS_ESPERADAS, ")")
    println("  Encontradas hasta ahora: ", length(rutas), "/", length(SEMILLAS_ESPERADAS))
    isempty(rutas) && error("No hay ningún CSV de semilla todavía -- corré experiments/22_... primero.")
    println("  Sigo con las que hay, pero el promedio no será sobre las 5 semillas planeadas.")
end

df_todas = vcat([CSV.read(r, DataFrame) for r in rutas]...; cols=:union)
println("✓ Cargadas ", nrow(df_todas), " filas de ", length(rutas), " semilla(s): ",
        sort(unique(df_todas.seed)))

# Columnas numéricas a promediar = todas menos m, seed, es_control, es_adoptado
cols_excluir = Set([:m, :seed, :es_control, :es_adoptado])
cols_numericas = [c for c in names(df_todas, Number) if Symbol(c) ∉ cols_excluir]
isempty(cols_numericas) && error("No encontré columnas numéricas para promediar -- revisá el CSV de origen.")
println("  Columnas promediadas entre semillas: ", cols_numericas)

funciones_agregacion = vcat(
    [c => mean => Symbol(string(c), "_mean") for c in cols_numericas],
    [c => std  => Symbol(string(c), "_sd")   for c in cols_numericas],
    :seed => (x -> length(unique(x))) => :n_semillas,
)

df_consolidado = combine(groupby(df_todas, :m), funciones_agregacion...)
sort!(df_consolidado, :m)

df_consolidado.es_control  = df_consolidado.m .== 1
df_consolidado.es_adoptado = df_consolidado.m .== 10

mkpath(DIR_BASE)
ruta_salida = joinpath(DIR_BASE, "datos_reales_sensibilidad_m_multiseed_consolidado.csv")
CSV.write(ruta_salida, df_consolidado)
println("\n✓ Consolidado escrito en: ", ruta_salida)

# Si el CSV trae una columna con "rmse" e "i_train" en el nombre (case-
# insensitive), mostrar el criterio de banda del 5% sobre la MEDIA entre
# semillas, para chequear a ojo si m=10 sigue siendo la elección razonable
# una vez promediado sobre semillas -- no reemplaza la discusión del texto,
# solo da una primera lectura.
col_train = findfirst(c -> occursin("rmse", lowercase(string(c))) && occursin("train", lowercase(string(c))) && endswith(string(c), "_mean"),
                       names(df_consolidado))
if col_train !== nothing
    nombre_col = names(df_consolidado)[col_train]
    mejor = minimum(df_consolidado[!, nombre_col])
    banda = mejor * 1.05
    println("\n  Criterio banda 5% sobre ", nombre_col, " (promedio entre semillas):")
    for row in eachrow(df_consolidado)
        marca = row[nombre_col] <= banda ? "  <- dentro de la banda del 5%" : ""
        etiqueta = row.es_control ? " [control m=1]" : (row.es_adoptado ? " [adoptado]" : "")
        println("    m=", lpad(row.m, 3), "  ", nombre_col, "=", round(row[nombre_col], digits=4), etiqueta, marca)
    end
else
    println("\n  No encontré automáticamente una columna 'RMSE...train...mean' para el chequeo")
    println("  de banda del 5% -- revisá manualmente el CSV consolidado, columnas: ",
            names(df_consolidado))
end

println("\n  Con esto ya se puede: (1) reportar RMSE_I_train/test y TV(β̂) como media±DE")
println("  entre 5 semillas en vez de un único valor: (2) chequear si el m elegido (m=10)")
println("  sigue cayendo en la banda del 5% una vez promediado sobre semillas.")
