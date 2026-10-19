# ============================================================
# Configuración unificada por escenario
# ============================================================
struct ScenarioConfig
    hidden::Int
    layers::Int
    m::Int
    epochs::Int
    lr::Float64
    clip_norm::Union{Nothing,Float64}   # recorte de gradiente (norma global); nothing = sin recorte
end

const SCENARIO_CONFIG = Dict(
    :constante    => ScenarioConfig(0,  1, 10, 3000, 0.010, nothing),
    :lineal       => ScenarioConfig(0,  1, 10, 7000, 0.010, nothing),
    # The tanh scenario changes rapidly near its transition, so its m-grid
    # includes shorter windows.
    :tanh         => ScenarioConfig(16, 2, 10, 8000, 0.005, nothing),
    :dos_olas     => ScenarioConfig(32, 2, 10, 8000, 0.005, nothing),
    :intervencion => ScenarioConfig(32, 2, 10, 8000, 0.005, nothing),
    :estacional   => ScenarioConfig(16, 2, 10, 8000, 0.005, nothing),
    # Gradient clipping stabilizes windowed training for this strongly
    # feedback-dependent scenario.
    :saturacion   => ScenarioConfig(16, 2, 10, 8000, 0.003, 5.0),
    # Architecture used for the real-data experiments; not in SCENARIO_ORDER.
    :realchile    => ScenarioConfig(16, 2, 10, 8000, 0.005, nothing),
)

const SCENARIO_ORDER = [:constante, :lineal, :tanh, :dos_olas,
                         :intervencion, :estacional, :saturacion]

# English file stems for generated artifacts; internal scenario symbols stay stable.
const SCENARIO_FILE_KEYS = Dict(
    :constante => "constant", :lineal => "linear", :tanh => "tanh",
    :dos_olas => "two_waves", :intervencion => "intervention",
    :estacional => "seasonal", :saturacion => "saturation",
    :realchile => "real_chile",
)
scenario_file_key(key::Symbol) = get(SCENARIO_FILE_KEYS, key, String(key))
scenario_file_key(key::AbstractString) = scenario_file_key(Symbol(key))

println("✓ SCENARIO_CONFIG definido para ", length(SCENARIO_CONFIG), " escenarios")
for key in SCENARIO_ORDER
    cfg = SCENARIO_CONFIG[key]
    @printf("  %-14s hidden=%-3d layers=%-2d m=%-3d epochs=%-6d lr=%.4f clip_norm=%s\n",
            String(key), cfg.hidden, cfg.layers, cfg.m, cfg.epochs, cfg.lr,
            string(cfg.clip_norm))
end

# ============================================================
# run_all_experiments — ejecuta y consolida TODOS los escenarios
# ============================================================
function run_all_experiments(; scenarios::Vector{Symbol}=SCENARIO_ORDER,
                              outdir::String="figures/all",
                              make_gif::Bool=true,
                              seed::Int=1234)
    mkpath(outdir)
    results = Dict{Symbol,Any}()
    rows    = NamedTuple[]
    prog    = iniciar_progreso("run_all_experiments (7 escenarios)", length(scenarios))

    for key in scenarios
        cfg = SCENARIO_CONFIG[key]
        println("\n" * "#"^70)
        println("  ", SCENARIO_LABELS[key],
                "  (hidden=$(cfg.hidden), layers=$(cfg.layers), m=$(cfg.m), epochs=$(cfg.epochs))")
        println("#"^70)

        res = run_experiment(key;
                              m         = cfg.m,
                              epochs    = epocas_final(cfg.epochs),
                              lr        = cfg.lr,
                              hidden    = cfg.hidden,
                              layers    = cfg.layers,
                              clip_norm = cfg.clip_norm,
                              seed      = seed,
                              outdir    = outdir,
                              save_csv  = true,
                              make_gif  = make_gif)
        results[key] = res
        avanzar!(prog; detalle=String(key))

        label = SCENARIO_LABELS[key]
        push!(rows, (escenario=label, modelo="UDE", m=NaN,
                      hidden=cfg.hidden, layers=cfg.layers,
                      RMSE_S=res.metrics_global.RMSE_S, RMSE_I=res.metrics_global.RMSE_I,
                      RMSE_R=res.metrics_global.RMSE_R, MAE_S=res.metrics_global.MAE_S,
                      MAE_I=res.metrics_global.MAE_I,   MAE_R=res.metrics_global.MAE_R,
                      RMSE_beta=res.metrics_global.RMSE_β, MAE_beta=res.metrics_global.MAE_β))
        push!(rows, (escenario=label, modelo="SW-UDE", m=Float64(cfg.m),
                      hidden=cfg.hidden, layers=cfg.layers,
                      RMSE_S=res.metrics_windowed.RMSE_S, RMSE_I=res.metrics_windowed.RMSE_I,
                      RMSE_R=res.metrics_windowed.RMSE_R, MAE_S=res.metrics_windowed.MAE_S,
                      MAE_I=res.metrics_windowed.MAE_I,   MAE_R=res.metrics_windowed.MAE_R,
                      RMSE_beta=res.metrics_windowed.RMSE_β, MAE_beta=res.metrics_windowed.MAE_β))
    end

    df_resumen = DataFrame(rows)
    CSV.write("$outdir/summary_ALL_scenarios.csv", df_resumen)
    println("\n✓ Resumen consolidado guardado en $outdir/summary_ALL_scenarios.csv")
    println(df_resumen)
    finalizar_progreso!(prog)

    return results, df_resumen
