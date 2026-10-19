# Ejecutar una sola vez si no están instaladas:
# import Pkg; Pkg.add(["HypothesisTests", "StatsPlots"])
using HypothesisTests   # OneSampleTTest (t pareada), SignedRankTest (Wilcoxon pareada)
using StatsPlots        # boxplot(...)

println("✓ HypothesisTests y StatsPlots cargadas")

"""
    generar_datos(caso_beta::Symbol; seed_datos::Int=1234,
                  sigma_ruido::Float64=0.0, seed_ruido::Int=1234)

Genera la trayectoria sintética de referencia para `caso_beta` (reutiliza
`generate_sir_trajectory` + `BETA_FUNCTIONS`, Secciones 3–4) y, si
`sigma_ruido > 0`, una versión contaminada con ruido observacional.

REDISEÑO (05-sep-2026): `sigma_ruido` se reinterpreta como σ_rel, el nivel
de ruido MULTIPLICATIVO relativo a la magnitud de cada observación (ya no
una fracción de N) -- ver `src/lib/27_noise_relative.jl` para la justificación
completa y `agregar_ruido_relativo_sir` para la implementación:

    X_obs(k) = max(0, X_true(k)·(1+ε_k)),  ε_k ~ N(0, σ_rel²)

con renormalización por columna para preservar S+I+R=N. Esto REEMPLAZA el
esquema anterior (σ_abs = sigma_ruido·N vía `add_gaussian_noise`,
src/lib/07_noise_sensitivity.jl -- eliminado) y unifica el criterio con el que
antes usaba `experiments/03_run_noise_sensitivity_all.jl` (σ absoluto en
individuos, también eliminado). Se usa SIEMPRE `seed_ruido` -- así la
misma realización de ruido puede reutilizarse en UDE global y UDE por
ventanas (ver nota de comparación pareada arriba). Grilla recomendada:
sigma_ruido (=σ_rel) ∈ {0.00, 0.05, 0.10, 0.20}.

`seed_datos` se conserva por compatibilidad de interfaz: la generación de
la trayectoria limpia es determinística dado `caso_beta` (sin componente
aleatorio en `generate_sir_trajectory`), así que hoy no cambia el
resultado. Se deja explícito para no sugerir variabilidad de datos donde
la única fuente real de variabilidad es `seed_red` (inicialización de la
red) y, si corresponde, `seed_ruido`.

Devuelve una NamedTuple con:
- `datos_limpio`  : trayectoria de referencia sin ruido (SIEMPRE se evalúa contra esta)
- `datos_entren`  : trayectoria usada para entrenar (= datos_limpio si sigma_ruido=0)
- `beta_fn`       : función β_real(t,I) del escenario
"""
function generar_datos(caso_beta::Symbol; seed_datos::Int=1234,
                        sigma_ruido::Float64=0.0, seed_ruido::Int=1234)
    @assert haskey(BETA_FUNCTIONS, caso_beta) "Caso beta desconocido: $caso_beta"
    beta_fn      = BETA_FUNCTIONS[caso_beta]
    datos_limpio = generate_sir_trajectory(beta_fn)

    datos_entren = sigma_ruido > 0.0 ?
        agregar_ruido_relativo_sir(datos_limpio, sigma_ruido; seed=seed_ruido, N=Float64(N)) :
        datos_limpio

    return (caso_beta=caso_beta, beta_fn=beta_fn,
            datos_limpio=datos_limpio, datos_entren=datos_entren,
            sigma_ruido=sigma_ruido, seed_ruido=seed_ruido, seed_datos=seed_datos)
end

println("✓ generar_datos definida")

"""
    entrenar_global(datos_pack; seed_red, hiperparametros)

`hiperparametros` es una NamedTuple con al menos `hidden, layers, lr,
epochs` (campos extra como `clip_norm` se ignoran, ya que `train_global`
no lo usa). Entrena sobre `datos_pack.datos_entren` (con o sin ruido) y
devuelve todo lo necesario para evaluar después con `calcular_metricas`.
"""
function entrenar_global(datos_pack; seed_red::Int, hiperparametros::NamedTuple)
    h = hiperparametros
    nn_beta, p0, st_nn = build_network(h.hidden, h.layers; seed=seed_red)
    p_g, losses, _, _ = train_global(datos_pack.datos_entren, nn_beta, st_nn, p0;
                                      epochs=h.epochs, lr=h.lr,
                                      guardar_cada=h.epochs + 1)
    return (metodo=:global, m=missing, p=p_g, nn_beta=nn_beta, st_nn=st_nn,
            losses=losses, hiperparametros=h, seed_red=seed_red)
