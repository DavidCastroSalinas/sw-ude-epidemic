# Datos

## `datos_reales_curvas.csv`

Serie de entrada de la destilación paramétrica (experimento 11). 206
filas, una por día, y nueve columnas:

| Columna | Contenido |
|---|---|
| `dia` | índice del día, 0 a 205 |
| `es_test` | `false` en días 0–164 (entrenamiento), `true` en 165–205 |
| `I_observado` | serie observada de infectados, ya reescalada por el factor de anclaje |
| `I_UDE` | trayectoria ajustada por la UDE sin ventana |
| `I_Windowed` | trayectoria ajustada por la SW-UDE |
| `beta_UDE` | tasa de transmisión recuperada por la UDE |
| `beta_Windowed` | $\hat\beta$ recuperada por la SW-UDE — el objeto que se destila |
| `Reff_UDE`, `Reff_Windowed` | número reproductivo efectivo de cada ajuste |

Las columnas `I_UDE`, `I_Windowed`, `beta_*` y `Reff_*` **no son datos
observados**: son salidas de la corrida de entrenamiento con semilla
`1234`. La única serie empírica del archivo es `I_observado`.

## Procedencia

> **Pendiente de confirmar antes de publicar.**

La serie proviene de los registros del DEIS/MINSAL de Chile, citados en el
manuscrito como `MinsalDEIS2020`. Hay que dejar consignado aquí:

1. el conjunto exacto y la fecha de descarga;
2. la licencia bajo la cual se redistribuye;
3. el factor de anclaje aplicado y su justificación (Córdova-Lepe et al.).

**Importante para quien reproduzca**: la serie que entra al pipeline es la
**reescalada por el factor de anclaje**, no la cruda. Partir de los datos
crudos del DEIS sin aplicar ese reescalamiento no reproduce las cifras del
manuscrito.

## Condiciones iniciales

Son fijas y no se derivan de la serie:

```
N  = 19 660 000
S0 = 19 348 776
I0 =      26 390
R0 =     284 834
```

con `S0 + I0 + R0 == N` exactamente. Los runners abortan si la igualdad no
se cumple.

## Licencia

El archivo derivado que se distribuye aquí está bajo CC BY 4.0
(`../LICENSE-DATA`). La serie de origen mantiene la licencia de su fuente
institucional, que debe quedar consignada arriba.
