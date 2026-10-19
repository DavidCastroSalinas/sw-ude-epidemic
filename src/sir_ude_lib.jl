# Shared Julia library for synthetic and real-data SIR-UDE experiments.
# Load from a runner with:
#   include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

const LIBDIR = joinpath(@__DIR__, "lib")

# ── Núcleo compartido (setup, entrenamiento, ploteo base, config, progreso) ─
include(joinpath(LIBDIR, "00_setup.jl"))
include(joinpath(LIBDIR, "01_model_training.jl"))
include(joinpath(LIBDIR, "02_plotting_base.jl"))
include(joinpath(LIBDIR, "03_scenario_config.jl"))
include(joinpath(LIBDIR, "04_progress.jl"))

# ── Experimentos SINTÉTICOS (7 escenarios) ────────────────────────────────
include(joinpath(LIBDIR, "05_run_experiment.jl"))
include(joinpath(LIBDIR, "27_noise_relative.jl"))
include(joinpath(LIBDIR, "08_experiment18_core.jl"))
include(joinpath(LIBDIR, "09_experiment18_plots.jl"))
include(joinpath(LIBDIR, "10_final_synthetic_experiments.jl"))

# ── Experimentos con datos reales ───────────────────────────────────────
include(joinpath(LIBDIR, "11_real_data.jl"))
include(joinpath(LIBDIR, "12_extended_metrics.jl"))
include(joinpath(LIBDIR, "14_real_data_window_sensitivity.jl"))
include(joinpath(LIBDIR, "15_real_data_extrapolation_horizons.jl"))

println("\n✓ sir_ude_lib.jl cargada: experimentos sintéticos y de datos reales disponibles.")
