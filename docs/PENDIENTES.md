# Pendientes para cerrar el repositorio

Estado al 2026-09-20. Lo que sigue es la lista exacta de lo que falta,
con el origen de cada archivo en el árbol de trabajo de David.

---

## 1. Lo que ya está completo

El **experimento 11, destilación paramétrica v5.1**, está entero:

| Pieza | Ubicación |
|---|---|
| Módulo | `src/lib/29_destilacion_parametrica_v51.jl` (sin modificar) |
| Runner de línea de comandos | `experiments/29_run_destilacion_parametrica_v51.jl` |
| Notebook original | `experiments/29_notebook_destilacion_parametrica_v51.ipynb` |
| Serie de entrada | `data/datos_reales_curvas.csv` (206 días, 9 columnas) |
| Resultados | `results/destilacion_v51/` — 42 CSV |
| Figuras | las seis de `main.tex`, en `figures/` |
| Scripts de figura | un `figures_src/generar_fig_<nombre>.py` por figura, más `estilo_figuras.py` y `figuras_notebook.py` |
| Verificación | 60 cifras declaradas en `verify/cifras_manuscrito.yaml` |

Esto resuelve el bloqueador crítico del plan: la sección más nueva y más
expuesta del artículo ya tiene código, datos y verificación en el
repositorio.

---

## 2. Lo que falta copiar desde el árbol de trabajo

Al 2026-10-18 los módulos y los runners ya están en su sitio, adaptados a
la disposición del repositorio; lo que sigue faltando son los resultados
de los bloques 1–10, el entorno de Julia y los archivos de raíz. Las dos
listas que siguen quedan como referencia de qué se conserva y qué no:
`bin/poblar_repositorio.sh` las aplica en un paso.

### 2.1 Biblioteca (`src/lib/`)

```
00_setup.jl                        05_run_experiment.jl
01_model_training.jl               08_experiment18_core.jl
02_plotting_base.jl                09_experiment18_plots.jl
03_scenario_config.jl              10_final_synthetic_experiments.jl
04_progress.jl                     11_real_data.jl
12_extended_metrics.jl             14_real_data_window_sensitivity.jl
15_real_data_extrapolation_horizons.jl
18_real_data_window_sensitivity_split.jl
19_real_data_multiseed.jl
27_ruido_relativo.jl
29_destilacion_parametrica_v51.jl
```

Diecisiete. Eran diecinueve: el 2026-10-18 se eliminaron el `06` y el `24`,
los dos enteros, por no tener un solo llamador. Ver §2.10.

más el cargador `src/sir_ude_lib.jl`. Diecinueve módulos, no diecisiete: el
cargador incluye diecisiete, y los runners 16 (pareado), 21 y 22 cargan en
diferido el 18 y el 19 (§2.8 bis). El 29 viene del directorio del
notebook, no de `lib/` (§2.8 ter).

**No se copian** (decisión del plan, §2): `16_symbolic_regression_beta.jl`,
`17_pipeline_beta_simbolica.jl`, `07_noise_sensitivity.jl` y
`13_real_data_sensitivity_n_gamma.jl`. Con eso el `Project.toml` deja de
depender de `SymbolicRegression.jl` y `MLJ.jl`, que son los dos paquetes
pesados y los únicos que fallaron al instalar en la corrida de septiembre.

### 2.2 Runners (`experiments/`)

```
01_run_all_scenarios.jl
04_run_saturacion_stress_test.jl
09_run_final_synthetic_experiments.jl
09b_run_ruido_pareado.jl
13_run_real_data_extrapolation_horizons.jl
16_run_real_data_multiseed_PAREADO_exp10.jl
16_run_real_data_multiseed_REFF_POSITIVIDAD_exp14.jl
16b_recuperar_resumen_exp14.jl
20_run_window_sensitivity_all_v2.jl
21_run_real_data_window_sensitivity_split_v2.jl
22_run_real_data_window_sensitivity_multiseed.jl
23_consolidar_multiseed_real_data.jl
29_run_destilacion_parametrica_v51.jl   (nativo del repositorio)
```

**No se copian**: los cuatro runners de regresión simbólica (25, 26, 27,
28 y `14_run_pipeline_beta_simbolica.jl`), ni los de sensibilidad a
$N$/$\gamma$ ya eliminados del artículo.

### 2.3 Resultados (`results/`)

