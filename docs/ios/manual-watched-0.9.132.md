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
retenida durante un cambio de perfil. La ejecución Apple
[40675700785](https://github.com/Said129/harbor/actions/runs/40675700785), fuente
`041ca4830c46bc98d04c104253d7d2795056d2c2`, aprobó los cinco casos, sin omitidos,
fallos ni advertencias nuevas. Los árboles y los registros originales coinciden.
El archivo original de evidencia mide 52.661 bytes y tiene SHA-256
`14ac0ccd414131bc229f4ec6032d9c2f9be717eb0bc290570a579d48e13662e5`, igual al
digest de GitHub. La selección es nativa y no genera imágenes ni una IPA.

Se conservan los casos aprobados de las suites anteriores. No se afirma validación
visual, autorización real de Trakt ni equivalencia global terminada. La ampliación
posterior para mostrar marcas locales en Historial y los rótulos de episodio se
documenta por separado y todavía necesita su propia ejecución.
