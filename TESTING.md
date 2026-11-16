# Pruebas

Los tests puros cubren estadística y contratos. Los tests de integración deben ejecutar dos procesos en loopback y después dispositivos reales para cada par de sistemas. Las pruebas de hotspot, permisos, Wi-Fi, precisión temporal y rendimiento prolongado requieren hardware y deben registrar modelo, versión del sistema y resultado. No se consideran validadas por una compilación.

El CI ejecuta la suite completa en Linux. En Windows ejecuta las pruebas de red local, SQLite, exportación y ciencia antes del build nativo. Android se compila en CI, pero las pruebas de permisos y hotspot requieren un dispositivo. La instalación local del APK en un teléfono Android 16 fue cancelada por el dispositivo (`INSTALL_FAILED_USER_RESTRICTED`), por lo que no cuenta como prueba física superada.