Los CSV de la corrida de septiembre, en las carpetas que el README
enumera. Sin ellos el verificador informa ocho bloques omitidos.

Antes de copiar, **medir el tamaño**. Si `results/` supera ~100 MB conviene
podar las trayectorias día a día de los experimentos sintéticos y dejar
solo los resumidos, o mover lo pesado a un depósito Zenodo de datos
separado. Los CSV de la destilación pesan 404 KB y son irrelevantes para
esa decisión.

### 2.4 Figuras y sus scripts

En `figures/` faltan siete de los nueve PDF. Además, dos de ellos
—`beta_siete_escenarios.pdf` y `datos_reales_combinado.pdf`— se generaban
desde notebooks (`figuras_articulo_completo.ipynb`,
`regenerar_figuras_articulo.ipynb`) y **no desde scripts**. Hay que
convertirlos a `.py` como los demás, o el repositorio queda con dos de
nueve figuras no regenerables.

En `figures_src/` faltan `estilo_figuras.py` y los `generar_fig_*.py` de
las figuras S1, S2, S4, dos olas y datos reales. **No se copian**
`sr_comun.py` ni los `generar_fig_sr_*.py`: son de la regresión simbólica,
que ya no aparece en el manuscrito.

### 2.5 Entorno

Detectado el 2026-09-21. **Acotado el 2026-10-18** con la salida real de
`Pkg.status()`.

Faltan `Project.toml` y `Manifest.toml`, y no por descuido: la corrida que
produjo las cifras no usó un entorno propio del proyecto, usó el global de
Julia 1.10. No hay Manifest de la corrida; lo único que queda es la lista
de paquetes de primer nivel con su versión, ya registrada en
`docs/ENTORNO.md`.

Con esa lista cotejada contra los `using` del código publicado aparecen
dos cosas:

- **El Nivel 2 es más liviano de lo que parecía.** El código no usa ningún
  solver ODE —el SIR es un Euler explícito escrito a mano, Δt = 1 día— de
  modo que `DifferentialEquations`, `SciMLBase` y `Distributions` no son
  dependencias. Con `SymbolicRegression`, `MLJ` e `IJulia` fuera, el
  entorno del anexo son veinte paquetes, cinco de ellos de la biblioteca
  estándar.

- **Faltan tres que el código sí usa**: `StatsPlots` y `HypothesisTests`
  (módulo 08, bloques 3 y 4) y `Glob` (runner 23, bloque 7). No estaban en
  el entorno global del 2026-10-18. El módulo 08 lleva el rastro de
  haberlos instalado en su línea 2. **Hay que confirmar si la corrida de
  referencia los tenía y en qué versión**: si los tenía, esa versión es
  parte del entorno y no está registrada en ninguna parte. Es lo único que
  queda entre esto y poder declarar el Nivel 2 reproducible.

`bin/generar_entorno.jl` escribe los dos archivos con las versiones de la
tabla fijadas una por una. Hay que correrlo en la máquina de la corrida:

    julia bin/generar_entorno.jl

---

### 2.6 La cadena que produce la entrada del experimento 11

Detectado el 2026-09-21 al cotejar el plan del 2026-09-20 contra el árbol.

`data/datos_reales_curvas.csv` es la entrada del experimento 11, pero ocho
de sus nueve columnas —`I_UDE`, `I_Windowed`, `beta_*`, `Reff_*`— son
salida de la corrida de entrenamiento con semilla `1234`, como ya advierte
`data/README.md`. La única columna empírica es `I_observado`, y viene
reescalada por el factor de anclaje.

Faltan las dos piezas que unen esa cadena:

1. **La serie empírica de origen**, que el plan llama
   `datos_historicos_julio_enero.csv` y que no está en el repositorio. Es
   el archivo sobre el que recae la nota de procedencia del DEIS/MINSAL:
   hoy §3.b no se puede responder porque el archivo al que se refiere no
   se entrega.
2. **El paso que escribe `datos_reales_curvas.csv`.** Ningún runner del
   repositorio lo produce; el notebook de la destilación lo lee desde
   `/home/tesis/codigos/SW_UDE/notebook/regresion_variantes_v5_1_corregido/`,
   un directorio de trabajo que no corresponde a la salida de ningún
   experimento. Con los bloques 1–10 copiados habrá que verificar si el
   archivo se reconstruye desde `results/datos_reales/` o si hace falta un
   script de consolidación explícito.

