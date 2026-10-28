# Historial combinado y vista de episodios

Referencia fija: Desktop 0.9.132, commit
`0834340cec5531650bfe78cd628628702e636987`. Este incremento sigue pendiente de
compilación, ejecución y revisión visual en Apple; no certifica el port completo.

La pestaña Historial de Biblioteca utiliza ahora su proyección propia. Incluye
títulos empezados y vistos, conserva los registros temporales y excluye las
entradas retiradas. Combina los registros locales de Harbor con el historial de
Trakt; el título local tiene prioridad y las entradas remotas repetidas se
reducen a la primera por IMDb, como en `history-merge.ts`. La consulta de esta
pestaña usa 200 entradas y no depende de que responda la lista de guardados. La
lectura global de marcas sigue usando su consulta independiente de 1.000.

El filtro por tipo, búsqueda, orden, agrupación y cambio entre pósteres y tarjetas
de episodios se mantienen en la interfaz móvil. Las tarjetas horizontales
incluyen el progreso, tiempo restante, marca de visto, fecha y, cuando existe,
la imagen y el nombre del episodio. La fecha usada para agrupar y ordenar es la
de modificación; la fecha mostrada en la tarjeta puede ser la última reproducción.
Las tarjetas remotas sin coordenadas conservan el comportamiento de la referencia
y abren el título.

El modo elegido se guarda con las preferencias del propietario de Biblioteca.
Los datos anteriores, que no contienen `historyView`, abren en modo pósteres.
No se añade una sesión Stremio. La retirada requiere confirmación y conserva los
campos desconocidos y el progreso del registro, cambiando `removed` y `temp` como
la función de referencia. No borra el historial Trakt ni los datos de otro perfil.

Abrir una tarjeta de episodio proporciona una pista a Detalle para seleccionar
su temporada. La pista se conserva cuando los metadatos llegan después de abrir
la pantalla y admite temporada cero. La coincidencia del episodio mantiene su
identidad de origen en las secciones que reúnen varias entradas de anime.

Se portan la entrada de 440 ms con desplazamiento de 10 puntos y curva
`cubic-bezier(0.16, 1, 0.3, 1)`, la carga de dos grupos de 14 y 8 pósteres, el
escalonado de 35 ms y el barrido de 1,5 segundos. «Reducir movimiento» desactiva
esas animaciones; el barrido también se detiene fuera de la escena activa.
Las traducciones añaden solo diez rótulos que faltaban entre los 21 utilizados
en los 16 idiomas fijados de Desktop; se conservan los demás textos existentes.

El generador ejecuta `history-merge.ts`, las funciones de `shared.tsx` y los
cuerpos originales de `libraryMetaType` y `episodeFromVideoId`, extraídos por AST
de `stremio.ts`. No se afirma ejecutar todo Stremio ni renderizar React. Ocho
escenarios comparan filtro, combinación, prioridad local, fechas, progreso,
numeración de anime y especiales, identificadores ausentes y límites de visto.
Se conservan entradas, salidas y hashes, además del CSS original de las animaciones.

Seis casos nativos nuevos comprueban esos resultados, la consulta independiente,
la persistencia y retirada real, compatibilidad de preferencias, separación de
fechas y cancelación por cambio de perfil. Un montaje de componentes prepara
cuatro capturas con imágenes propias decodificadas en los dos tamaños. Dos
recorridos nuevos de la app normal, con preparación de datos locales sin
credenciales, verifican cambio de modo, búsqueda, confirmación, retirada y
reinicio. Estos recorridos usan títulos sintéticos sin portadas; no certifican
arte de proveedores. Las imágenes del montaje cubren ese aspecto por separado.

El intento inicial 40617349724,
en `a5c1bb0f`, falló al compilar: el `error` implícito del `catch` ocultaba la
propiedad del modelo. La asignación usa ahora `self.error`. El archivo de
diagnósticos original, de 30.924 bytes, conserva SHA-256
`abf0b00b34011cc96309c22a9e17d5e9f651d3beb1a83ec5a03ec2552809c15f`,
igual al digest de GitHub. No se atribuye ninguna ejecución a ese intento.
La validación anterior de
listas y marcas Trakt terminó con 27 de 28 aprobaciones: 24 casos nativos, dos
preparaciones y el recorrido del iPad aprobaron. Se conserva su evidencia. El
recorrido del iPhone falló al consultar `isHittable` en una pestaña fuera del área
visible. La reparación revela el marco completo antes de activarla y conserva
la comprobación de selección tras el toque real.

