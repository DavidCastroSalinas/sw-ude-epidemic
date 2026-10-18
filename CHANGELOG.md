# Registro de cambios

Cambios de este repositorio respecto del árbol de trabajo del que
proviene. No es el historial del proyecto: es la lista de lo que se podó,
se renombró o se corrigió al armar el anexo del artículo, para que quien
compare ambos árboles sepa qué esperar.

## No publicado

### Eliminado respecto del árbol de trabajo

- **937 líneas de código que el artículo no usa** (2026-10-18). Dos
  módulos enteros, `06_window_sensitivity_extra.jl` y
  `24_generar_grilla_m.jl`, y ocho funciones sueltas, todas la versión
  previa a una revisión y superadas por su variante `_v2`, `_split` o
  `_multisemilla`: `sugerir_N`, `run_window_sensitivity_real`,
  `elegir_m_automatico`, `evaluar_datos_reales`,
  `correr_experimento_1_lineal`, `correr_experimento_3_no_lineales`,
  `plot_sir_reconstruido` y `run_sensitivity_extra`. Ninguna tenía un solo
  llamador entre los trece runners publicados, y las 102 cifras verificadas
  no cambian. En cada sitio queda una nota de dos líneas que dice qué
  había y por qué se fue. El detalle, con la tabla de reemplazos, en
  `docs/PENDIENTES.md` §2.10.

  De paso corrigió dos errores de documentación: `EXPERIMENTOS.md` citaba
  el módulo `06` como motor del experimento 2 —es el `03`— y afirmaba que
  la grilla de $m$ se genera escalada por $1/\gamma$, cosa que dejó de ser
  cierta con la reversión del 2026-09-05.

- **Regresión simbólica completa (experimentos 15–19).** Ya no aparece en
  el manuscrito; la reemplazó la destilación paramétrica v5.1. Salen los
  módulos `16_symbolic_regression_beta.jl` y
  `17_pipeline_beta_simbolica.jl`, los runners 25 a 28 y
  `14_run_pipeline_beta_simbolica.jl`, y los scripts `sr_comun.py` y
  `generar_fig_sr_*.py`.

  Con esto el `Project.toml` deja de depender de `SymbolicRegression.jl` y
  `MLJ.jl`, los dos únicos paquetes que fallaron al instalar en la corrida
  de septiembre. El entorno queda instalable de una sola pasada.
- **Sensibilidad a $N$ y $\gamma$ (experimento 13).** Eliminado del
  artículo en la séptima pasada; su código ya no existía.
- **Variación total de $\hat\beta$ (experimento 6).** Eliminado por
  decisión.
- **Figura S3 y el experimento de ruido absoluto.** Superados por el
  esquema multiplicativo unificado ($\sigma$ relativo).
- **Módulos `07_noise_sensitivity.jl` y
  `13_real_data_sensitivity_n_gamma.jl`**, que solo servían a lo anterior.

### Renombrado

- `lib/` pasa a `src/lib/`, y `runners/` a `experiments/`.
- La numeración de los runners **conserva los huecos del árbol original**
  (01, 04, 09, 09b, 13, 16 ×2, 20–23, 29). Es historia del proyecto, no
  orden de lectura; renombrarla rompería la trazabilidad con la
  documentación previa y con los nombres de las carpetas de salida. El
  orden de lectura lo da la tabla del `README.md`.

### Añadido en esta pasada (2026-10-18)

- **`LICENSE` (MIT)** y **`CITATION.cff`**. Titulares del copyright, los
  tres autores del manuscrito y la Universidad Tecnológica Metropolitana.
  El MIT cubre el código; los
  datos, los resultados y las figuras siguen bajo CC BY 4.0 en
  `LICENSE-DATA`, y los dos archivos declaran el mismo reparto. El
  `CITATION.cff` lleva los tres autores con ORCID y afiliación, tomados
  del manuscrito, y un `preferred-citation` de tipo `article`. Quedan tres
  campos marcados `PENDIENTE` dentro del archivo: la revista y el DOI del
  artículo, el DOI de Zenodo del software y `repository-code`. Ninguno
  existe todavía.

- **`bin/generar_entorno.jl`**, que escribe `Project.toml` y
  `Manifest.toml` con las doce versiones conocidas de la corrida de
  referencia fijadas una por una. Hay que correrlo en esa máquina.

