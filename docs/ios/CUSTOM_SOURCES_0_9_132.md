# Filas de fuentes personalizadas de Desktop

La referencia es Harbor Desktop 0.9.132 Beta, commit
`0834340cec5531650bfe78cd628628702e636987`. Esta integración añade las filas
`customSources` del inicio, con carpetas horizontales y de póster, importación
por URL o JSON, edición de portada y GIF, nombre, orden, ocultación y borrado.
El selector de Archivos de iOS permite también importar un JSON local.

Las carpetas resuelven los catálogos del addon instalado que identifica el
documento, descubrimiento y colecciones de TMDB o listas públicas de Trakt.
Una carpeta de otro addon no necesita descargar además el manifiesto de
Cinemeta. Los GIF se decodifican fuera del hilo principal al recibir foco o
puntero, con límites de memoria y respeto por Reducir movimiento.

Se conserva el JSON completo al editar: los campos futuros y las identidades
públicas de addon y catálogo sobreviven. Las direcciones privadas de transporte
de la cuenta no se incorporan a la fila. Las ediciones de fuentes se guardan
atómicamente con la procedencia del perfil; las colas de sincronización guardan
también la proyección original cuando una edición no cambia las preferencias
tipadas. Los conflictos conservan una copia recuperable de la sección completa.

La adopción inicial de una cuenta guarda también las filas importadas como
invitado. Si la cuenta todavía no tiene esa sección, la importación de invitado
se conserva sin subirla automáticamente; una edición explícita posterior ya
pertenece al perfil de la cuenta. Estos dos comportamientos se contrastaron
ejecutando las funciones originales de Desktop. Los controles nuevos incorporan
sus traducciones de referencia: 320 entradas añadidas en 16 idiomas, sin cambiar
ni eliminar traducciones anteriores. Se mantiene el fallback original para
textos que Desktop tampoco traduce.

## Evidencia y límites

Se ejecutaron el parser original de Desktop en 12 ejemplos, su acción de carpeta
en 8 y sus funciones de cola y adopción inicial en 4. Son comprobaciones de la
referencia TypeScript, no ejecuciones de la implementación Swift. Una consulta
anónima real de Trakt devolvió dos elementos públicos. El cliente nativo también
aprobó su consulta real en Apple, sin cargar una sesión de cuenta; ese caso se
conserva sin repetirlo.

La [ejecución 40238599670](https://github.com/Said129/harbor/actions/runs/40238599670)
falló durante la compilación, sin ejecutar pruebas, por una referencia fuera de
alcance a `addonID`. La corrección restablece exactamente la función previamente
aprobada y coloca la selección de manifiesto en el método nuevo correspondiente.
El archivo original del diagnóstico tiene SHA256
`b9c1e80e374affc1bda806fc9223fceea09ca284a8e3613ff3907f860cbb27d7`.

La [validación de la corrección](https://github.com/Said129/harbor/actions/runs/40239615319)
congela `dedbd9e9111f2980d1bf1a81275e44b3f18fbce7`: 30 casos nativos,
dos preparaciones limpias y dos recorridos nuevos de iPhone/iPad, con 12 capturas
requeridas. Aprobaron 29 casos nativos y las dos preparaciones, sin advertencias
nuevas. El caso nativo restante comparaba dos codificaciones JSON con distinto
orden de claves; la corrección compara los bytes que escribió la propia prueba.
Ambos recorridos de interfaz se detuvieron al buscar «Seleccionar todo» en el
campo vacío de URL, antes de producir sus capturas requeridas. Ahora esos campos
vacíos reciben texto normalmente. El archivo original de evidencia tiene SHA256
`b80fd94fa01c01703e92fa6e90d36df01ffc242511892dfc5e6ccaac90a5f26a`.

La revisión de equivalencia de esta zona incluye aún la validación de los diálogos,
las opciones de tarjetas póster/TV y sus ajustes y los destinos no audiovisuales. Tampoco certifica
cuentas personales reales, el comportamiento en un dispositivo físico ni el port
completo. Esta validación no produce una IPA. El
[registro estructurado](custom-sources-parity.json) mantiene los hashes y el
alcance exacto.

## Interfaz adicional pendiente de Apple

La revisión posterior añade avisos temáticos al tocar una carpeta sin la clave
de TMDB o sin el addon requerido; cerrarlos conserva el inicio. Las tarjetas usan
los bordes y colores del tema y activan el GIF también al mantener pulsado. El
decodificador evita guardar en caché los fotogramas originales de tamaño completo.
El importador distingue el error al descargar un documento y su formato inválido,
sin mostrar direcciones privadas en el mensaje.

La cuadrícula cuenta los resultados originales del proveedor, sigue tras una
página de duplicados y respeta el límite de cuarenta páginas de Desktop. El
indicador de carga permanece montado durante la petición y conserva el cursor
al volver de una ficha. Cinco casos ejecutados sobre la función original de
Desktop confirman el comportamiento de paginación; no son ejecuciones de Swift.

Esta revisión todavía no está incluida en la ejecución anterior. La selección
añade cuatro casos nativos nuevos —dos de requisitos y dos de paginación—,
repite el único caso afectado del GIF y corrige el caso fallido de lectura de
archivo: seis casos nativos en total. Conserva los otros veintiocho aprobados.
Las dos preparaciones y dos recorridos de interfaz suman diez ejecuciones, con
veinticuatro capturas requeridas de iPhone/iPad, incluidas las hojas de importación
y edición de imágenes. El servidor controlado devuelve errores 404, JSON inválido,
una página duplicada y después el quinto título; las portadas original y editada
son imágenes propias diferentes. Estos resultados Apple siguen pendientes.