La selección inicial de seguimiento contenía ocho casos nativos sin ejecutar y un montaje afectado:
la captura Trakt compacta anterior tenía una portada aún en carga, por lo que
ahora debe esperar las cuatro. Hay tres preparaciones y tres recorridos: dos
nuevos de Historial y solo el recorrido anterior fallido del iPhone. Total:
15 ejecuciones y 19 capturas originales previstas. Se conservan las otras
23 aprobaciones nativas y la del recorrido anterior del iPad. Permanecen
pendientes las demás secciones, servicios, interfaces, animaciones y validaciones
físicas del objetivo general, y una sola IPA final.

La revisión de los originales en inglés detectó encabezados, pestañas, filtros y
vacíos de Biblioteca aún escritos en español. Ahora usan claves canónicas del
Desktop fijado; se actualizan solo 40 rótulos en los 16 idiomas. La instrucción
para añadir títulos utiliza una pulsación móvil en lugar del clic derecho de
Desktop. Las vistas observan el idioma del entorno sin reconstruirse ni perder
la búsqueda o el modo elegido; el traductor admite identificadores regionales
como `en_US` y conserva el comportamiento por defecto de los demás consumidores.
Un nuevo caso compara 20 claves por idioma contra catálogos originales extraídos,
la instrucción móvil y la interpolación de temporadas y episodios. Los recorridos
de Historial exigen también el encabezado y la pestaña en inglés, y el montaje
de Historial captura expresamente ese idioma. Sigue pendiente su ejecución Apple;
esta revisión no certifica la traducción completa de todas las pantallas.

## Adaptación al historial independiente y rótulos de episodios

La retirada solicitada de las sesiones Stremio requiere que las marcas manuales
locales también sean visibles en Historial. Un título nuevo se guardaba como
retirado y no temporal: aunque su decisión de visto persistía, el filtro de
Historial lo descartaba. Al marcarlo pasa a ser temporal si está retirado, sin
añadirlo automáticamente a Mi lista. El filtro acepta las decisiones nativas
booleanas positivas de película o episodio. Desmarcarlas sin progreso ni otra
actividad retira esa entrada del historial; quitarla expresamente conserva sus
decisiones y su progreso, como las demás entradas. Los campos del protocolo no
se reinterpretan ni se añaden cuentas remotas.

Tres casos nuevos ejercitan el marcado individual, su retirada, el marcado de
película y serie completa, reapertura y separación de propietario, con cero
peticiones a cuentas. También conservan los ocho escenarios del filtro original
y rechazan cadenas o números usados como decisiones booleanas. La ampliación es
la adaptación local a la excepción de cuentas del propietario; no se atribuye al
filtro original de Desktop, que requería su sesión para obtener la colección.

El rótulo visible de episodio de Historial usa ahora `S{season} E{episode}` del
catálogo elegido, en lugar de una «T» fija. El mismo rótulo se comunica como valor
de accesibilidad de la tarjeta. Dos recorridos nuevos, aún pendientes de Apple,
exigen `S5 E23` en la app normal en inglés y capturan ese estado en iPhone/iPad.

La selección `independent-history` reúne esos tres casos nativos, el montaje del
componente afectado por el rótulo, dos preparaciones y los dos recorridos nuevos:
ocho ejecuciones y seis capturas previstas. Conserva los cinco casos de marcado
ya aprobados en 40675700785 y no reinicia la validación anterior de Historial.

## Resultado Apple y reparación de los recorridos pendientes

