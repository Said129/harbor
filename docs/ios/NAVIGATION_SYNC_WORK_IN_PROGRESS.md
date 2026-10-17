# Navegación y sincronización — integración en curso

Esta integración forma parte del port completo de Desktop **0.9.132**. No genera otra IPA ni completa el port. La fuente `c70ba2dab84b6e8fd37b37abef097cfcc4933dd4` compiló y superó 27 ejecuciones afectadas en la [validación Apple 39049307894](https://github.com/Said129/harbor/actions/runs/39049307894), sin avisos nuevos.

## Comportamiento

La navegación se guarda por propietario de Stremio y por cuenta/perfil Harbor. Los perfiles vinculados comparten sus preferencias locales, mientras que las revisiones y los cambios pendientes se guardan por documento de servidor. Al actualizar una instalación, la configuración global anterior se conserva y se migra al primer propietario que se recupere correctamente. Un error de lectura no se interpreta como una configuración vacía.

El cliente utiliza el documento Desktop `<syncId>:nav`, con `order`, `hidden` y `renamed`. Conserva los identificadores que iOS no muestra —incluido Games— y los campos futuros del documento. Buscar sigue siendo una opción móvil local. La navegación predeterminada sigue el orden de la referencia para las secciones presentes.

La primera lectura adopta la configuración del servidor y no sube valores predeterminados. Los cambios explícitos del usuario se envían con `baseRev`; la revisión del servidor decide el orden. Si otro dispositivo gana un conflicto, se adopta su versión y se conserva la local para «Restaurar mi versión». Ese botón restaura las opciones móviles sobre los campos actuales del servidor, sin sobrescribir configuraciones exclusivas de Desktop. No se mezclan automáticamente dos órdenes de navegación.

Una edición recibida durante una petición conserva su versión pendiente y usa la revisión recién aceptada en el siguiente envío. Las respuestas tardías de otra cuenta se descartan. Los borradores de los campos de nombre también quedan ligados a su cuenta: perder el foco durante un cambio de propietario no puede escribir un nombre anterior en el nuevo.

El acceso de red reutiliza la autenticación y la renovación de tokens existentes en `HarborProfileSync`. No cambia el formato de la sesión almacenada. La cola y las versiones guardadas utilizan claves separadas del llavero y se conservan al cerrar sesión.

## Referencia comprobada

- `src/chrome/nav-items.tsx`: orden e identificadores y forma de `NavCustomization`.
- `src/lib/layout-sync/sections.ts` y `store.ts`: sección `nav`, preferencias vinculadas y lectura nula antes de estar preparados.
- `src/lib/profile-sync/types.ts`, `sections.ts`, `engine.ts`, `limits.ts` y `parked.ts`: claves por perfil, revisión del servidor, límite de 96 KiB y copia local de los conflictos de secciones reemplazadas completas.

Se conserva la referencia `0834340cec5531650bfe78cd628628702e636987`. Las secciones `settings`, `theme` y `playerlayout` de esa referencia pertenecen a su configuración TV: esta integración no escribe preferencias generales ni credenciales en esos documentos.

## Evidencia y validación pendiente

Dieciocho métodos nuevos comprobaron migración, cuentas y perfiles vinculados, errores de almacenamiento, mensajes tardíos, documentos inválidos, campos desconocidos, revisión del servidor, conflictos, restauración explícita, edición durante una petición y recuperación tras reiniciar. Dos recorridos nuevos de interfaz editaron, ocultaron, movieron y recuperaron la navegación al relanzar la app en iPhone/iPad, con seis capturas. Los otros siete casos ejecutados cubrieron las imágenes corregidas y los recorridos de sistema e idiomas pendientes.

Se inspeccionaron las 26 capturas de esa ejecución. Los controles de navegación, el nombre guardado y los elementos ocultos se ven correctamente en ambos tamaños. La revisión también detectó títulos de sistema demasiado grandes y un nombre de invitado sin traducir: esas cuatro pruebas de interfaz vuelven a ejecutarse tras corregir los elementos que renderizan. Se conservan los otros 23 casos de esta ejecución. El paquete de evidencia contiene 6.848.628 bytes, SHA-256 `8957a1968b6523b49cda9e3906c71dccced42283e555ab684b36508995fcf254`; no contiene una IPA.

Las pruebas de sincronización inyectan memoria y transporte controlados en los componentes reales. No acceden a cuentas personales ni envían configuraciones a terceros. La comprobación física de dos dispositivos y el resto de las secciones sincronizables siguen pendientes. Esta integración tampoco añade todavía la selección de varios perfiles ni sus controles infantiles o PIN.

La ejecución anterior de sistema `39045971697` compiló y ejecutó doce métodos: once aprobados y uno fallido. El fallo mostró que ImageIO puede crear un contenedor para datos que no contienen ninguna imagen. La validación compartida comprueba ahora tipo reconocido, número de imágenes y estado completo, sin decodificar una imagen de tamaño ilimitado. Sus tres casos afectados pasaron en `39049307894`. Se conservan los otros nueve métodos aprobados y las tres capturas reales del vector Home de la ejecución anterior, cuyo resultado global sigue registrado como fallido. La comprobación nativa de idiomas aprobada en `39028548982` tampoco se repitió.
