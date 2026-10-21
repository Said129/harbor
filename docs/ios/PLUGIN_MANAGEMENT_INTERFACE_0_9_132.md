# Administración nativa de plugins — implementación pendiente de Apple

La referencia es `0834340cec5531650bfe78cd628628702e636987`, especialmente `plugins-panel.tsx`, `plugin-settings-modal.tsx`, `installed-tab.tsx`, `repositories-tab.tsx` y `manga/plugins/store-factory.ts`. Este bloque añade código a la única entrega final del port completo; no crea una IPA intermedia.

## Pantallas y acciones conectadas

Configuración abre Plugins con las pestañas de instalados y repositorios. Las acciones utilizan el gestor real: añadir varios enlaces, actualizar un manifiesto conservando sus últimos datos válidos, instalar una entrada, activar/desactivar, actualizar el código, revertir una versión y eliminar plugins o repositorios. La eliminación pide confirmación adaptada a la interacción táctil. La búsqueda filtra los registros cargados. Los botones quedan bloqueados mientras se confirma una operación y los errores visibles no incluyen URL, cabeceras ni credenciales.

El editor consulta el método real `settings`, conserva el orden de cabeceras e información y muestra texto, contraseñas, selectores e interruptores. Los valores por defecto siguen `defaultsOf` de la referencia, incluidos el primer valor de un selector y los ajustes antiguos desconocidos. Las contraseñas no declaradas por la versión actual del formulario conservan su condición secreta al guardar. Una actualización, eliminación o configuración confirmada después de abrir el formulario impide sobrescribirla con ese borrador antiguo. Cerrar o guardar limpia el borrador; un fallo conserva la edición para poder corregirla o cancelarla.

Las tarjetas usan los colores y controles existentes de Harbor, campos de 44 puntos o mayores y contenido acotado con desplazamiento. Los grupos de acciones se apilan cuando no caben. Se conserva Reducir movimiento. Los iconos instalados se leen únicamente de datos ya descargados y se generan miniaturas de tamaño acotado; una URL de icono no inicia una descarga de imagen fuera del transporte aprobado.

## Instalación local y activaciones

La revisión del código original confirma que `createPluginStore("harbor-stream-plugins")` abre un IndexedDB de la instalación. No recibe un identificador de perfil ni es un documento de sincronización de preferencias. La sesión nativa conserva esa semántica con un catálogo local del dispositivo. No envía los plugins ni sus contraseñas al servicio de perfiles. Esto concreta el enlace que antes figuraba como pendiente: no se convierte el catálogo local de Desktop en un catálogo distinto por perfil.

Cada activación recibe un gestor nuevo con su propietario y UUID actuales. Cambiar la cuenta, bloquear el contexto o retirar la disponibilidad del almacenamiento cancela y desecha el gestor anterior desde la raíz de la app. Reabrir Configuración reutiliza el gestor listo en la misma activación y no repite la lectura ni crea otro escritor del mismo catálogo. El inicio de la app no espera la carga de plugins: se abre cuando hace falta.

## Evidencia y límites

Tres casos nativos nuevos comprueban campos y valores reales del worker, guardado con referencias de Keychain y conservación de secretos que el formulario no declara, rechazo de un borrador anterior a una configuración nueva, y persistencia local entre activaciones con desecho del gestor anterior. Una preparación independiente instala exclusivamente datos propios en un simulador sin cuentas configuradas. Los dos recorridos nuevos de iPhone/iPad comprueban el editor, persistencia tras relanzar, repositorios y eliminación, y conservan cinco capturas por dispositivo. Estas ejecuciones y su inspección visual todavía están pendientes.

Las traducciones nuevas proceden de los catálogos fijados de Desktop, con dos mensajes móviles traducidos a los 16 idiomas. Cada clave y valor anterior se conserva; las aprobaciones anteriores de idiomas no se convierten en evidencia de estas nuevas pantallas.

La validación `39580297724` usa la fuente anterior `354b883b87b657611238d6fd3ef44fa3b20597e1`: once casos nuevos del gestor/normalizador y cuatro afectados por la entrega asíncrona a WebKit. No contiene estas pantallas ni sus tres casos nuevos. Hay que recoger sus resultados reales antes de elegir la siguiente validación, conservando los éxitos y seleccionando únicamente fallos, cambios afectados o casos no ejecutados.

Siguen pendientes la sala completa de Plugins con sus catálogos y organización, las opciones globales, el pool, salud y registros, pausa automática, reintento persistente de limpieza, productores de streams/subtítulos, adaptadores de manga/ebook y proveedores reales. El resto del alcance funcional, visual y de animaciones de Desktop permanece activo.
