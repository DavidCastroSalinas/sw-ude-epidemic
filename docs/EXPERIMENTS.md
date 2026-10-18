# Índice de experimentos

Tabla de equivalencia entre el artículo, el código y los archivos de
salida. La numeración de los runners es la del proyecto original: tiene
huecos y dos archivos con el mismo número porque refleja la historia del
trabajo, no un orden de lectura. Se conservó deliberadamente para no
romper la trazabilidad con la documentación previa ni con los nombres de
las carpetas de salida.

El orden de lectura es el de esta tabla, que sigue el del artículo.

---

## 1 · Panorama de siete escenarios sintéticos

- **Runner**: `experiments/01_run_all_scenarios.jl`
- **Módulos**: `src/lib/05_run_experiment.jl`, `03_scenario_config.jl`
- **Salida**: `results/all_scenarios/`
- **Sustenta**: `tab:synthetic_scenarios`, `fig:no_lineales_beta`,
  `fig:beta_siete_escenarios`

## 2 · Sensibilidad al tamaño de ventana $m$, sintético

- **Runner**: `experiments/20_run_window_sensitivity_all_v2.jl`
- **Módulos**: `src/lib/03_scenario_config.jl`, que es donde está
  `run_all_sensitivity`, el motor que el runner llama
- **Salida**: `results/window_sensitivity_v2/`
- **Sustenta**: `fig:m_sensitivity`

La grilla de $m$ es **manual y explícita**, declarada en el runner:

    [1, 2, 5, 7, 10, 15, 20, 30, 50]

Conviene decir por qué, porque hubo un intento de automatizarla y se
revirtió. Entre el 2026-08-30 y el 2026-09-05 el runner generaba la grilla
escalada por el período infeccioso medio, $m_\gamma = \lceil 1/(\gamma
\Delta t)\rceil$, lo que para $\gamma = 0{,}10$ daba
`[5, 10, 20, 30, 40, 50]`. Esa grilla **no contiene $m = 1$ ni $m = 2$**, y
son justamente los dos puntos sobre los que descansa el argumento de la
sección: el mínimo de RMSE$_\beta$ cae ahí en la mayoría de los escenarios
y eso es lo que se muestra como artefacto de sobreajuste. Tampoco contiene
$m = 7$ ni $m = 15$. Se volvió a la grilla manual para no perder la
reproducibilidad de lo ya escrito, y el módulo que generaba la automática
se eliminó el 2026-10-18 al quedar sin uso.

El runner sí calcula $m_\gamma$, en una línea, pero solo para etiquetar
qué valores quedan por debajo del piso epidemiológico (columnas
`es_control` y `r_m` del CSV).

## 3 · Pareado multisemilla sin ruido

- **Runner**: `experiments/09_run_final_synthetic_experiments.jl`
- **Módulos**: `src/lib/10_final_synthetic_experiments.jl`
- **Salida**: `results/final_suite/`
- **Sustenta**: `tab:synthetic_multiseed`,
  `fig:S1_lineal_boxplots`

## 4 · Ruido observacional $\sigma_{rel}$

- **Runner**: `experiments/09b_run_noise_paired.jl`
- **Módulos**: `src/lib/27_noise_relative.jl`
- **Salida**: `results/final_suite_ruido/`
- **Sustenta**: `tab:noise_beta`

El esquema vigente es multiplicativo ($\sigma$ relativo), implementado en
`src/lib/27_noise_relative.jl`. Reemplazó al esquema absoluto ($\sigma$
como fracción de $N$) del antiguo `07_noise_sensitivity.jl`; las cifras del
artículo deben corresponder a este esquema.

## 5 · Saturación hospitalaria

- **Runner**: `experiments/04_run_saturation_stress_test.jl`
- **Módulos**: `src/lib/08_experiment18_core.jl`, `09_experiment18_plots.jl`
- **Salida**: `results/saturacion_stress_test/`
- **Sustenta**: `fig:hospital_state`

## 6 · Sensibilidad a $m$, datos reales

- **Runner**: `experiments/21_run_real_data_window_sensitivity_split_v2.jl`
- **Módulos**: `src/lib/14_real_data_window_sensitivity.jl` y
  `src/lib/18_real_data_window_sensitivity_split.jl`, éste cargado en
  diferido por el propio runner (ver la nota al final)
- **Salida**: `results/datos_reales/`
- **Sustenta**: `tab:real_m_selection`

## 7 · Sensibilidad a $m$, datos reales, cinco semillas

- **Runner**: `experiments/22_run_real_data_window_sensitivity_multiseed.jl`,
  una corrida por semilla, y luego
  `experiments/23_consolidate_multiseed_real_data.jl`
