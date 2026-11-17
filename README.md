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

El diseño factorial E1–E6 reproduce la investigación «Proyecto Final - Servidor Hotspot (Requerimientos y Estadísticas)» proporcionada por el responsable. Las distancias objetivo son 1, 6 y 12 m, con un cliente o 3–5 clientes. La vista previa adapta participantes, carga, intervalo, espera y calentamiento según los dispositivos listos, el ambiente cerrado o abierto y el perfil de carga. También se pueden guardar escenarios propios. El tamaño de referencia es 100 solicitudes por escenario y es configurable. RTT HTTP, jitter, throughput, errores y contexto se guardan por ensayo; nunca se presentan resultados de ejemplo como mediciones reales.

La distancia real no se exige para iniciar. Un servidor Android o Linux con Bluetooth LE anuncia una baliza temporal; un cliente Android o Linux puede estimar la distancia a ese equipo a partir de varias lecturas RSSI y guardar un margen orientativo, las lecturas originales y el origen de la estimación. No se necesita emparejar los dispositivos: la baliza se lee de forma pasiva y se coteja con el identificador temporal publicado por el servidor LAN. Bluetooth solo aporta la variable de distancia: las pruebas siguen por HTTP, TCP o UDP. Esta cifra no sustituye una medición física ni representa un intervalo de confianza calibrado; [Microsoft documenta las limitaciones del RSSI para medir distancias reales](https://learn.microsoft.com/en-us/windows/uwp/devices-sensors/ble-beacon). Si no hay baliza, Android intenta [Wi-Fi RTT](https://developer.android.com/develop/connectivity/wifi/wifi-rtt) únicamente si el servidor coincide con el punto de acceso conectado y ambos admiten 802.11mc; en otros casos conserva el campo vacío o permite registrar una medición externa como manual. [ESPectre](https://github.com/francescopace/espectre) usa información de estado del canal Wi-Fi para detectar movimiento, no ofrece por sí solo una medida fiable de metros entre cualquier par de clientes LAN.

En **Análisis** se puede filtrar por sesión, fase, prueba y ensayo, y explorar distribuciones teóricas con parámetros propios. La selección puede exportarse como CSV, JSON, XLSX, PDF o ZIP; el ZIP incluye manifiesto y hashes SHA-256. En **Red local**, las transferencias HTTP y TCP de descarga y subida usan bloques reproducibles con verificación de integridad; el eco UDP mide respuesta o ausencia de respuesta por datagrama. Los participantes coordinados conservan lotes de resultados pendientes en SQLite hasta recibir confirmación.

Para revisar una exportación con NumPy, SciPy, Pandas y Matplotlib sin modificar la app, consulte [REPRODUCIBILITY.md](REPRODUCIBILITY.md) y la utilidad opcional `tools/verify_export.py`.

Para una prueba entre dispositivos: en el equipo servidor, abre **Red local → Ofrecer servidor** y comparte la dirección y el código; en el cliente, pulsa **Buscar servidores LANXIS** (mDNS, UDP y sondeo local), selecciona el servidor y usa **Conectar y comprobar**. Si la red bloquea el descubrimiento, introduce la URL manualmente. Después crea o selecciona una sesión y una fase, revisa la vista previa del escenario y pulsa **Iniciar ensayo**. Para E4–E6, los clientes deben activar **Participar en ensayo de otro dispositivo** y el servidor muestra cuántos están listos.

## Licencia

Código y contenido originales de LANXIS: [Creative Commons Attribution-NonCommercial 4.0 International](LICENSE). Se permite usar, compartir y adaptar para fines no comerciales con atribución y aviso de cambios. El texto legal oficial prevalece. Las dependencias y fuentes tienen sus propias licencias, detalladas en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Titular del proyecto: **sergio-rubin y colaboradores de LANXIS**. Repositorio oficial: [sergio-rubin/lanxis](https://github.com/sergio-rubin/lanxis).
