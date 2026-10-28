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
