# LANXIS

**Local Area Network eXperimentation & Inference Suite**. Laboratorio nativo y local para investigar redes entre dispositivos Android, Windows y Linux. Los experimentos no requieren Internet. La app registra mediciones reales y conserva las muestras originales para análisis reproducible.

> Estado: implementación en curso. Véase [matriz de requisitos](docs/REQUIREMENTS.md); ninguna capacidad de hotspot o interoperabilidad entre dispositivos se considera validada sin pruebas en hardware.

## Desarrollo

Se requiere Flutter estable. Después de instalar los prerrequisitos de cada plataforma:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Las compilaciones nativas se hacen en su sistema correspondiente. `flutter build apk --release --split-per-abi`, `flutter build windows --release` y `flutter build linux --release` son los comandos objetivo. Los bundles de escritorio incluyen más que el ejecutable.

## Investigación de referencia

El diseño factorial E1–E6 reproduce la investigación «Proyecto Final - Servidor Hotspot (Requerimientos y Estadísticas)» proporcionada por el responsable. Las distancias nominales son 1, 6 y 12 m, con un cliente o 3–5 clientes. El tamaño de referencia es 100 solicitudes por escenario y es configurable. RTT HTTP, jitter, throughput, errores y contexto se guardan por ensayo; nunca se presentan resultados de ejemplo como mediciones reales.

En **Análisis** se puede filtrar por sesión, fase, prueba y ensayo. La selección puede exportarse como CSV, JSON, XLSX, PDF o ZIP; el ZIP incluye manifiesto y hashes SHA-256. En **Red local**, las transferencias HTTP de descarga y subida usan bloques reproducibles con verificación de integridad. Los participantes coordinados conservan lotes de resultados pendientes en SQLite hasta recibir confirmación.

## Licencia

Código y contenido originales de LANXIS: [Creative Commons Attribution-NonCommercial 4.0 International](LICENSE). Se permite usar, compartir y adaptar para fines no comerciales con atribución y aviso de cambios. El texto legal oficial prevalece. Las dependencias y fuentes tienen sus propias licencias, detalladas en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Titular del proyecto: **sergio-rubin y colaboradores de LANXIS**. Repositorio oficial: [sergio-rubin/lanxis](https://github.com/sergio-rubin/lanxis).
