# Marcas manuales: identificadores y episodios emitidos

Referencia: Harbor Desktop 0.9.132, commit
`0834340cec5531650bfe78cd628628702e636987`, funciones originales de
`mark-watched.ts`, `aired.ts` y `trakt/ids.ts`.

El marcado de películas conserva su identificador local de addon y utiliza el
IMDb explícito de los metadatos para escribir en Trakt. Cuando el identificador
original también aporta un TMDB de película válido, se envían ambos. Las series
con identificador propio y un IMDb explícito utilizan este último para los
episodios y para la resolución posterior. La confirmación del proveedor sigue
siendo obligatoria antes de actualizar su caché; el guardado local ocurre primero.
No se crea una sesión Stremio ni se envía nada a sus servicios de cuenta.

El marcado de serie completa sigue la selección original: temporadas desde la
uno, episodios ordenados por temporada y número y exclusión de emisiones futuras.
Si hay fechas, un episodio sin fecha solo se incluye hasta el último episodio
emitido; sin fechas se conservan todos los episodios ordinarios. Los especiales
permanecen disponibles para marcado individual y no se eliminan al desmarcar la
serie completa. Esta política se utiliza también para decidir si la serie está
completamente vista. No modifica la selección de reproducción ni el siguiente
episodio.

Como en el original, el marcado de anime completo no envía números sin mapear
a Trakt. Un episodio individual conserva la resolución verificada por episodio;
el IMDb del título por sí solo no autoriza asociar un número absoluto a otra
temporada. Se rechazan identificadores explícitos inválidos antes de enviar.

El generador ejecuta los tres módulos originales, sin red ni cuentas personales,
con nueve escenarios. La fixture conserva entradas, objetivos, episodios emitidos
y hashes de los tres módulos. Cinco casos nativos nuevos contrastan esos resultados
y ejercitan el `LibraryModel` real, la escritura y reapertura de la caché, los
especiales individuales, la confirmación, el aislamiento de anime y una escritura
retenida durante un cambio de perfil. Siguen sin ejecutarse en Apple a la fecha
de este cambio. No se afirma validación visual, autorización real de Trakt ni
equivalencia global terminada. Se conservan los casos aprobados de las suites
anteriores; no se genera una IPA en esta selección.
