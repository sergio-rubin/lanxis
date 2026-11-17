# Soporte por plataforma

| Capacidad | Android | Windows | Linux |
| --- | --- | --- | --- |
| Flutter nativo | Objetivo | Objetivo | Objetivo |
| Servidor/cliente HTTP, transferencia TCP y eco UDP por LAN existente | Implementación compartida | Implementación compartida | Implementación compartida |
| SQLite local | Implementación compartida | Implementación compartida | Implementación compartida |
| Distancia automática al punto de acceso | Wi-Fi RTT mediante API oficial cuando el equipo, el punto de acceso y los permisos lo permiten; con incertidumbre y procedencia | Sin medición automática implementada | Sin medición automática implementada |
| Hotspot controlado por la app | Adaptador Kotlin `startLocalOnlyHotspot`, sujeto a permisos y fabricante; compilado, pendiente prueba física | No implementado; usar hotspot de Windows o LAN existente | Adaptador `nmcli`/NetworkManager con detección AP, PolicyKit y perfil temporal; compilado, pendiente prueba con hardware |

Estos son objetivos de implementación, no certificaciones generales de hardware. La aplicación muestra las capacidades de red anunciadas por el servidor y mantiene una ruta manual de LAN cuando un adaptador no está disponible. HTTP, TCP y UDP han pasado pruebas de loopback en Linux; las pruebas de red y persistencia pasan también en CI de Windows. En Wi-Fi real se probó Android como servidor y Linux como cliente con 35/35 mediciones válidas. Faltan la dirección inversa, Windows en hardware y otras combinaciones. El eco UDP actual envía datagramas secuenciales y no informa reordenamiento. Android 17/API 37 requiere revisar `ACCESS_LOCAL_NETWORK` al actualizar el SDK objetivo.

La distancia es opcional. Wi-Fi RTT solo se intenta si el servidor coincide con el gateway de la red y el punto de acceso anuncia 802.11mc. Si falla una condición, se conserva «sin dato»; la aplicación no deduce metros a partir de RSSI ni confunde la distancia objetivo de un escenario con una observación. Se puede introducir una distancia medida externamente, identificada como manual.
