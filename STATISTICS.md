# Convenciones estadísticas

RTT HTTP mide solicitud y respuesta desde un mismo dispositivo con reloj monotónico. Jitter principal: `|RTTᵢ − RTTᵢ₋₁|` entre respuestas válidas consecutivas. SLA de referencia: latencia **< 50 ms**; exactamente 50 ms incumple. El evento de lag severo es **> 50 ms**, por lo que 50 ms no es lag severo aunque incumpla SLA.

Las estadísticas descriptivas usan varianza muestral con `n−1`; `n < 2` produce varianza no definida. Los cuartiles deben declarar su método. Los fallos se conservan y cuentan como incumplimiento, pero no se imputan como latencias numéricas. Las pruebas inferenciales deberán declarar supuestos y evitar tratar medidas repetidas como independientes.
