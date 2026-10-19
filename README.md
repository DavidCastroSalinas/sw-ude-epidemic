# SW-UDE — Horizonte de supervisión temporal en un SIR-UDE

Código, datos y resultados del artículo *Temporal Supervision Horizon and
Latent-Dynamics Recovery in SIR Universal Differential Equations* (referencia
completa en `CITATION.cff`).

---

## De qué trata

Un modelo híbrido neuronal-mecanicista aprende una parte desconocida de un
sistema dinámico a partir de trajectories observadas. Acá el sistema es un
SIR y la parte desconocida es la tasa de transmisión, representada por una
función neuronal $\beta_\theta(t, I)$:

$$S_{k+1} = S_k - \beta_\theta(t_k, I_k)\,\frac{S_k I_k}{N}\,\Delta t, \qquad
I_{k+1} = I_k + \beta_\theta(t_k, I_k)\,\frac{S_k I_k}{N}\,\Delta t - \gamma I_k \Delta t$$

El problema es que a $\beta_\theta$ nadie la supervisa directamente. Solo se
la corrige a través de los estados que ayuda a generar, de modo que
reconstruir bien la trayectoria no implica haber recuperado bien la función
latente. Son dos cosas distintas y pueden premiar soluciones distintas.

**Lo que este código estudia es el horizonte temporal de esa supervisión.**
Si el error de estados se acumula sobre la trayectoria completa antes de
corregir, la supervisión es global. Si se acumula sobre ventanas de $m$
pasos, cada una re-anclada a una observación, la supervisión es local. El
modelo mecanicista y la red son los mismos en los dos casos; lo único que
cambia es $m$.

Los resultados principales, que este repositorio reproduce:

- Con observaciones exactas, **horizontes más cortos recuperan mejor la ley
  de transmisión** en siete escenarios sintéticos con $\beta$ conocida. Pero
  la mejora en la función latente no siempre coincide con una mejora en la
  reconstrucción de estados.
- Con **ruido observacional, la ventaja se invierte**: el entrenamiento por
  ventanas da mayor error de $\beta$ que el global en 18 de 21 combinaciones
  de escenario y nivel de ruido. La supervisión local aporta información
  cuando los anclajes son exactos y se vuelve frágil cuando no lo son.
- En una **serie real de COVID-19 de Chile**, donde no hay $\beta$ verdadera
  contra la que comparar, la supervisión anclada a observaciones da errores
  de estado menores y menos variables, estimaciones de transmisión positivas
  en todas las inicializaciones, y dinámica más estable. Ninguno de los dos
  métodos le gana a la persistencia re-anclada en predicción a corto plazo.
- Finalmente, **aproximar la $\beta$ aprendida por una forma cerrada no
  preserva la trayectoria** que esa forma genera al insertarla
  recursivamente en el modelo.

La integración es Euler explícito discreto con $\Delta t = 1$ día. No se usa
ningún solver ODE continuo.

---

## Instalación

El repositorio tiene dos mitades independientes. Los experimentos son Julia;
las figuras y la comprobación de cifras son Python. **Para regenerar las
figuras no hace falta Julia, y para comprobar las cifras no hace falta
ninguna de las dos cosas instaladas.**

### Julia, para correr los experimentos

Si aún no tienes Julia, instala Juliaup y Julia desde una terminal:

```bash
curl -fsSL https://install.julialang.org | sh
```

Al terminar la instalación, abre una nueva terminal y comprueba que Julia
esté disponible:

```bash
julia --version
```

El repositorio incluye `Manifest.toml`, que registra Julia 1.12.7 y las
versiones resueltas de los paquetes. Desde el directorio raíz del proyecto,
instala las dependencias con:

```bash
julia --project=. install_dependencies.jl
```

Consulta `docs/ENVIRONMENT.md` para más detalles sobre el entorno y las
pruebas de ejecución.

### Python, para las figuras

