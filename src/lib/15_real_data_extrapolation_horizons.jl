# ============================================================
# src/lib/15_real_data_extrapolation_horizons.jl
# ------------------------------------------------------------
# Métricas de EXTRAPOLACIÓN por horizonte sobre datos reales -- cierra el
# último paso del flujo de trabajo de datos reales: "obtener métricas de
# extrapolación (RMSE) para 1, 2, 3, 5, 7, 10 días a futuro".
#
# Diseño (rolling-origin / walk-forward, no un solo punto):
#   - Con un único origen de pronóstico (p. ej. anclar solo en el día de
#     corte train/test y medir el error a h días), "RMSE" tendría n=1 --
#     en la práctica sería solo el error absoluto de un punto, no una
#     métrica estadísticamente robusta.
#   - En cambio, `rmse_extrapolacion_horizontes` recorre TODOS los días de
#     origen r desde el último día de entrenamiento (inclusive) hasta el
#     final de la serie (r ∈ dia_split:last(idx_test)), y para cada uno
#     propaga el modelo YA ENTRENADO (sin reentrenar nada acá) h días
#     hacia adelante, anclando SIEMPRE en el estado REAL observado en r
#     (mismo criterio que `train_windowed_rd`: anclar en dato real, no en
#     la propia predicción del modelo, para no mezclar error acumulado de
#     un rollout largo con la habilidad de pronóstico genuina a horizonte
#     h). El RMSE_h agrega el error sobre TODOS esos orígenes válidos.
#   - Se restringe a orígenes desde el día de corte en adelante para que
#     cada instancia evaluada sea una extrapolación genuina -- el modelo
#     nunca usó esos días como objetivo de entrenamiento, salvo el propio
#     día de corte (el último día de entrenamiento), que es el origen
#     "natural" de cualquier pronóstico y por eso se incluye.
# ============================================================


"""
    rmse_extrapolacion_horizontes(cfg, SIR, p, st_nn, nn_beta;
                                   idx_test, horizontes=[1,2,3,5,7,10],
                                   etiqueta="")

Ver docstring del módulo para la metodología completa (rolling-origin,
orígenes restringidos a `dia_split:last(idx_test)`, siempre anclados en el
estado real).

`p`, `st_nn`, `nn_beta` deben ser los parámetros/arquitectura YA
ENTRENADOS de un modelo (Global o SW-UDE) -- esta función NO entrena
nada, solo evalúa hacia adelante con `paso_sir_ude_rd`.

Devuelve un `DataFrame` con una fila por horizonte: `horizonte`,
`n_origenes` (cuántos orígenes válidos se promediaron para ese
horizonte), `RMSE_h`, `MAE_h` (sobre I(t), la única serie realmente
observada), `etiqueta` (para distinguir UDE/SW-UDE al concatenar
resultados de varios modelos).
"""
function rmse_extrapolacion_horizontes(cfg, SIR::Matrix{Float64},
                                        p, st_nn, nn_beta;
                                        idx_test::AbstractRange{Int},
                                        horizontes::Vector{Int}=[1, 2, 3, 5, 7, 10],
                                        etiqueta::String="")
    dia_split           = first(idx_test) - 1        # último día de entrenamiento
    origenes_candidatos = dia_split:last(idx_test)    # día de corte + todo el tramo de test

    filas = NamedTuple[]
    for h in horizontes
        origenes_validos = [r for r in origenes_candidatos if (r + h) <= cfg.T]
        @assert !isempty(origenes_validos) "Sin orígenes válidos para horizonte h=$h -- " *
            "idx_test demasiado corto (o h demasiado grande) para esta serie"

        errores = Float64[]
        for r in origenes_validos
            u_hat = SIR[:, r + 1]                     # ancla en el estado REAL del día r
            for j in 0:(h - 1)
                u_hat = paso_sir_ude_rd(cfg, u_hat, cfg.ts[r + 1 + j], p, st_nn, nn_beta)
            end
            push!(errores, u_hat[2] - SIR[2, r + h + 1])   # error sobre I (única serie observada)
        end

        push!(filas, (
            horizonte  = h,
            n_origenes = length(origenes_validos),
            RMSE_h     = sqrt(mean(errores .^ 2)),
            MAE_h      = mean(abs.(errores)),
            etiqueta   = etiqueta,
        ))
    end

    return DataFrame(filas)
