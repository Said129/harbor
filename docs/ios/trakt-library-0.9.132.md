# Biblioteca y transferencia Trakt de Desktop 0.9.132

Referencia: `0834340cec5531650bfe78cd628628702e636987`.
Implementación nueva pendiente de compilación y ejecución Apple. No hay otra IPA.

## Incremento implementado

- Pestaña Trakt de Biblioteca cuando la cuenta del perfil está conectada, con
  lista de seguimiento e historial separados, búsqueda, tipos, contadores y
  ordenación. Las tarjetas usan los componentes y preferencias de Harbor, con
  enriquecimiento de metadatos e imágenes. Se conserva la preferencia de TMDB
  para la lista y la deduplicación por IMDb del historial de la referencia.
- Caché protegida del perfil y de la identidad durable de conexión Trakt. Una
  renovación del token no cambia de biblioteca; conectar otra cuenta no recibe
  los datos anteriores. Una respuesta de red fallida no sustituye la caché por
  una lista vacía y las tarjetas disponibles siguen visibles al actualizar.
- Importar y exportar desde Ajustes de Trakt, con confirmación, progreso,
  resultado y cancelación por salida o cambio de perfil. La exportación conserva
  los lotes de 100, el descarte de identificadores de anime sin correspondencia,
  la continuación tras un lote fallido y los contadores confirmados por Trakt.
- La importación utiliza el almacén local de Harbor. Guarda sin alternar ni
  quitar títulos ya existentes, conserva su progreso y sus campos desconocidos
  y valida propietario y perfil antes de escribir. Sustituye el requisito de
  sesión Stremio de la referencia conforme a la instrucción del propietario.
- Quitar una tarjeta de la lista Trakt utiliza el tipo e identificadores del
  proveedor; no borra el historial ni otra biblioteca personal.

Las escrituras solo se inician por una acción del usuario. Este incremento no
conecta ni modifica cuentas personales durante las pruebas.

## Evidencia disponible y límites

El generador ejecutó seis módulos originales sin red: `trakt/watchlist.ts`,
`trakt/watchlist-sync.ts`, `trakt/history.ts`, `trakt/to-meta.ts`,
`views/library/history-merge.ts` y las funciones de `views/library/shared.tsx`.
Se conservaron sus hashes y entradas/resultados en la fixture: siete listas,
cuatro historiales, cinco planes, cuatro exportaciones de varios lotes, dos
importaciones con fallos controlados y doce filtros. Ejecutar sus funciones no
afirma haber renderizado la interfaz React original.

Nueve casos nativos nuevos comparan esos resultados y comprueban la caché,
respuestas tardías, escrituras individuales y la composición real de importación
con LibraryModel, persistencia, progreso existente y reinicio sin cuenta Stremio.
Un montaje nuevo muestra los componentes de lista, historial y transferencia con
portadas decodificadas en ambos tamaños. Dos recorridos UI nuevos comprueban las
pestañas locales afectadas y la ausencia de pestañas de proveedores desconectados.
Estas pruebas aún no se han ejecutado en Apple.

Los montajes con transporte y metadatos controlados no certifican el recorrido
completo de una cuenta OAuth personal ni los botones de confirmación en una
instalación física. Sus capturas originales deben recogerse y revisarse.

## Pendientes de fidelidad que siguen en el objetivo

La referencia también sincroniza automáticamente guardar/quitar de la lista
local y agrega identificadores de las listas externas. Ese enlace global y la
proyección de sus marcas de visto siguen pendientes; los controles manuales de
este incremento no los sustituyen. También permanecen las listas públicas,
recomendaciones, calendario, avatar, comentarios y valoraciones Trakt, además
del resto del alcance compatible del port. No se considera cerrado Trakt ni el
port completo por añadir esta pestaña.