Python 3.10 o superior, más matplotlib, numpy y pandas:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r figures_src/requirements.txt
```

En Debian y Ubuntu `pip install` al Python del sistema está bloqueado por
PEP 668; de ahí el entorno virtual. La receta alternativa con paquetes de la
distribución está en `docs/ENVIRONMENT.md`.

---

## Cómo correr

### Todo, en el orden del artículo

```bash
./run_all.sh --listar     # qué correría, sin correr nada
./run_all.sh              # los once experimentos
./run_all.sh 11           # solo uno
```

Horas a días según el experimento. Usa todos los hilos disponibles; con
`JULIA_NUM_THREADS=8` se limita.

> **Pisa `results/`.** Los CSV versionados son los que sustentan las cifras
> del artículo: una vez sobrescritos, la comparación contra el manuscrito se
> pierde. El script pide confirmación antes de empezar. Para correr sin
> perderlos, trabajar sobre una copia de `results/`.

### Antes de comprometer horas: la corrida de prueba

```bash
SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia
```

Corre los runners compatibles con épocas y multistarts reducidos. No
reproduce las cifras: confirma que el entorno está bien armado. Sin
`--con-julia` comprueba solo lo que no necesita Julia. La destilación se
omite en esta modalidad para evitar ejecutar su barrido completo.

Para probar también el flujo reducido de destilación (dos arranques y las
familias principales), usa:

```bash
SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia --con-destilacion-smoke
```

Ese modo solo comprueba el flujo de ejecución; guarda los resultados de
prueba en un directorio temporal y no reproduce cifras del artículo.

### SW-UDE con datos reales, paso a paso

El cuaderno [notebooks/SW_UDE_step_by_step.ipynb](notebooks/SW_UDE_step_by_step.ipynb)
recorre una ejecución de SW-UDE con la serie real: carga y prepara los datos,
entrena una sola semilla, calcula métricas de I(t) y grafica I(t), β̂, R_eff
y la pérdida. No ejecuta ni compara con UDE. Las figuras exportadas quedan en
notebooks/outputs/ y no se mezclan con los resultados del artículo.

### Un escenario sintético, desde el REPL

Es la forma más corta de ver el método funcionando. `src/sir_ude_lib.jl`
carga los 17 módulos de la biblioteca:

```julia
julia> include("src/sir_ude_lib.jl")

julia> run_experiment(:lineal; m=10, epochs=2000, seed=1234,
                      outdir="results/prueba", make_gif=false)
```

Entrena los dos métodos sobre el escenario, escribe las métricas y las
curvas en `results/prueba/` e informa RMSE de estados y de $\beta$ para cada
uno. Los siete escenarios son:

| Clave | Ley de transmisión |
|---|---|
| `:constante` | $\beta$ constante |
| `:lineal` | decreciente lineal |
| `:tanh` | transición suave |
| `:dos_olas` | dos olas |
| `:intervencion` | caída abrupta por intervención |
| `:estacional` | forzamiento estacional |
| `:saturacion` | saturación hospitalaria |

La arquitectura y los hiperparámetros con que se corrió cada uno están en
`SCENARIO_CONFIG`, en `src/lib/03_scenario_config.jl`. Para el escenario
lineal, por ejemplo, son `hidden=0, layers=1, epochs=3000, lr=0.010`.

### El barrido de $m$

```julia
julia> run_all_sensitivity(; m_values=[1, 2, 5, 7, 10, 15, 20, 30, 50],
                             outdir="results/mi_barrido")
```

Esa es la grilla del artículo. Incluye $m = 1$ y $m = 2$ a propósito, como
controles por debajo del piso epidemiológico $m_\gamma = \lceil 1/(\gamma
\Delta t)\rceil$: el mínimo de RMSE$_\beta$ cae ahí en la mayoría de los
escenarios, y mostrar que eso es un artefacto de sobreajuste es el argumento
de esa sección.

### Los dos métodos, por separado

Si lo que interesa es el contraste y no el experimento completo:

```julia
julia> datos = generar_datos(:lineal)                      # sin ruido
julia> datos = generar_datos(:lineal; sigma_ruido=0.05)    # 5% relativo

julia> g = entrenar_global(datos; seed_red=1234,
                           hiperparametros=(hidden=0, layers=1,
                                            epochs=3000, lr=0.010,
                                            clip_norm=nothing))
julia> v = entrenar_ventanas(datos; m=10, seed_red=1234,
                             hiperparametros=(hidden=0, layers=1,
                                              epochs=3000, lr=0.010,
                                              clip_norm=nothing))

julia> evaluar_completo(g, datos), evaluar_completo(v, datos)
```

El ruido es multiplicativo relativo a cada observación,
$X_{\mathrm{obs}} = \max(0,\, X_{\mathrm{true}}(1+\varepsilon))$ con
$\varepsilon \sim \mathcal{N}(0, \sigma_{\mathrm{rel}}^2)$. Está en
`src/lib/27_noise_relative.jl`, con el motivo de por qué no se escala por
$N$.

### Sobre tu propia serie

`cargar_serie_real` acepta cualquier CSV con una columna de valores y una de
orden consecutiva, y los nombres se le pasan:

```julia
julia> I_obs = cargar_serie_real("mi_serie.csv";
                                 columna_valor=:casos, columna_orden=:dia)
