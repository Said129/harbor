# Transporte nativo de plugins

La referencia sigue siendo Harbor Desktop 0.9.132, `0834340cec5531650bfe78cd628628702e636987`: `manga/plugins/host-http.ts`, `worker-host.ts`, `same-site-host.ts`, `streams/plugins/runtime.ts` y las reglas de redirección y red pública de `src-tauri/src/http_fetch.rs`.

## Implementación en validación

El adaptador dispone de una interfaz C asíncrona separada de las operaciones puras anteriores. Cada solicitud aceptada obtiene un identificador y una única respuesta, también al cancelarse. El llamador conserva sus objetos; Rust solo recibe bytes y un contexto opaco que devuelve a su callback. La respuesta se copia durante ese callback. La cancelación aborta la operación de red y permite descartar cualquier respuesta tardía. No se bloquea el hilo de interfaz ni se espera una operación de red dentro de una llamada pura de `CoreBridge`.

`HarborNativeNetwork` enlaza esa interfaz con continuaciones Swift de una sola resolución, protegidas frente a la carrera entre recibir un resultado, cancelar y asignar el identificador. `HarborNativePluginTransport` adapta HTTP y gRPC al protocolo del worker, con las políticas distintas de instalación, ejecución de streams y lectura. Conserva el contenido binario mediante base64; el texto utiliza UTF-8 como el `TextDecoder` de referencia. gRPC mantiene sus propios límites y cabeceras, además de la negociación HTTP/2 por TLS.

El backend conserva métodos, tamaños, tiempos, redirecciones manuales, cambios POST→GET y las restricciones de redirecciones que reenvían cuerpos. Las cabeceras personalizadas se retiran al cruzar un origen. El permiso para Referer y Cookie usa dominios registrables con sufijos privados, por lo que dos usuarios distintos de github.io no se confunden con un mismo sitio. No hay almacén automático de cookies ni de credenciales. Las URL, cuerpos y cabeceras no aparecen en los errores del backend.

La resolución DNS comprueba y fija las direcciones que se utilizarán en cada conexión, manteniendo el nombre original para TLS. Las direcciones privadas se rechazan también cuando llegan mediante un nombre DNS. La política pública añade los rangos reservados de la referencia. En redes móviles IPv6, DNS64 con el prefijo conocido 64:ff9b::/96 se comprueba por su IPv4 incorporada: se conserva el socket IPv6 y se rechaza una dirección privada incorporada. Las listas de hosts bloqueados se reciben del llamador; su enlace con las preferencias de privacidad todavía pertenece a la integración del gestor.

El límite del sobre JSON entre nativo y WebKit pasa a 64 MiB para poder transportar una respuesta gRPC válida de 8 MiB: sus campos body y messages contienen base64 y ocupan más de 22 MiB en JSON. El límite de la respuesta de red no aumenta. La codificación de ese sobre se hace fuera del actor de interfaz y se vuelve a comprobar el perfil activo antes de publicarlo.

## Resultados conservados y pruebas pendientes

La [ejecución 39504615361](https://github.com/Said129/harbor/actions/runs/39504615361), fuente `a488db07303df8a59993a42abc85c494dfc3efd4`, aprobó 12 de sus 13 casos y compiló sin advertencias nuevas. Se conservan los resultados y el árbol original de Xcode. Confirmó la corrección de los cierres de sinopsis, el reinicio explícito, el mensaje de inicialización y el uso de la API de HTML. También confirmó la corrección de la advertencia del escritor del catálogo, conservando las ocho pruebas anteriores de ese catálogo.

Solo falló la separación de trailers gRPC con CRLF: Swift trata CRLF como un único carácter, por lo que dividir por el carácter LF no separaba las líneas. Se normaliza CRLF antes de dividir. Se mantienen los mismos resultados esperados del módulo original; el caso fallido se selecciona otra vez.

El bloque nuevo selecciona ocho contratos Rust de DNS, cabeceras, sockets HTTP propios, redirecciones, límites, cancelación y callback; cinco casos nativos nuevos; tres recorridos del worker afectados por la respuesta asíncrona; el caso gRPC fallido; y una consulta pública nueva que comprueba la interfaz C real, TLS y HTTP/2. No repite otros casos de sinopsis, reinicio, catálogos o perfiles ya aprobados. Los servidores locales y el resolvedor propio de las pruebas solo pertenecen al módulo Rust de pruebas, sin un interruptor de pruebas en el protocolo de producción.

Se adquirieron Cargo, rustc y rustfmt oficiales en una carpeta de herramientas de este trabajo, verificando los hashes del manifiesto y los componentes. No se instalaron globalmente. El nuevo archivo de dependencias conserva las 48 versiones anteriores y añade la red; no actualiza las dependencias ya aprobadas de las operaciones puras. La comprobación local de Rust en Windows se detuvo antes de analizar el código por faltar `link.exe`. La comprobación Desktop sin conexión también encontró dependencias ajenas sin caché. Son limitaciones registradas, no comprobaciones aprobadas. La compilación y las pruebas del código nuevo requieren el SDK de Apple.

Este transporte todavía debe conectarse al gestor de repositorios, contraseñas, pool y productores reales. Las pantallas de Plugins y el resto del alcance completo siguen pendientes. No hay una IPA nueva ni una aprobación global de estabilidad, compatibilidad visual o rendimiento físico.
