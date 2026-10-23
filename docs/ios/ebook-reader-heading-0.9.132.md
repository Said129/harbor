# Presentación del lector de Desktop 0.9.132

El lector continuo incorpora la hoja, sus colores y sombra, la cabecera
«Harbor Reader», el título del capítulo y la portada interior que muestra
`harbor-reader.tsx` en la referencia 0.9.132. La cabecera utiliza la fuente y
dirección de lectura seleccionadas. El brillo se aplica a los colores del papel
y la tinta con el mismo cálculo que el lector impreso. La navegación y el pie
también respetan el papel claro para conservar el contraste de sus controles.
Los estilos Literario y Clásico utilizan Georgia y Palatino, como la referencia
y las páginas impresas, en lugar de alternar con la fuente de sistema al resaltar.

La portada corresponde al primer capítulo del orden visible, en ambos modos.
El índice original del proveedor sigue identificando el capítulo y el progreso:
una fuente que entregue los capítulos desordenados conserva sus rutas. Las
portadas locales se leen del documento y no se sustituye una portada ausente por
una imagen genérica dentro del lector. Las fuentes remotas conservan su política
de acceso. La cabecera queda fuera de los destinos de párrafos, sin cambiar sus
identificadores de búsqueda, marcadores, notas o narración.

El modo de concentración también retira la barra principal de Harbor mientras
se ocultan los controles; la recupera al interactuar o salir del lector.
El panel de voces mantiene el buscador visible en iPad y libera el teclado al
seleccionar una voz o cambiar la altura disponible. Las capturas de giro esperan
a que exista la ventana horizontal y se retire el teclado. Los gestos de las
pruebas recorren únicamente la parte visible de la lista, evitando el teclado y
el pie del panel.

La validación selecciona dos recorridos nuevos de portada y cabecera, cuatro rutas
fallidas y dos rutas aprobadas cuya presentación ha cambiado. Conserva las notas
aprobadas y todos los contratos nativos de áreas intactas. Un EPUB de prueba
propio incluye dos capítulos y una portada geométrica reconocible, sin cuentas
ni descargas externas. La compilación Apple y la revisión de las 46 capturas
esperadas siguen pendientes. No genera una IPA ni completa el port por sí solo.