Mientras falten, el experimento 11 se verifica en Nivel 0 —que es lo que
importa para el revisor— pero no se reproduce en Nivel 2: su entrada llega
como dato dado y sin trazabilidad hacia la serie observada. Conviene
decidir si eso se resuelve o si el README lo declara abiertamente.

---

### 2.7 `SIR_UDE_SMOKE_TEST`: implementada, salvo en el bloque 11

Detectado el 2026-09-21. **Corregido el 2026-10-18**: la redacción
anterior decía que la variable no aparecía en ningún archivo del
repositorio. Eso era cierto de la copia de entonces, que no tenía los
módulos ni los runners de los bloques 1–10, y falso del código: con los
veintiocho archivos ya en su sitio, la variable está implementada.

Se define en `src/lib/00_setup.jl:31`:

```julia
const SMOKE_TEST = get(ENV, "SIR_UDE_SMOKE_TEST", "0") == "1"
```

y la honran `src/lib/18_real_data_window_sensitivity_split.jl` y los
runners 09, 16 (pareado), 21 y 22, que reducen épocas y multistarts
cuando está puesta. Para esos experimentos el Nivel 1 existe de verdad.

La excepción es el bloque 11, la destilación paramétrica. Su runner carga
el módulo 29 directamente, sin pasar por `00_setup.jl`, de modo que
`SMOKE_TEST` no está definida en su ámbito y el runner corre completo —con
sus 50 multistarts— sobrescribiendo `results/destilacion_v51/`.

Queda entonces una sola tarea, más pequeña que la que decía esta entrada:
hacer que el bloque 11 respete la variable, sea incluyendo `00_setup.jl`
en el runner 29, sea leyendo el entorno en el propio módulo. Mientras no
esté, `smoke_test.sh` deja la etapa de Julia desactivada salvo que se pida
con `--con-julia`, y comprueba sin Julia lo que sí puede comprobar: que el
verificador no reporta fallas, que las figuras se regeneran desde los CSV
entregados y que el manifiesto cuadra.

---

### 2.8 Dos archivos de nombre casi igual y cifras distintas

Detectado el 2026-10-12 al declarar las cifras de la Sección 4.2.5.

Hay dos resúmenes por semilla de la serie real, con nombres y columnas
casi idénticos y de corridas distintas:

| Archivo | Experimento | Reff_max SW-UDE | peor UDE |
|---|---|---|---|
| `results/datos_reales_multiseed/resumen_multisemilla.csv` | 10 | 1,313 ± 0,084 | 1,698 |
| `results/datos_reales_multisemilla/datos_reales_multisemilla.csv` | 8 | 1,316 ± 0,087 | 1,598 |

**El manuscrito cita el primero.** Verificar la Sección 4.2.5 contra el
segundo da FALLA en la mitad de las cifras. Las carpetas se llaman
`datos_reales_multiseed` y `datos_reales_multisemilla`, que se distinguen
en dos letras.

No es un error: son dos experimentos. Pero antes de publicar conviene
renombrar uno de los dos, o al menos que `docs/EXPERIMENTOS.md` lo diga
en la entrada de cada uno. El `README.md` ya lleva el aviso.

Quedan fuera del verificador, por ahora, los cuatro valores del inicio
del cruce sostenido de R_eff —t=126, 132, 16 y 151—: se derivan de las
curvas día a día de las diez semillas y no están en ningún resumen.
`figures_src/generar_fig_real_multiseed_v2.py` los recalcula y los
imprime cada vez que corre.

---

### 2.8 bis Los módulos 18 y 19 faltaban, y por qué nadie lo notó

Detectado el 2026-10-18 al revisar el árbol de trabajo completo.

`src/sir_ude_lib.jl` incluye diecisiete módulos en orden fijo; la lista
blanca de `bin/poblar_repositorio.sh` se armó siguiendo esa cadena, y por
eso copiaba diecisiete. Pero los runners 16 (pareado), 21 y 22 cargan dos
módulos más por su cuenta, en diferido, dentro de un `if` y con su propio
`joinpath` —el 18 y el 19—, así que no aparecen en la cadena del cargador.
Faltaban los dos.

Faltaba también la ruta con que esos tres runners los buscan: la escriben
por componentes, `joinpath(@__DIR__, "..", "lib", "19_….jl")`, forma que el
renombre por literal de `bin/adaptar_salidas.sh` no veía, de modo que
apuntaban a un `lib/` de raíz que en el repositorio no existe.