La [ejecución 40674798409](https://github.com/Said129/harbor/actions/runs/40674798409),
fuente `079a5da425564110ffed6380f8aee889362b919b`, aprobó los nueve casos nativos:
seis de Historial, dos montajes y el cotejo de los 16 idiomas. No hubo omitidos ni
advertencias nuevas. Las tres preparaciones y los tres recorridos no llegaron a
ejecutarse: el script de interfaz tenía una lista cerrada de cantidades de imágenes
que no admitía 19. La reparación comprueba la igualdad entre cantidad declarada,
capturas requeridas y nombres únicos. El código real de esa comprobación se
ejecutó localmente con cuatro cantidades válidas, incluida 19, y cuatro planes
inválidos; no se presenta esa comprobación local como una ejecución en iOS.

Se descargaron y revisaron individualmente las diez imágenes nativas originales.
El archivo de 597.135 bytes tiene SHA-256
`8ab909c56c4767eb8d3fb9fcfddace0f7cd50231b15562c23088c91b7eaf7460`, igual al
digest de GitHub. Las cuatro portadas Trakt ya están decodificadas en ambos tamaños.
Quedaban una «T» fija en las tarjetas de episodio, una diferencia de alineación
vertical entre películas y episodios y un encabezado de transferencia que usaba
el idioma de preferencias mientras su contenido usaba el del entorno.

El rótulo ya usa el catálogo; la cuadrícula alinea las tarjetas arriba y el
encabezado de transferencia recibe el mismo idioma que su contenido. El parámetro
opcional de sección conserva el comportamiento anterior para sus demás usos.
Estas reparaciones visuales todavía necesitan nuevas capturas.

La selección `library-history-interface` conserva siete aprobaciones nativas
intactas y repite únicamente los dos montajes cuyo aspecto cambió. Añade las tres
preparaciones y los tres recorridos sin ejecutar: ocho ejecuciones y 19 imágenes
previstas, sin IPA. Los tres modelos de historial independiente y los dos nuevos
recorridos específicos de rótulos siguen en su validación separada.

La [ejecución independiente 40677771264](https://github.com/Said129/harbor/actions/runs/40677771264),
fuente `e028a83ea104b8d9ebf59f5822704ecf6a98c0a4`, aprobó sus ocho ejecuciones:
tres modelos nuevos de historial local, un montaje afectado, dos preparaciones
y los dos recorridos de rótulos. No hubo omitidos ni advertencias nuevas. Se
revisaron individualmente las seis imágenes originales: el encabezado, las
pestañas y el rótulo `S5 E23` se ven en inglés en la app normal en ambos tamaños.
Los títulos sintéticos usan imágenes genéricas por diseño; el montaje muestra
sus imágenes propias decodificadas. El archivo de 28.897.890 bytes tiene SHA-256
`b0d251069a8bd0ceb95a48d82f69a2738edd8e20edb43b4c32ff4e7a2bc9b981`, igual al
digest de GitHub. La alineación superior corregida después, en `8875df1d`, sigue
pendiente de sus nuevas capturas. Se conservan los resultados aprobados y no se
atribuye a esta ejecución una aprobación física, de animación o del port completo.

La ejecución `40678694048`, fuente `8875df1d`, aprobó seis de ocho ejecuciones:
los dos montajes, las tres preparaciones y el recorrido de pestañas del iPhone.
Solo fallaron los dos recorridos completos de Historial al localizar el mensaje
de búsqueda sin coincidencias. Las grabaciones originales muestran la consulta
escrita y el mensaje visible en ambos tamaños; los registros identifican el campo
de texto con el identificador del contenedor. Se retira ese identificador de la
vista contenedora para no propagarlo a los elementos y se espera el botón de
actualización propio de Historial al abrirlo. La reparación necesita ejecución;
no se presenta el fallo como una búsqueda que no filtrase el contenido.

Se conservaron los resultados parciales y 17 imágenes originales. El archivo de
37.478.828 bytes tiene SHA-256
`80bd36fa8a97fad984d8f9faa28316f549bcaf33e4daf023de0d6ee1c5a32fcc`, igual al
digest de GitHub. Faltan las dos capturas posteriores a retirada porque los
recorridos no llegaron a esa parte. La revisión individual completa de estos
17 originales todavía está pendiente; los fotogramas diagnósticos extraídos de
las grabaciones se conservan aparte con su procedencia.
