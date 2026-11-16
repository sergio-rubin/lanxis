# Soporte por plataforma

| Capacidad | Android | Windows | Linux |
| --- | --- | --- | --- |
| Flutter nativo | Objetivo | Objetivo | Objetivo |
| Servidor/cliente HTTP por LAN existente | Implementación compartida | Implementación compartida | Implementación compartida |
| SQLite local | Implementación compartida | Implementación compartida | Implementación compartida |
| Hotspot controlado por la app | Adaptador Kotlin `startLocalOnlyHotspot`, sujeto a permisos y fabricante; compilado, pendiente prueba física | No implementado; usar hotspot de Windows o LAN existente | Adaptador `nmcli`/NetworkManager con detección AP, PolicyKit y perfil temporal; compilado, pendiente prueba con hardware |

Estos son objetivos de implementación, no certificaciones de hardware. La aplicación debe mostrar la capacidad detectada y una ruta manual de LAN cuando un adaptador no esté disponible. Windows se compila en Windows; Linux en Linux. Android 17/API 37 requiere revisar `ACCESS_LOCAL_NETWORK` al actualizar el SDK objetivo.
