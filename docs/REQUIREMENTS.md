# LANXIS: matriz de requisitos

Fuente: prompt maestro del proyecto y «Proyecto Final - Servidor Hotspot (Requerimientos y Estadísticas).pdf». Los estados se actualizan con evidencia, no por intención de diseño.

| ID | Requisito | Evidencia esperada | Estado |
| --- | --- | --- | --- |
| P1 | Proyecto Flutter Android, Windows y Linux | `flutter analyze`, builds por plataforma | APK Android y bundle Linux compilados localmente; CI de Android, Linux y Windows completado correctamente; Windows sin prueba manual |
| N1 | Servidor y cliente LAN sin Internet, protocolo versionado | Prueba entre procesos y dispositivos | HTTP bidireccional probado en loopback; dispositivos físicos pendientes |
| N2 | Descubrimiento, emparejamiento y control de capacidad | Prueba en LAN y escenarios de permiso denegado | UDP y registro probados en loopback; LAN real pendiente |
| N3 | Hotspot según capacidad real del sistema | Pruebas en hardware Android, Windows y Linux | Pendiente de hardware |
| E1 | Sesión, fase, prueba, ensayo, medición y evento persistentes | Tests de SQLite, interrupción y recuperación | SQLite y migraciones implementados; identidad y outbox probados tras reapertura; interrupciones reales pendientes |
| E2 | Escenarios factoriales E1–E6 y experimentos libres | Tests de configuración y ejecución real | Coordinación E4 probada con dos instancias locales; hardware real pendiente |
| M1 | RTT HTTP, jitter, throughput, errores y trazabilidad | Tests de red y comparación monotónica | Descarga y subida por streaming probadas en loopback; validación física pendiente |
| S1 | Unidad 1: descriptivas y cinco gráficas obligatorias | Casos conocidos y gráficas con datos reales | Implementadas y probadas con casos unitarios; revisión visual con datasets reales pendiente |
| S2 | Unidad 2: probabilidad condicional, total y Bayes | Comparación numérica con SciPy | Implementada; contraste exhaustivo con SciPy pendiente |
| S3 | Unidad 3: Bernoulli, binomial, geométrica y Poisson | Casos conocidos y extremos | Implementada con explorador de parámetros y gráfica teórica; casos numéricos básicos probados, extremos pendientes |
| S4 | Unidad 4: normal, exponencial, t y chi cuadrada | Valores de referencia y supuestos | Implementada con explorador de densidad, acumulada y áreas; referencias básicas probadas, validación amplia pendiente |
| S5 | Unidad 5: intervalos y pruebas de hipótesis | Valores críticos y p-valores de referencia | Implementada; referencias y supuestos adicionales pendientes |
| X1 | CSV original y exportaciones JSON/JSONL/XLSX/PDF/HTML/ZIP | Validación de archivos generados | Formatos y exportación por sesión/fase/prueba/ensayo implementados; ZIP/PDF/XLSX probados |
| U1 | UI completa, clara/oscura, branding y movimiento solicitado | Pruebas visuales móvil/escritorio y accesibilidad | Diseño, movimiento y pruebas visuales de dos tamaños implementados; revisión de accesibilidad y prueba física pendientes |
| D1 | CI, documentación, licencia y avisos | Artefactos en GitHub Actions y revisión legal | CI de análisis, Android, Linux y Windows en verde; licencia y avisos presentes, revisión legal pendiente |

Issues de requisitos creados el 16 de noviembre de 2026 en GitHub: [fundamentos #1](https://github.com/sergio-rubin/lanxis/issues/1), [red #2](https://github.com/sergio-rubin/lanxis/issues/2), [ciencia #3](https://github.com/sergio-rubin/lanxis/issues/3) y [producto #4](https://github.com/sergio-rubin/lanxis/issues/4). Cada uno tiene etiquetas de Android, Windows y Linux, además de su área.
