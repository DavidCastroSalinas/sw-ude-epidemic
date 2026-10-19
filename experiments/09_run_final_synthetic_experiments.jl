# Runner 09: multi-seed comparisons and trajectories for synthetic scenarios.
#
# Full execution can take hours. For a quick pipeline check:
#   SIR_UDE_SMOKE_TEST=1 julia experiments/09_run_final_synthetic_experiments.jl
# Smoke mode runs :constante, m=10, seeds 1:2, and 30 epochs by default.
# Smoke results are not valid for the article. Override the epoch limit with
# SIR_UDE_SMOKE_EPOCHS. Use run_final_paralelo.sh for a full run with progress.

if get(ENV, "SIR_UDE_SMOKE_TEST", "0") == "1"
    ENV["SIR_UDE_SMOKE_EPOCHS"] = get(ENV, "SIR_UDE_SMOKE_EPOCHS", "30")
end

include(joinpath(@__DIR__, "..", "src", "sir_ude_lib.jl"))

const OUTDIR = "results/final_suite"
const TRAJECTORY_DIR = "results/trajectories"
mkpath(OUTDIR)
mkpath(TRAJECTORY_DIR)

const SMOKE_RUN = SMOKE_TEST
const SCENARIOS_RUN = SMOKE_RUN ? [:constante] : SCENARIO_ORDER
const SEEDS_RUN = SMOKE_RUN ? (1:2) : (1:10)
const M_VALUES_RUN = SMOKE_RUN ? [10] : nothing

t_inicio_total = time()

println("\n" * "="^70)
println("  (A) Multi-semilla + comparación pareada — $(length(SCENARIOS_RUN)) escenario(s)")
println("="^70)
t0 = time()
correr_todos_experimentos_multisemilla(
    escenarios=SCENARIOS_RUN,
    seeds_red=SEEDS_RUN,
    m_values=M_VALUES_RUN,
    outdir=OUTDIR,
)
println("  (A) tiempo total: ", formatear_duracion(time() - t0))

println("\n" * "="^70)
println("  (B) Trayectorias — $(length(SCENARIOS_RUN)) escenario(s)")
println("="^70)
t0 = time()
graficar_todas_trajectories(
    escenarios=SCENARIOS_RUN,
    seed_red=1,
    outdir=TRAJECTORY_DIR,
)
println("  (B) tiempo total: ", formatear_duracion(time() - t0))

println("\n✓ Runner 09 completado en ", formatear_duracion(time() - t_inicio_total))
println("  Comparación: $(OUTDIR)/comparison_paired_ALL_scenarios.csv")
println("  Trayectorias: $(TRAJECTORY_DIR)/")
