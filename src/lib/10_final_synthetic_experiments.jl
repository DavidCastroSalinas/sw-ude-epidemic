# ============================================================
# src/lib/10_final_synthetic_experiments.jl — Versión final: cierra los experimentos
# SINTÉTICOS (7 escenarios) que en el proyecto original quedaron parciales
# o sin ejecutar.
# ------------------------------------------------------------
# Gaps identificados por revisión de código (ver auditoría previa) y que
# este archivo resuelve:
#
#   1. Multi-semilla (10 seeds) + comparación pareada (t de Student +
#      Wilcoxon) solo existían, de hecho, para :lineal (Experimento 1) y
#      parcialmente para :dos_olas/:estacional (Experimento 3, sin barrido
#      de m ni test pareado). :constante, :tanh, :intervencion y
#      :saturacion nunca tuvieron más que una corrida puntual con
#      seed=1234. Este archivo generaliza el patrón de
#      `correr_experimento_1_lineal` a CUALQUIER escenario.
#
#   2. :saturacion estaba excluida a propósito de Experimento 3 "hasta
#      confirmar estabilidad". SCENARIO_CONFIG[:saturacion] YA tiene la
#      configuración estabilizada (lr=0.003, clip_norm=5.0, Sección 17),
#      y `ejecutar_repeticion` la toma automáticamente de ahí -- así que
#      generalizar el experimento multi-semilla también cierra este punto,
#      sin tocar la arquitectura ni el optimizador.
#
#   3. graficar_trayectorias (Sección 18) es genérica pero solo se había
#      invocado para :lineal. Se generaliza a los 7 escenarios.
#
# NOTA (21-ago-2026, renumeración): este archivo se llamaba
# `src/lib/11_final_experiments.jl` y traía, además de lo anterior, un cuarto
# punto sobre sensibilidad de datos reales a N/γ -- ESE punto (la función
# `evaluar_sensibilidad_datos_reales`) se separó a su propio archivo,
# `src/lib/13_real_data_sensitivity_n_gamma.jl`, para que todo lo que trabaja
# con datos reales (src/lib/11 a src/lib/17) quede en un bloque de números
# contiguo, sin este archivo -- que es 100% sobre los 7 escenarios
# SINTÉTICOS -- interrumpiéndolo en el medio.
# ============================================================


# ── 1. Grid de m por defecto, específico por escenario ───────────────────
"""
    default_m_grid(caso_beta)

Grid de valores de m para el barrido multi-semilla de cada escenario.
Reutiliza el mismo criterio ya usado en `02_run_window_sensitivity_all.jl`
(grid más fino para :tanh/:saturacion, cuya transición real ocurre en 1-2
pasos) y en el Experimento 1 original para :lineal, extendido al resto de
escenarios con el grid estándar [1,3,5,10,20,50] centrado en el `m` de
`SCENARIO_CONFIG`.
"""
function default_m_grid(caso_beta::Symbol)
    caso_beta == :lineal                    && return [1, 3, 6, 10, 15, 25]
    caso_beta in (:tanh, :saturacion)        && return [1, 2, 3, 5, 7, 10, 20]
    return [1, 3, 5, 10, 20, 50]
end

println("✓ default_m_grid definida")


