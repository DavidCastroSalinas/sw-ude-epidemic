# Entorno de ejecución

## Versiones

| | |
|---|---|
| Julia | 1.10.5 |
| Python (figuras y verificador) | 3.10 o superior |
| Kernel del notebook de destilación | `julia-1.10` |

Las versiones exactas de los paquetes de Julia están congeladas en
`Manifest.toml`. Para reproducir el entorno:

```bash
julia --project=. install_dependencies.jl
```

## El entorno de la corrida de referencia

**Al 2026-10-18 el repositorio todavía no tiene `Project.toml` ni
`Manifest.toml`.** Conviene decir por qué, porque no es un olvido: la
corrida que produjo las cifras no usó un entorno propio del proyecto. Usó
el entorno global de Julia 1.10, de modo que `--project=.` resolvía contra
`~/.julia/environments/v1.10/`. No hay, por tanto, un Manifest de la
corrida: lo único que queda de ella es la lista de paquetes de primer
nivel y su versión, que es esto, tal como la reportó `Pkg.status()`:

| Paquete | Versión | ¿lo usa el código publicado? |
|---|---|---|
| CSV | 0.10.17 | sí |
| Colors | 0.13.1 | sí |
| ComponentArrays | 0.15.47 | sí |
| DataFrames | 1.8.2 | sí |
| DifferentialEquations | 8.1.1 | **no** |
| Distributions | 0.25.131 | **no** |
| IJulia | 1.34.4 | no: notebook, no Nivel 2 |
| Lux | 1.31.4 | sí |
| MLJ | 0.23.3 | no: regresión simbólica, podada |
| Measures | 0.3.3 | sí |
| Optim | 2.2.2 | sí |
| Optimisers | 0.4.9 | sí |
| Optimization | 5.9.0 | sí |
| OptimizationOptimisers | 0.3.23 | sí |
| Plots | 1.41.7 | sí |
| SciMLBase | 3.53.3 | **no** |
| SymbolicRegression | 2.1.0 | no: regresión simbólica, podada |
| Zygote | 0.7.12 | sí |

Las tres filas en negrita son el hallazgo que importa para el Nivel 2:
**el código publicado no depende de ningún solver ODE.** El SIR se integra
con un Euler explícito escrito a mano, con $\Delta t = 1$ día (ver
`docs/DECISIONES.md`), y no hay un solo `ODEProblem` en los diecinueve
módulos ni en los trece runners. `DifferentialEquations`, `SciMLBase` y
`Distributions` estaban en el entorno de trabajo por otras cosas. El
entorno del anexo es bastante más liviano de lo que sugiere el global.

En el otro sentido faltan tres, y éste sí es un problema: el código usa
`StatsPlots`, `HypothesisTests` y `Glob`, y ninguno estaba en el entorno
global del 2026-10-18.

| Paquete | Dónde | Sin él no corre |
|---|---|---|
| `StatsPlots` | `src/lib/08_experiment18_core.jl` | bloques 3 y 4 |
| `HypothesisTests` | `src/lib/08_experiment18_core.jl` | bloques 3 y 4 |
| `Glob` | `experiments/23_consolidar_multiseed_real_data.jl` | bloque 7 |

El módulo 08 lleva el rastro en su línea 2:
`# import Pkg; Pkg.add(["HypothesisTests", "StatsPlots"])`. Se añadieron
en algún momento, y el `status` del 2026-10-18 no los muestra, así que o
se instalaron en otro entorno o se quitaron después. Hay que confirmarlo
antes de declarar el Nivel 2 reproducible: si la corrida de referencia los
tenía, su versión forma parte del entorno y no está registrada en ninguna
parte.

### Cómo generar los dos archivos

`bin/generar_entorno.jl` los escribe, con las versiones de la tabla
fijadas una por una. Hay que correrlo en la máquina de la corrida:

```bash
julia bin/generar_entorno.jl
```

La lista de paquetes que declara sale de los `using` e `import` del código
publicado, no del entorno global: veinte en total, los veinte que el
código usa y ninguno más. Deja `Project.toml` y `Manifest.toml` en la raíz
para versionar.

No se pueden escribir a mano con fundamento. El `Manifest.toml` lista el
árbol completo de dependencias con su versión y su hash, y eso solo lo
escribe `Pkg` resolviendo de verdad; el `Project.toml` necesita el UUID de
cada paquete, y un UUID mal copiado da un error que no dice qué pasó.

El verificador de cifras (`verify/verificar_cifras.py`) funciona con la
biblioteca estándar de Python: no necesita pandas, numpy ni PyYAML. Si
PyYAML está instalado lo usa; si no, recurre a su lector interno.

