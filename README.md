# SW-UDE — Windowed Recurrent SIR-UDE

Repositorio acompañante del manuscrito *(título y referencia completa en
`CITATION.cff`)*. Contiene el código, los datos y **los resultados** que
sustentan cada tabla y cada figura del artículo.

El repositorio no es un respaldo del proyecto: es el anexo verificable del
artículo. El criterio de diseño es que un revisor pueda confirmar, sin
instalar Julia y en menos de un minuto, que cada número citado en el
manuscrito sale del CSV que este repositorio entrega.

---

## Tres niveles de reproducción

### Nivel 0 — verificar (segundos, sin Julia)

```bash
python3 verify/verificar_cifras.py
```

Recorre `verify/cifras_manuscrito.yaml`, recalcula cada cifra desde el CSV
que la sustenta y emite una tabla PASA / FALLA. No necesita Julia, pandas
ni numpy. Devuelve código de salida distinto de cero si alguna cifra falla.

También hay un comprobador de integridad, que no mira las cifras sino
los archivos: si está todo lo que el repositorio promete —licencias,
entorno, runners, módulos, las fuentes de cada cifra declarada, los
scripts de figura y los seis PDF—. Es la lista de control previa a
publicar.

```bash
python3 verify/comprobar_archivos.py --solo-faltantes
```

Y un inventario, que clasifica cada archivo por el papel que cumple
—lo que el revisor usa, lo que sirvió para construir el repositorio, las
notas internas y lo que se regenera—, señala los archivos que no
referencia nadie y levanta las señales conocidas de desorden.

```bash
python3 verify/inventario.py             # inventario completo
python3 verify/inventario.py --senales   # solo lo que hay que decidir
```

Y un comprobador de rutas, que lee cada script y avisa si lee o escribe
fuera de la disposición del repositorio. El árbol de trabajo usaba
`lib/`, `runners/` y `outputs/`; aquí son `src/lib/`, `experiments/` y
`results/`, y un script copiado sin adaptar sigue apuntando a los
nombres viejos.

```bash
python3 verify/comprobar_rutas.py --solo-problemas
```

```bash
python3 verify/verificar_cifras.py --tabla tab:closed_form_dynamics   # una sola tabla
python3 verify/verificar_cifras.py --solo-fallas               # solo lo que falla
python3 verify/verificar_cifras.py --json informe.json         # informe legible por máquina
```

### Nivel 1 — humo (minutos)

```bash
SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh
```

El smoke test incluye la regeneración de las seis figuras desde los CSV
entregados, que no necesita Julia.

Corre la cadena completa con épocas y multistarts reducidos. No reproduce
las cifras; confirma que el entorno está bien armado antes de comprometer
horas de cómputo.

> **Ojo.** La variable `SIR_UDE_SMOKE_TEST` todavía no está implementada
> en el módulo del experimento 11, así que la etapa de Julia queda
> desactivada salvo que se pida con `--con-julia`. Sin Julia el script
> comprueba el verificador, la regeneración de figuras y el manifiesto.
> Ver `docs/PENDIENTES.md` §2.7.

### Nivel 2 — completo (horas a días)

```bash
julia --project=. install_dependencies.jl
./run_all.sh
```

Los tiempos de pared medidos por experimento están en `docs/ENTORNO.md`.

---

## Mapa artículo → código → datos

Las quince piezas que `main.tex` cita —nueve tablas y seis figuras—, con
el código que las produce, los datos de los que salen y si esos datos ya
están en el repositorio.

| Pieza del artículo | Experimento | Runner | Resultados | Estado |
|---|---|---|---|---|
| `tab:synthetic_scenarios` | — definicional | `src/lib/03_scenario_config.jl` | — | configuración |
| `fig:temporal_supervision` | — esquema | `figures_src/generar_fig_temporal_supervision_horizon.py` | — | **completo** |
| `fig:m_sensitivity` | 2 · sensibilidad a $m$, sintético | `experiments/20_run_window_sensitivity_all_v2.jl` | `results/window_sensitivity_v2/` | **datos presentes** |
| `tab:synthetic_multiseed` | 3 · pareado multisemilla sin ruido | `experiments/09_run_final_synthetic_experiments.jl` | `results/final_suite/` | pendiente |
| `tab:noise_beta` | 4 · ruido observacional $\sigma_{rel}$ | `experiments/09b_run_ruido_pareado.jl` | `results/final_suite_ruido/` | pendiente |
| `fig:hospital_state` | 5 · saturación hospitalaria | `experiments/04_run_saturacion_stress_test.jl` | `results/all_scenarios/` | **datos presentes** |
| `tab:real_m_selection` | 6 y 7 · sensibilidad a $m$, datos reales | `experiments/21_…_split_v2.jl`, `22_…_multiseed.jl` ×5, `23_consolidar…jl` | `results/datos_reales/`, `results/datos_reales_multiseed/` | parcial |
| `tab:real_multiseed` | 8 · pareado $n=10$, datos reales | `experiments/16_run_real_data_multiseed_PAREADO_exp10.jl` | `results/datos_reales_multisemilla/` | **datos presentes** |
| `tab:horizon_persistence` | 9 · horizontes y rollout autónomo | `experiments/13_run_real_data_extrapolation_horizons.jl` | `results/datos_reales/` | pendiente |
| `fig:real_multiseed`, §4.2.5 | 10 · $R_{\mathrm{eff}}$ y positividad de $\hat\beta$ | `experiments/16_…_REFF_POSITIVIDAD_exp14.jl`, `16b_recuperar_resumen_exp14.jl` | `results/datos_reales_multiseed/` | **completo** |
| `tab:closed_form_parameters`, `tab:closed_form_dynamics`, `tab:closed_form_sensitivity`, `fig:closed_form_fidelity`, `fig:fidelity_plane` | 11 · destilación paramétrica v5.1 | `experiments/29_run_destilacion_parametrica_v51.jl` | `results/destilacion_v51/` | **completo** |