Los tres arreglos, aplicados:

- los dos módulos están en la lista blanca de `bin/poblar_repositorio.sh`;
- `bin/adaptar_salidas.sh` traduce también las dos formas por componentes,
  `joinpath("outputs", …)` y `joinpath(…, "..", "lib", …)`;
- `verify/comprobar_archivos.py` resuelve los `include` leyendo el código
  de los runners, no solo la cadena del cargador ni lo que cita
  `docs/EXPERIMENTOS.md`, y `verify/comprobar_rutas.py` reconoce la forma
  por componentes. Quitar cualquiera de los diecinueve módulos se detecta
  ahora antes de correr nada.

La lección, que vale para lo que quede: la lista de dependencias de un
runner no está en el cargador. Hay que leer el runner.

---

### 2.8 ter La destilación no vive donde viven los demás módulos

Detectado el 2026-10-18.

`src/lib/29_destilacion_parametrica_v51.jl` es copia byte a byte de
`notebook/regresion_variantes_v5_1_corregido/experimento_destilacion_parametrica_v5_1_familias_covid.jl`
del árbol de trabajo: 3777 líneas, mismo tamaño, `diff` vacío. No está en
`lib/` ni en `runners/`, y por eso `bin/poblar_repositorio.sh` no lo
copiaba: un repositorio poblado desde cero se quedaba sin el bloque 11
entero. Ya tiene su sección en el script, con la procedencia anotada.

El runner `experiments/29_run_destilacion_parametrica_v51.jl` es nativo
del repositorio —es el envoltorio que ancla la raíz con `@__DIR__`— y no
se copia de ninguna parte.

---

### 2.10 Código que no usa el artículo: 937 líneas fuera

Hecho el 2026-10-18, a pedido de David: «si algo no se usa, eliminar», y
el criterio para decidirlo, «lo que manda es el artículo». Es decir: se
conserva lo que algún runner de los trece publicados llama para producir
algo que el manuscrito cita. Lo demás sale.

`verify/comprobar_codigo_muerto.py` hace el barrido. Resultado: **937
líneas eliminadas, 24 añadidas** —notas que dicen qué había en cada sitio
y por qué se fue— sin que ninguna de las 102 cifras verificadas cambie.

Dos módulos enteros, por no tener un solo llamador:

- **`06_window_sensitivity_extra.jl`** (402 líneas). Cinco funciones de
  gráficos de Julia. El experimento 2 no las usa: llama a
  `run_all_sensitivity`, que está en el módulo `03`. `EXPERIMENTOS.md`
  citaba el `06` para ese experimento, y era el módulo equivocado.

- **`24_generar_grilla_m.jl`** (115 líneas). Generaba la grilla de $m$
  escalada por $1/\gamma$. Se introdujo el 2026-08-30 y **se revirtió el
  2026-09-05**, porque la grilla automática `[5, 10, 20, 30, 40, 50]` no
  contiene $m = 1$ ni $m = 2$, que son los dos controles
  sub-epidemiológicos sobre los que descansa el argumento de la sección de
  sensibilidad a $m$. Desde entonces el runner usa la grilla manual
  `[1, 2, 5, 7, 10, 15, 20, 30, 50]` y calcula $m_\gamma$ en una línea,
  solo para etiquetar `es_control` y `r_m`.

  Esto arregló algo peor que código muerto: `EXPERIMENTOS.md` afirmaba que
  la grilla «se genera escalada por $1/\gamma$ desde
  `24_generar_grilla_m.jl`». Describía el estado anterior a la reversión,
  de modo que un lector habría creído que la figura salió de una grilla
  que no la produjo.

Y ocho funciones sueltas, todas la versión previa a una revisión, superadas
por su variante `_v2`, `_split` o `_multisemilla`:

| Función | Módulo | La reemplazó |
|---|---|---|
| `sugerir_N` | `11` | `construir_serie_referencia_fija` |
| `run_window_sensitivity_real` | `14` | `run_window_sensitivity_real_split` (módulo 18) |
| `elegir_m_automatico` | `14` | $m = 10$ fijo, Tabla 2 |
| `evaluar_datos_reales` | `09` | `evaluar_datos_reales_v2` |
| `correr_experimento_1_lineal` | `08` | `correr_experimento_5_ruido`, general |
| `correr_experimento_3_no_lineales` | `08` | ídem |
| `plot_sir_reconstruido` | `11` | las figuras salen de `figures_src/`, en Python |
| `run_sensitivity_extra` | `06` | — (con el módulo entero) |