end

"""
    entrenar_ventanas(datos_pack; m, seed_red, hiperparametros)

Igual que `entrenar_global`, pero con entrenamiento por ventanas de
longitud `m` (Sección 8, `train_windowed`). Si `hiperparametros` incluye
`clip_norm`, se usa para recorte de gradiente (necesario para escenarios
como `:saturacion`, ver Sección 13.5/17).
"""
function entrenar_ventanas(datos_pack; m::Int, seed_red::Int, hiperparametros::NamedTuple)
    h = hiperparametros
    nn_beta, p0, st_nn = build_network(h.hidden, h.layers; seed=seed_red)
    clip_norm = get(h, :clip_norm, nothing)
    p_w, losses, _, _ = train_windowed(datos_pack.datos_entren, nn_beta, st_nn, p0;
                                        m=m, epochs=h.epochs, lr=h.lr,
                                        guardar_cada=h.epochs + 1,
                                        clip_norm=clip_norm)
    return (metodo=:ventanas, m=m, p=p_w, nn_beta=nn_beta, st_nn=st_nn,
            losses=losses, hiperparametros=h, seed_red=seed_red)
end

println("✓ entrenar_global y entrenar_ventanas definidas")

"""
    evaluar_completo(resultado, datos_pack)

Evalúa un `resultado` (de `entrenar_global`/`entrenar_ventanas`) SIEMPRE
contra `datos_pack.datos_limpio` y `datos_pack.beta_fn` — nunca contra la
trayectoria de entrenamiento, aunque tenga ruido. Devuelve trajectories
reconstruidas, β real/aprendida, y las métricas escalares. Sirve tanto para
`calcular_metricas` (solo el resumen escalar) como para las funciones de
graficación de más abajo (que necesitan las curvas completas).
"""
function evaluar_completo(resultado, datos_pack)
    pred = rollout(resultado.p, resultado.st_nn, resultado.nn_beta)
    ts_beta, β_true, β_hat, β_directa = eval_beta_on_ref(
        resultado.p, resultado.st_nn, resultado.nn_beta,
        datos_pack.datos_limpio, datos_pack.beta_fn)

    met = compute_metrics(pred, datos_pack.datos_limpio, β_hat, β_true)
    rmse_global = sqrt(mean((pred .- datos_pack.datos_limpio) .^ 2))

    return (pred=pred, ts_beta=ts_beta, β_true=β_true, β_hat=β_hat, β_directa=β_directa,
            metricas=(RMSE_S=met.RMSE_S, RMSE_I=met.RMSE_I, RMSE_R=met.RMSE_R,
                      RMSE_global=rmse_global, RMSE_beta=met.RMSE_β, MAE_beta=met.MAE_β))
end

"""
    calcular_metricas(resultado, datos_pack)

Versión resumida de `evaluar_completo`: solo el NamedTuple de métricas
escalares (RMSE_S, RMSE_I, RMSE_R, RMSE_global, RMSE_beta, MAE_beta).
`RMSE_global` se define como el RMSE combinado sobre S, I y R apilados
(no el promedio de los tres RMSE por separado).
"""
calcular_metricas(resultado, datos_pack) = evaluar_completo(resultado, datos_pack).metricas

println("✓ evaluar_completo y calcular_metricas definidas")

