# Marcas Trakt y decisiones manuales

Referencia fija: Desktop 0.9.132, commit
`0834340cec5531650bfe78cd628628702e636987`. Implementación pendiente de ejecución
en Apple; no certifica la entrega final del port.

La app consulta `/sync/history?limit=1000` para las marcas globales. La pestaña de
historial mantiene su consulta independiente de 200 títulos. La caché global
separa propietario y conexión, no contiene credenciales, utiliza protección de
archivos y deja de aportar marcas después de 24 horas. Se restaura antes de la
red y conserva la respuesta anterior cuando el proveedor falla. Una respuesta
de otro perfil o conexión no puede publicarse. Una lectura anterior tampoco
puede sobrescribir una escritura confirmada posterior.

LibraryModel consulta esas marcas en los episodios que usan Detalle,
PlayerEpisodesView, el orden de reproducción y los grupos de anime. Cada episodio
mantiene su identidad original para guardar el progreso, y consulta Trakt con
sus coordenadas IMDb verificadas cuando existen. Una coincidencia de otro show
no marca el episodio actual. Para anime se exige la correspondencia por episodio
en lugar de asumir que la numeración del título coincide con IMDb.

Las decisiones explícitas locales sobreviven al reinicio junto con los demás
campos del registro. «No visto» tiene prioridad sobre el historial remoto y la
decisión canónica solo actúa si no existe una decisión para el episodio original.
Desmarcar no elimina el historial Trakt, conforme a la referencia.

El marcado manual escribe primero localmente. Las escrituras al proveedor se
envían en orden y exigen un recibo con elementos añadidos o existentes. Los
episodios reutilizan la resolución de coordenadas y la búsqueda de películas
especiales ya presentes; un HTTP 200 sin correspondencias no confirma el marcado.
Cambiar de conexión o perfil cancela las acciones pendientes del propietario
anterior. El marcado completo de un título anime conserva la exclusión del
envío Trakt de `markMetaWatched`; el marcado individual puede utilizar su
correspondencia. No se introduce una cola persistente nueva para estas acciones.

El generador ejecuta cuatro módulos originales, sin peticiones a proveedores:
seis historiales (incluido uno de 1.000 títulos), seis casos de caché, cinco casos
de numeración canónica/prioridad manual, tres respuestas canceladas o fallidas y
cuatro rutas de marcado directo, resuelto, especial o sin confirmación. Las
entradas, salidas y hashes quedan en la fixture. Seis casos nativos nuevos
comprueban esas reglas con el transporte, la caché protegida, LibraryModel y su
reinicio reales. Los seis aprobaron en Apple en la ejecución 40613602917,
fuente `a250493946884de12a2c269786996917ded08e42`.

La compilación anterior 40611330498 aprobó el SDK completo sin advertencias
nuevas, pero no ejecutó pruebas: una aserción nueva de listas usaba `.array` sin
tipo contextual. Se corrigió a `JSONValue.array` conservando las expectativas.
Su archivo de evidencias y el árbol vacío se mantienen; no cuentan como pruebas
aprobadas. La siguiente selección conserva los casos aún no ejecutados y añade
estos seis, sin repetir áreas aprobadas intactas ni producir otra IPA.

La ejecución 40613602917 aprobó los 24 casos nativos seleccionados y 27 de 28
ejecuciones totales. El recorrido del iPhone falló al consultar la visibilidad
de Favoritos fuera de la ventana horizontal; el recorrido del iPad aprobó.
Aparecieron dos `try` redundantes en estas pruebas, ya retirados del código sin
cambiar sus expectativas. La siguiente compilación deberá confirmar que no
quedan advertencias nuevas; no se repiten estos seis casos por ese ajuste.

Siguen pendientes la revisión visual de las marcas en los episodios, las listas
públicas, recomendaciones, calendario y demás diferencias del port. Historial
combinado y su vista por episodios están implementados en un incremento posterior
con ejecución pendiente; véase `library-history-0.9.132.md`.
