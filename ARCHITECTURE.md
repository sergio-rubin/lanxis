# Arquitectura

LANXIS comparte código Flutter y Dart entre Android, Windows y Linux. La interfaz consume servicios de aplicación; estos coordinan red, persistencia y análisis. La lógica de medición y estadística no reside en widgets.

La jerarquía persistente es `Sesión → Fase → Prueba → Ensayo → Medición/Evento`. Los IDs son globales y las marcas de tiempo civiles se guardan en UTC; el tiempo transcurrido se mide con reloj monotónico. Los datos originales nunca se reemplazan con agregados.

El transporte principal usa `dart:io`, contratos JSON versionados y cargas generadas por bloques. Las capacidades Wi-Fi y de hotspot se detectan por plataforma. La falta de control del hotspot no impide usar una LAN existente.

El motor estadístico acepta muestras tipadas sin conocer la red ni la interfaz. Las exportaciones incorporan parámetros, unidades, procedencia y versiones de método.
