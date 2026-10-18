# Entorno de ejecución

## Julia

El código se desarrolló con Julia 1.10.5. Esta rama todavía no contiene
`Project.toml` ni `Manifest.toml`, por lo que no fija el árbol completo de
dependencias y una instalación nueva no garantiza las mismas versiones que
la corrida del artículo.

El script de mantenimiento `bin/generar_entorno.jl` crea esos archivos a
partir de las versiones de paquetes registradas para la corrida de
referencia. Para publicar una versión reproducible, hay que ejecutarlo en
el entorno de referencia, revisar y versionar ambos archivos. Después de
eso, el entorno puede instalarse con:

```bash
julia --project=. install_dependencies.jl
```

## Python

Python 3.10 o superior se usa para regenerar las figuras. En un entorno
virtual:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r figures_src/requirements.txt
python3 figures_src/figuras_notebook.py
```

Los scripts de verificación de cifras usan la biblioteca estándar de
Python:

```bash
python3 verify/verificar_cifras.py
```

Para comprobar el flujo de ejecución Julia con parámetros reducidos:

```bash
SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia
```

La prueba reducida de destilación es opcional:

```bash
SIR_UDE_SMOKE_TEST=1 ./smoke_test.sh --con-julia --con-destilacion-smoke
```

## Figuras y resultados

Los PDF pueden regenerarse de forma determinista fijando `SOURCE_DATE_EPOCH`:

```bash
SOURCE_DATE_EPOCH=1760000000 python3 figures_src/figuras_notebook.py
```

El manifiesto de sumas de comprobación permite verificar los archivos de
datos, resultados y figuras entregados:

```bash
bin/generar_manifest.sh --verificar
```

El manifiesto confirma que los archivos coinciden con el inventario
publicado; no demuestra que una nueva corrida produzca los mismos bytes.