end

println("✓ rmse_extrapolacion_horizontes definida")


"""
    evaluar_extrapolacion_horizontes_real(resultado, SIR; hidden, layers,
                                           seed_red=1234,
                                           horizontes=[1,2,3,5,7,10],
                                           outdir="results/datos_reales")

Envoltorio de conveniencia sobre el `resultado` devuelto por
`evaluar_datos_reales_v2` (src/lib/11_real_data.jl): reconstruye la
arquitectura (`build_network`, mismos `hidden`/`layers`/`seed_red` usados
para entrenar) para UDE y SW-UDE -- no hace falta que
`evaluar_datos_reales_v2` devuelva `nn_beta`/`st_nn` explícitamente,
porque esos objetos son puramente estructurales (no dependen de los
parámetros ya entrenados `p_g`/`p_w`, que sí vienen en `resultado`) -- y
corre `rmse_extrapolacion_horizontes` para ambos métodos, concatenando el
resultado en un único DataFrame/CSV (columna `etiqueta`: "UDE" /
"SW-UDE").

Guarda dos archivos en `outdir`:
  - `datos_reales_extrapolacion_horizontes.csv`
  - `datos_reales_extrapolacion_horizontes.{png,pdf,eps}` (RMSE_h vs.
    horizonte, una curva por modelo)

Devuelve el `DataFrame`.
"""
function evaluar_extrapolacion_horizontes_real(resultado, SIR::Matrix{Float64};
                                                hidden::Int, layers::Int,
                                                seed_red::Int=1234,
                                                horizontes::Vector{Int}=[1, 2, 3, 5, 7, 10],
                                                outdir::String="results/datos_reales")
    mkpath(outdir)
    cfg      = resultado.config
    idx_test = resultado.idx_test

    nn_beta, _, st_nn = build_network(hidden, layers; seed=seed_red, bias_inicial=Float32(BETA0_REF_FIJO))

    df_g = rmse_extrapolacion_horizontes(cfg, SIR, resultado.global_.p, st_nn, nn_beta;
                                          idx_test=idx_test, horizontes=horizontes, etiqueta="UDE")
    df_w = rmse_extrapolacion_horizontes(cfg, SIR, resultado.ventanas.p, st_nn, nn_beta;
                                          idx_test=idx_test, horizontes=horizontes,
                                          etiqueta="SW-UDE")
    df = vcat(df_g, df_w)

    path = joinpath(outdir, "datos_reales_extrapolacion_horizontes.csv")
    CSV.write(path, df)
    println("\n✓ CSV de extrapolación por horizonte guardado en $path")
    println("  Columnas: etiqueta (UDE/SW-UDE), horizonte (días a futuro), ",
            "n_origenes, RMSE_h, MAE_h")
    println(df)

    # Figura de referencia: RMSE_h vs. horizonte, una curva por modelo
    p_h = plot(xlabel="Forecast horizon (days ahead)", ylabel="RMSE (extrapolation)",
               title="Real data — extrapolation error by horizon",
               legend=:outertopright, size=(900, 480),
               left_margin=6mm, right_margin=2mm, bottom_margin=8mm)
    for et in unique(df.etiqueta)
        sub   = sort(filter(r -> r.etiqueta == et, df), :horizonte)
        color = et == "UDE" ? :orange : :steelblue
        plot!(p_h, sub.horizonte, sub.RMSE_h, lw=2, marker=:circle, color=color, label=et)
    end
    savefig_all(p_h, joinpath(outdir, "datos_reales_extrapolacion_horizontes");
                formats=(:png, :pdf, :eps))
    println("  Figura guardada en $outdir/datos_reales_extrapolacion_horizontes.{png,pdf,eps}")

    return df
end

println("✓ evaluar_extrapolacion_horizontes_real definida")
