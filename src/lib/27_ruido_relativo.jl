# ============================================================
# src/lib/27_ruido_relativo.jl
# ------------------------------------------------------------
# Rediseño del ruido observacional (2026-09-05, a pedido de David) --
# REEMPLAZA los dos esquemas anteriores por uno solo:
#
#   (a) Ruido aditivo como fracción de N: σ_abs = σ·N, σ∈{0.01,0.05,0.10}
#       (usado por generar_datos/correr_experimento_5_ruido, src/lib/08 y
#       src/lib/10 -- Exp 4 del inventario).
#   (b) Ruido aditivo absoluto: σ∈{0,2,5,10,20} individuos (experiments/03,
#       src/lib/07 -- Exp 5 del inventario).
#
# PROBLEMA con (a): escalar por N (tamaño POBLACIONAL) en vez de por la
# magnitud de la variable observada I(t) puede producir perturbaciones
# desproporcionadas cuando I(t) es pequeño frente a N. Ejemplo: N=1000,
# I0=10 -> 0.01·N=10 individuos = 100% de I0 (un "1% de ruido" que en
# realidad duplica la observación). (a) y (b) tampoco son comparables
# entre sí al no compartir unidad.
#
# NUEVO ESQUEMA -- ruido MULTIPLICATIVO relativo a cada observación:
#
#   X_obs(k) = max(0, X_true(k) · (1 + ε_k)),   ε_k ~ N(0, σ_rel²)
#
# con grilla única σ_rel ∈ {0.00, 0.05, 0.10, 0.20} (0%, 5%, 10%, 20%),
# la MISMA para los 7 escenarios sintéticos -- reemplaza tanto a (a) como
# a (b). La magnitud del ruido ahora se adapta automáticamente a la
# escala de la observación en cada instante, en vez de depender de N.
#
# NOTA METODOLÓGICA: 5%/10%/20% son una grilla interpretable y
# consistente para evaluar robustez observacional, NO umbrales
# epidemiológicos validados en la literatura -- no presentar como tales
# sin una justificación bibliográfica específica agregada aparte.
#
# Ver MAPA_EXPERIMENTOS.md para qué runners cambiaron y cuáles se
# retiraron como consecuencia de este rediseño.
# ============================================================

using Random

"""
    agregar_ruido_relativo(X_true, sigma_rel, rng)

Ruido observacional multiplicativo, relativo a la magnitud de CADA
observación (no a N, no a un valor absoluto fijo):

    X_obs = max.(0, X_true .* (1 .+ ε)),   ε ~ N(0, sigma_rel²)

Argumentos
----------
X_true    : serie o trayectoria "verdadera" (cualquier `AbstractArray`
            numérico -- un vector I(t), o una matriz S/I/R apilada).
sigma_rel : nivel de ruido relativo (p. ej. 0.05 = 5% de la magnitud de
            cada observación). `sigma_rel=0.0` devuelve `X_true` sin
            perturbar (ε≡0), útil como caso de referencia sin tener que
            ramificar en el código que llama.
rng       : generador de números aleatorios YA sembrado (p. ej.
            `MersenneTwister(seed)`) -- pasarlo explícito, en vez de un
            `seed::Int`, es lo que permite reutilizar EXACTAMENTE la
            misma realización de ruido al comparar UDE vs SW-UDE bajo
            diseño pareado: alcanza con construir el `rng` una sola vez
            por combinación (escenario, σ_rel, seed) y pasarlo a ambos
            métodos.

No garantiza `S+I+R=N` si se aplica por separado a cada compartimento de
una trayectoria SIR -- para eso usar `agregar_ruido_relativo_sir` (más
abajo), que agrega la renormalización necesaria.

Devuelve un array del mismo tamaño que `X_true`.
"""
function agregar_ruido_relativo(X_true::AbstractArray{<:Real}, sigma_rel::Real, rng::AbstractRNG)
    sigma_rel >= 0 || error("sigma_rel debe ser >= 0 (recibido $sigma_rel)")
    epsilon = sigma_rel .* randn(rng, size(X_true))
    X_obs = X_true .* (1 .+ epsilon)
    X_obs .= max.(X_obs, 0.0)
    return X_obs
end

"""
    agregar_ruido_relativo_sir(datos, sigma_rel; seed, N)

Envoltorio de `agregar_ruido_relativo` para una trayectoria SIR completa
(matriz 3×(T+1): filas S, I, R) -- reemplazo directo de
`add_gaussian_noise` (src/lib/07_noise_sensitivity.jl, esquema retirado) con
la misma firma de uso (matriz de entrada, `seed` entero, requiere `N`
para la restricción de conservación de población).

Aplica `agregar_ruido_relativo` a los tres compartimentos con la MISMA
`sigma_rel` (realizaciones de ruido independientes entre S, I y R, mismo
criterio que el esquema anterior), y como agregar ruido de forma
independiente a cada compartimento puede romper `S+I+R=N`, renormaliza
cada columna (cada instante `t`) para preservar esa restricción del
modelo SIR -- una de las dos alternativas discutidas para no violar las
restricciones epidemiológicas (la otra, aplicar ruido solo a la variable
observable I(t) y reconstruir S/R a partir de ella, es la que ya usa el
pipeline de datos reales, ver `construir_SIR_desde_I` en src/lib/11).

`seed` sembra un `MersenneTwister` propio de esta llamada -- pasar el
MISMO `seed` para UDE global y SW-UDE en una misma combinación
(escenario, σ_rel, seed_red) es lo que garantiza la comparación pareada
(exactamente el mismo patrón que `seed_ruido` ya usaba con el esquema
anterior en `generar_datos`, src/lib/08_experiment18_core.jl).
"""
function agregar_ruido_relativo_sir(datos::Matrix{Float64}, sigma_rel::Real;
                                     seed::Int, N::Float64)
    rng = MersenneTwister(seed)
    datos_noisy = agregar_ruido_relativo(datos, sigma_rel, rng)

    # Renormalizar cada columna (cada instante t) para que S*+I*+R*=N --
    # agregar_ruido_relativo ya recorta a cero, pero perturba cada
    # compartimento por separado y no preserva la suma por sí sola.
    col_sums = sum(datos_noisy, dims=1)
    col_sums .= max.(col_sums, 1e-10)   # evita división por cero si una columna quedó toda en cero
    datos_noisy .= datos_noisy .* (N ./ col_sums)

    return datos_noisy
end

println("✓ agregar_ruido_relativo / agregar_ruido_relativo_sir definidas -- ruido observacional")
println("  relativo a la magnitud de cada observación (reemplaza los esquemas de σ=fracción de N")
println("  y σ absoluto en individuos). Grilla recomendada: sigma_rel ∈ {0.00, 0.05, 0.10, 0.20}.")
