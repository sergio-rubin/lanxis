# LANXIS: matriz de requisitos

Fuente: prompt maestro del proyecto y «Proyecto Final - Servidor Hotspot (Requerimientos y Estadísticas).pdf». Los estados se actualizan con evidencia, no por intención de diseño.

| ID | Requisito | Evidencia esperada | Estado |
| --- | --- | --- | --- |
| P1 | Proyecto Flutter Android, Windows y Linux | `flutter analyze`, builds por plataforma | APK Android instalado y abierto en Android 16, bundle Linux compilado; CI de Android, Linux y Windows en verde; Windows sin prueba manual |
| N1 | Servidor y cliente LAN sin Internet, protocolo versionado | Prueba entre procesos y dispositivos | Android servidor → Linux cliente: 35 mediciones reales HTTP/TCP/UDP sin fallo; Linux servidor → Android cliente: conexión por descubrimiento y ensayo E1 5/5; Windows físico pendiente |
| N2 | Descubrimiento, emparejamiento y control de capacidad | Prueba en LAN y escenarios de permiso denegado | Búsqueda con UDP y respaldo HTTP encontró Linux desde Android 16; mDNS/DNS-SD anunció el Xiaomi y fue resuelto por Avahi/Bonsoir en Linux, y Android encontró el servidor Linux por mDNS solo en puerto 8050; selección, código y registro confirmados con 1 cliente; permisos denegados y otras redes pendientes |
| N3 | Hotspot según capacidad real del sistema | Pruebas en hardware Android, Windows y Linux | Pendiente de hardware |
| E1 | Sesión, fase, prueba, ensayo, medición y evento persistentes | Tests de SQLite, interrupción y recuperación | SQLite y migraciones implementados; identidad y outbox probados tras reapertura; interrupciones reales pendientes |
| E2 | Escenarios factoriales E1–E6 y experimentos libres | Tests de configuración y ejecución real | Planificador con vista previa por ambiente, carga y participantes listo; escenarios personalizados persistentes; coordinación E4 probada con instancias locales; hardware real pendiente |
| E3 | Distancia automática cuando el hardware lo permite | Prueba de precisión, permisos y ausencia de dato | Android Wi-Fi RTT implementado para servidor = punto de acceso compatible; baliza Linux→Android verificada (0,3 m ±1,5 m frente a unos 0,4 m); baliza Android→Linux repetida en versión 2013 con señal reciente y ensayo HTTP 3/3 (0,46 m ±3 m, marcado escaso); precisión general pendiente |
| M1 | RTT HTTP/TCP/UDP, jitter, throughput, errores y trazabilidad | Tests de red y comparación monotónica | Transferencias HTTP/TCP y eco UDP probados en loopback y en Android-servidor/Linux-cliente; reordenamiento UDP y validación de relojes pendientes |
| S1 | Unidad 1: descriptivas y cinco gráficas obligatorias | Casos conocidos y gráficas con datos reales | Implementadas y probadas con casos unitarios; revisión visual con datasets reales pendiente |
| S2 | Unidad 2: probabilidad condicional, total y Bayes | Comparación numérica con SciPy | Implementada; verificación independiente de proporciones en exportación física; contraste exhaustivo de particiones pendiente |
| S3 | Unidad 3: Bernoulli, binomial, geométrica y Poisson | Casos conocidos y extremos | Implementada con explorador; binomial y Poisson comparadas con SciPy 1.18.1; extremos adicionales pendientes |
| S4 | Unidad 4: normal, exponencial, t y chi cuadrada | Valores de referencia y supuestos | Implementada con explorador; cuatro distribuciones comparadas con SciPy; validación amplia pendiente |
| S5 | Unidad 5: intervalos y pruebas de hipótesis | Valores críticos y p-valores de referencia | Implementada; intervalos t/Wilson y pruebas Welch/varianza/binomial exacta comparados con SciPy; supuestos adicionales pendientes |
| X1 | CSV original y exportaciones JSON/JSONL/XLSX/PDF/HTML/ZIP | Validación de archivos generados | Formatos y exportación por sesión/fase/prueba/ensayo implementados; ZIP/PDF/XLSX probados |
| U1 | UI completa, clara/oscura, branding y movimiento solicitado | Pruebas visuales móvil/escritorio y accesibilidad | Flujo de red reorganizado, navegación por deslizamiento y burbuja geométrica; pruebas visuales móvil/escritorio y tests de interacción; nueva compilación Android pendiente validación física de fluidez |
| D1 | CI, documentación, licencia y avisos | Artefactos en GitHub Actions y revisión legal | CI de análisis, Android, Linux y Windows en verde; licencia y avisos presentes, revisión legal pendiente |

Issues de requisitos creados el 16 de noviembre de 2026 en GitHub: [fundamentos #1](https://github.com/sergio-rubin/lanxis/issues/1), [red #2](https://github.com/sergio-rubin/lanxis/issues/2), [ciencia #3](https://github.com/sergio-rubin/lanxis/issues/3) y [producto #4](https://github.com/sergio-rubin/lanxis/issues/4). Cada uno tiene etiquetas de Android, Windows y Linux, además de su área.
