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

Este incremento todavía no ofrece la sección al usuario. Faltan conectar la
pestaña y sus tarjetas, creación/edición/eliminación, selección de pertenencia,
búsqueda de títulos, reordenación táctil y accesible, apertura de manga conservando
su proveedor, filas de Inicio, traducciones y respaldo compatibles. También falta
comparar los estados y animaciones con la referencia en iPhone/iPad. La entrada
tipada desde `Media` no conserva todavía `addonOrigin`, porque ese modelo nativo
no lo expone: se debe integrar el origen completo antes de dar la función por
terminada. Los datos crudos y los vídeos ya tienen el contrato de persistencia.

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
interfaz de Mis listas sigue pendiente y no se genera otra IPA.
