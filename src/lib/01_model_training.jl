function generate_sir_trajectory(beta_fn)
    datos = zeros(3, T + 1)
    datos[:, 1] .= u0

    for k in 1:T
        S_k, I_k, R_k = datos[1, k], datos[2, k], datos[3, k]
        t_k = ts[k]   # ts[1]=0, ts[2]=1, ...

        β = beta_fn(t_k, I_k)
        β = max(β_min_real, β)

        contagios   = β * S_k * I_k / N * Δt
        recuperados = γ * I_k * Δt

        datos[1, k+1] = S_k - contagios
        datos[2, k+1] = I_k + contagios - recuperados
        datos[3, k+1] = R_k + recuperados
    end

    # Verificación de conservación S+I+R = N
    desvio = maximum(abs.(datos[1,:] .+ datos[2,:] .+ datos[3,:] .- N))
    @assert desvio < 1e-10 "Error: S+I+R ≠ N (desvío máx = $desvio)"

    return datos
end

println("✓ generate_sir_trajectory definida")

function build_network(hidden::Int=0, layers::Int=1; seed::Int=1234,
                        bias_inicial::Float32=0.25f0)
    # [2026-09-07] `bias_inicial` se agregó como kwarg OPCIONAL, con el
    # mismo default (0.25f0) que tenía hardcodeado antes -- ningún llamador
    # existente (los 7 escenarios sintéticos, Exp 1-7, ya reportados) cambia
    # de comportamiento. Los runners de datos reales que adoptan las
    # condiciones iniciales fijas de Córdova-Lepe et al. 2026 (Medwave
    # e3191) pueden pasar `bias_inicial=Float32(BETA0_REF_FIJO)` (=0.20f0)
    # explícitamente -- ver src/lib/11_real_data.jl, sección 1bis. NO se cambió
    # el default global: hacerlo alteraría silenciosamente la inicialización
    # de todos los escenarios sintéticos ya reportados en el manuscrito.
    rng = MersenneTwister(seed)

    if hidden == 0
        # Red lineal: arquitectura del notebook validado
        model = Lux.Chain(Lux.Dense(2 => 1, identity))
    else
        layer_list = Any[Lux.Dense(2 => hidden, tanh)]
        for _ in 2:layers
            push!(layer_list, Lux.Dense(hidden => hidden, tanh))
        end
        push!(layer_list, Lux.Dense(hidden => 1, identity))
        model = Lux.Chain(layer_list...)
    end

    p_nn, st = Lux.setup(rng, model)
    p0 = ComponentArray(p_nn)

    # Inicialización controlada: weights≈0, bias≈bias_inicial (0.25 por defecto)
    last_key = keys(p0)[end]
    if haskey(p0[last_key], :weight)
        p0[last_key].weight .= 0.0f0
    end
    if haskey(p0[last_key], :bias)
        p0[last_key].bias .= bias_inicial
    end

    return model, p0, st
end

println("✓ build_network definida")

function beta_theta(t, I, p, st_nn, nn_beta)
    x = Float32[t / T, I / N]
    z, _ = nn_beta(x, p, st_nn)
    return z[1]
end

function paso_sir_ude(u, t_k, p, st_nn, nn_beta)
    S, I, R = u[1], u[2], u[3]
    β = beta_theta(t_k, I, p, st_nn, nn_beta)
    contagios   = β * S * I / N * Δt
    recuperados = γ * I * Δt
    return [S - contagios, I + contagios - recuperados, R + recuperados]
end

println("✓ beta_theta y paso_sir_ude definidos")

function train_global(datos, nn_beta, st_nn, p0;
                      epochs::Int=1500, lr::Float64=0.01, guardar_cada::Int=25)
    losses         = Float64[]
    iter_snapshots = Int[]
    params_snaps   = Any[]

    push!(iter_snapshots, 0)
    push!(params_snaps, deepcopy(p0))

    function loss_fn(p, _)
        acc   = 0.0
        u_hat = datos[:, 1]
        for k in 1:T
            u_hat = paso_sir_ude(u_hat, ts[k], p, st_nn, nn_beta)
            diff  = (u_hat .- datos[:, k+1]) ./ N
            acc  += sum(diff .^ 2)
        end
        return acc / T
    end

    callback = function(state, loss)
        push!(losses, loss)
        iter = length(losses)
        if iter % guardar_cada == 0
            push!(iter_snapshots, iter)
            push!(params_snaps, deepcopy(state.u))
        end
        if iter % 100 == 0
            @printf("  [UDE]  iter %4d  L=%.6e\n", iter, loss)
        end
        return false
    end

    optf    = Optimization.OptimizationFunction(loss_fn, Optimization.AutoZygote())
    optprob = Optimization.OptimizationProblem(optf, p0)
    res     = Optimization.solve(optprob, ADAM(lr); maxiters=epochs, callback=callback)

    p_trained = res.u
    push!(iter_snapshots, length(losses))
    push!(params_snaps, deepcopy(p_trained))

    @printf("  [UDE] Final  L=%.6e\n", losses[end])
    return p_trained, losses, iter_snapshots, params_snaps