# ── 2. Multi-semilla + barrido de m, generalizado a cualquier escenario ──
"""
    correr_experimento_multisemilla(caso_beta; seeds_red=1:10, m_values=nothing,
                                     outdir="results/final_suite")

Generalización de `correr_experimento_1_lineal` (Sección 18.10) a
cualquier escenario de `BETA_FUNCTIONS`. Corre `seeds_red` repeticiones
del método global y, para cada `m` en `m_values` (o `default_m_grid` si
no se especifica), `seeds_red` repeticiones del método por ventanas.
Todos los hiperparámetros (hidden, layers, lr, epochs, clip_norm) se
toman automáticamente de `SCENARIO_CONFIG[caso_beta]` vía
`ejecutar_repeticion` -- para :saturacion esto ya incluye clip_norm=5.0.

Guarda `outdir/<caso_beta>_multisemilla.csv` y lo devuelve como DataFrame.
"""
function correr_experimento_multisemilla(caso_beta::Symbol;
                                          seeds_red=1:10,
                                          m_values::Union{Nothing,Vector{Int}}=nothing,
                                          outdir::String="results/final_suite")
    mkpath(outdir)
    seeds_red = semillas_final(seeds_red)
    mvals = m_values === nothing ? default_m_grid(caso_beta) : m_values
    label = SCENARIO_LABELS[caso_beta]

    println("\n" * "#"^70)
    println("  Multi-semilla — $label  (seeds=$(collect(seeds_red)), m_values=$mvals)")
    println("#"^70)

    n_total = length(seeds_red) + length(mvals) * length(seeds_red)
    prog    = iniciar_progreso("Multi-semilla $label", n_total)

    resultados = []
    for seed_red in seeds_red
        push!(resultados, ejecutar_repeticion(caso_beta, :global, missing, seed_red))
        avanzar!(prog; detalle="global, seed=$seed_red")
    end
    for m in mvals, seed_red in seeds_red
        push!(resultados, ejecutar_repeticion(caso_beta, :ventanas, m, seed_red))
        avanzar!(prog; detalle="ventanas, m=$m, seed=$seed_red")
    end
    finalizar_progreso!(prog)

    path = joinpath(outdir, "$(String(caso_beta))_multisemilla.csv")
    return guardar_resultados_csv(resultados; path=path)
end

println("✓ correr_experimento_multisemilla definida (genérica, todos los escenarios)")


# ── 3. Orquestador: multi-semilla + comparación pareada para los 7 ───────
"""
    correr_todos_experimentos_multisemilla(; escenarios=SCENARIO_ORDER,
                                            seeds_red=1:10,
                                            outdir="results/final_suite")

Ejecuta `correr_experimento_multisemilla` para cada escenario en
`escenarios` (por defecto los 7, incluyendo `:saturacion` con su
configuración ya estabilizada), genera las figuras de sensibilidad a m,
boxplot de RMSE_β y β promedio (reutilizando `graficar_*` de
`09_experiment18_plots.jl`), corre la comparación pareada
(`comparar_pareado`, t de Student + Wilcoxon) contra el `m` de referencia
de `SCENARIO_CONFIG`, y consolida los resultados de todas las pruebas
pareadas en un único CSV para citar directamente en el artículo:

    results/final_suite/comparacion_pareada_TODOS_escenarios.csv

con columnas: escenario, m, metrica, media_UDE, std_UDE, media_Windowed,
std_Windowed, t_stat, p_valor_t_dos_colas, p_valor_wilcoxon_dos_colas,
direccion_esperada (bool: ¿SW-UDE tuvo menor error promedio?).
"""
function correr_todos_experimentos_multisemilla(; escenarios::Vector{Symbol}=SCENARIO_ORDER,
                                                  seeds_red=1:10,
                                                  outdir::String="results/final_suite")
    mkpath(outdir)
    filas_comparacion = NamedTuple[]
    prog_escenarios = iniciar_progreso("(A) Multi-semilla + comparación pareada — escenarios", length(escenarios))

    for caso in escenarios
        cfg = SCENARIO_CONFIG[caso]
        caso_str = String(caso)
        label    = SCENARIO_LABELS[caso]

        df = correr_experimento_multisemilla(caso; seeds_red=seeds_red, outdir=outdir)

        # Figuras (reutilizan graficar_* de 09_experiment18_plots.jl,
        # ya genéricas en caso_beta -- solo no se habían invocado antes
        # para estos escenarios)
        graficar_sensibilidad_m(df; caso_beta=caso_str, outdir=outdir)
        graficar_boxplot_metrica(df; caso_beta=caso_str, metrica=:rmse_beta,
                                  m_ventanas=cfg.m, outdir=outdir)
        graficar_boxplot_metrica(df; caso_beta=caso_str, metrica=:rmse_global,
                                  m_ventanas=cfg.m, outdir=outdir)
        graficar_beta_promedio(caso, :global,   missing, seeds_red; outdir=outdir)
        graficar_beta_promedio(caso, :ventanas, cfg.m,   seeds_red; outdir=outdir)

        # Comparación pareada formal para las dos métricas de interés
        for metrica in (:rmse_beta, :rmse_global)
            res = comparar_pareado(df; caso_beta=caso_str, m=cfg.m, metrica=metrica)
            push!(filas_comparacion, (
                escenario   = label,
                m           = cfg.m,
                metrica     = String(metrica),
                media_UDE      = res.media_global,   std_UDE      = res.std_global,
                media_Windowed = res.media_ventanas,  std_Windowed = res.std_ventanas,
                t_stat                     = res.t_test.t,
                p_valor_t_dos_colas        = pvalue(res.t_test),
                p_valor_wilcoxon_dos_colas = pvalue(res.wilcoxon),
                direccion_esperada         = res.media_ventanas < res.media_global,
            ))
        end
        avanzar!(prog_escenarios; detalle=label)
    end
    finalizar_progreso!(prog_escenarios)

    df_comp = DataFrame(filas_comparacion)
    path = joinpath(outdir, "comparacion_pareada_TODOS_escenarios.csv")
    CSV.write(path, df_comp)
    println("\n✓ Comparación pareada consolidada guardada en $path")
    println(df_comp)

    return df_comp
