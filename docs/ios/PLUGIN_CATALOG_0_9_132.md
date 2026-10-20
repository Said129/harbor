# Repositorios e instalaciones de plugins

Referencia: Desktop 0.9.132, `0834340cec5531650bfe78cd628628702e636987`, especialmente `streams/plugins/manifest.ts`, `repos.ts`, `install.ts` y `store.ts`.

## Implementación

`HarborPluginManifest` reconoce los manifiestos Harbor, las listas provider-script y los índices Android. Conserva las URL relativas, las alternativas main/master/HEAD de GitHub, los tipos, idiomas, restricciones, notas y códigos de error para dirigir addons Stremio y repositorios de lectura a su lugar correspondiente. El identificador de instalación usa el mismo FNV-1a de unidades UTF-16 y base 36 de Desktop. Reconocer un índice Android no permite instalar ni ejecutar su bytecode en iOS.

`HarborPluginCatalogStore` conserva repositorios e instalaciones en un documento local con revisión. La escritura atómica confirma el estado en memoria después de guardar; la revisión rechaza resultados de red desactualizados. Una lectura corrupta bloquea la escritura y conserva el archivo. Cada documento exige un espacio de datos explícito y rechaza otro espacio al cargar. El enlace definitivo a los perfiles y al hogar sigue pendiente: no se deduce a partir de las preferencias sincronizadas, porque Desktop utiliza IndexedDB local para estas instalaciones.

La instalación comprueba tamaño, checksum declarado, formato y presencia de `streams` en los métodos comunicados por la sonda. La actualización conserva la elección de activación, los ajustes y la versión anterior; la reversión restaura código, hash y ETag. Una actualización del repositorio modifica disponibilidad y versión ofrecida sin reemplazar código instalado. Un fallo de actualización conserva las entradas anteriores. Se guardan archivos con protección de iOS y se excluye su directorio de las copias de seguridad; no se incorporan a recursos de aplicación. El documento contiene solo valores normales de configuración y referencias a claves secretas. La escritura y recuperación de contraseñas en Keychain todavía debe conectarse al gestor.

## Evidencia y límites

`build-plugin-manifest-fixtures.mjs` ejecuta los dos módulos TypeScript originales de la referencia en Node después de comprobar sus SHA-256 normalizados a LF. Genera los resultados esperados de 14 URL, 13 manifiestos y tres identificadores, incluyendo UTF-16 con caracteres fuera del plano básico. El archivo generado pertenece exclusivamente al destino de pruebas. Ejecutar el generador no comprueba la implementación Swift.

Ocho casos nativos nuevos comparan el codec con esos resultados y ejercitan las transacciones de instalación, checksum y formato, actualización/reversión, fallo de escritura, revisión desactualizada, aislamiento y lectura corrupta. Su ejecución con el SDK de Apple está pendiente. No se repiten los casos aprobados de otras áreas.

Este bloque todavía no descarga repositorios ni sondea candidatos reales. Faltan el gestor asíncrono, el transporte HTTP/gRPC de producción, las contraseñas, el pool de ejecución, los productores de fuentes y lectura, y las pantallas completas de Plugins. No hay una IPA nueva ni una declaración de estabilidad o de equivalencia global.