end

println("✓ train_global definida")

function train_windowed(datos, nn_beta, st_nn, p0;
                        m::Int=6, epochs::Int=1500, lr::Float64=0.01,
                        guardar_cada::Int=25,
                        clip_norm::Union{Nothing,Float64}=nothing)
    n_ventanas     = length(ts) - m    # = T+1 - m
    losses         = Float64[]
    iter_snapshots = Int[]
    params_snaps   = Any[]

    push!(iter_snapshots, 0)
    push!(params_snaps, deepcopy(p0))

    function loss_fn(p, _)
        acc = 0.0
        for idx0 in 1:n_ventanas
            u_hat = datos[:, idx0]          # ancla en estado observado
            for j in 0:(m-1)
                u_hat  = paso_sir_ude(u_hat, ts[idx0 + j], p, st_nn, nn_beta)
                u_real = datos[:, idx0 + j + 1]
                diff   = (u_hat .- u_real) ./ N
                acc   += sum(diff .^ 2)
            end
        end
        return acc / (n_ventanas * m)
    end

    callback = function(state, loss)
        push!(losses, loss)
        iter = length(losses)
        if iter % guardar_cada == 0
            push!(iter_snapshots, iter)
            push!(params_snaps, deepcopy(state.u))
        end
        if iter % 100 == 0
            @printf("  [SW-UDE m=%d]  iter %4d  L=%.6e\n", m, iter, loss)
        end
        return false
    end

    # Optimizador: ADAM simple, o ADAM + recorte de gradiente (norma global)
    # cuando se especifica `clip_norm`. Pensado para escenarios con
    # retroalimentación fuerte de β sobre I (p. ej. :saturacion), donde una
    # ventana mal inicializada puede producir gradientes muy grandes y
    # desestabilizar el entrenamiento (ver SCENARIO_CONFIG, Sección 13.5).
    optimiser = clip_norm === nothing ?
        ADAM(lr) :
        Optimisers.OptimiserChain(Optimisers.ClipNorm(clip_norm), ADAM(lr))

    optf    = Optimization.OptimizationFunction(loss_fn, Optimization.AutoZygote())
    optprob = Optimization.OptimizationProblem(optf, p0)
    res     = Optimization.solve(optprob, optimiser; maxiters=epochs, callback=callback)

    p_trained = res.u
    push!(iter_snapshots, length(losses))
    push!(params_snaps, deepcopy(p_trained))

    @printf("  [SW-UDE m=%d] Final  L=%.6e\n", m, losses[end])
    return p_trained, losses, iter_snapshots, params_snaps
end

println("✓ train_windowed definida (con soporte opcional de clip_norm)")

# Rollout autónomo desde u0
function rollout(p, st_nn, nn_beta)
    pred = zeros(3, T+1)
    pred[:, 1] .= u0
    for k in 1:T
        pred[:, k+1] .= paso_sir_ude(pred[:, k], ts[k], p, st_nn, nn_beta)
    end
    return pred
end

# Evaluación de β sobre trayectoria de referencia (k = 1:T)
function eval_beta_on_ref(p, st_nn, nn_beta, datos, beta_fn)
    idx_beta = 1:T
    ts_beta  = ts[idx_beta]

    β_true    = [beta_fn(ts[k], datos[2, k]) for k in idx_beta]
    β_hat     = [beta_theta(ts[k], datos[2, k], p, st_nn, nn_beta) for k in idx_beta]
    β_directa = [
        datos[1, k] * datos[2, k] >= UMBRAL_SI ?
            N * (datos[1, k] - datos[1, k+1]) / (datos[1, k] * datos[2, k] * Δt) :
            NaN
        for k in idx_beta
    ]

    return ts_beta, β_true, β_hat, β_directa
end

# Métricas RMSE y MAE
function compute_metrics(pred, datos, β_hat, β_true)
    rmse(a, b) = sqrt(mean((a .- b).^2))
    mae(a,  b) = mean(abs.(a .- b))
    (
        RMSE_S = rmse(pred[1,:], datos[1,:]),
        RMSE_I = rmse(pred[2,:], datos[2,:]),
        RMSE_R = rmse(pred[3,:], datos[3,:]),
        MAE_S  = mae( pred[1,:], datos[1,:]),
        MAE_I  = mae( pred[2,:], datos[2,:]),
        MAE_R  = mae( pred[3,:], datos[3,:]),
        RMSE_β = rmse(β_hat, β_true),
        MAE_β  = mae( β_hat, β_true),
    )
end

println("✓ rollout, eval_beta_on_ref y compute_metrics definidos")
