# ============================================================
# src/lib/04_progress.jl — Utilidades de progreso para corridas largas
# ------------------------------------------------------------
# Pensado específicamente para corridas lanzadas con `nohup` (sin
# terminal interactiva adjunta): cada `avanzar!` imprime una línea con
# timestamp, porcentaje, tiempo transcurrido y ETA estimado, para que
# `tail -f` sobre el log de un runner alcance para saber "en qué va".
#
# Deliberadamente NO decide nada por sí solo (no reintenta, no cambia
# hiperparámetros): solo instrumenta loops ya existentes con progreso
# legible, sin tocar la lógica de entrenamiento en sí.
# ============================================================

using Dates

"""
    formatear_duracion(segundos)

`segundos` (Float64, puede ser NaN si todavía no hay estimación) a texto
legible tipo "1h 23m 04s" / "45m 02s" / "12s". `NaN`/negativos -> "--".
"""
function formatear_duracion(segundos::Real)
    (isnan(segundos) || segundos < 0) && return "--"
    s = round(Int, segundos)
    h, resto = divrem(s, 3600)
    m, s2    = divrem(resto, 60)
    h > 0  && return @sprintf("%dh %02dm %02ds", h, m, s2)
    m > 0  && return @sprintf("%dm %02ds", m, s2)
    return @sprintf("%ds", s2)
end

"""
    Progreso(etiqueta, total)

Contador de progreso simple para un loop de `total` pasos conocidos de
antemano (p. ej. escenarios, semillas, combinaciones N×γ). Se construye
con `iniciar_progreso` y se actualiza con `avanzar!` dentro del loop.
"""
mutable struct Progreso
    etiqueta::String
    total::Int
    inicio::Float64
    completados::Int
end

"""
    iniciar_progreso(etiqueta::String, total::Int)

Imprime el encabezado ("▶ etiqueta: 0/total") y devuelve un `Progreso`
para usar con `avanzar!` en cada iteración del loop correspondiente.
"""
function iniciar_progreso(etiqueta::String, total::Int)
    println("\n▶ $etiqueta: 0/$total")
    flush(stdout)
    return Progreso(etiqueta, total, time(), 0)
end

"""
    avanzar!(p::Progreso; detalle="")

Incrementa el contador de `p` en 1 e imprime una línea de progreso:
timestamp, (completados/total, %), tiempo transcurrido, ETA estimado
(lineal, basado en el promedio de tiempo por paso hasta ahora) y un
`detalle` libre (p. ej. el nombre del escenario actual). Llama
`flush(stdout)` para que el progreso sea visible de inmediato en un log
de `nohup` (sin esperar a que el buffer de salida se llene).
"""
function avanzar!(p::Progreso; detalle::String="")
    p.completados += 1
    transcurrido = time() - p.inicio
    pct = 100 * p.completados / p.total
    eta = p.completados > 0 ? transcurrido / p.completados * (p.total - p.completados) : NaN
    ts  = Dates.format(Dates.now(), "HH:MM:SS")
    @printf("  [%s] %s (%d/%d, %.0f%%)  transcurrido=%s  ETA=%s%s\n",
            ts, p.etiqueta, p.completados, p.total, pct,
            formatear_duracion(transcurrido), formatear_duracion(eta),
            isempty(detalle) ? "" : "  — $detalle")
    flush(stdout)
end

"""
    finalizar_progreso!(p::Progreso)

Línea de cierre con el tiempo total real (para comparar contra el ETA
que se fue mostrando).
"""
function finalizar_progreso!(p::Progreso)
    total_transcurrido = time() - p.inicio
    println("  ✓ $(p.etiqueta) completo ($(p.completados)/$(p.total)) en $(formatear_duracion(total_transcurrido))")
    flush(stdout)
end

println("✓ Progreso (iniciar_progreso/avanzar!/finalizar_progreso!) definido")
