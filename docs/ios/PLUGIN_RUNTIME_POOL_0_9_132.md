# Pool y salud de plugins — implementación pendiente de Apple

La referencia es Harbor Desktop 0.9.132, `0834340cec5531650bfe78cd628628702e636987`: `streams/plugins/runtime.ts`, `gate.ts` y `source.ts`. El código de este bloque todavía necesita ejecución Apple. No completa el port ni genera una IPA intermedia.

El pool conserva el worker WebKit real mientras coincidan código, formato, identidad y configuración. Una configuración o instalación nueva invalida el worker anterior y cancela sus operaciones. El límite global de ocho operaciones es independiente del límite anterior de peticiones HTTP del bridge. La espera es cancelable y no retiene un permiso cuando se retira un llamador de la cola.

Se conservan como máximo cuatro workers inactivos y se retiran los que superen cinco minutos sin uso. Un barrido cada minuto se detiene cuando no queda ninguno. Al entrar en segundo plano se liberan los inactivos; los que tienen una operación activa no se desechan por ese barrido. Cambiar la activación cancela las tareas, retira todos los workers y limpia la salud y los registros de esa sesión.

Cada ejecución registra hora, duración, cantidad de respuestas, título, error y peticiones HTTP, con un máximo de cuarenta hosts observados y doscientas líneas de seiscientos caracteres. Las contraseñas conocidas se ocultan antes de limitar el texto de un registro. Una cancelación o respuesta retirada no incrementa fallos ni publica salud de otra activación. Los errores del pool no incluyen URL ni credenciales del transporte.

Los fallos reales actualizan de forma atómica el catálogo y pausan el plugin al tercero. Una comprobación explícita puede volver a preguntarle; una respuesta válida elimina la pausa y reinicia la cuenta. El resultado de una instalación/configuración anterior no puede modificar la cuenta de la actual. Un fallo de persistencia queda señalado; no se convierte en una respuesta ficticia del proveedor.

Seis casos nativos nuevos usan workers reales para comprobar reutilización y sustitución por configuración, presupuesto/expiración sin retirar un trabajo activo, pausa persistida y recuperación, cancelación/retirada de propietario y registros acotados con contraseñas largas. El caso del gate comprueba ocho trabajos admitidos y cancelación de un noveno en espera sin perder capacidad. La red y el almacén de secretos de estas comprobaciones son propios; no demuestran un proveedor público instalado ni miden rendimiento físico.

## Selección conjunta y fallo anterior

`39580297724`, fuente `354b883b87b657611238d6fd3ef44fa3b20597e1`, compiló la app sin advertencias nuevas. El cambio a `await evaluateJavaScript` eliminó la advertencia anterior en esa compilación. Las pruebas no empezaron: el control de la matriz de shell todavía exigía once identificadores, aunque el selector generaba quince. El fallo se corrige, se conserva su registro original y no se cuenta ninguna prueba aprobada de esa ejecución. La subida de evidencia de aquel job también informó de un fallo de conexión con GitHub.

La siguiente selección conjunta contiene veinticuatro casos de modelo: los once nuevos todavía no ejecutados de gestor/normalizador, los tres del formulario, estos seis y los cuatro recorridos afectados de entrega. Añade una preparación ordinaria y un recorrido de interfaz en cada dispositivo nuevo: veintiocho ejecuciones previstas, diez capturas y dos grabaciones. El shell real de selección se ejecuta localmente con un sustituto que únicamente registra los argumentos de Xcode; esa comprobación verifica la matriz, no ejecuta pruebas nativas. Se conservan las pruebas aprobadas de áreas intactas, incluidos transporte, consulta pública y Rust.

Siguen pendientes los productores y adaptadores de fuentes/subtítulos, la presentación de salud/registros y comprobación manual, las opciones globales compatibles, el reintento persistente de limpieza de secretos y los plugins de lectura. Las ejecuciones nuevas, capturas y revisión del movimiento siguen pendientes. Los catálogos de la sala Plugins dependientes de Android quedan documentados por separado en `PLUGIN_PARITY_0_9_132.md`; los plugins interpretados y sus interfaces compatibles permanecen incluidos.
