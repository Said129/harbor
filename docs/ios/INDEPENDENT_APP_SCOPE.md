# Perfiles propios y funcionamiento independiente

El 27 de octubre de 2026 el propietario precisó el objetivo: completar primero el port de Desktop 0.9.132 para iOS/iPadOS, manteniendo las exclusiones Games/Kids y conservando el sistema existente de perfiles de Harbor. Eliminar el sistema de cuentas/sesiones de Stremio, sin sustituir los perfiles de Harbor por otro sistema nuevo.

## Comportamiento requerido

- La entrada principal son los perfiles de la aplicación. Se puede crear, elegir y usar un perfil local sin autenticar con un tercero.
- Los ajustes, addons configurados, biblioteca e historial de cada propietario deben persistir localmente y conservarse si falla un proveedor de cuentas.
- Conservar los perfiles, su gestión y la cuenta de Harbor. Retirar la pestaña, el inicio de sesión web y por contraseña, el registro y la sincronización autenticada de Stremio, incluidos sus accesos en la guía inicial.
- Antes de retirar la dependencia de una sesión de Stremio, migrar sus addons, biblioteca, historial y progreso disponibles al propietario Harbor correspondiente. Una migración fallida debe conservar los originales y permitir recuperación; no cerrar sesiones del proveedor en otros dispositivos ni borrar su cuenta remota.
- Conservar el protocolo abierto de addons y las fuentes configuradas. La compatibilidad de un protocolo no obliga a usar su servicio de cuentas.
- Los datos importados de una colección defectuosa deben conservarse para recuperación; una entrada con manifest nulo no debe provocar la sustitución destructiva de toda la configuración.
- Un servicio auxiliar externo indisponible no debe bloquear la gestión de perfiles, la biblioteca local, la lectura o la reproducción de archivos ya descargados.

## Estado y límites

Ya existen el almacén local de perfiles, propietarios separados y configuración local de addons. El incremento actual retira la pestaña y los accesos de cuenta Stremio, sus servicios de autenticación y las llamadas de sincronización desde AppModel. Conserva las tres secciones de Cuenta: Tu perfil, Perfiles y Cuenta Harbor. Los datos originales se convierten en fuentes locales conservando sus propietarios, manifiestos completos, biblioteca y cambios pendientes; la sesión solo se descarta tras guardar los datos. El arranque habilita el almacenamiento antes de descargar Cinemeta y una respuesta tardía no reemplaza fuentes elegidas por el usuario. La actualización automática de manifiestos pasa a segundo plano; solo Actualizar espera al proveedor. Este incremento todavía necesita compilación y ejecución en Apple.

La selección de comprobación incorpora ocho casos nuevos de migración, dos de propietarios afectados y dos recorridos nuevos de Cuenta con preparaciones independientes en iPhone/iPad. No certifica todavía el primer arranque sin red ni los tres botones de guardado cuyo requisito de cuenta Stremio se ha retirado; esos recorridos también deben cerrarse antes de la entrega final.

La aclaración del propietario no exige diseñar un sistema de cuentas nuevo ni contratar un backend nuevo: se conserva el sistema de Harbor. La disponibilidad de su servidor y la validación de la sincronización siguen siendo asuntos distintos de los perfiles locales; no se ha desplegado un servidor propio ni se considera que los perfiles locales demuestren sincronización por Internet.

El trabajo de Trakt está en implementación y sin validar. Su proxy comunitario es una integración opcional; no constituye nuestro sistema de cuentas ni resuelve la independencia del núcleo de la aplicación.

## Plataformas posteriores

Primero terminar y validar la IPA única de iOS/iPadOS. Después se abordarán Desktop, Android y Android TV; el propietario mantiene flexible el orden entre esas tres plataformas. No se inicia un port paralelo en esta entrega.
