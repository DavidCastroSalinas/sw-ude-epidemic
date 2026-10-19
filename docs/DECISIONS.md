# Decisiones que afectan la reproducción

Este documento recoge las elecciones de modelado y de protocolo que un
tercero necesita conocer para interpretar los resultados. No son detalles
de implementación: cambiar cualquiera de ellas cambia las cifras.

---

## Serie real y condiciones iniciales

La serie epidemiológica tiene **206 días**. Se ancla a los valores de
Córdova-Lepe et al. y se reescala por un factor de anclaje; **la serie que
entra al pipeline es la reescalada, no la cruda**.

Las condiciones iniciales son **fijas**, no estimadas:

```
N  = 19 660 000
S0 = 19 348 776
I0 =      26 390
R0 =     284 834
```

con `S0 + I0 + R0 == N` exactamente. Los runners abortan si la suma no
coincide.

Esta decisión reemplazó a una versión anterior en que las condiciones
iniciales se derivaban de la serie; el cambio está documentado en
`validacion_reemplazo_real_data.md` del proyecto original y es la razón
de la función `construir_serie_referencia_fija` en
`src/lib/11_real_data.jl`.

## Partición temporal

| Segmento | Días | $n$ |
|---|---|---|
| Entrenamiento | 0 – 164 | 165 |
| Prueba | 165 – 205 | 41 |

La partición es **temporal y única**: no hay validación cruzada ni
remuestreo. Toda selección de modelo se hace sobre entrenamiento; prueba
interviene solo en la evaluación final.

## Parámetros fijados de antemano

- **$\gamma = 1/7$ d$^{-1}$**, tomado de literatura y no estimado.
- **$\beta_0 = 0{,}20$** en datos reales; **$0{,}25$** en los escenarios
  sintéticos.
- **$N$ fijo.** La sensibilidad a $N$ y $\gamma$ (antiguo experimento 13)
  se eliminó del artículo y su código ya no existe.
- **Semilla $1234$** en todas las corridas de semilla única, incluida la
  destilación paramétrica. Las corridas multisemilla declaran sus semillas
  en el runner.

## Líneas base

Se usan dos predictores de persistencia, **uno por eje**, y no son
comparables entre sí:

- para $\hat\beta$: la persistencia de la tasa estimada;
- para $I(t)$: la persistencia fija $I(t) \equiv I(164) = 16\,584$.

Los cocientes que aparecen en las tablas siempre se calculan contra la
línea base del eje que se está reportando.

## Destilación paramétrica (v5.1)

- **Integrador exclusivamente discreto**: Euler explícito con
  $\Delta t = 1$ día. No se usa ningún solver ODE continuo.
- **Dos objetivos separados**: fidelidad a $\beta_{\mathrm{SW-UDE}}$ y
  fidelidad dinámica sobre $I(t)$. La trayectoria autónoma evalúa
  $\beta$ siempre sobre $I_{\mathrm{simulada}}/N$.
- **Selección exclusivamente con entrenamiento.** La validez de prueba
  jamás interviene en el ranking.
- **La selección principal ocurre solo entre M1 y M2.** Las once familias
  restantes son análisis de sensibilidad y no compiten por el modelo
  principal, incluida E ($=$ `C15`), que es la de menor error de prueba.
  E se presenta por completar la secuencia estructural, no como modelo
  seleccionado.
- **Procedimiento**: 50 multistarts algebraicos por familia, refinamiento
  dinámico de las 10 mejores soluciones, $\lambda_\beta = \lambda_I = 0{,}5$
  en la pérdida conjunta, semilla `20260912` para los multistarts.
- Los parámetros de los 10 refinamientos se exportan completos
  (`top10_dinamico_*.csv`) para el anexo.

### Correspondencia de claves

El manuscrito etiqueta las familias S1–S10, E; la implementación usa
claves C*/M*. La tabla es:

| Manuscrito | Implementación | Forma |
|---|---|---|
| M1 | `M1` | $\beta_0 + bt + A\sin(\omega t + \varphi)$ |
| M2 | `M2` | M1 $- w_2 I/N$ |
| E | `C15` | $\exp[\eta_0 + \eta_1 t + A\sin(\omega t+\varphi) - \kappa I/N]$ |
| S1 | `C1` | $\beta_0 + bt$ |
| S2 | `C4` | $(\beta_0+bt)/(1+\kappa I/N)$ (Capasso–Serio) |
| S3 | `C5` | $(\beta_0+bt)\exp(-\kappa I/N)$ |
| S4 | `C6` | umbral sigmoide en $I/N$ |
| S5 | `C7` | saturación tipo Hill |
| S6 | `C8` | umbral tipo Hill sustractivo |
| S7 | `C12` | una transición logística $+$ retroalimentación |
| S8 | `C9` | dos transiciones logísticas $+$ retroalimentación |
| S9 | `C11` | M2 con período $\in[2,10]\times$ ventana |
| S10 | `C13` | M2 con período fijo en 365 d |

Esta correspondencia está codificada en `verify/manuscript_values.yaml`,
de modo que el verificador la comprueba en cada corrida.

### Cotas alcanzadas

La frecuencia $\omega$ converge a su cota en M1, M2 y E: el período llega
al más largo admisible, $164$ d, que es el largo del segmento de
entrenamiento. Los catorce parámetros restantes de esas tres formas quedan
en el interior de su rango. Entre las familias de sensibilidad, S4, S5, S6
y S8 tienen al menos un parámetro en su cota; en S8 es $t_1 = 82$ d, la
mitad de la ventana, que es el parámetro de mayor carga interpretativa de
esa familia. Esa es la razón por la que S8 no se presenta entre las formas
principales pese a su error de prueba.

## Lo que se eliminó del artículo

- **Regresión simbólica (experimentos 15–19).** Ya no aparece en el
  manuscrito; su rol lo ocupa la destilación paramétrica. Su código no se
  incluye en este repositorio, lo que elimina la dependencia de
  `SymbolicRegression.jl` y `MLJ.jl`.
- **Sensibilidad a $N$ y $\gamma$** (experimento 13).
- **Variación total de $\hat\beta$** (experimento 6).
- **Figura S3 y el experimento de ruido absoluto**, superados por el
  esquema multiplicativo unificado ($\sigma_{rel}$).
