# Mis listas: núcleo y almacenamiento en curso

Referencia: Harbor Desktop 0.9.132, commit
`0834340cec5531650bfe78cd628628702e636987`, `src/lib/custom-lists.ts` y las
funciones originales `persistableAddonOrigin` y `persistableVideos` de `cinemeta.ts`.

El núcleo nativo incorpora creación, renombrado, descripción, eliminación,
adición, retirada, cambio de identidad y alternancia de títulos; orden de listas
y títulos; máximo de 24 listas y 100 títulos por lista. Conserva el orden estable,
las fechas y los campos de metadatos usados por el original, incluido el origen
del addon. Al persistir vídeos retira sus streams, admite hasta 40 entradas y
mantiene el límite original de 64.000 unidades UTF-16.

El almacén pertenece al propietario de ajustes de Harbor. Los perfiles enlazados
usan su almacén compartido y un perfil independiente sin datos propios lee el
compartido hasta su primera modificación. Las escrituras se realizan fuera del
hilo de interfaz mediante un actor y sustitución atómica, con protección de
archivos hasta el primer desbloqueo. Un fallo de escritura conserva la edición
visible en memoria del propietario y permite reintentar; recargar no la descarta.
Un archivo ilegible impide sobrescribirlo con una colección vacía. No se añade
ninguna cuenta ni petición Stremio ni se inventa un endpoint remoto para listas.

La preparación de metadatos y las modificaciones del documento se ejecutan fuera
del hilo de interfaz. Cada lista guarda sus elementos ya preparados, por lo que
leer sus portadas durante un render no vuelve a serializar los vídeos. Una
recarga mantiene el almacén ocupado y reúne a sus solicitantes; no puede aceptar
una edición que luego sea sustituida por una lectura anterior. Un caso adicional
retiene la lectura real mediante una barrera y comprueba ese orden. Este caso y
la optimización posterior siguen pendientes de ejecución en Apple.

El generador ejecuta el módulo original completo de listas con almacenamiento y
reloj propios, más los dos cuerpos originales de persistencia extraídos por AST.
Ocho escenarios conservan operaciones, resultados, fechas y escrituras: edición,
tipos y metadatos, duplicados, orden parcial, cambio de identidad, ambos límites
y operaciones inválidas. No hay red ni cuentas personales. Cuatro casos nativos
contrastan esos escenarios y ejercitan reapertura, separación de propietarios,
herencia hasta la primera edición, memoria tras un fallo y conservación de bytes
ilegibles. Estos casos aún no se han ejecutado en Apple.

La interfaz ya conecta la pestaña «Mis listas» de Biblioteca con tarjetas de tres
portadas en abanico, creación, nombre y descripción, borrado con confirmación,
orden mediante arrastre y controles accesibles, detalle, retirada de títulos y
pertenencia a listas desde las fichas de vídeo y Manga. El editor conserva los
límites de 60/240 unidades UTF-16 sin cortar caracteres. Los arrastres pertenecen
a una activación de perfil y no se aceptan desde otra.

La búsqueda espera 260 ms, usa la búsqueda múltiple de TMDB y conserva los doce
primeros resultados de películas y doce de series, excluyendo personas y títulos
sin portada. Mantiene los títulos de anime y su alternativa inglesa conforme al
original. Sin clave TMDB explica qué ajuste falta. Una respuesta de una búsqueda
anterior o de otro perfil no puede sustituir los resultados actuales. Los textos
nuevos se generan selectivamente en los dieciséis idiomas, preservando los
rótulos anteriores.

Media ya conserva addonOrigin al leer, guardar y reabrir entradas; los catálogos
y respuestas de metadatos registran el proveedor. El enrutamiento preferido,
la separación de caché por origen y la prioridad de sus fuentes ya están
implementados; su comprobación específica Apple sigue pendiente. El documento
addon-origins-0.9.132.md describe el alcance, los contratos y las excepciones
de plataforma.
Los objetos preparados conservan también el Media analizado para evitar volver
a procesar episodios al dibujar cada tarjeta.

Manga abre la copia local del propietario o comprueba que el detalle remoto
corresponda al título guardado. Si cambió la identidad, busca coincidencias
exactas Unicode, incluyendo los calificadores de color del original, antes de
actualizar la entrada. Las búsquedas entre fuentes tienen cuatro solicitudes
simultáneas como máximo. Las copias locales no inicializan el motor de plugins.
Este recorrido y las portadas de Manga que necesitan rutas privadas o cabeceras
todavía requieren comprobación en Apple.

El nuevo generador de contratos ejecutó cinco módulos originales, cuatro
escenarios de búsqueda y catorce pares de títulos Manga sin red. Tres pruebas
nativas nuevas comparan esos resultados y la reapertura de vídeo con su origen.
Dos recorridos UI nuevos, con preparación en un invitado vacío para cada tamaño,
ejercitan creación, edición, orden, pertenencia, retirada y persistencia. La
ejecución 40691573028 cerró siete de siete pruebas sin nuevas advertencias.
Sus ocho capturas originales se revisaron individualmente: los estados
principales encajan en ambos tamaños; aparecieron un texto de ficha sin traducir
y «actualizado dentro de 0 s». Se conservan los resultados funcionales y se
validan esas correcciones mediante recorridos nuevos y acotados. Esta evidencia
no certifica todavía búsqueda en vivo, arrastre real, apertura o portadas privadas
de Manga.

Siguen pendientes las filas de Inicio, su selector de personalización, la
integración real de respaldo/sincronización, los recorridos completos de Manga y
la comparación visual de estados y animaciones en iPhone/iPad.

El campo `customLists` declarado en el esquema de ajustes Desktop no demuestra
sincronización de este almacén: el módulo original escribe por separado
`harbor.customlists.v1`. No se afirma sincronización entre dispositivos sin
comprobar los recorridos reales de cuenta y respaldo. Tampoco se atribuye este
trabajo a las listas de música, que utilizan otro modelo. No hay IPA nueva ni
aprobación de equivalencia completa de Mis listas.

El primer intento Apple `40682261066`, fuente `4c8e563a`, no ejecutó modelos:
la compilación encontró tres asignaciones a `error` dentro de bloques `catch`
que ocultaban la propiedad del almacén. Las tres usan ahora `self.error`.
El archivo original de diagnósticos mide 32.922 bytes y su SHA-256
`5c0ac1285f67c293ded64188455fbb31b4863c03b8416c86e7c233e590cf2b22` coincide
con el digest de GitHub. Se solicitó detener `40684549235` porque su fuente
contenía exactamente ese error conocido; no se reinicia por una espera vencida.

La selección `custom-lists-repair` reúne los cuatro contratos sin ejecutar, el
nuevo caso de concurrencia y solo los dos recorridos de Historial que fallaron,
con sus dos preparaciones necesarias: nueve ejecuciones y seis capturas previstas.
No vuelve a ejecutar los montajes ni el recorrido de pestañas aprobados. La
interfaz nueva de Mis listas pertenece a cambios posteriores a esa fuente y no
queda validada por dicha ejecución. No se genera otra IPA.
