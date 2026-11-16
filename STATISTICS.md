# Convenciones estadísticas

RTT HTTP mide solicitud y respuesta desde un mismo dispositivo con reloj monotónico. Jitter principal: `|RTTᵢ − RTTᵢ₋₁|` entre respuestas válidas consecutivas. SLA de referencia: latencia **< 50 ms**; exactamente 50 ms incumple. El evento de lag severo es **> 50 ms**, por lo que 50 ms no es lag severo aunque incumpla SLA.

Las estadísticas descriptivas usan varianza muestral con `n−1`; `n < 2` produce varianza no definida. Los cuartiles deben declarar su método. Los fallos se conservan y cuentan como incumplimiento, pero no se imputan como latencias numéricas. Las pruebas inferenciales deberán declarar supuestos y evitar tratar medidas repetidas como independientes.

La prueba unilateral de proporción usa la cola binomial exacta cuando `n·p₀ < 5` o `n·(1−p₀) < 5`; con muestras mayores usa la aproximación normal. La región de rechazo exacta se expresa con el menor conteo entero cuya cola es menor o igual a `α`.

La pantalla Análisis incluye un explorador de modelos teóricos Bernoulli, binomial, geométrico, Poisson, normal, exponencial, Student t y chi cuadrada. Permite editar los parámetros, consultar la masa o densidad, la función acumulada y la probabilidad puntual o de intervalo. Sus curvas son referencias matemáticas, no evidencia de ajuste a las mediciones. Para E1, el diagnóstico de Jarque–Bera se muestra por separado y tampoco confirma normalidad cuando no rechaza la hipótesis nula.
