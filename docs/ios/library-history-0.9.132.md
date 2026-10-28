# Historial combinado y vista de episodios

Referencia fija: Desktop 0.9.132, commit
`0834340cec5531650bfe78cd628628702e636987`. Este incremento sigue pendiente de
compilación, ejecución y revisión visual en Apple; no certifica el port completo.

La pestaña Historial de Biblioteca utiliza ahora su proyección propia. Incluye
títulos empezados y vistos, conserva los registros temporales y excluye las
entradas retiradas. Combina los registros locales de Harbor con el historial de
Trakt; el título local tiene prioridad y las entradas remotas repetidas se
reducen a la primera por IMDb, como en `history-merge.ts`. La consulta de esta
pestaña usa 200 entradas y no depende de que responda la lista de guardados. La
lectura global de marcas sigue usando su consulta independiente de 1.000.

El filtro por tipo, búsqueda, orden, agrupación y cambio entre pósteres y tarjetas
de episodios se mantienen en la interfaz móvil. Las tarjetas horizontales
incluyen el progreso, tiempo restante, marca de visto, fecha y, cuando existe,
la imagen y el nombre del episodio. La fecha usada para agrupar y ordenar es la
de modificación; la fecha mostrada en la tarjeta puede ser la última reproducción.
Las tarjetas remotas sin coordenadas conservan el comportamiento de la referencia
y abren el título.

El modo elegido se guarda con las preferencias del propietario de Biblioteca.
Los datos anteriores, que no contienen `historyView`, abren en modo pósteres.
No se añade una sesión Stremio. La retirada requiere confirmación y conserva los
campos desconocidos y el progreso del registro, cambiando `removed` y `temp` como
la función de referencia. No borra el historial Trakt ni los datos de otro perfil.

Abrir una tarjeta de episodio proporciona una pista a Detalle para seleccionar
su temporada. La pista se conserva cuando los metadatos llegan después de abrir
la pantalla y admite temporada cero. La coincidencia del episodio mantiene su
identidad de origen en las secciones que reúnen varias entradas de anime.

Se portan la entrada de 440 ms con desplazamiento de 10 puntos y curva
`cubic-bezier(0.16, 1, 0.3, 1)`, la carga de dos grupos de 14 y 8 pósteres, el
escalonado de 35 ms y el barrido de 1,5 segundos. «Reducir movimiento» desactiva
esas animaciones; el barrido también se detiene fuera de la escena activa.
Las traducciones añaden solo diez rótulos que faltaban entre los 21 utilizados
en los 16 idiomas fijados de Desktop; se conservan los demás textos existentes.

El generador ejecuta `history-merge.ts`, las funciones de `shared.tsx` y los
cuerpos originales de `libraryMetaType` y `episodeFromVideoId`, extraídos por AST
de `stremio.ts`. No se afirma ejecutar todo Stremio ni renderizar React. Ocho
escenarios comparan filtro, combinación, prioridad local, fechas, progreso,
numeración de anime y especiales, identificadores ausentes y límites de visto.
Se conservan entradas, salidas y hashes, además del CSS original de las animaciones.

Seis casos nativos nuevos comprueban esos resultados, la consulta independiente,
la persistencia y retirada real, compatibilidad de preferencias, separación de
fechas y cancelación por cambio de perfil. Un montaje de componentes prepara
cuatro capturas con imágenes propias decodificadas en los dos tamaños. Dos
recorridos nuevos de la app normal, con preparación de datos locales sin
credenciales, verifican cambio de modo, búsqueda, confirmación, retirada y
reinicio. Estos recorridos usan títulos sintéticos sin portadas; no certifican
arte de proveedores. Las imágenes del montaje cubren ese aspecto por separado.

Ninguno de estos casos nuevos se ha ejecutado todavía. La validación anterior de
listas y marcas Trakt sigue en curso y se conserva como una ejecución distinta.
Sus casos aprobados solo deberán repetirse si esta modificación afecta a su
comportamiento. Permanecen pendientes las demás secciones, servicios, interfaces,
animaciones y validaciones físicas del objetivo general, y una sola IPA final.