### Dependencias de las figuras

Las figuras necesitan matplotlib, numpy y pandas. En Debian, Ubuntu y
derivados, `pip install` al Python del sistema está bloqueado por PEP 668
y falla con `error: externally-managed-environment`. Hay dos salidas.

Entorno virtual, que es la recomendada y no toca el Python del sistema:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r figures_src/requirements.txt
python3 figures_src/figuras_notebook.py
```

`.venv/` está en el `.gitignore`. Para salir, `deactivate`.

O los paquetes de la distribución, si se prefiere no crear un entorno:

```bash
sudo apt install python3-numpy python3-pandas python3-matplotlib
```

En cualquier otro sistema, `pip install -r figures_src/requirements.txt`
sin más.

**El Nivel 0 no necesita nada de esto.** `verify/verificar_cifras.py`
corre con la biblioteca estándar de Python a propósito, para que un
revisor pueda comprobar las cifras sin instalar ni configurar nada.

## Paralelismo

Los experimentos usan `Threads.@threads` sobre los multistarts y sobre las
semillas. Hay que lanzar Julia con hilos:

```bash
julia --project=. --threads=auto experiments/<runner>.jl
```

En la destilación paramétrica se fija `BLAS.set_num_threads(1)`
deliberadamente: los multistarts ya saturan los núcleos y el paralelismo
anidado de BLAS degrada el tiempo total. Los demás runners no tocan la
configuración de BLAS.

Con un solo hilo los experimentos corren igual, pero sin paralelizar; los
runners emiten una advertencia.

## Tiempos de pared

> **Pendiente de completar con las mediciones de la corrida de
> septiembre.** Los tiempos son la información que decide si un revisor
> intenta el Nivel 2, así que conviene que sean medidos y no estimados.

| # | Experimento | Hilos | Tiempo de pared |
|---|---|---|---|
| 1 | Panorama 7 escenarios | | |
| 2 | Sensibilidad a $m$, sintético | | |
| 3 | Pareado multisemilla sin ruido | | |
| 4 | Ruido observacional | | |
| 5 | Saturación hospitalaria | | |
| 6 | Sensibilidad a $m$, datos reales | | |
| 7 | Sensibilidad a $m$, 5 semillas | | |
| 8 | Pareado $n=10$, datos reales | | |
| 9 | Horizontes + rollout | | |
| 10 | $R_{\mathrm{eff}}$ y positividad | | |
| 11 | Destilación paramétrica v5.1 | | |
| | **Total (`run_all.sh`)** | | |

## Hardware de la corrida de referencia

> Pendiente: modelo de CPU, número de núcleos físicos, memoria, sistema
> operativo. Todas las cifras del manuscrito provienen de esta máquina.

## Manifiesto y determinismo de las figuras

`bin/generar_manifest.sh` escribe `results/MANIFEST.sha256` con la huella
SHA-256 de todo lo que el repositorio entrega como dato: `results/`,
`data/` y `figures/`. `--verificar` lo contrasta contra el disco. Es la
forma barata de comprobar que un clon trae los CSV que produjeron las
cifras, sin correr nada.

Dos advertencias sobre su alcance:

- **Las figuras.** matplotlib estampa la fecha de creación dentro del PDF,
  así que dos corridas del mismo script dan huellas distintas.
  `figures_src/regenerar_todas.sh` fija `SOURCE_DATE_EPOCH` y con eso el
  PDF sale byte a byte idéntico entre corridas. **Al 2026-10-18 los seis
  PDF versionados se regeneraron con esa convención**, de modo que la
  advertencia anterior ya no aplica: regenerarlos en sitio y verificar el
  manifiesto después no reporta diferencias. Para reproducirlo:

      SOURCE_DATE_EPOCH=1760000000 python3 figures_src/figuras_notebook.py
      bin/generar_manifest.sh --verificar
- **Los resultados.** Una corrida completa del experimento 11 deja 45
  archivos en `results/destilacion_v51/` —los 42 CSV más tres PNG de
  control que no se versionan—, de modo que el manifiesto queda
  desactualizado hasta regenerarlo.

En ambos casos el manifiesto certifica lo que el repositorio entrega, no
que una reproducción vaya a dar los mismos bytes.

## Determinismo

Las corridas de semilla única usan `seed = 1234` y son reproducibles bit a
bit en la misma máquina y la misma versión de Julia. Entre versiones de
Julia o de BLAS pueden aparecer diferencias en los últimos dígitos; por eso
el verificador compara contra el valor impreso en el manuscrito y no
contra el CSV completo.

Los multistarts de la destilación usan `RANDOM_SEED = 20260912`, fijado
dentro del módulo.
