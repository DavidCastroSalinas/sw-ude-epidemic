# Estándar de figuras — qué cambió y por qué

Normalización del 2026-10-12. Todo lo de abajo se puede comprobar; nada
es cuestión de gusto.

## 1. Tamaño: se dibuja al tamaño final

`main.tex` es clase MDPI a una columna y llama a las figuras con
`width=0.95\textwidth` (cinco) y `width=0.82\textwidth` (el plano). Con
`\textwidth = 16 cm` eso son 5,98 y 5,17 pulgadas.

Las figuras se dibujaban más anchas y LaTeX las reducía:

| Figura | Dibujada | Caja | Factor | Cuerpo de 9 pt impreso a |
|---|---|---|---|---|
| hospital_state_reconstruction | 9,00 in | 5,98 | 0,66 | 5,9 pt |
| m_sensitivity_v2 | 7,50 in | 5,98 | 0,80 | 7,2 pt |
| temporal_supervision_horizon | 7,20 in | 5,98 | 0,83 | 7,5 pt |
| closed_form_fidelity_plane | 6,30 in | 5,17 | 0,82 | 7,4 pt |

Ahora `figsize()` devuelve el ancho de la caja y el factor es 1.
`comprobar_minimos()` avisa si una figura no coincide con ninguna caja.

**Confirmar una vez**: poner `\the\textwidth` en el .tex. Si no son
16 cm, ajustar `ANCHO_CAJA_CM` en `estilo_figuras.py`.

## 2. Color: la paleta anterior no era segura para daltonismo

`#d62728` (SW-UDE) y `#2ca02c` (forma cerrada) se separan **ΔE 3,9 bajo
deuteranopía**, y aparecían juntos en el panel (a) de
`closed_form_fidelity`. Para una fracción apreciable de lectores eran el
mismo color.

La paleta nueva es Okabe-Ito, validada en conjunto:

| Papel | Antes | Ahora |
|---|---|---|
| UDE global | `#1f77b4` | `#0072B2` |
| SW-UDE | `#d62728` | `#D55E00` |
| Forma cerrada | `#2ca02c` | `#009E73` |
| Observado | negro | negro |

Peor par: **ΔE 11,0 deutan · 25,8 visión normal**. Las tres superan 3:1
de contraste contra papel blanco.

Las trece familias **no** llevan un matiz cada una. Tres matices oscuros,
mutuamente distinguibles y además distinguibles del bermellón, no caben:
oscurecerlos para el contraste les quita el croma que la separación
necesita (probadas cuatro combinaciones, todas fallan). Las familias son
una categoría frente a SW-UDE, así que comparten el verde y se separan
por trazo. E va en neutro, un escalón atrás, que es la jerarquía pedida.

La identidad nunca depende solo del color: cada serie lleva trazo y
marcador propios y la figura se lee en escala de grises.

## 3. Trazo y tipografía: pisos impresos

Nada por debajo de 7 pt ni de 0,5 pt al tamaño final.
`comprobar_minimos()` recorre la figura construida y lo verifica; cada
script lo llama antes de guardar.

## 4. Un solo registro de figuras

`figuras_notebook.py` es el registro único: qué script produce cada
figura y con qué argumentos. Se usa de tres maneras, todas sobre la misma
lista.

Desde un notebook:

```python
from figuras_notebook import generar_y_mostrar
generar_y_mostrar(outputs_dir="outputs")     # las seis, mostradas en línea
generar_y_mostrar(4, ancho=1000)             # una, por número o por nombre
```

Desde la línea de comandos:

```bash
python3 figures_src/figuras_notebook.py        # desde cualquier directorio
python3 figures_src/figuras_notebook.py --catalogo
```

Las rutas por omisión son `results/` y `figures/` **del repositorio**,
resueltas desde la ubicación del módulo y no desde el directorio actual.

Y `regenerar_todas_figuras.sh`, que ahora es un envoltorio de tres líneas
sobre lo anterior. Antes la lista de figuras vivía en el shell y volvía a
estar en el notebook; dos listas es la vía segura para que una figura se
regenere con argumentos viejos.

`figuras.ipynb` es un notebook mínimo de ejemplo.

**Las figuras 5 y 6 leen de otro sitio.** Sus CSV —`trayectorias.csv` y
`resumen_familias.csv`— no están bajo `outputs/`: la corrida de la
destilación escribió en el directorio de trabajo del notebook y no en el
árbol de salidas. Es el mismo hecho que `docs/PENDIENTES.md` §2.6
registra sobre la entrada del experimento 11. Por eso su ubicación es un
parámetro aparte:

```python
fn.localizar_destilacion("~/codigos/SW_UDE")   # imprime los candidatos
fn.usar_destilacion("<la ruta que salga>")     # la fija para la sesión
```

o `--destilacion-dir` por línea de comandos, y la variable de entorno
`DESTILACION_DIR` para el envoltorio de shell. Si no se indica, se toma
`<outputs_dir>/destilacion_v51` y, cuando falla, el error dice qué hacer.

Cada figura se genera en un proceso aparte, con el intérprete del kernel.
Así una corrida desde el notebook da exactamente el mismo PDF que la de
shell, y el estado de matplotlib del notebook no contamina el de las
figuras. `SOURCE_DATE_EPOCH` se fija en los tres caminos: verificado, las
seis salen byte a byte idénticas entre corridas, de modo que
`results/MANIFEST.sha256` no da falsos negativos.