end

println("✓ correr_todos_experimentos_multisemilla definida")


# ── 4. Ruido (rediseño 05-sep-2026, σ_rel multiplicativo) para los 7 ─────
"""
    tabla_ruido_unificada(df::DataFrame, label::String)

Traduce el esquema de columnas "interno" de `ejecutar_repeticion`
(caso_beta, metodo, seed_red, sigma_ruido, rmse_I, rmse_global, rmse_beta,
...) al esquema de salida UNIFICADO pedido para el rediseño de ruido
(sección 6 de la propuesta de David):

    escenario, metodo, seed, sigma_rel, porcentaje_ruido,
    RMSE_SIR, RMSE_I, RMSE_beta

con `metodo` mapeado a las etiquetas del artículo ("global"→"UDE",
"ventanas"→"SW-UDE"), `sigma_rel`←sigma_ruido (ya reinterpretado como
ruido relativo, ver `generar_datos`), `porcentaje_ruido`←100·sigma_rel, y
`RMSE_SIR`←rmse_global (mismo RMSE combinado sobre S,I,R apiladas, solo
renombrado para que coincida con el nombre pedido en la tabla del
artículo).
"""
function tabla_ruido_unificada(df::DataFrame, label::String)
    metodo_map = Dict("global" => "UDE", "ventanas" => "SW-UDE")
    return DataFrame(
        escenario        = fill(label, nrow(df)),
        metodo           = [metodo_map[m] for m in df.metodo],
        seed             = df.seed_red,
        sigma_rel        = df.sigma_ruido,
        porcentaje_ruido = 100.0 .* df.sigma_ruido,
        RMSE_SIR         = df.rmse_global,
        RMSE_I           = df.rmse_I,
        RMSE_beta        = df.rmse_beta,
    )
end

println("✓ tabla_ruido_unificada definida")

