# Gestor asíncrono de plugins de streams

Referencia: Harbor Desktop 0.9.132, `0834340cec5531650bfe78cd628628702e636987`, especialmente `streams/plugins/install.ts`, `repos.ts`, `source.ts` y `store.ts`.

## Implementación pendiente de ejecución Apple

`HarborStreamPluginManager` conecta el cliente de descargas, el almacén de catálogo y una sonda real de WebKit. Antes de instalar descarga el código, comprueba su tamaño y SHA-256 declarado, inicializa el worker con el compositor correspondiente y exige el método `streams`. Solo después confirma la instalación. La sonda siempre se desecha. Conserva la distinción de Desktop entre un plugin sin ese método y uno que no logra iniciarse.

El identificador del código provider-script utiliza el ID de la entrada del manifiesto, como `SCRAPER_ID` en Desktop. El identificador de instalación sigue incluyendo el repositorio; ambos ya no se confunden al componer el programa. Los demás llamadores del runtime conservan su ID anterior por defecto. El código original del compositor permanece fijado e intacto.

El gestor añade y actualiza repositorios, mantiene las entradas utilizables ante un fallo de actualización, instala actualizaciones, revierte, activa, desinstala y elimina repositorios. Conserva la elección de activación y los ajustes al actualizar. Un candidato descargado no puede reemplazar una entrada o instalación que haya cambiado mientras se comprobaba. Los conflictos de revisión de operaciones independientes se vuelven a intentar sin repetir la descarga o la sonda. Los plugins retirados del manifiesto dejan de ser ejecutables mediante `listed`, como en Desktop.

Cada operación tiene una tarea cancelable y el gestor rechaza resultados de otra activación. Desecharlo cancela las operaciones y vacía su documento observable. El espacio local de almacenamiento se recibe de forma explícita: este componente no decide por sí mismo el enlace definitivo con el hogar o el perfil.

## Configuración y contraseñas

Los valores normales permanecen en el documento del catálogo. `HarborPluginSecretVault` guarda las contraseñas en Keychain con protección para este dispositivo. Sus claves se derivan de la combinación inequívoca de espacio, plugin y revisión; un plugin o espacio diferente no puede obtener el valor usando la misma revisión.

Una configuración nueva se prepara en una revisión inmutable de Keychain. La escritura atómica del catálogo selecciona esa revisión y sus nombres de claves secretas, sin incluir los valores. Si la escritura falla, se conserva la configuración anterior y se elimina únicamente la revisión preparada que no llegó a confirmarse. Si la escritura ya terminó y después cambió el perfil, se conserva la revisión confirmada aunque se rechace su publicación en la interfaz antigua. La desinstalación y la eliminación del repositorio limpian las referencias activas. Un fallo de limpieza queda señalado en `secretCleanupPending`; todavía falta conectar el reintento persistente al mantenimiento del gestor.

La configuración completa solo se reconstruye para el worker del espacio y la activación vigentes. Los campos ausentes conservan sus secretos anteriores; un campo de contraseña vacío lo elimina. Los campos y sus tipos deben proceder del método `settings` real al conectar el editor. No hay todavía un editor nuevo ni se presentan interruptores sin comportamiento.

## Comprobaciones nuevas

Ocho casos nativos preparados cubren:

- Descarga, sonda WebKit real, instalación, actualización, elección de activación, reversión y eliminación persistida.
- Checksum incorrecto, método ausente en Harbor y provider-script, y fallo de sonda sin instalar el candidato.
- ID real de provider-script y lectura de la configuración secreta por la sonda real de actualización, sin incluirla en el archivo.
- Fallo de escritura de ajustes, conservación de credenciales anteriores y limpieza de la revisión no confirmada.
- Cambio de espacio justo después de la escritura, sin publicar en la interfaz anterior ni borrar la revisión confirmada.
- Cancelación, cambio de propietario y cambio del manifiesto durante la descarga, sin confirmar candidatos tardíos.
- Fallo de actualización del repositorio, conservando el código instalado y registrando el error para reintentar.
- Revisiones reales de Keychain, aislamiento por espacio y plugin, y eliminación de una revisión sin afectar a otra.

Los documentos y respuestas de red de estas pruebas son propios. Varias sondas utilizan el worker real; el caso de Keychain utiliza el almacén real. Todavía no se han ejecutado con el SDK de Apple y no prueban un proveedor público instalado, la interfaz de administración ni rendimiento físico.

Siguen pendientes el enlace definitivo con el contexto del hogar/perfil, el editor de campos reales, el pool, la salud y pausa automática, los productores de streams y subtítulos, los adaptadores de manga y ebook y las pantallas completas. Continúa el resto del alcance funcional, visual y de animaciones de Desktop. No hay una IPA nueva ni una aprobación global del port.