`sugerir_N` estaba previsto: §3 c decía «se conserva únicamente si alguna
función viva la llama; si no, se borra». Ninguna la llamaba.

Las menciones en prosa de los runners —«antes se derivaba con `sugerir_N`;
ya no aplica»— **se conservan a propósito**. Documentan por qué $N$ está
fijo a la fuente de referencia en vez de derivarse, que es una decisión
metodológica; borrarlas quitaría la traza del cambio.

Lo que el barrido NO puede decidir, y por eso separa lo seguro de lo
dudoso: si algo se llama desde el notebook, desde el REPL o por un nombre
construido en ejecución. Las nueve eliminadas no tenían llamador en
ninguna de las dos categorías.

---

### 2.9 El tamaño de results/: eran las imágenes, no los datos

Medido el 2026-10-13. `results/` pesa **122 MB** en el árbol de trabajo,
por encima del umbral de ~100 MB que §2.3 fijó. Pero al desglosarlo
aparece que **ningún CSV llega a 1 MB**: el peso está en los EPS, PNG y
PDF de control que cada runner deja junto a sus datos. Una sola carpeta,
`datos_reales_multiseed`, pesa 19 MB y casi todo son tres imágenes por
semilla; `datos_reales_multisemilla` son 1,4 MB de los cuales el grueso
son los boxplot en tres formatos.

Esas imágenes no son datos. El repositorio regenera sus seis figuras
desde los CSV con `figures_src/`, así que no tienen por qué estar.

Por eso `bin/poblar_repositorio.sh` copia de `results/` **solo los
.csv**, informa cuántos archivos no-csv omite en cada carpeta, y al final
imprime el tamaño de lo que efectivamente va a copiar. Esa cifra es la
que decide si hace falta podar más.

Además, el poblado ya no pisa lo que haya: dentro de `results/` copia con
`cp -n` salvo que se pase `--forzar`, y dice cuántos archivos respetó.
Comprobado el 2026-10-13 con `diff -rq` contra el árbol de trabajo: los
CSV que el repositorio ya trae son idénticos a los del origen —ninguna
línea «differ»—, de modo que no hay dos corridas en conflicto en esas
cuatro carpetas.

Si los CSV solos siguen pasando de ~100 MB, la poda que queda es la de
§2.3: conservar los resumidos y mover las trayectorias día a día de los
sintéticos a un depósito Zenodo aparte. El criterio es el del
verificador: un CSV que no sustenta ninguna cifra citada ni ninguna
figura no tiene por qué estar en el anexo.

---

## 3. Cosas que hay que decidir o confirmar, no solo copiar

**a. La tabla de ruido.** `trazabilidad_tablas_datos.md` marca
`tab:noise_beta` como no reproducible bajo el código
actual, porque las cifras citadas venían del esquema viejo ($\sigma$ como
fracción de $N$). La corrida de septiembre debería haberlo resuelto, pero
no hay ningún documento que lo registre. **Verificar antes de publicar**:
es el tipo de discrepancia que el verificador va a encontrar en cuanto se
copien los CSV.

**b. Procedencia y licencia de la serie.** Depende de §2.6: el archivo
cuya procedencia hay que consignar todavía no está en el repositorio.
`data/README.md` está escrito como plantilla: hay que confirmar el origen exacto
(DEIS/MINSAL, citado como `MinsalDEIS2020`), bajo qué licencia se
redistribuye y dejar explícito que la serie que entra al pipeline es la
reescalada por el factor de anclaje.

**c. `sugerir_N` y la cota mecánica $N = 80\,851$.** Se conserva
únicamente si alguna función viva la llama; si no, se borra y se menciona
en el `CHANGELOG.md`.

**d. El DOI de Zenodo.** Reservado el 2026-10-18: `10.5281/zenodo.23459303`. Ya está en
`CITATION.cff`, en el `README.md` y anotado en `.zenodo.json`.

Queda ponerlo en el `\dataavailability` del manuscrito, que todavía trae el
marcador azul y, además, una promesa que hay que poder cumplir: dice que se
depositarán «the `Project.toml` and `Manifest.toml` files of the environment
in which the final experiments were run», y esos dos archivos no existen
todavía (§2.5). Son el único bloqueante técnico que queda.