"""
    correr_todo_experimento5_ruido(; escenarios=SCENARIO_ORDER,
                                    sigma_values=[0.00,0.05,0.10,0.20],
                                    seeds_red=1:10, outdir="results/final_suite")

Experimento de ruido unificado (rediseño 05-sep-2026 -- REEMPLAZA lo que
antes eran dos experimentos separados e incompatibles entre sí: Exp 4,
σ=fracción de N vía esta misma función, y Exp 5, σ absoluto en individuos
vía `experiments/03_run_noise_sensitivity_all.jl`/`src/lib/07`, ambos eliminados).
`sigma_values` son niveles de σ_rel -- ruido multiplicativo relativo a la
magnitud de cada observación (ver `generar_datos`), la MISMA grilla para
los 7 escenarios.

`correr_experimento_5_ruido` ya era genérica en `caso_beta`. Aquí se corre
para los 7 escenarios y se producen tres salidas en `outdir`:

  - `exp_ruido_<escenario>_multisemilla.csv`      : esquema interno, por escenario
  - `comparacion_pareada_ruido_TODOS_escenarios.csv` : t pareada + Wilcoxon por (escenario, σ_rel)
  - `ruido_detalle_unificado_TODOS_escenarios.csv`   : TODAS las repeticiones individuales,
    esquema unificado (escenario, metodo, seed, sigma_rel, porcentaje_ruido,
    RMSE_SIR, RMSE_I, RMSE_beta) -- la tabla pedida para el artículo.
"""
function correr_todo_experimento5_ruido(; escenarios::Vector{Symbol}=SCENARIO_ORDER,
                                          sigma_values::Vector{Float64}=[0.00, 0.05, 0.10, 0.20],
                                          seeds_red=1:10,
                                          outdir::String="results/final_suite")
    mkpath(outdir)
    seeds_red = semillas_final(seeds_red)
    filas = NamedTuple[]
    tablas_unificadas = DataFrame[]
    prog  = iniciar_progreso("(B) Experimento de ruido (σ_rel unificado) — escenarios", length(escenarios))

    for caso in escenarios
        cfg = SCENARIO_CONFIG[caso]
        label = SCENARIO_LABELS[caso]
        println("\n→ Experimento de ruido (σ_rel multiplicativo, unificado) — $label")

        df = correr_experimento_5_ruido(caso_beta=caso, sigma_values=sigma_values,
                                         seeds_red=seeds_red, m=cfg.m)
        # correr_experimento_5_ruido ya escribe "exp5_ruido_multisemilla.csv"
        # en la raíz del proyecto (comportamiento heredado); además
        # guardamos una copia por escenario para no pisar resultados entre
        # escenarios sucesivos.
        percaso_path = joinpath(outdir, "exp_ruido_$(String(caso))_multisemilla.csv")
        CSV.write(percaso_path, df)
        push!(tablas_unificadas, tabla_ruido_unificada(df, label))

        for sigma in sigma_values
            res = comparar_pareado(df; caso_beta=String(caso), m=cfg.m,
                                    metrica=:rmse_beta, sigma_ruido=sigma)
            push!(filas, (
                escenario = label, sigma_ruido = sigma, m = cfg.m,
                media_UDE = res.media_global, std_UDE = res.std_global,
                media_Windowed = res.media_ventanas, std_Windowed = res.std_ventanas,
                t_stat = res.t_test.t,
                p_valor_t_dos_colas = pvalue(res.t_test),
                p_valor_wilcoxon_dos_colas = pvalue(res.wilcoxon),
                direccion_esperada = res.media_ventanas < res.media_global,
            ))
        end
        avanzar!(prog; detalle=label)
    end
    finalizar_progreso!(prog)

    df_out = DataFrame(filas)
    path = joinpath(outdir, "comparacion_pareada_ruido_TODOS_escenarios.csv")
    CSV.write(path, df_out)
    println("\n✓ Comparación pareada bajo ruido consolidada en $path")

    df_unificado = vcat(tablas_unificadas...)
    path_unificado = joinpath(outdir, "ruido_detalle_unificado_TODOS_escenarios.csv")
    CSV.write(path_unificado, df_unificado)
    println("✓ Detalle unificado (esquema del artículo: escenario, metodo, seed, sigma_rel,")
    println("  porcentaje_ruido, RMSE_SIR, RMSE_I, RMSE_beta) guardado en $path_unificado")

    return df_out
end

println("✓ correr_todo_experimento5_ruido definida")


# ── 5. Trayectorias puntuales para los 7 escenarios ───────────────────────
"""
    graficar_todas_trayectorias(; escenarios=SCENARIO_ORDER, seed_red=1,
                                 outdir="results/trayectorias")

`graficar_trayectorias` (Sección 18) es genérica pero solo se había usado
para `:lineal`. La corre aquí para los 7 escenarios (global y ventanas,
m tomado de `SCENARIO_CONFIG`).
"""
function graficar_todas_trayectorias(; escenarios::Vector{Symbol}=SCENARIO_ORDER,
                                      seed_red::Int=1,
                                      outdir::String="results/trayectorias")
    mkpath(outdir)
    prog = iniciar_progreso("(C) Trayectorias puntuales — escenarios", length(escenarios))
    for caso in escenarios
        cfg = SCENARIO_CONFIG[caso]
        graficar_trayectorias(caso, :global,   missing, seed_red; outdir=outdir)
        graficar_trayectorias(caso, :ventanas, cfg.m,   seed_red; outdir=outdir)
        avanzar!(prog; detalle=String(caso))
    end
    finalizar_progreso!(prog)
    println("✓ Trayectorias generadas para los $(length(escenarios)) escenarios en $outdir")
end

println("✓ graficar_todas_trayectorias definida")

println("\n✓ src/lib/10_final_synthetic_experiments.jl cargado -- experimentos generalizados a los 7 escenarios sintéticos")
println("  (la sensibilidad de datos reales a N/γ vive ahora en src/lib/13_real_data_sensitivity_n_gamma.jl)")