- **Módulos**: `src/lib/18_real_data_window_sensitivity_split.jl`, cargado
  en diferido por el runner 22 (ver la nota al final)
- **Salida**: `results/datos_reales_multiseed/`
- **Sustenta**: `tab:real_m_selection`

## 8 · Pareado $n = 10$, datos reales

- **Runner**: `experiments/16_run_real_data_multiseed_PAIRED_exp10.jl`
- **Módulos**: `src/lib/11_real_data.jl`, `12_extended_metrics.jl` y
  `src/lib/19_real_data_multiseed.jl`, éste cargado en diferido por el
  propio runner (ver la nota al final)
- **Salida**: `results/real_data_paired_multiseed/`
- **Sustenta**: `tab:real_multiseed` y su tabla suplementaria

## 9 · Horizontes de extrapolación y rollout autónomo

- **Runner**: `experiments/13_run_real_data_extrapolation_horizons.jl`
- **Módulos**: `src/lib/15_real_data_extrapolation_horizons.jl`
- **Salida**: `results/datos_reales/`
- **Sustenta**: `tab:horizon_persistence`, `fig:real_multiseed`

## 10 · $R_{\mathrm{eff}}$ y positividad de $\hat\beta$

- **Runner**: `experiments/16_run_real_data_multiseed_REFF_POSITIVITY_exp14.jl`,
  y `16b_recover_summary_exp14.jl` para recuperar el resumen
- **Salida**: `results/datos_reales_multiseed/`
- **Sustenta**: prosa de §4.2.6

## 11 · Destilación paramétrica de $\beta_{\mathrm{SW-UDE}}(t,I)$, v5.1

- **Runner**: `experiments/29_run_distillation_parametric_v51.jl`
- **Módulo**: `src/lib/29_distillation_parametric_v51.jl`
- **Entrada**: `data/real_data_curves.csv`
- **Salida**: `results/destilacion_v51/` (42 CSV, más tres PNG de
  control que no se versionan)
- **Sustenta**: `tab:closed_form_parameters`, `tab:closed_form_dynamics`,
  `tab:closed_form_sensitivity`, `fig:closed_form_fidelity`,
  `fig:fidelity_plane`

Las trece familias y su correspondencia con las etiquetas del manuscrito
están en `docs/DECISIONS.md`; su definición formal, en
`docs/DISTILLATION_FAMILIES.txt`. La exportación admite el número de parámetros definido por cada familia; el
runner de Julia es la entrada canónica del experimento.

Archivos de salida, por familia $F$:

| Archivo | Contenido |
|---|---|
| `multistart_algebraic_F.csv` | los 50 multistarts de la etapa algebraica |
| `refinement_dynamic_F.csv` | los 10 refinamientos dinámicos, con convergencia |
| `top10_dynamic_F.csv` | parámetros y métricas completas de esos 10 |
| `summary_families.csv` | una fila por familia, 36 columnas |
| `comparison_I.csv` | RMSE de $I(t)$ de las 13 formas más las 3 líneas base |
| `trajectories.csv` | $I(t)$ día a día de cada forma |

---


## Nota · los dos módulos que no carga `src/sir_ude_lib.jl`

`src/sir_ude_lib.jl` incluye diecisiete módulos en orden fijo, y ésa es la
lista que uno lee para saber de qué se compone la biblioteca. Dos quedan
fuera: el 18 y el 19. No por descuido, sino porque los runners 16 (pareado
$n = 10$), 21 y 22 los cargan por su cuenta, en diferido, solo si la
función que necesitan no está definida todavía:

```julia
if !isdefined(Main, :run_window_sensitivity_real_split)
    ruta = joinpath(@__DIR__, "..", "src", "lib",
                    "18_real_data_window_sensitivity_split.jl")
    isfile(ruta) || error("Falta $ruta")
    include(ruta)
end
```

Conviene saberlo por dos razones. La primera es que recorrer la cadena de
`include` del cargador no da la lista completa de módulos del que depende
el Nivel 2: hay que leer también los runners. La segunda es que un módulo
cargado así falla tarde, ya empezada la corrida, y con un mensaje que
habla de un archivo y no del experimento.

El smoke test comprueba las dependencias y rutas necesarias antes de iniciar
los experimentos.

## Tablas que no son salida de un experimento

`tab:hiperparametros` y `tab:escenarios_beta_definiciones` son
configuración, no resultado. Están codificadas en:

- hiperparámetros de entrenamiento: `src/lib/01_model_training.jl`
- definiciones de los escenarios $\beta$: `src/lib/03_scenario_config.jl`