«Completo» significa código, datos y verificación de cifras. «Datos
presentes» significa que los CSV están y la figura se regenera, pero las
cifras de su tabla todavía no están declaradas en
`verify/cifras_manuscrito.yaml`.

La numeración de los runners conserva la del proyecto original, con sus
huecos, para no romper la trazabilidad con la documentación previa ni con
los nombres de las carpetas de salida. El orden de lectura es el de la
tabla.

> **Cuidado con dos archivos de nombre casi igual.**
> `results/datos_reales_multiseed/resumen_multisemilla.csv` es el
> experimento 10 y es el que sustenta la Sección 4.2.5.
> `results/datos_reales_multisemilla/datos_reales_multisemilla.csv` es el
> experimento 8: columnas casi idénticas, cifras parecidas pero de otra
> corrida. Verificar la Sección 4.2.5 contra el segundo da FALLA en la
> mitad de las cifras.

### Las figuras

Las seis se regeneran desde los CSV entregados, sin Julia:

```bash
cd figures_src && python3 figuras_notebook.py
```

o desde un notebook, mostrándolas en línea:

```python
from figuras_notebook import generar_y_mostrar
generar_y_mostrar()
```

Las figuras necesitan matplotlib, numpy y pandas. En Debian y Ubuntu
`pip install` al Python del sistema está bloqueado por PEP 668; la receta
con entorno virtual está en `docs/ENTORNO.md`. El verificador de cifras
no necesita ninguna de las tres.

`figures_src/figuras_notebook.py` es el registro único: qué script
produce cada figura y con qué argumentos. El estándar de presentación
—tamaño a escala final, paleta validada para daltonismo, pisos
tipográficos— está en `docs/ESTILO_FIGURAS.md`.

## Supuestos que afectan la reproducción

- **Condiciones iniciales fijas.** Serie de 206 días anclada a
  Córdova-Lepe et al.; $N = 19\,660\,000$, $S_0 = 19\,348\,776$,
  $I_0 = 26\,390$, $R_0 = 284\,834$. La serie que entra al pipeline es la
  reescalada por el factor de anclaje, no la cruda.
- **$\gamma = 1/7$**, tomado de literatura y no estimado.
- **$\beta_0 = 0{,}20$** en datos reales frente a $0{,}25$ en sintéticos.
- **Semilla $1234$** para todas las corridas de semilla única, incluida la
  destilación. Las corridas multisemilla usan las semillas listadas en el
  runner correspondiente.
- **Partición temporal de la serie real**: entrenamiento días 0–164
  ($n=165$), prueba días 165–205 ($n=41$).
- La destilación integra con **Euler explícito discreto, $\Delta t = 1$
  día**; no usa ningún solver ODE continuo.

Los detalles están en `docs/DECISIONES.md`.

---

## Contenido

```
data/         la serie de entrada y su procedencia
src/          la biblioteca de Julia (ex lib/)
experiments/  un runner por experimento del artículo
figures_src/  un script por figura, más el estilo y el registro común
results/      los CSV exactos detrás de cada cifra citada
figures/      los seis PDF que compila el manuscrito
verify/       el verificador de cifras y su archivo de cifras
docs/         experimentos, entorno, decisiones, estilo de figuras, pendientes
bin/          poblado del repositorio y manifiesto de huellas
```

---

## Cómo citar

Ver `CITATION.cff`, que trae dos citas: la del **artículo**, que es la que
GitHub ofrece por omisión, y la de **este software**, para referenciar una
versión concreta del código.

DOI del software: [10.5281/zenodo.23459303](https://doi.org/10.5281/zenodo.23459303)

## Licencias

- Código: ver `LICENSE`.
- Datos, figuras y CSV de salida: ver `LICENSE-DATA` (CC BY 4.0).
- La serie epidemiológica de origen mantiene la licencia de su fuente; ver
  `data/README.md`.