- **Los diecinueve módulos y los trece runners, adaptados.** Vienen del
  árbol de trabajo tal cual, con un único cambio de contenido: la
  disposición de carpetas, que el repositorio renombró. Lo aplica
  `bin/adaptar_salidas.sh`, que enumera cada cambio con número de línea,
  es idempotente y no escribe nada sin `--aplicar`.

- **Dos módulos que faltaban**, el 18 y el 19. No los carga
  `src/sir_ude_lib.jl`: los cargan en diferido los runners 16 (pareado),
  21 y 22, de modo que no aparecían al recorrer la cadena de `include` del
  cargador. Con ellos faltaba también la forma por componentes de su ruta.
  Ver `docs/PENDIENTES.md` §2.8 bis.

- **El módulo de la destilación en la lista blanca.** Es copia byte a byte
  del archivo del directorio del notebook, que no está en `lib/`, así que
  un repositorio poblado desde cero se quedaba sin el bloque 11 entero.
  Ver §2.8 ter.

### Corregido

- **`verify/comprobar_archivos.py` resuelve los `include` leyendo el
  código** de los runners, no solo la cadena del cargador ni lo que cita
  `docs/EXPERIMENTOS.md`. Quitar cualquiera de los diecinueve módulos se
  detecta antes de correr nada; antes no se detectaba nunca.

- **`verify/comprobar_rutas.py` reconoce la ruta armada por
  componentes**, `joinpath("outputs", …)` y `joinpath(…, "..", "lib", …)`,
  que no aparece como literal y por eso se escapaba. Y exime a las tres
  herramientas que nombran la disposición vieja por oficio.

- **`docs/PENDIENTES.md` §2.7 decía que `SIR_UDE_SMOKE_TEST` no estaba
  implementada en ningún archivo.** Era cierto de la copia de entonces y
  falso del código: se define en `src/lib/00_setup.jl:31` y la honran el
  módulo 18 y los runners 09, 16, 21 y 22. La excepción real es solo el
  bloque 11, cuyo runner no pasa por `00_setup.jl`.

- El recuento de salidas del experimento 11 decía **43 archivos** en
  `README.md`, `docs/PENDIENTES.md`, `docs/EXPERIMENTOS.md` y en la
  cabecera del runner. Son **42 CSV**: trece familias × tres archivos
  (`multistart_algebraico_*`, `refinamiento_dinamico_*`,
  `top10_dinamico_*`) más `resumen_familias.csv`, `comparacion_I.csv` y
  `trayectorias.csv`. Ninguna familia carece de archivo y ninguna cifra
  del verificador apunta a un archivo ausente, de modo que no falta nada:
  el número estaba mal contado.

  El módulo escribe además tres PNG de control —`beta_familias.png`,
  `I_familias.png`, `I_test.png`— que el runner copia junto con los CSV
  pero que **no se versionan**: son diagnóstico, no figuras del
  manuscrito. Tras una corrida completa, `results/destilacion_v51/`
  contiene 45 archivos y el manifiesto deja de cuadrar hasta regenerarlo.

### Añadido

- `bin/poblar_repositorio.sh` — copia con lista blanca desde el árbol de
  trabajo; simulacro por omisión.
- `bin/generar_manifest.sh` — `results/MANIFEST.sha256` sobre `results/`,
  `data/` y `figures/`, con modo `--verificar`.
- `run_all.sh`, `smoke_test.sh`, `install_dependencies.jl`,
  `figures_src/regenerar_todas.sh`, `figures_src/requirements.txt`.
- `figures_src/regenerar_todas.sh` fija `SOURCE_DATE_EPOCH`, con lo que
  los PDF salen byte a byte idénticos entre corridas. Los PDF versionados
  en `figures/` se produjeron antes de esta convención y llevan la fecha
  de su corrida original: coinciden en contenido con una regeneración,
  pero no en huella.

### Pendiente de decidir

- `sugerir_N` y la cota mecánica $N = 80\,851$: se conserva solo si alguna
  función viva la llama; si no, se borra y el borrado se anota aquí.
- La licencia del código (`LICENSE`), que el plan dejó como «MIT o
  Apache-2.0».
- La cadena que produce `data/datos_reales_curvas.csv`; ver
  `docs/PENDIENTES.md` §2.6.