"""
    ejecutar_repeticion(caso_beta, metodo, m, seed_red;
                        sigma_ruido=0.0, seed_ruido=1234,
                        hiperparametros=nothing)

Corre una repetición completa (genera datos → entrena → evalúa) y devuelve
una fila lista para `guardar_resultados_csv`, con el esquema de columnas
pedido: caso_beta, metodo, m, seed_red, sigma_ruido, seed_ruido, rmse_S,
rmse_I, rmse_R, rmse_global, rmse_beta, mae_beta, lr, epochs, arquitectura,
activacion.

Si `hiperparametros` es `nothing`, se toma de `SCENARIO_CONFIG[caso_beta]`
(misma arquitectura ya usada y documentada en el resto del notebook).
`metodo` debe ser `:global` o `:ventanas`; `m` se ignora si `metodo==:global`.

**Importante para comparaciones pareadas (Experimento 5):** llamar dos
veces (una por método) con el mismo `seed_ruido` para que ambos métodos
entrenen sobre la misma trayectoria contaminada.
"""
function ejecutar_repeticion(caso_beta::Symbol, metodo::Symbol, m,
                              seed_red::Int;
                              sigma_ruido::Float64=0.0, seed_ruido::Int=1234,
                              hiperparametros::Union{Nothing,NamedTuple}=nothing)
    @assert metodo in (:global, :ventanas) "metodo debe ser :global o :ventanas"

    cfg = SCENARIO_CONFIG[caso_beta]
    h = hiperparametros === nothing ?
        (hidden=cfg.hidden, layers=cfg.layers, lr=cfg.lr,
         epochs=epocas_final(cfg.epochs), clip_norm=cfg.clip_norm) :
        hiperparametros

    datos_pack = generar_datos(caso_beta; sigma_ruido=sigma_ruido, seed_ruido=seed_ruido)

    resultado = metodo == :global ?
        entrenar_global(datos_pack; seed_red=seed_red, hiperparametros=h) :
        entrenar_ventanas(datos_pack; m=m, seed_red=seed_red, hiperparametros=h)

    met = calcular_metricas(resultado, datos_pack)

    return (caso_beta=String(caso_beta), metodo=String(metodo),
            m=(metodo == :global ? missing : m),
            seed_red=seed_red, sigma_ruido=sigma_ruido, seed_ruido=seed_ruido,
            rmse_S=met.RMSE_S, rmse_I=met.RMSE_I, rmse_R=met.RMSE_R,
            rmse_global=met.RMSE_global, rmse_beta=met.RMSE_beta, mae_beta=met.MAE_beta,
            lr=h.lr, epochs=h.epochs,
            arquitectura="hidden=$(h.hidden),layers=$(h.layers)",
            activacion=(h.hidden == 0 ? "identity" : "tanh"))
end

"""
    guardar_resultados_csv(resultados::Vector; path)

Convierte un vector de filas (NamedTuples de `ejecutar_repeticion`) a
DataFrame y lo guarda en `path`. Devuelve el DataFrame.
"""
function guardar_resultados_csv(resultados::Vector; path::String="resultados_experiments.csv")
    df = DataFrame(resultados)
    CSV.write(path, df)
    println("✓ Resultados guardados en $path  ($(nrow(df)) filas)")
    return df
end

println("✓ ejecutar_repeticion y guardar_resultados_csv definidas")

# [2026-10-18] `correr_experimento_1_lineal` estaba aquí. Ningún runner del
# artículo la llamaba: quedó superada y se eliminó. Ver CHANGELOG.md.

"""
    resumen_por_m(df; caso_beta="lineal")

Experimento 2 (sensibilidad a m): agrupa las filas `:ventanas` del
Experimento 1 por `m` y calcula media ± desviación estándar de
`rmse_global` y `rmse_beta`. No entrena nada nuevo — reutiliza el CSV de
`correr_experimento_1_lineal`.
"""
function resumen_por_m(df::DataFrame; caso_beta::String="lineal")
    sub = filter(r -> r.metodo == "ventanas" && r.caso_beta == caso_beta, df)
    return combine(groupby(sub, :m),
                   :rmse_global => mean => :rmse_global_media,
                   :rmse_global => std  => :rmse_global_std,
                   :rmse_beta   => mean => :rmse_beta_media,
                   :rmse_beta   => std  => :rmse_beta_std)
end

# [2026-10-18] `correr_experimento_3_no_lineales` estaba aquí. Ningún runner del
# artículo la llamaba: quedó superada y se eliminó. Ver CHANGELOG.md.

