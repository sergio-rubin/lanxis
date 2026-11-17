# Reproducibilidad

Conserve el dataset bruto, versiones de LANXIS y protocolo, configuración exacta, banda, dispositivos, unidades, definición de métricas, eventos, exclusiones y parámetros de análisis. Ejecute E1–E6 según `EXPERIMENTS.md`. Una muestra de 100 no garantiza normalidad ni independencia. Compare resultados derivados con el dataset exportado; el motor debe recalcular sin alterar mediciones.

## Revisión numérica independiente

`tools/verify_export.py` es opcional; LANXIS no usa Python durante los experimentos. Acepte un JSON jerárquico o un CSV exportado por la app e instale las bibliotecas de `tools/requirements.txt` en un entorno Python aparte. Por ejemplo:

```sh
python -m venv .venv-reference
. .venv-reference/bin/activate
python -m pip install -r tools/requirements.txt
python tools/verify_export.py mi_exportacion.json --output informe_verificacion.json --plots graficas_verificacion
```

El informe guarda SHA-256 de la entrada, versiones de NumPy/Pandas/SciPy, número de solicitudes y exclusiones, estadísticas por escenario e intervalos. Si el JSON contiene el resumen calculado por Dart, compara ocho resultados con NumPy/SciPy y falla si la tolerancia absoluta de 1e-9 o relativa de 1e-8 no se cumple. Las gráficas PNG se generan con Matplotlib a partir de la entrada real. No se publican automáticamente ni el dataset ni el informe.

En la exportación física Android→Linux de 35 solicitudes válidas, los ocho campos del resumen Dart coincidieron: diferencia máxima 7,11×10⁻¹⁵ en media y desviación estándar; mediana, P95, SLA y conteos coincidieron exactamente. Esta verificación confirma el cálculo de esa exportación, no la precisión física del hardware ni la independencia de las muestras.

`tools/generate_scipy_reference.py` regenera `test/fixtures/scipy_reference.json`. Sus 14 casos cubren binomial, Poisson, normal, exponencial, t, chi cuadrada, intervalos de media y Wilson, Welch, prueba de varianza y proporción binomial exacta. `test/inference_test.dart` compara esos valores con el motor Dart usando tolerancias explícitas. Si se actualizan los métodos o bibliotecas, regenere la referencia, revise las diferencias y documente el cambio antes de aceptar un nuevo resultado.