---

## 3 bis. La lista de control de archivos

`python3 verify/comprobar_archivos.py --solo-faltantes` recorre lo que el
repositorio promete y dice qué falta, separando lo que bloquea la
publicación de lo que conviene tener. Correrlo antes de etiquetar
`v1.0.0`.

Al 2026-10-18 quedan dos, y los dos son del entorno, no decisiones:

| Archivo | Qué hace falta |
|---|---|
| `Project.toml` | `julia bin/generar_entorno.jl` en la máquina de la corrida |
| `Manifest.toml` | lo escribe el mismo script, resolviendo |

Antes de correrlo hay que contestar lo de §2.5: si la corrida de
referencia tenía `StatsPlots`, `HypothesisTests` y `Glob`, y en qué
versión.

### Resueltos el 2026-10-18

`LICENSE`: **MIT**, decidido por David. Titulares, los tres autores del
manuscrito —Castro-Salinas, Vergara Quezada y Sepúlveda Oehninger— y la
Universidad Tecnológica Metropolitana. Cubre el código —`src/`,
`experiments/`, `figures_src/`, `verify/`, `bin/` y los scripts de la
raíz—; `data/`, `results/` y `figures/` se rigen por `LICENSE-DATA`
(CC BY 4.0), y los dos archivos declaran el mismo reparto.

`CITATION.cff`: los tres autores con su ORCID y su afiliación, tomados del
manuscrito, más el título del artículo y la licencia. Lleva
`preferred-citation` de tipo `article`, que es la cita que GitHub ofrece en
«Cite this repository». Quedan tres campos marcados `PENDIENTE` dentro del
archivo, y ninguno se puede llenar todavía porque no existe:

- la revista y el DOI del artículo;
- el DOI de Zenodo del software, que no hay hasta depositar;
- `repository-code`, que no hay hasta publicar el repositorio.

Está comprobado que el YAML parsea y que no falta ninguna clave
obligatoria de CFF 1.2.0.


---

## 4. Cifras del manuscrito que no reproducen

Esto es lo que encontró el Nivel 0 al declarar los bloques 3 y 4 con los
datos del árbol de trabajo, el 2026-10-18. **Es lo primero que hay que
resolver antes de enviar**, porque un revisor que corra el anexo lo va a
ver, y el anexo existe precisamente para que lo vea.

### 4.1 El esquema de ruido del manuscrito es el que el código reemplazó

Detectado y resuelto el 2026-10-18. La redacción anterior de esta entrada
decía que `tab:noise_beta` «no se reproduce desde los datos entregados», que
era el síntoma. La causa es otra y es más simple de arreglar.

`src/lib/27_ruido_relativo.jl` documenta el cambio en su propio encabezado.
El 2026-09-05 el ruido observacional pasó de

    aditivo escalado por N:   X_obs = X_true + ε,  ε ~ N(0, σ²),
                              σ ∈ {0.01N, 0.05N, 0.10N}

a

    multiplicativo relativo:  X_obs = max(0, X_true·(1+ε)),
                              ε ~ N(0, σ_rel²),
                              σ_rel ∈ {0.05, 0.10, 0.20}

con un motivo escrito ahí mismo: escalar por el tamaño poblacional produce
perturbaciones desproporcionadas cuando $I(t)$ es pequeño frente a $N$. Con
$N = 1000$ e $I_0 = 10$, un «1 % de ruido» ($0{,}01N$ = 10 individuos) iguala
a toda la población infecciosa inicial.

El manuscrito quedó describiendo el esquema viejo, en la línea 543 de
`main.tex`, y su tabla y sus dos recuentos de significancia venían de esa
corrida. Por eso no reproducían.

**Lo que hay que cambiar son cuatro sitios**, y está todo escrito en el
parche `parche_seccion_ruido.tex` que acompaña a esta entrada:

| Línea | Qué | Por qué |
|---|---|---|
| 543 | la definición del ruido, en Métodos | describe el esquema aditivo |
| 1080 | el párrafo del ejemplo | usa Linear, que en la corrida vigente va al revés en el nivel más bajo |
| 1082 | los dos recuentos | decía diez y seis; son **17 y 16** |
| 1084–1123 | la tabla entera | siete escenarios, tres niveles, 42 celdas, con las negritas puestas |

