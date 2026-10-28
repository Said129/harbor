# Origen de entradas guardadas

La referencia es Harbor Desktop 0.9.132, revisión
0834340cec5531650bfe78cd628628702e636987. Eliminar la sesión de Stremio no elimina
el protocolo HTTP de addons ni las credenciales propias de cada proveedor.

La ficha intenta primero la dirección guardada y después las instancias
configuradas del mismo addon, sin consultar otros proveedores en esa fase.
Conserva el origen al recuperar metadatos desde Anime/Cinemeta. La información
canónica mantiene su enriquecimiento TMDB; si ese enriquecimiento falla, una ficha
válida del proveedor sigue disponible. Las peticiones ya fallidas no se repiten
inmediatamente en la misma carga.

La clave privada de caché incluye el origen completo además del propietario,
addons y configuración. Dos entradas con el mismo ID y diferentes instancias de
un proveedor no reutilizan por error la misma ficha. Las direcciones y claves
solo forman parte del digest y no se guardan en texto en dicha caché.

Las peticiones de fuentes conservan los demás proveedores. Una entrada propia
puede consultar el addon guardado aunque su manifiesto no declare ese ID y
recuperar otro tipo declarado cuando la consulta primaria está vacía. Las
alternativas respetan los prefijos de cada recurso y se prueban en orden; una
respuesta válida detiene los reintentos. El motor nativo recibe la misma
preferencia de origen que Desktop: 250 puntos adicionales, sin eliminar fuentes.

Para episodios se conserva su ID real del proveedor. Desktop fuerza el ID de la
ficha en ese recorrido; iOS conserva el ID seleccionado del episodio y las otras
peticiones canónicas para evitar consultar la serie entera o convertir una etiqueta
de presentación, como episodio 99, en sus coordenadas reales T5 E23. Las URLs
con parámetros conservan su consulta separada de la ruta, y los identificadores
se codifican como segmentos.

Un plugin JavaScript nativo instalado y ejecutable puede responder a su propia
entrada sin consultar los demás plugins. La agrupación por repositorio conserva
su grupo y la pausa general prevalece. Un proveedor desactivado o ausente no
inhabilita los demás. Las extensiones Android siguen excluidas: este trabajo no
convierte su bytecode en código ejecutable de iOS.

Siete pruebas nuevas contrastan cinco archivos originales ejecutados, metadatos
ordenados, cancelación, aislamiento de caché, alternativas de tipo, episodio real,
ranking del motor y selección de plugins. Se selecciona también un único caso
anterior afectado que atraviesa la mezcla real de plugins, adaptador y ranking.
Son pruebas pendientes de ejecución Apple hasta recibir el resultado de esta
fuente.

La revisión de las ocho capturas originales de Mis listas encontró además texto
español en la ficha inglesa y «actualizado dentro de 0 s». Se conserva la prueba
funcional aprobada y se añaden solo dos recorridos UI centrados en esos estados,
uno por tamaño. La ausencia de metadatos sigue siendo visible, traducida en los
dieciséis idiomas; no se oculta un fallo real.

No se considera completa la equivalencia global ni se produce una IPA por este
incremento. Continúan pendientes las filas de listas en Inicio, su selector de
personalización, portadas privadas de Manga y los demás bloques del inventario.

## Resultados reales y reparación seleccionada, 28 de octubre de 2026

La ejecución ARM `40727046556` no recibió máquina en ninguno de sus dos
intentos: cero pruebas ejecutadas. GitHub indicó falta de capacidad ARM. Se
conservan sus anotaciones y se envió la misma fuente y selección, una sola vez,
a Intel con un recibo independiente.

La ejecución Intel `40740807507`, fuente exacta `baf87971970e0109a15328a64a637f5c7fc9e64e`,
compiló y ejecutó doce casos: diez aprobados y dos fallidos, sin nuevas
advertencias. El cotejo de tipos encontró que Desktop conserva tipos repetidos
en la declaración genérica. La reparación conserva esa declaración original y
suprime URLs duplicadas al planificar las peticiones; no repite llamadas idénticas.
Se repiten solo la comparación fallida y el caso de planificación afectado.

El recorrido inglés del iPhone aprobó «Updated now», el botón de guardar y el
mensaje de metadatos. Sus dos imágenes originales se revisaron individualmente.
El iPad falló antes de entrar en Biblioteca: la grabación muestra el menú y el
destino visibles, mientras XCTest no encontró un marco válido para desplazar su
contenedor. La reparación limita la consulta al ScrollView real y espera el
destino dentro del marco de la aplicación, conservando todas las aserciones.
Se repite únicamente ese recorrido y su preparación necesaria.

Archivo autenticado: 12.802.292 bytes, SHA-256
`0e3d85b40841c09e5291a5d115813cc5db6c86a0080183b8b8f06ada7261ad51`,
igual al digest de GitHub. Los fotogramas diagnósticos del iPad guardan el hash
de la grabación de origen. Las filas de listas y portadas privadas se
implementaron después en `28386ee0`; sus resultados parciales y hallazgos
figuran en `home-lists-0.9.132.md`. El objetivo completo permanece abierto.

La reparación `40773669603`, fuente exacta
`415ed880ca6228d0ad5c8588936088471f50dce3`, aprobó seis de seis ejecuciones,
sin omisiones, fallos ni nuevas advertencias. Aprobaron la comparación con los
tipos originales, la supresión de peticiones repetidas y el recorrido pendiente
del iPad, junto con los dos casos de restablecimiento y su preparación necesaria.
Las dos imágenes originales del iPad se revisaron individualmente: «Updated now»,
guardado y mensaje de metadatos en inglés, con el diseño ajustado a la ventana.
La portada genérica de esa ficha pertenece al caso de prueba sin artwork.
Se conservaron los otros resultados nativos y el recorrido aprobado del iPhone.
La procedencia del archivo y sus hashes figuran también en
`home-lists-0.9.132.md`. No se produjo una IPA.