Una figura que falla no detiene a las demás: se informa con el error del
script y se sigue. Lo que se muestra en el notebook es el PNG de control
que cada script escribe junto al PDF; el PDF es lo que compila LaTeX.

## 5. Sin títulos internos

Ninguna figura lleva título general: lo describe el caption, que además
compone la revista con su tipografía. Los rótulos de panel se reducen a
`(a) Functional fidelity` y equivalentes.

## Estado

| Figura | Estado |
|---|---|
| temporal_supervision_horizon | normalizada y renderizada |
| closed_form_fidelity_v2 | normalizada, traducida y renderizada |
| closed_form_fidelity_plane_v2 | normalizada, traducida, renderizada |
| hospital_state_reconstruction | normalizada y renderizada |
| m_sensitivity_v2 | normalizada y renderizada |
| real_multiseed_v2 | normalizada y renderizada; cifras verificadas |

## 6. Lo que apareció al dibujar con los datos reales

Dos cosas que los CSV postizos escondían.

**Las líneas de referencia del UDE global coinciden exactamente con el
punto m=50.** Comprobado: en los dos escenarios y en los dos paneles, la
fila `modelo == "UDE"` de `resumen_TODOS_escenarios.csv` es idéntica,
hasta 1e-12, a la fila m=50 del CSV de sensibilidad. Es correcto por
construcción —m=50=T es el caso global— pero conviene que el caption lo
diga, porque si no parece una coincidencia sospechosa o un error de
trazado. Las líneas se conservan: sirven para ver de un golpe qué m
superan a la referencia.

**Las dash-dot no estaban explicadas en ninguna parte.** Al quitar el
suptitle se perdió la única mención a ellas. Ahora hay una leyenda única
al pie que declara los dos escenarios, la referencia del UDE global y
`m_ref`.

**El eje x pasó a logarítmico.** La grilla es {1,2,5,7,10,15,20,30,50} y
en escala lineal los m chicos se apelotonan contra el margen, que es
justo donde están los mínimos: `RMSE_beta` mínimo en m=2 para *Abrupt
intervention* y en m=1 para *Seasonal*; `RMSE_I` mínimo en m=30 y en m=1
respectivamente. Los dos paneles discrepan sobre el mejor m en *Abrupt
intervention*, que es exactamente la tesis del artículo.

Esto confirma además que quitar el sombreado valió la pena: los mínimos
de la fidelidad funcional están en m=2 y m=1, dentro de la región que la
versión anterior marcaba como excluida.

**En `hospital_state_reconstruction` la fila de error en escala
logarítmica era necesaria**: los errores van de 1e-2 a 1e1, tres órdenes
de magnitud, y en lineal todo lo que está por debajo de 1 desaparece. La
fila muestra que en este escenario SW-UDE es **peor** que el UDE global
en los tres estados (RMSE_S 3,38 contra 1,95; RMSE_I 2,24 contra 1,95;
RMSE_R 2,59 contra 0,57), que es lo que el texto afirma.

El CSV de sensibilidad trae además dos columnas que la figura ignora a
propósito: `es_control`, en `true` para m en {1,2,5,7}, y `r_m = m·gamma`.
`es_control` es la marca del piso epidemiológico que V2 retira. Es
descriptiva y no molesta, pero si un revisor abre el CSV la va a ver.


## 7. real_multiseed_v2 — verificación contra el manuscrito

Las diez curvas vienen de `outputs/datos_reales_multiseed/seedN/
datos_reales_curvas.csv`, 206 días cada una, 41 de prueba.

**Las trece cifras de la Sección 4.2.5 se recalculan desde esos CSV y
coinciden todas**: beta de SW-UDE en [0,106 , 0,219] y positivo en las
diez; beta del UDE negativo en cuatro de diez con mínimo −0,286; cruce
sostenido de R_eff entre t=126 y t=132 para SW-UDE y entre t=16 y t=151
para el UDE; R_eff máximo 1,313±0,084 contra 1,151±0,197, con una corrida
del UDE en 1,698. El script las reimprime cada vez que se corre, para que
la comprobación no dependa de que alguien se acuerde de hacerla.

Decisiones de trazado:

- Las diez curvas individuales van a trazo fino y alfa 0,45, por delante
  de la banda intercuartílica, que va a 0,16. La dispersión entre
  semillas es el resultado, no ruido que convenga suavizar.
- El panel (a) se recorta en 100 mil casos. Una de las diez corridas del
  UDE global llega a 6,5×10⁵ —dieciocho veces el máximo observado— y en
  escala completa aplasta todo lo demás. El recorte y su magnitud están
  anotados dentro del panel.
- Seis de las diez corridas del UDE se quedan prácticamente planas en
  I₀ ≈ 26 390, es decir no se mueven de la condición inicial. Eso se ve
  directamente en el panel (a) y es parte de lo que la figura muestra.

## 8. Procedencia de la entrada de la destilación

Comparando `data/datos_reales_curvas.csv` del repositorio contra las diez
semillas: la columna `I_observado` es **idéntica** en las once, diferencia
exactamente cero, de modo que la serie empírica es la misma. Las columnas
ajustadas no coinciden con ninguna; la más cercana es `seed4`, y aun así
difiere en 1 251 casos en `I_Windowed` y 2,3e-3 en `beta_Windowed`.

Conclusión: la entrada del experimento 11 sale de otra corrida, con la
misma serie observada. El candidato natural es la corrida de semilla
única del experimento 9, cuya salida es `outputs/datos_reales/`. Queda
por confirmar; ver `docs/PENDIENTES.md` §2.6.