"""
    correr_experimento_5_ruido(; caso_beta=:lineal, sigma_values=[0.00,0.05,0.10,0.20],
                                 seeds_red=1:10, m=nothing,
                                 outdir="results/final_suite_noise", save_csv=true)

Experimento de ruido (Exp 4/5 unificados, rediseño 05-sep-2026).
`sigma_values` son niveles de σ_rel -- ruido MULTIPLICATIVO relativo a la
magnitud de cada observación, no una fracción de N ni un σ absoluto en
individuos (ver `generar_datos` y `src/lib/27_noise_relative.jl`). Grilla por
defecto {0.00, 0.05, 0.10, 0.20}, la MISMA para los 7 escenarios --
reemplaza tanto al esquema de fracción-de-N (antes en esta función) como
al de σ absoluto (antes `experiments/03_run_noise_sensitivity_all.jl`, ambos
eliminados). Para cada combinación (sigma, seed_red) se construye un
`seed_ruido` único y se usa el MISMO para :global y :ventanas --
comparación pareada garantizada por construcción, no por casualidad.
"""
function correr_experimento_5_ruido(; caso_beta::Symbol=:lineal,
                                       sigma_values::Vector{Float64}=[0.00, 0.05, 0.10, 0.20],
                                       seeds_red=1:10, m::Union{Nothing,Int}=nothing,
                                       outdir::String="results/final_suite_noise",
                                       save_csv::Bool=true)
    cfg = SCENARIO_CONFIG[caso_beta]
    m_use = m === nothing ? cfg.m : m
    resultados = []
    for sigma in sigma_values, seed_red in seeds_red
        seed_ruido = 10_000 * Int(round(sigma * 1000)) + seed_red
        resultados_global  = ejecutar_repeticion(caso_beta, :global, missing, seed_red;
                                                  sigma_ruido=sigma, seed_ruido=seed_ruido)
        resultados_ventana = ejecutar_repeticion(caso_beta, :ventanas, m_use, seed_red;
                                                  sigma_ruido=sigma, seed_ruido=seed_ruido)
        push!(resultados, resultados_global)
        push!(resultados, resultados_ventana)
    end
    if save_csv
        mkpath(outdir)
        path = joinpath(outdir, "exp5_noise_multiseed.csv")
        return guardar_resultados_csv(resultados; path=path)
    end
    return DataFrame(resultados)
end

println("✓ resumen_por_m, correr_experimento_5_ruido definidas")

"""
    comparar_pareado(df; caso_beta, m, metrica=:rmse_beta, sigma_ruido=0.0)

Compara :global vs :ventanas de forma PAREADA por `seed_red` (misma
semilla de red para ambos métodos), para la métrica indicada, dentro del
subconjunto con el `sigma_ruido` dado (0.0 = sin ruido).

H0: metrica_global == metrica_ventanas
H1: metrica_ventanas <  metrica_global   (ventanas reduce el error)

Devuelve el resultado de una prueba t pareada (`OneSampleTTest` sobre las
diferencias) y una prueba de Wilcoxon pareada (`SignedRankTest`), además de
las medias de cada grupo. El p-value reportado por ambos tests es de dos
colas; para el test de una cola (H1 dirigida) dividir por 2 cuando el
signo de la diferencia media va en la dirección esperada.
"""
function comparar_pareado(df::DataFrame; caso_beta::String, m,
                           metrica::Symbol=:rmse_beta, sigma_ruido::Float64=0.0)
    g = sort(filter(r -> r.caso_beta == caso_beta && r.metodo == "global" &&
                          r.sigma_ruido == sigma_ruido, df), :seed_red)
    w = sort(filter(r -> r.caso_beta == caso_beta && r.metodo == "ventanas" &&
                          r.m == m && r.sigma_ruido == sigma_ruido, df), :seed_red)
    @assert nrow(g) == nrow(w) && g.seed_red == w.seed_red "Las semillas de UDE y SW-UDE no coinciden -- la comparación pareada no es válida"

    x_g = Float64.(g[!, metrica])
    x_w = Float64.(w[!, metrica])
    diffs = x_g .- x_w   # > 0 si ventanas mejora (error menor)

    t_test = OneSampleTTest(diffs)
    w_test = SignedRankTest(x_g, x_w)

    println("Comparación pareada — $caso_beta, m=$m, σ=$sigma_ruido, métrica=$metrica")
    @printf("  UDE:          media=%.6f  std=%.6f  (n=%d)\n", mean(x_g), std(x_g), length(x_g))
    @printf("  SW-UDE:       media=%.6f  std=%.6f  (n=%d)\n", mean(x_w), std(x_w), length(x_w))
    @printf("  t pareada (2 colas):       t=%.4f  p=%.4g\n", t_test.t, pvalue(t_test))
    @printf("  Wilcoxon pareada (2 colas): p=%.4g\n", pvalue(w_test))
    if mean(diffs) > 0
        println("  → diferencia media va en la dirección esperada (SW-UDE < UDE); ",
                "p de una cola ≈ p_dos_colas/2")
    else
        println("  → ¡atención! la diferencia media va en dirección CONTRARIA a H1 ",
                "(SW-UDE no mejora en promedio para esta métrica/escenario)")
    end

    return (t_test=t_test, wilcoxon=w_test,
            media_global=mean(x_g), std_global=std(x_g),
            media_ventanas=mean(x_w), std_ventanas=std(x_w))
end

println("✓ comparar_pareado definida")