```

Rechaza la serie si la columna de orden tiene saltos o duplicados, si hay
NaN o infinitos, o si hay valores negativos. Los días faltantes hay que
interpolarlos explícitamente antes, no ignorarlos.

El paso siguiente reconstruye $S$ y $R$ a partir de $I$ y de condiciones
iniciales. Las del artículo son las de la fuente de referencia chilena y son
los valores por omisión, así que **para otra serie hay que pasar las
propias**:

```julia
julia> anclaje = construir_serie_referencia_fija(I_obs;
                    N=1_000_000.0, S0=995_000.0, I0=5_000.0, R0=0.0,
                    γ=1/7, dia_ancla_idx=1)
julia> SIR = anclaje.SIR

julia> df = run_window_sensitivity_real_split(SIR;
                N=1_000_000.0, γ=1/7,
                hidden=16, layers=2, lr=0.005, epochs=8000,
                m_abs=[1, 2, 5, 10, 20, 54, 107],
                frac_train=0.8, outdir="results/mi_serie")
```

`I0` es el ancla: la serie se reescala para que su primer día valga `I0`
exactamente, lo que vuelve comparables una serie de incidencia notificada y
una prevalencia modelada. El factor aplicado vuelve en
`anclaje.factor_reescala`.

La serie del artículo entra así reescalada, no cruda. Una corrida sobre los
datos del DEIS sin ese paso no reproduce las cifras.

### Las figuras

Las seis se regeneran desde los CSV entregados, sin Julia:

```bash
python3 figures_src/figure_registry.py
```

o desde un notebook, mostrándolas en línea:

```python
from figure_registry import generar_y_mostrar
generar_y_mostrar()
```

Con `SOURCE_DATE_EPOCH` fijo salen byte a byte idénticas entre corridas:

```bash
SOURCE_DATE_EPOCH=1760000000 python3 figures_src/figure_registry.py
```

`figures_src/figure_registry.py` es el registro único de qué script produce
cada figura y con qué argumentos. El estándar de presentación —tamaño a
escala final, paleta validada para daltonismo, pisos tipográficos— está en
`docs/FIGURE_STYLE.md`.

### Variables de entorno

| Variable | Efecto |
|---|---|
| `SIR_UDE_SEED` | semilla de la red; por omisión 1234 |
| `SIR_UDE_M_OVERRIDE` | fuerza un $m$ distinto al del runner |
| `SIR_UDE_SMOKE_TEST=1` | épocas y multistarts reducidos |
| `JULIA_NUM_THREADS` | hilos; por omisión todos |
| `SIR_UDE_SIN_PREGUNTAR=1` | `run_all.sh` no pide confirmación |

---

## De dónde sale cada resultado del artículo

Las quince piezas que cita el manuscrito —nueve tablas y seis figuras—, con
el código que las produce y los datos de los que salen.

| Pieza | Experimento | Runner | Resultados |
|---|---|---|---|
| `tab:synthetic_scenarios` | definicional | `src/lib/03_scenario_config.jl` | — |
| `fig:temporal_supervision` | esquema | `figures_src/generate_fig_temporal_supervision_horizon.py` | — |
| `fig:m_sensitivity` | 2 · sensibilidad a $m$, sintético | `experiments/20_run_window_sensitivity_all_v2.jl` | `results/window_sensitivity_v2/` |
| `tab:synthetic_multiseed` | 3 · pareado multisemilla sin ruido | `experiments/09_run_final_synthetic_experiments.jl` | `results/final_suite/` |
| `tab:noise_beta` | 4 · ruido observacional | `experiments/09b_run_noise_paired.jl` | `results/final_suite_noise/` |
| `fig:hospital_state` | 5 · saturación hospitalaria | `experiments/04_run_saturation_stress_test.jl` | `results/all_scenarios/` |
| `tab:real_m_selection` | 6 y 7 · sensibilidad a $m$, datos reales | `experiments/21_…_split_v2.jl`, `22_…_multiseed.jl` ×5, `23_consolidar…jl` | `results/real_data/`, `results/real_data_multiseed/` |
| `tab:real_multiseed` | 8 · pareado $n=10$, datos reales | `experiments/16_run_real_data_multiseed_PAIRED_exp10.jl` | `results/real_data_paired_multiseed/` |
| `tab:horizon_persistence` | 9 · horizontes y rollout autónomo | `experiments/13_run_real_data_extrapolation_horizons.jl` | `results/real_data/` |
| `fig:real_multiseed`, §4.2.5 | 10 · $R_{\mathrm{eff}}$ y positividad de $\hat\beta$ | `experiments/16_…_REFF_POSITIVITY_exp14.jl`, `16b_…` | `results/real_data_multiseed/` |
| `tab:closed_form_*` ×3, `fig:closed_form_fidelity`, `fig:fidelity_plane` | 11 · destilación paramétrica v5.1 | `experiments/29_run_distillation_parametric_v51.jl` | `results/distillation_v51/` |

`docs/EXPERIMENTS.md` tiene el detalle de cada uno: qué módulos usa, qué
escribe y qué afirmación del artículo sustenta.

La numeración de los runners conserva la del proyecto original, con sus
huecos, para no romper la trazabilidad con los nombres de las carpetas de
salida. El orden de lectura es el de esta tabla.

> **Dos carpetas de nombre casi igual.**
> `results/real_data_multiseed/` es el experimento 10 y sustenta la
> Sección 4.2.5. `results/real_data_paired_multiseed/` es el experimento 8:
> columnas casi idénticas, cifras parecidas, otra corrida. Comprobar la
> Sección 4.2.5 contra la segunda da FALLA en la mitad de las cifras.

---

## Supuestos que afectan la reproducción

- **Condiciones iniciales fijas** para la serie real, tomadas de
  Córdova-Lepe et al.: $N = 19\,660\,000$, $S_0 = 19\,348\,776$,
  $I_0 = 26\,390$, $R_0 = 284\,834$. La serie que entra al pipeline es la
  reescalada por el factor de anclaje.
- **$\gamma = 1/7$**, de literatura, no estimado.
- **$\beta_0 = 0{,}20$** en datos reales frente a $0{,}25$ en sintéticos.
- **Semilla 1234** en todas las corridas de semilla única. Las multisemilla
  usan las semillas listadas en su runner.
- **Partición temporal de la serie real**: entrenamiento días 0–164
  ($n = 165$), prueba días 165–205 ($n = 41$). El conjunto de prueba no se
  usó para elegir $m$.
- **Euler explícito, $\Delta t = 1$ día.**

`docs/DECISIONS.md` explica por qué cada uno y qué cambia si se cambia.

---

## Comprobar que las cifras cuadran

Hay un comprobador que recalcula cada número citado en el artículo desde el
CSV que lo sustenta y emite PASA o FALLA. **Corre con la biblioteca estándar
de Python**: sin Julia, sin pandas, sin numpy, en segundos.

```bash
python3 verify/verify_values.py
python3 verify/verify_values.py --solo-fallas
python3 verify/verify_values.py --tabla tab:noise_beta
```

`verify/manuscript_values.yaml` declara cada cifra con su fuente, su columna,
su filtro y su redondeo, de modo que se puede leer qué se está comprobando
sin leer el código.

Los scripts de diagnóstico interno del árbol de trabajo no forman parte
del flujo mínimo de reproducción. La comprobación pública de cifras es
`verify/verify_values.py`; el smoke test valida las herramientas y las
rutas de ejecución disponibles.

---

## Contenido

```
data/         la serie de entrada y su procedencia
src/          la biblioteca de Julia: sir_ude_lib.jl carga src/lib/
experiments/  un runner por experimento del artículo
figures_src/  un script por figura, más el estilo y el registro común
results/      los CSV exactos detrás de cada cifra citada
figures/      los seis PDF que compila el manuscrito
verify/       los comprobadores y el archivo de cifras declaradas
docs/         mapa de experimentos, entorno, decisiones y estilo de figuras
bin/          utilidades necesarias para regenerar el manifiesto y verificar salidas
```

---

## Cómo citar

`CITATION.cff` identifica el software, sus autores y el artículo asociado.
Completar los datos editoriales del artículo y los metadatos de archivo del
software cuando se emita la versión citable definitiva.

## Licencias

- Código: `LICENSE` (MIT).
- Datos, figuras y CSV de salida: `LICENSE-DATA` (CC BY 4.0).
- Antes de redistribuir la serie epidemiológica, completar y verificar la
  referencia y las condiciones de la fuente original; ver `data/README.md`.