**Y cuatro sitios que revisé y no hay que tocar**, porque sus afirmaciones
se sostienen con la corrida vigente: el resumen (línea 87), el párrafo de
métodos que cuenta 7 × 3 = 21 (760), el primer párrafo de §4.1.3 (1078) y la
discusión (1524). El recuento «18 de 21» da 18 de 21 en las dos corridas, y
eso es justamente por lo que el problema pasó inadvertido: las tres
afirmaciones de alto nivel del artículo eran correctas mientras la tabla y
los recuentos finos no lo eran.

**El resultado queda más fuerte, no más débil.** Con la corrida vigente, 17
comparaciones son nominalmente significativas bajo ambas pruebas y 16
sobreviven a Benjamini-Hochberg, contra las diez y seis que reporta el
manuscrito. Y las 17 van en la dirección de mayor error latente para las
ventanas: ninguna en contra. La afirmación «no noisy condition shows a
statistically significant latent-recovery advantage for windowed training»
se sostiene, y la comprobé explícitamente: de las 21 combinaciones, cero
tienen las ventanas mejores con $p < 0{,}05$ en alguna de las dos pruebas.

Las 42 celdas y los tres recuentos están declarados en
`verify/cifras_manuscrito.yaml` y los 45 pasan. Los dos archivos de
`results/final_suite_ruido/` —el detalle por semilla y el resumen pareado—
son independientes y coinciden en las 21 filas al $10^{-9}$.

Queda una sola cosa, y es del artículo, no del repositorio: aplicar el
parche. Hasta entonces el manuscrito y el anexo no dicen lo mismo.

---

### 4.2 Cinco celdas de `tab:synthetic_multiseed`

Las 84 celdas de la tabla están declaradas y **79 reproducen exactas**.
Cinco no, y las cinco son del manuscrito: recalculé media y desviación
desde los diez archivos por semilla y dan lo mismo que el CSV resumen, así
que el dato es consistente entre dos fuentes independientes.

| Celda | Dice | Debe decir |
|---|---|---|
| Tanh / RMSE$_{\mathrm{SIR}}$ / $p_t$ | 0.430 | **0.427** |
| Two-wave / RMSE$_{\mathrm{SIR}}$ / $p_t$ | 0.260 | **0.262** |
| Two-wave / RMSE$_\beta$ / sd de $m=10$ | 0.0086 | **0.0085** |
| Two-wave / RMSE$_\beta$ / $p_t$ | 0.250 | **0.253** |
| Abrupt intervention / RMSE$_{\mathrm{SIR}}$ / media UDE | 0.694 | **0.693** |

Cuatro son el último dígito. La de Tanh es mayor —0.430 contra 0.427— y
tiene la misma pinta que el §4.1: una corrida anterior.

Las cinco entradas del YAML quedan en FALLA a propósito, cada una con su
nota. Pasarán a PASA cuando se corrija la tabla, no antes.

### 4.3 Dos problemas de forma de la tabla de ruido, resueltos en el parche

El `\caption` prometía «the seven synthetic scenarios at the three noise
levels» y la tabla imprimía **cinco**, con una nota al pie ambigua sobre
Seasonal y Hospital saturation. La tabla del parche trae los siete, así que
el caption pasa a ser cierto y la nota al pie desaparece.

Y el mismo `\caption` decía «Bold entries **should** identify comparisons
for which...», un «should» de nota al autor que quedó en el texto. En el
parche las negritas están puestas —las 16 que sobreviven a
Benjamini-Hochberg— y el caption dice «identify».

---

## 5. Orden sugerido

1. Correr `bin/poblar_repositorio.sh` apuntando al árbol de trabajo, y
   resolver con él la serie empírica de origen (§2.6).
2. Regenerar `Project.toml` sin `SymbolicRegression` ni `MLJ`; comprobar
   que instala de una pasada.
3. Convertir las dos figuras de notebook a script.
4. Extender `verify/cifras_manuscrito.yaml` a las cifras de los bloques
   1–10 y correr el verificador hasta que todo pase. **Aquí es donde van a
   aparecer las discrepancias reales**, incluida (a).
5. Generar `results/MANIFEST.sha256` con `bin/generar_manifest.sh`.
6. Completar `docs/ENTORNO.md` con los tiempos de pared medidos.
7. Smoke test completo desde un clon limpio.
8. Tag `v1.0.0` → Zenodo → DOI → manuscrito y `CITATION.cff`.
