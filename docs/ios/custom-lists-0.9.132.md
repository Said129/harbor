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
