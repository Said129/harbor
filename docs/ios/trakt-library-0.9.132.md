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
La primera compilación Apple (40608969355, fuente 5984eac) detectó dos errores
en el bloque nuevo: una propiedad privada consultada desde la vista y una
asignación a `error` sin `self` dentro de `catch`. Ambos están corregidos. Esa
ejecución no llegó a iniciar pruebas; no aporta aprobaciones nativas ni visuales.

Se añadió la agregación automática de la lista Trakt al iniciar y volver a la
app, sin bloquear el inicio. Las tarjetas y botones reconocen ambas rutas IMDb
y TMDB, mantienen el tipo película/serie y conservan los metadatos y el progreso
locales. La proyección externa no copia títulos a la biblioteca persistente;
la importación manual sigue guardándolos explícitamente.

Guardar o quitar desde Harbor escribe primero localmente y envía después la
acción Trakt en orden. La retirada elimina también los alias locales enlazados
sin borrar su progreso ni campos desconocidos. Una decisión de retirada por
perfil y conexión impide que una respuesta antigua la resucite; una nueva alta
remota posterior o una conexión distinta puede volver a mostrar el título.
Las respuestas y acciones de un perfil o conexión retirados no publican ni
envían la siguiente acción. La cola es de mejor esfuerzo, como la referencia;
no se afirma una cola persistente de cambios de lista sin conexión.

Otros cuatro módulos originales se ejecutaron sin red para obtener seis
escenarios y once acciones de sincronización automática, más la barrera contra
publicaciones de otro perfil. Seis casos nativos nuevos comprueban ese contrato,
la composición real con LibraryModel, reinicio, conservación del progreso,
cambio de conexión, carrera con actualización y espera de transferencias. Los
controles individuales usan el tipo de Media también para IMDb de series,
evitando enviarlo al bucket de películas. Esa corrección explícita conserva
el comportamiento útil, en lugar del error de inferencia de la referencia.
Todos estos casos nativos siguen pendientes de ejecución Apple.

Los montajes con transporte y metadatos controlados no certifican el recorrido
completo de una cuenta OAuth personal ni los botones de confirmación en una
instalación física. Sus capturas originales deben recogerse y revisarse.

## Pendientes de fidelidad que siguen en el objetivo

Las listas, transferencias, enlace automático y marcas globales aprobaron sus
24 casos nativos en la ejecución 40613602917; véase `trakt-watched-0.9.132.md`.
De las once capturas originales revisadas individualmente, la primera lista
compacta conservaba una portada en carga. Se exige ahora esperar las cuatro
portadas y repetir solo ese montaje afectado; el resto de las aprobaciones se
conserva. El recorrido de pestañas del iPhone también requiere reparación.
Historial combinado y su vista por episodios están implementados en un incremento
posterior con ejecución pendiente. También permanecen las listas públicas,
recomendaciones, calendario, avatar, comentarios y valoraciones Trakt, además
del resto del alcance compatible del port. No se considera cerrado Trakt ni el
port completo por añadir esta pestaña.