end

println("✓ run_all_experiments definida")

# ============================================================
# run_all_sensitivity — sensibilidad a m para TODOS los escenarios,
# consolidada en un único CSV. Reutiliza hidden/layers/lr/clip_norm de
# SCENARIO_CONFIG para que cada escenario use la arquitectura correcta.
#
# `m_values_override` permite pasar un grid de m distinto para escenarios
# puntuales (p. ej. :tanh y :saturacion, donde conviene un grid más fino
# que el default [1,3,5,10,20,50] — ver Sección 14b).
# ============================================================
function run_all_sensitivity(; scenarios::Vector{Symbol}=SCENARIO_ORDER,
                              m_values::Vector{Int}=[1,3,5,10,20,50],
                              m_values_override::Dict{Symbol,Vector{Int}}=Dict{Symbol,Vector{Int}}(),
                              outdir::String="figures/all",
                              seed::Int=1234)
    mkpath(outdir)
    all_dfs = DataFrame[]
    prog = iniciar_progreso("run_all_sensitivity (7 escenarios)", length(scenarios))

    for key in scenarios
        cfg   = SCENARIO_CONFIG[key]
        mvals = get(m_values_override, key, m_values)
        println("\n→ Sensibilidad m — ", SCENARIO_LABELS[key],
                "  (hidden=$(cfg.hidden), layers=$(cfg.layers), clip_norm=$(cfg.clip_norm), m_values=$mvals)")
        run_sensitivity(key; m_values=mvals, epochs=epocas_final(cfg.epochs),
                         lr=cfg.lr, hidden=cfg.hidden, layers=cfg.layers,
                         clip_norm=cfg.clip_norm,
                         seed=seed, outdir=outdir, save_csv=true)
        df_i = CSV.read("$outdir/$(scenario_file_key(key))_sensitivity_m.csv", DataFrame)
        push!(all_dfs, df_i)
        avanzar!(prog; detalle=String(key))
    end

    df_all = vcat(all_dfs...)
    CSV.write("$outdir/sensitivity_m_ALL_scenarios.csv", df_all)
    println("\n✓ Sensibilidad consolidada guardada en $outdir/sensitivity_m_ALL_scenarios.csv")
    finalizar_progreso!(prog)
    return df_all
end

println("✓ run_all_sensitivity definida (soporta m_values_override y clip_norm por escenario)")

# ============================================================
# Gráfico resumen: recuperación de β para TODOS los escenarios
# en una sola figura de publicación.
# ============================================================
function plot_beta_grid_summary(results::Dict;
                                 scenarios::Vector{Symbol}=SCENARIO_ORDER,
                                 outdir::String="figures/all",
                                 ncols::Int=4,
                                 filename::String="figura_resumen_beta_todos_escenarios")
    mkpath(outdir)
    nrows = ceil(Int, length(scenarios) / ncols)

    subplots = Plots.Plot[]
    for (i, key) in enumerate(scenarios)
        res   = results[key]
        label = SCENARIO_LABELS[key]

        p = plot(res.ts_beta, res.β_true,
                 lw = 2.2, color = :black, label = (i == 1 ? "β (observed data)" : ""),
                 xlabel = "t (days)",
                 ylabel = (mod1(i, ncols) == 1 ? "β(t,I)" : ""),
                 title = label, titlefontsize = 10, guidefontsize = 9,
                 tickfontsize = 7, legendfontsize = 8,
                 legend = (i == 1 ? :outertopright : false),
                 framestyle = :box)
        plot!(p, res.ts_beta, res.β_global, lw = 1.8, ls = :dash, color = :royalblue,
              label = (i == 1 ? "UDE" : ""))
        plot!(p, res.ts_beta, res.β_windowed, lw = 1.8, ls = :dot, color = :crimson,
              label = (i == 1 ? "SW-UDE (m=$(res.m_used))" : ""))
        push!(subplots, p)
    end

    # Rellena con paneles vacíos si el número de escenarios no completa la grilla
    while length(subplots) < nrows * ncols
        push!(subplots, plot(framestyle = :none, showaxis = false, grid = false))
    end

    fig = plot(subplots...; layout = (nrows, ncols),
               size = (380 * ncols, 320 * nrows), dpi = 300,
               left_margin = 6Plots.mm, right_margin = 4Plots.mm,
               top_margin = 6Plots.mm, bottom_margin = 6Plots.mm)

    savefig_all(fig, "$outdir/$(filename)"; formats=(:png, :pdf, :eps))
    println("✓ Figura resumen guardada en $outdir/$(filename).{pdf,png,eps}")
    return fig
end

println("✓ plot_beta_grid_summary definida")
